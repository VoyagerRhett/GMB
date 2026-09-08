//! 高层钱包 submit-and-watch、准确 finalized 终态和中断持久门测试。

#![allow(clippy::expect_used, clippy::unwrap_used)]

use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Arc, Mutex,
};

use citizen_sdk_contracts::{
    store::{HistoryTransactionStatus, TransactionHistoryState, TransactionHistoryStore},
    AccountId32, ChainIdentity, ContractError, ContractErrorCode, ContractFuture, ContractResult,
    ContractStream, ExecutionConclusion, ExportedChainState, ExtrinsicWatchEvent,
    FinalizedBlockRef, Hash32, RuntimeContext, RuntimeVersion, SignedExtrinsic, StateImportReceipt,
    SubmittedExtrinsic, VerifiedBlockRef, VerifiedChainClient,
};
use futures::executor::block_on;

use crate::{
    finalized_history_runtime::{FinalizedHistoryRunGuard, FinalizedHistoryRuntime},
    signed_extrinsic_hash,
    transaction_history::TransactionHistoryService,
    wallet_service::WalletClock,
    wallet_transfer_watch::{
        watch_recorded_transfer, WalletTransferObserver, WalletTransferResolution,
        WalletTransferWatchStage, WalletTransferWatchUpdate,
    },
    EngineError,
};

const METADATA_HEX: &str =
    include_str!("../../../test/transaction/citizenchain-runtime-v14-metadata.hex");
const EVENTS_HEX: &str =
    include_str!("../../../test/transaction/citizenchain-runtime-system-events.hex");
const FIXTURE_EXTRINSIC: &[u8] = &[0x0c, 0x84, 0x01, 0x02];

#[test]
fn transfer_budget_begins_at_watch_and_changes_only_for_this_request() {
    let token = crate::WalletTransferCancellation::default();
    let other = crate::WalletTransferCancellation::default();
    assert!(token.remaining_budget().is_none());
    token.begin_watch();
    let remaining = token.remaining_budget().unwrap();
    assert!(remaining <= std::time::Duration::from_secs(1200));
    assert!(remaining > std::time::Duration::from_secs(1190));
    token.begin_execution();
    let remaining = token.clone().remaining_budget().unwrap();
    assert!(remaining <= std::time::Duration::from_secs(30));
    assert!(remaining > std::time::Duration::from_secs(20));
    assert!(!token.is_cancelled());
    assert!(other.remaining_budget().is_none());
}

#[derive(Debug)]
struct MemoryHistoryStore {
    state: Mutex<TransactionHistoryState>,
    fail_after_write: AtomicBool,
    fail_next_load: AtomicBool,
    fail_before_write: AtomicBool,
    pause_next: Mutex<Option<futures::channel::oneshot::Receiver<()>>>,
    cas_entered: AtomicBool,
}

impl Default for MemoryHistoryStore {
    fn default() -> Self {
        Self {
            state: Mutex::new(
                TransactionHistoryState::try_new(0, Vec::new(), Vec::new(), Vec::new())
                    .expect("空历史状态有效"),
            ),
            fail_after_write: AtomicBool::new(false),
            fail_next_load: AtomicBool::new(false),
            fail_before_write: AtomicBool::new(false),
            pause_next: Mutex::new(None),
            cas_entered: AtomicBool::new(false),
        }
    }
}

impl MemoryHistoryStore {
    fn snapshot(&self) -> TransactionHistoryState {
        self.state.lock().unwrap().clone()
    }
}

impl TransactionHistoryStore for MemoryHistoryStore {
    fn load(&self) -> ContractFuture<'_, TransactionHistoryState> {
        Box::pin(async move {
            if self.fail_next_load.swap(false, Ordering::SeqCst) {
                return Err(ContractError::new(
                    ContractErrorCode::Storage,
                    "测试回读中断",
                ));
            }
            Ok(self.state.lock().unwrap().clone())
        })
    }

    fn compare_and_swap(
        &self,
        expected_revision: u64,
        next: TransactionHistoryState,
    ) -> ContractFuture<'_, TransactionHistoryState> {
        Box::pin(async move {
            let pause = self.pause_next.lock().unwrap().take();
            if let Some(pause) = pause {
                self.cas_entered.store(true, Ordering::SeqCst);
                pause.await.expect("已进入的 CAS 不能被取消丢弃");
            }
            if self.fail_before_write.swap(false, Ordering::SeqCst) {
                return Err(ContractError::new(
                    ContractErrorCode::Storage,
                    "测试写前中断",
                ));
            }
            let mut state = self.state.lock().unwrap();
            if state.revision() != expected_revision {
                return Err(ContractError::new(
                    ContractErrorCode::Conflict,
                    "测试历史 revision 冲突",
                ));
            }
            *state = next.clone();
            if self.fail_after_write.swap(false, Ordering::SeqCst) {
                self.fail_next_load.store(true, Ordering::SeqCst);
                return Err(ContractError::new(
                    ContractErrorCode::Storage,
                    "测试写后中断",
                ));
            }
            Ok(next)
        })
    }
}

#[derive(Debug, Default)]
struct TestClock(AtomicU64);

impl WalletClock for TestClock {
    fn now_millis(&self) -> ContractResult<u64> {
        Ok(2_000_000_000_000 + self.0.fetch_add(1, Ordering::SeqCst))
    }
}

#[derive(Debug, Default)]
struct AlwaysRunning;

impl FinalizedHistoryRunGuard for AlwaysRunning {
    fn ensure_current(&self) -> Result<(), EngineError> {
        Ok(())
    }
}

struct TransferGuard(crate::WalletTransferCancellation);
impl FinalizedHistoryRunGuard for TransferGuard {
    fn ensure_current(&self) -> Result<(), EngineError> {
        if self.0.is_cancelled() {
            Err(EngineError::contract(
                ContractErrorCode::InvalidState,
                "测试请求取消",
            ))
        } else {
            Ok(())
        }
    }
    fn poll_cancelled(&self, cx: &mut std::task::Context<'_>) -> std::task::Poll<()> {
        self.0.signal.poll_cancelled(cx)
    }
}

#[derive(Debug, Default)]
struct RecordingObserver {
    updates: Mutex<Vec<WalletTransferWatchUpdate>>,
    panic_on_update: bool,
}

impl RecordingObserver {
    fn stages(&self) -> Vec<WalletTransferWatchStage> {
        self.updates
            .lock()
            .unwrap()
            .iter()
            .map(|update| update.stage().clone())
            .collect()
    }
}

impl WalletTransferObserver for RecordingObserver {
    fn on_update(&self, update: WalletTransferWatchUpdate) {
        if self.panic_on_update {
            panic!("测试观察器 panic");
        }
        self.updates.lock().unwrap().push(update);
    }
}

struct FakeChainClient {
    head: u64,
    metadata: Vec<u8>,
    events: Vec<u8>,
    body: Mutex<Vec<Vec<u8>>>,
    watch_events: Mutex<Option<Vec<ContractResult<ExtrinsicWatchEvent>>>>,
    expected_extrinsic: Vec<u8>,
    history_store: Arc<MemoryHistoryStore>,
    watch_saw_pending: AtomicBool,
    reject_best_runtime: bool,
}

impl FakeChainClient {
    fn new(
        head: u64,
        watch_events: Vec<ContractResult<ExtrinsicWatchEvent>>,
        store: Arc<MemoryHistoryStore>,
    ) -> Self {
        Self {
            head,
            metadata: hex_bytes(METADATA_HEX),
            events: hex_bytes(EVENTS_HEX),
            body: Mutex::new(vec![FIXTURE_EXTRINSIC.to_vec(), vec![0x08, 0x84, 0x03]]),
            watch_events: Mutex::new(Some(watch_events)),
            expected_extrinsic: FIXTURE_EXTRINSIC.to_vec(),
            history_store: store,
            watch_saw_pending: AtomicBool::new(false),
            reject_best_runtime: false,
        }
    }
}

impl VerifiedChainClient for FakeChainClient {
    fn identity(&self) -> ContractFuture<'_, ChainIdentity> {
        Box::pin(async { Ok(ChainIdentity::citizenchain()) })
    }

    fn get_best_head(&self) -> ContractFuture<'_, VerifiedBlockRef> {
        let head = block(self.head);
        Box::pin(async move { Ok(VerifiedBlockRef::best(head.hash(), head.number())) })
    }

    fn get_finalized_head(&self) -> ContractFuture<'_, FinalizedBlockRef> {
        let head = block(self.head);
        Box::pin(async move { Ok(head) })
    }

    fn get_finalized_block_at(&self, number: u64) -> ContractFuture<'_, FinalizedBlockRef> {
        let head = self.head;
        Box::pin(async move {
            if number > head {
                return Err(ContractError::new(
                    ContractErrorCode::NotFound,
                    "测试高度尚未 finalized",
                ));
            }
            Ok(block(number))
        })
    }

    fn get_finalized_blocks_at(
        &self,
        start_number: u64,
        end_number: u64,
    ) -> ContractFuture<'_, Vec<FinalizedBlockRef>> {
        let head = self.head;
        Box::pin(async move {
            if start_number > end_number || end_number > head {
                return Err(ContractError::new(
                    ContractErrorCode::NotFound,
                    "测试 finalized 区间无效",
                ));
            }
            Ok((start_number..=end_number).map(block).collect())
        })
    }

    fn get_storage_at(
        &self,
        _block: VerifiedBlockRef,
        _key: Vec<u8>,
    ) -> ContractFuture<'_, Option<Vec<u8>>> {
        let events = self.events.clone();
        Box::pin(async move { Ok(Some(events)) })
    }

    fn get_storage_batch_at(
        &self,
        _block: VerifiedBlockRef,
        keys: Vec<Vec<u8>>,
    ) -> ContractFuture<'_, Vec<Option<Vec<u8>>>> {
        let events = self.events.clone();
        Box::pin(async move { Ok(keys.into_iter().map(|_| Some(events.clone())).collect()) })
    }

    fn get_runtime_context_at(
        &self,
        block: VerifiedBlockRef,
    ) -> ContractFuture<'_, RuntimeContext> {
        if self.reject_best_runtime && !block.is_finalized() {
            return Box::pin(async {
                Err(ContractError::new(
                    ContractErrorCode::Unavailable,
                    "测试 best Runtime 已不可读；finalized 同步可继续",
                ))
            });
        }
        let metadata = self.metadata.clone();
        Box::pin(
            async move { RuntimeContext::try_new(block, RuntimeVersion::new(100, 12), metadata) },
        )
    }

    fn get_block_extrinsics_at(
        &self,
        _block: VerifiedBlockRef,
    ) -> ContractFuture<'_, Vec<Vec<u8>>> {
        let body = self.body.lock().unwrap().clone();
        Box::pin(async move { Ok(body) })
    }

    fn submit_extrinsic(
        &self,
        _extrinsic: SignedExtrinsic,
    ) -> ContractFuture<'_, SubmittedExtrinsic> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::InvalidState,
                "高层钱包协调器不得调用 submit_extrinsic",
            ))
        })
    }

    fn watch_extrinsic(
        &self,
        extrinsic: SignedExtrinsic,
    ) -> ContractStream<'_, ExtrinsicWatchEvent> {
        assert_eq!(extrinsic.as_bytes(), self.expected_extrinsic);
        let snapshot = self.history_store.snapshot();
        self.watch_saw_pending.store(
            snapshot.records().len() == 1
                && matches!(
                    snapshot.records()[0].status(),
                    HistoryTransactionStatus::Pending
                ),
            Ordering::SeqCst,
        );
        let events = self
            .watch_events
            .lock()
            .unwrap()
            .take()
            .expect("每个测试 client 只允许启动一次 watch");
        Box::pin(futures::stream::iter(events))
    }

    fn export_state(&self) -> ContractFuture<'_, ExportedChainState> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::Unsupported,
                "测试不导出状态",
            ))
        })
    }

    fn import_state(&self, _state: ExportedChainState) -> ContractFuture<'_, StateImportReceipt> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::Unsupported,
                "测试不导入状态",
            ))
        })
    }
}

struct Harness {
    client: Arc<FakeChainClient>,
    runtime: FinalizedHistoryRuntime,
    history: TransactionHistoryService,
    store: Arc<MemoryHistoryStore>,
    account_id: AccountId32,
    transaction_hash: Hash32,
    signed: SignedExtrinsic,
}

impl Harness {
    async fn new(watch_events: Vec<ContractResult<ExtrinsicWatchEvent>>) -> Self {
        let store = Arc::new(MemoryHistoryStore::default());
        let history = TransactionHistoryService::new(store.clone(), Arc::new(TestClock::default()));
        let account_id = account(0x11);
        let destination = account(0x22);
        let signed = SignedExtrinsic::try_new(FIXTURE_EXTRINSIC.to_vec()).unwrap();
        let context = RuntimeContext::try_new(
            block(1).verified(),
            RuntimeVersion::new(100, 12),
            hex_bytes(METADATA_HEX),
        )
        .unwrap();
        let transaction_hash = signed_extrinsic_hash(&context, &signed).unwrap();
        history
            .ensure_cursors(&[account_id], block(0))
            .await
            .unwrap();
        history
            .record_pending_before_broadcast(
                account_id,
                transaction_hash,
                0,
                destination,
                123_456,
                "CitizenSDK production Runtime fixture",
                signed.clone(),
                citizen_sdk_contracts::VerifiedBlockRef::best(
                    citizen_sdk_contracts::Hash32::from_bytes([1; 32]),
                    1,
                ),
                citizen_sdk_contracts::RuntimeVersion::new(100, 12),
                citizen_sdk_contracts::ChainIdentity::citizenchain().genesis_hash(),
            )
            .await
            .unwrap();
        let client = Arc::new(FakeChainClient::new(1, watch_events, store.clone()));
        let runtime = FinalizedHistoryRuntime::new(client.clone(), history.clone());
        Self {
            client,
            runtime,
            history,
            store,
            account_id,
            transaction_hash,
            signed,
        }
    }

    async fn watch(
        &self,
        observer: Arc<dyn WalletTransferObserver>,
    ) -> Result<crate::WalletTransferWatchResult, EngineError> {
        watch_recorded_transfer(
            self.client.as_ref(),
            &self.runtime,
            &self.history,
            &AlwaysRunning,
            &observer,
            self.account_id,
            self.transaction_hash,
            self.signed.clone(),
        )
        .await
    }
}

#[test]
fn pending_precedes_provider_and_finalized_requires_exact_system_outcome() {
    block_on(async {
        let finalized = block(1);
        let harness = Harness::new(vec![
            Ok(ExtrinsicWatchEvent::Ready),
            Ok(ExtrinsicWatchEvent::InBlock {
                block: VerifiedBlockRef::best(finalized.hash(), finalized.number()),
            }),
            Ok(ExtrinsicWatchEvent::Finalized { block: finalized }),
        ])
        .await;
        let observer = Arc::new(RecordingObserver::default());
        let result = harness.watch(observer.clone()).await.unwrap();

        assert!(harness.client.watch_saw_pending.load(Ordering::SeqCst));
        assert_eq!(result.transaction_hash(), harness.transaction_hash);
        assert!(matches!(
            result.resolution(),
            WalletTransferResolution::Finalized(ExecutionConclusion::Success {
                block,
                extrinsic_index: 0,
            }) if *block == finalized.verified()
        ));
        assert!(matches!(
            result.history().records()[0].status(),
            HistoryTransactionStatus::Execution(ExecutionConclusion::Success { .. })
        ));
        assert!(matches!(
            observer.stages().as_slice(),
            [
                WalletTransferWatchStage::Pending,
                WalletTransferWatchStage::Ready,
                WalletTransferWatchStage::InBlock { .. },
                WalletTransferWatchStage::Finalized { .. }
            ]
        ));
    });
}

#[test]
fn cancelling_during_inblock_or_terminal_cas_preserves_the_real_write_without_late_events() {
    use futures::FutureExt;
    block_on(async {
        for event in [
            ExtrinsicWatchEvent::InBlock {
                block: block(1).verified(),
            },
            ExtrinsicWatchEvent::Invalid,
            ExtrinsicWatchEvent::Finalized { block: block(1) },
        ] {
            let harness = Harness::new(vec![Ok(event.clone())]).await;
            let (release, receiver) = futures::channel::oneshot::channel();
            *harness.store.pause_next.lock().unwrap() = Some(receiver);
            let token = crate::WalletTransferCancellation::default();
            let guard = TransferGuard(token.clone());
            let observed = Arc::new(RecordingObserver::default());
            let observer: Arc<dyn WalletTransferObserver> = observed.clone();
            let mut operation = Box::pin(watch_recorded_transfer(
                harness.client.as_ref(),
                &harness.runtime,
                &harness.history,
                &guard,
                &observer,
                harness.account_id,
                harness.transaction_hash,
                harness.signed.clone(),
            ));
            for _ in 0..100_000 {
                assert!(operation.as_mut().now_or_never().is_none());
                if harness.store.cas_entered.load(Ordering::SeqCst) {
                    break;
                }
                std::thread::yield_now();
            }
            assert!(harness.store.cas_entered.load(Ordering::SeqCst));
            token.cancel();
            assert!(
                operation.as_mut().now_or_never().is_none(),
                "取消不能丢弃状态 CAS"
            );
            assert!(matches!(
                harness.store.snapshot().records()[0].status(),
                HistoryTransactionStatus::Pending
            ));
            release.send(()).unwrap();
            assert!(operation.await.is_err());
            let state = harness.store.snapshot();
            match event {
                ExtrinsicWatchEvent::InBlock { .. } => assert!(matches!(
                    state.records()[0].status(),
                    HistoryTransactionStatus::InBlock { .. }
                )),
                ExtrinsicWatchEvent::Invalid => assert!(matches!(
                    state.records()[0].status(),
                    HistoryTransactionStatus::PoolRejected { .. }
                )),
                ExtrinsicWatchEvent::Finalized { .. } => assert!(matches!(
                    state.records()[0].status(),
                    HistoryTransactionStatus::Execution(ExecutionConclusion::Success { .. })
                )),
                _ => unreachable!(),
            }
            assert_eq!(observed.stages(), vec![WalletTransferWatchStage::Pending]);
        }
    });
}

#[test]
fn cancelling_during_pending_cas_finishes_persistence_but_never_starts_broadcast() {
    use futures::FutureExt;
    block_on(async {
        let harness = Harness::new(vec![Ok(ExtrinsicWatchEvent::Invalid)]).await;
        let snapshot = harness.store.snapshot();
        let record = snapshot.records()[0].clone();
        *harness.store.state.lock().unwrap() = TransactionHistoryState::try_new(
            snapshot.revision(),
            snapshot.cursors().to_vec(),
            Vec::new(),
            Vec::new(),
        )
        .unwrap();
        let (release, receiver) = futures::channel::oneshot::channel();
        *harness.store.pause_next.lock().unwrap() = Some(receiver);
        let token = crate::WalletTransferCancellation::default();
        let guard = TransferGuard(token.clone());
        let observer: Arc<dyn WalletTransferObserver> = Arc::new(RecordingObserver::default());
        let mut operation = Box::pin(async {
            harness
                .history
                .record_pending_before_broadcast(
                    harness.account_id,
                    harness.transaction_hash,
                    record.nonce(),
                    record.destination_account_id(),
                    record.amount_fen(),
                    record.remark(),
                    record.signed_extrinsic().clone(),
                    record.block(),
                    record.runtime_version(),
                    record.genesis_hash(),
                )
                .await?;
            watch_recorded_transfer(
                harness.client.as_ref(),
                &harness.runtime,
                &harness.history,
                &guard,
                &observer,
                harness.account_id,
                harness.transaction_hash,
                harness.signed.clone(),
            )
            .await
        });
        for _ in 0..100_000 {
            assert!(operation.as_mut().now_or_never().is_none());
            if harness.store.cas_entered.load(Ordering::SeqCst) {
                break;
            }
            std::thread::yield_now();
        }
        assert!(harness.store.cas_entered.load(Ordering::SeqCst));
        token.cancel();
        assert!(operation.as_mut().now_or_never().is_none());
        release.send(()).unwrap();
        assert!(operation.await.is_err());
        assert!(matches!(
            harness.store.snapshot().records()[0].status(),
            HistoryTransactionStatus::Pending
        ));
        assert!(
            harness.client.watch_events.lock().unwrap().is_some(),
            "取消后不得广播"
        );
    });
}

#[test]
fn invalid_and_usurped_are_pool_rejections_not_chain_success() {
    block_on(async {
        for (event, expected_replacement) in [
            (ExtrinsicWatchEvent::Invalid, None),
            (
                ExtrinsicWatchEvent::Usurped {
                    replacement_hash: hash(0xaa),
                },
                Some(hash(0xaa)),
            ),
        ] {
            let harness = Harness::new(vec![Ok(event)]).await;
            let observer = Arc::new(RecordingObserver::default());
            let result = harness.watch(observer.clone()).await.unwrap();
            assert!(matches!(
                result.resolution(),
                WalletTransferResolution::PoolRejected { .. }
            ));
            assert!(result.history().records()[0]
                .status()
                .pool_rejection_reason()
                .is_some());
            assert!(matches!(
                observer.stages().last(),
                Some(WalletTransferWatchStage::PoolRejected {
                    replacement_hash,
                    ..
                }) if *replacement_hash == expected_replacement
            ));
        }
    });
}

#[test]
fn finalized_watch_fact_without_exact_body_and_system_outcome_never_becomes_success() {
    block_on(async {
        let finalized = block(1);
        let harness = Harness::new(vec![Ok(ExtrinsicWatchEvent::Finalized {
            block: finalized,
        })])
        .await;
        *harness.client.body.lock().unwrap() = vec![vec![0x08, 0x84, 0x03]];

        let error = harness
            .watch(Arc::new(RecordingObserver::default()))
            .await
            .unwrap_err();
        assert!(matches!(error, EngineError::InvalidEvents(_)));
        assert!(matches!(
            harness.store.snapshot().records()[0].status(),
            HistoryTransactionStatus::Pending
        ));
    });
}

#[test]
fn disconnect_and_nondefinitive_watch_failures_keep_the_durable_account_gate() {
    block_on(async {
        let event_sets = vec![
            Vec::new(),
            vec![Ok(ExtrinsicWatchEvent::Dropped)],
            vec![
                Ok(ExtrinsicWatchEvent::InBlock {
                    block: VerifiedBlockRef::best(hash(0x51), 5),
                }),
                Ok(ExtrinsicWatchEvent::Retracted {
                    block: VerifiedBlockRef::best(hash(0x51), 5),
                }),
            ],
            vec![Ok(ExtrinsicWatchEvent::FinalityTimeout { block: None })],
        ];
        for events in event_sets {
            let harness = Harness::new(events).await;
            let observer = Arc::new(RecordingObserver::default());
            let error = harness.watch(observer).await.unwrap_err();
            assert!(matches!(error, EngineError::Contract(_)));
            assert!(matches!(
                harness.store.snapshot().records()[0].status(),
                HistoryTransactionStatus::Pending | HistoryTransactionStatus::InBlock { .. }
            ));
            let conflict = harness
                .history
                .record_pending_before_broadcast(
                    harness.account_id,
                    hash(0xbb),
                    0,
                    account(0x33),
                    1,
                    "must remain gated",
                    harness.signed.clone(),
                    citizen_sdk_contracts::VerifiedBlockRef::best(
                        citizen_sdk_contracts::Hash32::from_bytes([1; 32]),
                        1,
                    ),
                    citizen_sdk_contracts::RuntimeVersion::new(100, 12),
                    citizen_sdk_contracts::ChainIdentity::citizenchain().genesis_hash(),
                )
                .await
                .unwrap_err();
            assert!(matches!(
                conflict,
                EngineError::Contract(ref inner) if inner.code() == ContractErrorCode::Conflict
            ));
        }
    });
}

#[test]
fn provider_error_notifies_interruption_and_observer_panic_cannot_abort_terminal_state() {
    block_on(async {
        let disconnected = Harness::new(vec![Err(ContractError::new(
            ContractErrorCode::Network,
            "测试断线",
        ))])
        .await;
        let observer = Arc::new(RecordingObserver::default());
        let error = disconnected.watch(observer.clone()).await.unwrap_err();
        assert!(matches!(
            error,
            EngineError::Contract(ref inner) if inner.code() == ContractErrorCode::Network
        ));
        assert!(matches!(
            observer.stages().last(),
            Some(WalletTransferWatchStage::Interrupted { .. })
        ));
        assert!(matches!(
            disconnected.store.snapshot().records()[0].status(),
            HistoryTransactionStatus::Pending
        ));

        let rejected = Harness::new(vec![Ok(ExtrinsicWatchEvent::Invalid)]).await;
        let panicking: Arc<dyn WalletTransferObserver> = Arc::new(RecordingObserver {
            updates: Mutex::new(Vec::new()),
            panic_on_update: true,
        });
        let result = rejected.watch(panicking).await.unwrap();
        assert!(matches!(
            result.resolution(),
            WalletTransferResolution::PoolRejected { .. }
        ));
    });
}

#[test]
fn restart_reconciles_finalized_transaction_without_broadcasting_it_again() {
    block_on(async {
        let harness = Harness::new(vec![Ok(ExtrinsicWatchEvent::Invalid)]).await;
        // Pending 已持久但首个 watch 尚未创建，模拟取消/退出后的重新打开。
        crate::wallet_transfer_watch::reconcile_before_rebroadcast(
            harness.client.as_ref(),
            &harness.runtime,
            &harness.history,
            &AlwaysRunning,
            harness.account_id,
        )
        .await
        .unwrap();
        let observer = Arc::new(RecordingObserver::default());
        let result = harness.watch(observer).await.unwrap();
        assert!(matches!(
            result.resolution(),
            WalletTransferResolution::Finalized(_)
        ));
        assert!(
            harness.client.watch_events.lock().unwrap().is_some(),
            "finalized 历史已证明执行，必须不创建 submit-and-watch"
        );
        assert_eq!(
            harness.store.snapshot().records()[0].signed_extrinsic(),
            &harness.signed
        );
    });
}

#[test]
fn pool_terminal_and_changed_authorized_bytes_never_rebroadcast() {
    block_on(async {
        let harness = Harness::new(vec![Ok(ExtrinsicWatchEvent::Invalid)]).await;
        let result = harness
            .watch(Arc::new(RecordingObserver::default()))
            .await
            .unwrap();
        assert!(matches!(
            result.resolution(),
            WalletTransferResolution::PoolRejected { .. }
        ));
        // Fake provider 对第二次 watch 会 panic；复用终态必须只读本机结果。
        assert!(harness
            .watch(Arc::new(RecordingObserver::default()))
            .await
            .is_ok());
        let mut changed = Harness::new(Vec::new()).await;
        changed.signed = SignedExtrinsic::try_new(vec![0x84]).unwrap();
        assert!(changed
            .watch(Arc::new(RecordingObserver::default()))
            .await
            .is_err());
        assert!(changed.client.watch_events.lock().unwrap().is_some());
    });
}

#[test]
#[cfg(all(
    feature = "wallet",
    feature = "signing",
    feature = "transactions",
    feature = "history"
))]
fn public_engine_resumes_outbox_after_failed_write_receipt_without_wallet_or_new_nonce() {
    use citizen_sdk_contracts as c;
    // 任一钱包/秘密访问都会使测试失败；恢复必须只使用已经持久的公开授权。
    struct NoWallet;
    impl c::WalletProfileStore for NoWallet {
        fn load(&self) -> c::ContractFuture<'_, c::WalletState> {
            panic!("恢复不得读取钱包秘密入口");
        }
        fn compare_and_swap(
            &self,
            _: u64,
            _: c::WalletState,
        ) -> c::ContractFuture<'_, c::WalletState> {
            panic!("恢复不得改钱包");
        }
    }
    impl c::EncryptedSecretBlobStore for NoWallet {
        fn load(&self, _: c::SecretRef) -> c::ContractFuture<'_, c::EncryptedSecretBlobSnapshot> {
            panic!("恢复不得读取秘密");
        }
        fn compare_and_swap(
            &self,
            _: c::SecretRef,
            _: u64,
            _: c::EncryptedSecretBlobState,
        ) -> c::ContractFuture<'_, c::EncryptedSecretBlobSnapshot> {
            panic!("恢复不得写秘密");
        }
    }
    impl c::SecretVault for NoWallet {
        fn availability(&self) -> c::ContractFuture<'_, c::VaultAvailability> {
            panic!("恢复不得调用金库");
        }
        fn seal(
            &self,
            _: [u8; 16],
            _: c::SecretRef,
            _: c::SecretBuffer,
        ) -> c::ContractFuture<'_, c::EncryptedSecretEnvelope> {
            panic!("恢复不得封装秘密");
        }
        fn open(
            &self,
            _: c::SecretRef,
            _: c::EncryptedSecretEnvelope,
        ) -> c::ContractFuture<'_, c::SecretBuffer> {
            panic!("恢复不得解锁秘密");
        }
        fn has_wallet_key(&self, _: u32, _: c::VaultGeneration) -> c::ContractFuture<'_, bool> {
            panic!("恢复不得查询金库");
        }
        fn delete_wallet_key(
            &self,
            _: [u8; 16],
            _: u32,
            _: c::VaultGeneration,
        ) -> c::ContractFuture<'_, ()> {
            panic!("恢复不得删除金库");
        }
    }
    struct Nonce(AtomicBool);
    impl c::AccountNonceSource for Nonce {
        fn account_next_index(
            &self,
            account_id: AccountId32,
            best: VerifiedBlockRef,
        ) -> c::ContractFuture<'_, c::AccountNonce> {
            assert!(self.0.load(Ordering::SeqCst), "恢复不得请求新 nonce");
            Box::pin(async move {
                c::AccountNonce::try_new(&ChainIdentity::citizenchain(), best, account_id, 9)
            })
        }
    }
    impl WalletClock for NoWallet {
        fn now_millis(&self) -> c::ContractResult<u64> {
            Ok(1)
        }
    }
    block_on(async {
        for finalized in [false, true] {
            let store = Arc::new(MemoryHistoryStore::default());
            let history = TransactionHistoryService::new(store.clone(), Arc::new(NoWallet));
            let nonce = Arc::new(Nonce(AtomicBool::new(true)));
            let signer = Arc::new(citizen_signer::Sr25519SoftwareSigner);
            let secret = c::SecretBuffer::try_new(vec![0x71; 32]).unwrap();
            use c::ChainSigner;
            let source =
                AccountId32::from_bytes(*signer.public_key(&secret).await.unwrap().as_bytes());
            let mut client =
                FakeChainClient::new(0, vec![Ok(ExtrinsicWatchEvent::Invalid)], store.clone());
            let built = crate::transaction_builder::TransactionBuilder::new(
                &client,
                nonce.as_ref(),
                signer.as_ref(),
            )
            .build_transfer_with_remark(&secret, source, account(0x72), 1, "resume")
            .await
            .unwrap();
            drop(secret);
            nonce.0.store(false, Ordering::SeqCst);
            client.expected_extrinsic = built.signed().extrinsic().as_bytes().to_vec();
            let hash = signed_extrinsic_hash(
                &client
                    .get_runtime_context_at(built.signed().payload().block())
                    .await
                    .unwrap(),
                built.signed().extrinsic(),
            )
            .unwrap();
            if finalized {
                client.head = 1;
                *client.body.lock().unwrap() = vec![built.signed().extrinsic().as_bytes().to_vec()];
                client.reject_best_runtime = true;
            }
            history.ensure_cursors(&[source], block(0)).await.unwrap();
            let persist = || {
                history.record_pending_before_broadcast(
                    source,
                    hash,
                    9,
                    account(0x72),
                    1,
                    "resume",
                    built.signed().extrinsic().clone(),
                    built.signed().payload().block(),
                    built.signed().payload().runtime_version(),
                    built.signed().payload().genesis_hash(),
                )
            };
            store.fail_before_write.store(true, Ordering::SeqCst);
            assert!(persist().await.is_err());
            assert!(store.snapshot().records().is_empty());
            let runtime = FinalizedHistoryRuntime::new(
                Arc::new(FakeChainClient::new(0, Vec::new(), store.clone())),
                history.clone(),
            );
            let observer: Arc<dyn WalletTransferObserver> = Arc::new(RecordingObserver::default());
            assert!(watch_recorded_transfer(
                &client,
                &runtime,
                &history,
                &AlwaysRunning,
                &observer,
                source,
                hash,
                built.signed().extrinsic().clone()
            )
            .await
            .is_err());
            assert!(
                client.watch_events.lock().unwrap().is_some(),
                "写前失败不得广播"
            );
            store.fail_after_write.store(true, Ordering::SeqCst);
            assert!(persist().await.is_err(), "写后回读也失败，调用者看到中断");
            assert_eq!(
                store.snapshot().records()[0].signed_extrinsic(),
                built.signed().extrinsic()
            );
            let client = Arc::new(client);
            let components = crate::EngineComponents::new(
                Some(client.clone()),
                Some(signer),
                Some(Arc::new(NoWallet)),
                None,
                None,
                Some(Arc::new(NoWallet)),
                Some(store.clone()),
                Some(Arc::new(NoWallet)),
            )
            .with_account_nonce_source(nonce);
            let engine = crate::CitizenEngine::new(components);
            engine
                .update_capabilities(
                    c::CapabilityName::ALL
                        .into_iter()
                        .map(crate::CapabilityProbe::ready)
                        .collect(),
                )
                .unwrap();
            engine.begin_provider_start().unwrap();
            engine.complete_provider_start().await.unwrap();
            let conflict = engine
                .transfer_with_remark_and_watch(
                    source,
                    account(0x72),
                    2,
                    "resume".to_owned(),
                    observer.clone(),
                    crate::WalletTransferCancellation::default(),
                )
                .await
                .unwrap_err();
            assert!(
                matches!(conflict, EngineError::Contract(ref error) if error.code() == ContractErrorCode::Conflict)
            );
            assert!(client.watch_events.lock().unwrap().is_some());
            let result = engine
                .transfer_with_remark_and_watch(
                    source,
                    account(0x72),
                    1,
                    "resume".to_owned(),
                    observer,
                    crate::WalletTransferCancellation::default(),
                )
                .await
                .unwrap();
            assert_eq!(result.transaction_hash(), hash);
            assert_eq!(result.history().records()[0].nonce(), 9);
            if finalized {
                assert!(matches!(
                    result.resolution(),
                    WalletTransferResolution::Finalized(_)
                ));
                assert!(
                    client.watch_events.lock().unwrap().is_some(),
                    "finalized 已证明终态，不能读取 best Runtime 或重广播"
                );
            } else {
                assert!(client.watch_saw_pending.load(Ordering::SeqCst));
                assert!(matches!(
                    result.resolution(),
                    WalletTransferResolution::PoolRejected { .. }
                ));
            }
        }
    });
}

fn account(byte: u8) -> AccountId32 {
    AccountId32::from_bytes([byte; 32])
}

fn hash(byte: u8) -> Hash32 {
    Hash32::from_bytes([byte; 32])
}

fn block(number: u64) -> FinalizedBlockRef {
    let mut bytes = [0_u8; 32];
    bytes[..8].copy_from_slice(&number.to_le_bytes());
    bytes[8..].fill(0x5a);
    FinalizedBlockRef::from_parts(Hash32::from_bytes(bytes), number)
}

fn hex_bytes(value: &str) -> Vec<u8> {
    let value = value.trim().strip_prefix("0x").unwrap_or(value.trim());
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let text = std::str::from_utf8(pair).unwrap();
            u8::from_str_radix(text, 16).unwrap()
        })
        .collect()
}
