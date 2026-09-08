#![cfg(feature = "chain")]

use std::{
    collections::{HashMap, HashSet},
    sync::{
        atomic::{AtomicBool, AtomicUsize, Ordering},
        mpsc::{sync_channel, Receiver, SyncSender},
        Arc, Mutex,
    },
    time::Duration,
};

use citizen_sdk_contracts::{
    AccountId32, AccountNonce, AccountNonceSource, CapabilityName, ChainIdentity, ChainSigner,
    ContractError, ContractErrorCode, ContractFuture, ContractResult, ContractStream,
    EncryptedSecretBlobSnapshot, EncryptedSecretBlobState, EncryptedSecretBlobStore,
    EncryptedSecretEnvelope, ExportedChainState, ExtrinsicWatchEvent, FinalizedBlockRef, Hash32,
    Hash32Bytes, HistoryTransactionStatus, Modules, RuntimeContext, RuntimeVersion, SecretBuffer,
    SecretRef, SecretVault, SignedExtrinsic, StateImportReceipt, SubmittedExtrinsic,
    TransactionHistoryCursor, TransactionHistoryState, TransactionHistoryStore, VaultAvailability,
    VaultGeneration, VerifiedBlockRef, VerifiedChainClient, WalletProfileStore, WalletState,
};
use citizen_sdk_engine::{
    CapabilityProbe, CitizenEngine, EngineComponents, EngineError, WalletTransferResolution,
};
use serde_json::Value as JsonValue;
use subxt_core::{
    config::{substrate::BlakeTwo256, Hasher},
    ext::codec::Decode,
    Metadata,
};
use zeroize::Zeroizing;

const TRANSFER_METADATA_HEX: &str =
    include_str!("../../../test/transaction/citizenchain-runtime-v14-metadata.hex");
const TRANSFER_VECTOR_JSON: &str =
    include_str!("../../../test/transaction/citizenchain-transfer-build-v1.json");
const WALLET_VECTOR_JSON: &str =
    include_str!("../../../test/wallet/citizenchain-wallet-derivation-v1.json");

struct CountingClient {
    reads: AtomicUsize,
    submits: AtomicUsize,
    watches: AtomicUsize,
    block: FinalizedBlockRef,
    best_error: Option<ContractErrorCode>,
}

impl CountingClient {
    fn new() -> Self {
        Self {
            reads: AtomicUsize::new(0),
            submits: AtomicUsize::new(0),
            watches: AtomicUsize::new(0),
            block: FinalizedBlockRef::from_parts(Hash32::from_bytes([0x31; 32]), 31),
            best_error: None,
        }
    }

    fn failing_best(code: ContractErrorCode) -> Self {
        Self {
            best_error: Some(code),
            ..Self::new()
        }
    }
}

impl VerifiedChainClient for CountingClient {
    fn identity(&self) -> ContractFuture<'_, ChainIdentity> {
        Box::pin(async { Ok(ChainIdentity::citizenchain()) })
    }

    fn get_best_head(&self) -> ContractFuture<'_, VerifiedBlockRef> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        let error = self.best_error;
        Box::pin(async move {
            if let Some(code) = error {
                Err(ContractError::new(code, "typed best-head failure"))
            } else {
                Ok(self.block.into())
            }
        })
    }

    fn get_finalized_head(&self) -> ContractFuture<'_, FinalizedBlockRef> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        Box::pin(async move { Ok(self.block) })
    }

    fn get_storage_at(
        &self,
        _block: VerifiedBlockRef,
        key: Vec<u8>,
    ) -> ContractFuture<'_, Option<Vec<u8>>> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        Box::pin(async move { Ok(Some(key)) })
    }

    fn get_storage_batch_at(
        &self,
        _block: VerifiedBlockRef,
        keys: Vec<Vec<u8>>,
    ) -> ContractFuture<'_, Vec<Option<Vec<u8>>>> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        Box::pin(async move { Ok(keys.into_iter().map(Some).collect()) })
    }

    fn get_runtime_context_at(
        &self,
        _block: VerifiedBlockRef,
    ) -> ContractFuture<'_, RuntimeContext> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::Unsupported,
                "not used by this test",
            ))
        })
    }

    fn get_block_extrinsics_at(
        &self,
        _block: VerifiedBlockRef,
    ) -> ContractFuture<'_, Vec<Vec<u8>>> {
        Box::pin(async { Ok(Vec::new()) })
    }

    fn submit_extrinsic(
        &self,
        _extrinsic: SignedExtrinsic,
    ) -> ContractFuture<'_, SubmittedExtrinsic> {
        self.submits.fetch_add(1, Ordering::SeqCst);
        Box::pin(async { Ok(SubmittedExtrinsic::new(Hash32::from_bytes([0x44; 32]))) })
    }

    fn watch_extrinsic(
        &self,
        _extrinsic: SignedExtrinsic,
    ) -> ContractStream<'_, ExtrinsicWatchEvent> {
        self.watches.fetch_add(1, Ordering::SeqCst);
        Box::pin(futures::stream::iter([Ok(ExtrinsicWatchEvent::Ready)]))
    }

    fn export_state(&self) -> ContractFuture<'_, ExportedChainState> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::Unsupported,
                "not used by this test",
            ))
        })
    }

    fn import_state(&self, _state: ExportedChainState) -> ContractFuture<'_, StateImportReceipt> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::Unsupported,
                "not used by this test",
            ))
        })
    }
}

#[test]
fn genesis_hash_is_static_but_still_obeys_module_and_dispose_gates() {
    let client = Arc::new(CountingClient::new());
    let engine = engine(client.clone());
    assert_eq!(
        engine
            .genesis_hash()
            .unwrap_or_else(|error| panic!("genesis failed: {error}")),
        ChainIdentity::citizenchain().genesis_hash()
    );
    assert_eq!(client.reads.load(Ordering::SeqCst), 0);
    engine
        .dispose()
        .unwrap_or_else(|error| panic!("dispose failed: {error}"));
    assert!(engine.genesis_hash().is_err());

    let local = CitizenEngine::new(
        EngineComponents::new(None, None, None, None, None, None, None, None).with_modules(
            Modules::try_new(Modules::WALLET)
                .unwrap_or_else(|error| panic!("modules failed: {error}")),
        ),
    );
    assert!(
        matches!(local.genesis_hash(), Err(EngineError::Contract(error)) if error.code() == ContractErrorCode::Unsupported)
    );
}

#[test]
fn empty_balance_batch_requires_running_chain_and_never_reads_provider() {
    let client = Arc::new(CountingClient::new());
    let engine = engine(client.clone());
    assert!(futures::executor::block_on(engine.finalized_account_balances(Vec::new())).is_err());
    assert_eq!(client.reads.load(Ordering::SeqCst), 0);
    engine
        .begin_provider_start()
        .unwrap_or_else(|error| panic!("start failed: {error}"));
    futures::executor::block_on(engine.complete_provider_start())
        .unwrap_or_else(|error| panic!("complete start failed: {error}"));
    let before = client.reads.load(Ordering::SeqCst);
    assert!(
        futures::executor::block_on(engine.finalized_account_balances(Vec::new()))
            .unwrap_or_else(|error| panic!("empty batch failed: {error}"))
            .is_empty()
    );
    assert_eq!(client.reads.load(Ordering::SeqCst), before);
    engine
        .mark_provider_stopped()
        .unwrap_or_else(|error| panic!("stop failed: {error}"));
    assert!(futures::executor::block_on(engine.finalized_account_balances(Vec::new())).is_err());
    assert_eq!(client.reads.load(Ordering::SeqCst), before);
    engine
        .dispose()
        .unwrap_or_else(|error| panic!("dispose failed: {error}"));
    assert!(futures::executor::block_on(engine.finalized_account_balances(Vec::new())).is_err());
}

#[test]
fn chain_readiness_refresh_preserves_local_facts_and_cannot_open_a_stopped_engine() {
    let client = Arc::new(CountingClient::new());
    let engine = engine(client);
    let before = engine
        .capabilities()
        .unwrap_or_else(|error| panic!("snapshot failed: {error}"))
        .unwrap_or_else(|| panic!("snapshot missing"));
    engine
        .update_chain_readiness(false)
        .unwrap_or_else(|error| panic!("chain update failed: {error}"));
    engine
        .begin_provider_start()
        .unwrap_or_else(|error| panic!("start failed: {error}"));
    futures::executor::block_on(engine.complete_provider_start())
        .unwrap_or_else(|error| panic!("complete start failed: {error}"));
    assert!(futures::executor::block_on(engine.finalized_account_balances(Vec::new())).is_err());
    let ready = engine
        .update_chain_readiness(true)
        .unwrap_or_else(|error| panic!("chain update failed: {error}"));
    assert!(ready
        .status(CapabilityName::ChainRead)
        .is_some_and(|status| status.is_ready()));
    for name in [
        CapabilityName::WalletProfile,
        CapabilityName::LocalSigning,
        CapabilityName::HardwareVault,
        CapabilityName::UserAuthentication,
    ] {
        assert_eq!(ready.status(name), before.status(name));
    }
    engine
        .mark_provider_stopped()
        .unwrap_or_else(|error| panic!("stop failed: {error}"));
    let stopped = engine
        .update_chain_readiness(true)
        .unwrap_or_else(|error| panic!("chain update failed: {error}"));
    assert!(!stopped
        .status(CapabilityName::ChainRead)
        .is_some_and(|status| status.is_ready()));
    assert!(engine.genesis_hash().is_ok());
}

#[test]
fn provider_contract_error_code_survives_the_engine_boundary() {
    let client = Arc::new(CountingClient::failing_best(ContractErrorCode::Timeout));
    let engine = engine(client);
    engine
        .begin_provider_start()
        .unwrap_or_else(|error| panic!("begin start failed: {error}"));
    futures::executor::block_on(engine.complete_provider_start())
        .unwrap_or_else(|error| panic!("complete start failed: {error}"));

    let error = futures::executor::block_on(engine.best_head())
        .err()
        .unwrap_or_else(|| panic!("best head must fail"));
    match error {
        EngineError::Contract(error) => {
            assert_eq!(error.code(), ContractErrorCode::Timeout);
            assert_eq!(error.message(), "typed best-head failure");
        }
        other => panic!("unexpected Engine error: {other}"),
    }
}

fn probes() -> Vec<CapabilityProbe> {
    CapabilityName::ALL
        .into_iter()
        .map(|name| match name {
            CapabilityName::ChainRead
            | CapabilityName::TransactionSubmit
            | CapabilityName::TransactionVerify => CapabilityProbe::ready(name),
            _ => CapabilityProbe {
                name,
                supported: false,
                available: false,
                enabled: false,
                runtime_ready: false,
                not_ready_reason: None,
            },
        })
        .collect()
}

fn engine(client: Arc<CountingClient>) -> CitizenEngine {
    let chain: Arc<dyn VerifiedChainClient> = client;
    let engine = CitizenEngine::new(EngineComponents::new(
        Some(chain),
        None,
        None,
        None,
        None,
        None,
        None,
        None,
    ));
    engine
        .update_capabilities(probes())
        .unwrap_or_else(|error| panic!("capabilities failed: {error}"));
    engine
}

#[test]
fn typed_chain_access_is_closed_before_start_and_open_while_running() {
    let client = Arc::new(CountingClient::new());
    let engine = engine(Arc::clone(&client));

    assert!(futures::executor::block_on(engine.best_head()).is_err());
    assert_eq!(client.reads.load(Ordering::SeqCst), 0);

    engine
        .begin_provider_start()
        .unwrap_or_else(|error| panic!("begin start failed: {error}"));
    futures::executor::block_on(engine.complete_provider_start())
        .unwrap_or_else(|error| panic!("complete start failed: {error}"));

    let best = futures::executor::block_on(engine.best_head())
        .unwrap_or_else(|error| panic!("best head failed: {error}"));
    let finalized = futures::executor::block_on(engine.finalized_head())
        .unwrap_or_else(|error| panic!("finalized head failed: {error}"));
    assert_eq!(best.number(), 31);
    assert_eq!(finalized.number(), 31);

    let values =
        futures::executor::block_on(engine.storage_batch_at(best, vec![vec![1], vec![2], vec![1]]))
            .unwrap_or_else(|error| panic!("batch storage failed: {error}"));
    assert_eq!(values, vec![Some(vec![1]), Some(vec![2]), Some(vec![1])]);

    #[cfg(feature = "transactions")]
    {
        let signed = SignedExtrinsic::try_new(vec![0x08, 0xaa])
            .unwrap_or_else(|error| panic!("extrinsic fixture failed: {error}"));
        let submitted = futures::executor::block_on(engine.submit_signed_extrinsic(signed.clone()))
            .unwrap_or_else(|error| panic!("submit failed: {error}"));
        assert_eq!(submitted.hash(), Hash32::from_bytes([0x44; 32]));

        let mut watch = engine
            .watch_signed_extrinsic(signed)
            .unwrap_or_else(|error| panic!("watch failed: {error}"));
        let event = futures::executor::block_on(futures::StreamExt::next(&mut watch));
        assert_eq!(event, Some(Ok(ExtrinsicWatchEvent::Ready)));
        assert_eq!(client.submits.load(Ordering::SeqCst), 1);
        assert_eq!(client.watches.load(Ordering::SeqCst), 1);
    }

    engine
        .mark_provider_stopped()
        .unwrap_or_else(|error| panic!("stop failed: {error}"));
    let reads_after_stop = client.reads.load(Ordering::SeqCst);
    assert!(futures::executor::block_on(engine.finalized_head()).is_err());
    assert_eq!(client.reads.load(Ordering::SeqCst), reads_after_stop);
}

#[test]
#[cfg(feature = "transactions")]
fn raw_broadcast_entries_cannot_bypass_history_when_any_wallet_component_is_present() {
    let client = Arc::new(CountingClient::new());
    let chain: Arc<dyn VerifiedChainClient> = client.clone();
    let signer: Arc<dyn ChainSigner> = Arc::new(citizen_signer::Sr25519SoftwareSigner);
    let engine = CitizenEngine::new(EngineComponents::new(
        Some(chain),
        Some(signer),
        None,
        None,
        None,
        None,
        None,
        None,
    ));
    engine
        .update_capabilities(probes())
        .unwrap_or_else(|error| panic!("capabilities failed: {error}"));
    engine
        .begin_provider_start()
        .unwrap_or_else(|error| panic!("begin start failed: {error}"));
    futures::executor::block_on(engine.complete_provider_start())
        .unwrap_or_else(|error| panic!("complete start failed: {error}"));

    let signed = SignedExtrinsic::try_new(vec![0x08, 0xbb])
        .unwrap_or_else(|error| panic!("extrinsic fixture failed: {error}"));
    let error = match futures::executor::block_on(engine.submit_signed_extrinsic(signed.clone())) {
        Err(error) => error,
        Ok(_) => panic!("钱包栈不完整时原始提交必须在广播前关闭"),
    };
    assert!(matches!(error, EngineError::CapabilityUnavailable(_)));
    assert_eq!(client.submits.load(Ordering::SeqCst), 0);

    let watch_error = match engine.watch_signed_extrinsic(signed) {
        Err(error) => error,
        Ok(_) => panic!("组合钱包组件后原始 submit-and-watch 必须在广播前关闭"),
    };
    assert_contract_error(watch_error, ContractErrorCode::InvalidState);
    assert_eq!(client.watches.load(Ordering::SeqCst), 0);
}

#[test]
#[cfg(feature = "transactions")]
fn public_nonce_source_does_not_turn_a_chain_client_into_a_wallet() {
    use citizen_sdk_contracts::Modules;
    let client = Arc::new(CountingClient::new());
    let engine = CitizenEngine::new(
        EngineComponents::new(
            Some(client.clone()),
            None,
            None,
            None,
            None,
            None,
            None,
            None,
        )
        .with_modules(Modules::try_new(Modules::CHAIN | Modules::TRANSACTIONS).unwrap())
        .with_account_nonce_source(Arc::new(FixedTransferNonce { value: 7 })),
    );
    engine.update_capabilities(probes()).unwrap();
    engine.begin_provider_start().unwrap();
    futures::executor::block_on(engine.complete_provider_start()).unwrap();
    let signed = SignedExtrinsic::try_new(vec![4, 1]).unwrap();
    futures::executor::block_on(engine.submit_signed_extrinsic(signed.clone())).unwrap();
    let _watch = engine.watch_signed_extrinsic(signed).unwrap();
    assert_eq!(client.submits.load(Ordering::SeqCst), 1);
    assert_eq!(client.watches.load(Ordering::SeqCst), 1);
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum HistoryWriteMode {
    Gated,
    Immediate,
    FailBeforeWrite,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ProviderWatchMode {
    Invalid,
    StreamEnded,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum TransferOrderEvent {
    PendingCasCommitted(Hash32),
    ProviderWatchEntered(Hash32),
}

struct OrderedHistoryStore {
    state: Mutex<TransactionHistoryState>,
    mode: HistoryWriteMode,
    cas_entered: Option<SyncSender<()>>,
    allow_commit: Mutex<Option<Receiver<()>>>,
    gate_pending_once: AtomicBool,
    events: Arc<Mutex<Vec<TransferOrderEvent>>>,
}

impl OrderedHistoryStore {
    fn new(
        mode: HistoryWriteMode,
        events: Arc<Mutex<Vec<TransferOrderEvent>>>,
        account_id: AccountId32,
        start_finalized: FinalizedBlockRef,
    ) -> (Arc<Self>, Option<Receiver<()>>, Option<SyncSender<()>>) {
        let (cas_entered, entered_receiver, allow_commit, commit_receiver) =
            if mode == HistoryWriteMode::Gated {
                let (entered_sender, entered_receiver) = sync_channel(1);
                let (commit_sender, commit_receiver) = sync_channel(1);
                (
                    Some(entered_sender),
                    Some(entered_receiver),
                    Some(commit_sender),
                    Some(commit_receiver),
                )
            } else {
                (None, None, None, None)
            };
        let cursor =
            TransactionHistoryCursor::try_new(account_id, start_finalized, start_finalized)
                .unwrap_or_else(|error| panic!("history cursor fixture failed: {error}"));
        let state = TransactionHistoryState::try_new(0, vec![cursor], Vec::new(), Vec::new())
            .unwrap_or_else(|error| panic!("initial history fixture failed: {error}"));
        (
            Arc::new(Self {
                state: Mutex::new(state),
                mode,
                cas_entered,
                allow_commit: Mutex::new(commit_receiver),
                gate_pending_once: AtomicBool::new(mode == HistoryWriteMode::Gated),
                events,
            }),
            entered_receiver,
            allow_commit,
        )
    }

    fn snapshot(&self) -> TransactionHistoryState {
        self.state
            .lock()
            .unwrap_or_else(|error| panic!("history state poisoned: {error}"))
            .clone()
    }
}

impl TransactionHistoryStore for OrderedHistoryStore {
    fn load(&self) -> ContractFuture<'_, TransactionHistoryState> {
        let state =
            self.state.lock().map(|state| state.clone()).map_err(|_| {
                ContractError::new(ContractErrorCode::Internal, "history state poisoned")
            });
        Box::pin(async move { state })
    }

    fn compare_and_swap(
        &self,
        expected_revision: u64,
        next: TransactionHistoryState,
    ) -> ContractFuture<'_, TransactionHistoryState> {
        Box::pin(async move {
            let pending_hash = match next.records() {
                [record] if matches!(record.status(), HistoryTransactionStatus::Pending) => {
                    Some(record.transaction_hash())
                }
                _ => None,
            };
            if self.mode == HistoryWriteMode::FailBeforeWrite && pending_hash.is_some() {
                return Err(ContractError::new(
                    ContractErrorCode::Storage,
                    "injected history CAS failure before write",
                ));
            }
            if pending_hash.is_some() && self.gate_pending_once.swap(false, Ordering::SeqCst) {
                if let Some(sender) = self.cas_entered.as_ref() {
                    sender.send(()).map_err(|_| {
                        ContractError::new(
                            ContractErrorCode::Internal,
                            "history CAS observer disappeared",
                        )
                    })?;
                    let release = self.allow_commit.lock().map_err(|_| {
                        ContractError::new(
                            ContractErrorCode::Internal,
                            "history CAS release gate poisoned",
                        )
                    })?;
                    release
                        .as_ref()
                        .ok_or_else(|| {
                            ContractError::new(
                                ContractErrorCode::Internal,
                                "history CAS release gate missing",
                            )
                        })?
                        .recv()
                        .map_err(|_| {
                            ContractError::new(
                                ContractErrorCode::Internal,
                                "history CAS release sender disappeared",
                            )
                        })?;
                }
            }
            let mut state = self.state.lock().map_err(|_| {
                ContractError::new(ContractErrorCode::Internal, "history state poisoned")
            })?;
            if state.revision() != expected_revision
                || next.revision() != expected_revision.saturating_add(1)
            {
                return Err(ContractError::new(
                    ContractErrorCode::Conflict,
                    "history revision conflict",
                ));
            }
            *state = next.clone();
            drop(state);
            if let Some(pending_hash) = pending_hash {
                self.events
                    .lock()
                    .map_err(|_| {
                        ContractError::new(ContractErrorCode::Internal, "order log poisoned")
                    })?
                    .push(TransferOrderEvent::PendingCasCommitted(pending_hash));
            }
            Ok(next)
        })
    }
}

struct MemoryTransferProfileStore {
    state: Mutex<WalletState>,
}

impl Default for MemoryTransferProfileStore {
    fn default() -> Self {
        Self {
            state: Mutex::new(WalletState::empty()),
        }
    }
}

impl WalletProfileStore for MemoryTransferProfileStore {
    fn load(&self) -> ContractFuture<'_, WalletState> {
        let state = self.state.lock().map(|state| state.clone()).map_err(|_| {
            ContractError::new(ContractErrorCode::Internal, "wallet profile state poisoned")
        });
        Box::pin(async move { state })
    }

    fn compare_and_swap(
        &self,
        expected_revision: u64,
        next: WalletState,
    ) -> ContractFuture<'_, WalletState> {
        Box::pin(async move {
            let mut state = self.state.lock().map_err(|_| {
                ContractError::new(ContractErrorCode::Internal, "wallet profile state poisoned")
            })?;
            if state.revision() != expected_revision
                || next.revision() != expected_revision.saturating_add(1)
            {
                return Err(ContractError::new(
                    ContractErrorCode::Conflict,
                    "wallet profile revision conflict",
                ));
            }
            *state = next.clone();
            Ok(next)
        })
    }
}

#[derive(Default)]
struct MemoryTransferSecretStore {
    entries: Mutex<HashMap<SecretRef, EncryptedSecretBlobSnapshot>>,
}

impl EncryptedSecretBlobStore for MemoryTransferSecretStore {
    fn load(&self, secret_ref: SecretRef) -> ContractFuture<'_, EncryptedSecretBlobSnapshot> {
        let snapshot = self
            .entries
            .lock()
            .map(|entries| {
                entries
                    .get(&secret_ref)
                    .cloned()
                    .unwrap_or_else(EncryptedSecretBlobSnapshot::empty)
            })
            .map_err(|_| ContractError::new(ContractErrorCode::Internal, "secret state poisoned"));
        Box::pin(async move { snapshot })
    }

    fn compare_and_swap(
        &self,
        secret_ref: SecretRef,
        expected_revision: u64,
        next_state: EncryptedSecretBlobState,
    ) -> ContractFuture<'_, EncryptedSecretBlobSnapshot> {
        Box::pin(async move {
            let mut entries = self.entries.lock().map_err(|_| {
                ContractError::new(ContractErrorCode::Internal, "secret state poisoned")
            })?;
            let current = entries
                .get(&secret_ref)
                .cloned()
                .unwrap_or_else(EncryptedSecretBlobSnapshot::empty);
            if current.revision() != expected_revision {
                return Err(ContractError::new(
                    ContractErrorCode::Conflict,
                    "secret revision conflict",
                ));
            }
            let next = current.try_advance(next_state)?;
            entries.insert(secret_ref, next.clone());
            Ok(next)
        })
    }
}

#[derive(Default)]
struct MemoryTransferVault {
    wallet_keys: Mutex<HashSet<(u32, VaultGeneration)>>,
}

impl SecretVault for MemoryTransferVault {
    fn availability(&self) -> ContractFuture<'_, VaultAvailability> {
        Box::pin(async { Ok(VaultAvailability::Available) })
    }

    fn seal(
        &self,
        _provisioning_operation_id: [u8; 16],
        secret_ref: SecretRef,
        secret: SecretBuffer,
    ) -> ContractFuture<'_, EncryptedSecretEnvelope> {
        Box::pin(async move {
            self.wallet_keys
                .lock()
                .map_err(|_| {
                    ContractError::new(ContractErrorCode::Internal, "vault state poisoned")
                })?
                .insert((secret_ref.wallet_index(), secret_ref.generation()));
            let ciphertext = secret.with_secret(ToOwned::to_owned);
            EncryptedSecretEnvelope::try_new(
                1,
                Hash32Bytes::from_bytes(transfer_secret_digest(secret_ref)),
                ciphertext,
            )
        })
    }

    fn open(
        &self,
        secret_ref: SecretRef,
        envelope: EncryptedSecretEnvelope,
    ) -> ContractFuture<'_, SecretBuffer> {
        Box::pin(async move {
            let has_key = self
                .wallet_keys
                .lock()
                .map_err(|_| {
                    ContractError::new(ContractErrorCode::Internal, "vault state poisoned")
                })?
                .contains(&(secret_ref.wallet_index(), secret_ref.generation()));
            if !has_key
                || envelope.associated_data_digest().as_bytes()
                    != &transfer_secret_digest(secret_ref)
            {
                return Err(ContractError::new(
                    ContractErrorCode::Integrity,
                    "vault envelope identity mismatch",
                ));
            }
            SecretBuffer::try_new(envelope.ciphertext().to_vec())
        })
    }

    fn has_wallet_key(
        &self,
        wallet_index: u32,
        generation: VaultGeneration,
    ) -> ContractFuture<'_, bool> {
        let result = self
            .wallet_keys
            .lock()
            .map(|keys| keys.contains(&(wallet_index, generation)))
            .map_err(|_| ContractError::new(ContractErrorCode::Internal, "vault state poisoned"));
        Box::pin(async move { result })
    }

    fn delete_wallet_key(
        &self,
        _cleanup_operation_id: [u8; 16],
        wallet_index: u32,
        generation: VaultGeneration,
    ) -> ContractFuture<'_, ()> {
        Box::pin(async move {
            self.wallet_keys
                .lock()
                .map_err(|_| {
                    ContractError::new(ContractErrorCode::Internal, "vault state poisoned")
                })?
                .remove(&(wallet_index, generation));
            Ok(())
        })
    }
}

struct FixedTransferNonce {
    value: u64,
}

impl AccountNonceSource for FixedTransferNonce {
    fn account_next_index(
        &self,
        account_id: AccountId32,
        at_best: VerifiedBlockRef,
    ) -> ContractFuture<'_, AccountNonce> {
        let value = self.value;
        Box::pin(async move {
            AccountNonce::try_new(&ChainIdentity::citizenchain(), at_best, account_id, value)
        })
    }
}

#[derive(Clone)]
struct ExpectedTransfer {
    source: AccountId32,
    destination: AccountId32,
    amount_fen: u128,
    remark: String,
    nonce: u64,
}

struct OrderedTransferClient {
    best: VerifiedBlockRef,
    finalized: FinalizedBlockRef,
    context: RuntimeContext,
    history: Arc<OrderedHistoryStore>,
    expected: ExpectedTransfer,
    watch_mode: ProviderWatchMode,
    submits: AtomicUsize,
    watches: AtomicUsize,
    events: Arc<Mutex<Vec<TransferOrderEvent>>>,
}

impl OrderedTransferClient {
    fn validate_watch(&self, extrinsic: &SignedExtrinsic) -> ContractResult<Hash32> {
        let local_hash = provider_extrinsic_hash(&self.context, extrinsic)?;
        let snapshot = self.history.snapshot();
        let record = match snapshot.records() {
            [record] if matches!(record.status(), HistoryTransactionStatus::Pending) => record,
            _ => {
                return Err(ContractError::new(
                    ContractErrorCode::Integrity,
                    "provider watch observed no exact persisted pending record",
                ));
            }
        };
        if snapshot.revision() != 1
            || record.transaction_hash() != local_hash
            || record.account_id() != self.expected.source
            || record.destination_account_id() != self.expected.destination
            || record.amount_fen() != self.expected.amount_fen
            || record.remark() != self.expected.remark.as_str()
            || record.nonce() != self.expected.nonce
        {
            return Err(ContractError::new(
                ContractErrorCode::Integrity,
                "provider watch observed inconsistent pending facts or hash",
            ));
        }
        self.events
            .lock()
            .map_err(|_| ContractError::new(ContractErrorCode::Internal, "order log poisoned"))?
            .push(TransferOrderEvent::ProviderWatchEntered(local_hash));
        Ok(local_hash)
    }
}

impl VerifiedChainClient for OrderedTransferClient {
    fn identity(&self) -> ContractFuture<'_, ChainIdentity> {
        Box::pin(async { Ok(ChainIdentity::citizenchain()) })
    }

    fn get_best_head(&self) -> ContractFuture<'_, VerifiedBlockRef> {
        let best = self.best;
        Box::pin(async move { Ok(best) })
    }

    fn get_finalized_head(&self) -> ContractFuture<'_, FinalizedBlockRef> {
        let finalized = self.finalized;
        Box::pin(async move { Ok(finalized) })
    }

    fn get_storage_at(
        &self,
        _block: VerifiedBlockRef,
        _key: Vec<u8>,
    ) -> ContractFuture<'_, Option<Vec<u8>>> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::Unsupported,
                "transfer ordering test does not read storage",
            ))
        })
    }

    fn get_storage_batch_at(
        &self,
        _block: VerifiedBlockRef,
        _keys: Vec<Vec<u8>>,
    ) -> ContractFuture<'_, Vec<Option<Vec<u8>>>> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::Unsupported,
                "transfer ordering test does not read storage batch",
            ))
        })
    }

    fn get_runtime_context_at(
        &self,
        block: VerifiedBlockRef,
    ) -> ContractFuture<'_, RuntimeContext> {
        let result = if block == self.best {
            Ok(self.context.clone())
        } else {
            Err(ContractError::new(
                ContractErrorCode::Integrity,
                "transfer ordering test received the wrong runtime block",
            ))
        };
        Box::pin(async move { result })
    }

    fn get_block_extrinsics_at(
        &self,
        _block: VerifiedBlockRef,
    ) -> ContractFuture<'_, Vec<Vec<u8>>> {
        Box::pin(async { Ok(Vec::new()) })
    }

    fn submit_extrinsic(
        &self,
        _extrinsic: SignedExtrinsic,
    ) -> ContractFuture<'_, SubmittedExtrinsic> {
        self.submits.fetch_add(1, Ordering::SeqCst);
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::InvalidState,
                "高层钱包测试禁止退回 submit_extrinsic",
            ))
        })
    }

    fn watch_extrinsic(
        &self,
        extrinsic: SignedExtrinsic,
    ) -> ContractStream<'_, ExtrinsicWatchEvent> {
        self.watches.fetch_add(1, Ordering::SeqCst);
        if let Err(error) = self.validate_watch(&extrinsic) {
            return Box::pin(futures::stream::once(async move { Err(error) }));
        }
        match self.watch_mode {
            ProviderWatchMode::Invalid => Box::pin(futures::stream::once(async {
                Ok(ExtrinsicWatchEvent::Invalid)
            })),
            ProviderWatchMode::StreamEnded => Box::pin(futures::stream::empty()),
        }
    }

    fn export_state(&self) -> ContractFuture<'_, ExportedChainState> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::Unsupported,
                "transfer ordering test does not export state",
            ))
        })
    }

    fn import_state(&self, _state: ExportedChainState) -> ContractFuture<'_, StateImportReceipt> {
        Box::pin(async {
            Err(ContractError::new(
                ContractErrorCode::Unsupported,
                "transfer ordering test does not import state",
            ))
        })
    }
}

struct TransferFixture {
    best: VerifiedBlockRef,
    runtime_version: RuntimeVersion,
    source: AccountId32,
    destination: AccountId32,
    amount_fen: u128,
    remark: String,
    nonce: u64,
    mnemonic: String,
    password: String,
}

struct TransferHarness {
    engine: CitizenEngine,
    client: Arc<OrderedTransferClient>,
    history: Arc<OrderedHistoryStore>,
    fixture: TransferFixture,
    cas_entered: Option<Receiver<()>>,
    allow_commit: Option<SyncSender<()>>,
}

fn transfer_harness(
    history_mode: HistoryWriteMode,
    watch_mode: ProviderWatchMode,
) -> TransferHarness {
    let fixture = transfer_fixture();
    let events = Arc::new(Mutex::new(Vec::new()));
    let finalized = FinalizedBlockRef::from_parts(fixture.best.hash(), fixture.best.number());
    let (history, cas_entered, allow_commit) =
        OrderedHistoryStore::new(history_mode, events.clone(), fixture.source, finalized);
    let context = RuntimeContext::try_new(
        fixture.best,
        fixture.runtime_version,
        transfer_metadata_bytes(),
    )
    .unwrap_or_else(|error| panic!("transfer runtime context failed: {error}"));
    let expected = ExpectedTransfer {
        source: fixture.source,
        destination: fixture.destination,
        amount_fen: fixture.amount_fen,
        remark: fixture.remark.clone(),
        nonce: fixture.nonce,
    };
    let client = Arc::new(OrderedTransferClient {
        best: fixture.best,
        finalized,
        context,
        history: history.clone(),
        expected,
        watch_mode,
        submits: AtomicUsize::new(0),
        watches: AtomicUsize::new(0),
        events,
    });
    let signer: Arc<dyn ChainSigner> = Arc::new(citizen_signer::Sr25519SoftwareSigner);
    let vault: Arc<dyn SecretVault> = Arc::new(MemoryTransferVault::default());
    let profiles: Arc<dyn WalletProfileStore> = Arc::new(MemoryTransferProfileStore::default());
    let secrets: Arc<dyn EncryptedSecretBlobStore> = Arc::new(MemoryTransferSecretStore::default());
    let chain: Arc<dyn VerifiedChainClient> = client.clone();
    let history_component: Arc<dyn TransactionHistoryStore> = history.clone();
    let nonce_source: Arc<dyn AccountNonceSource> = Arc::new(FixedTransferNonce {
        value: fixture.nonce,
    });
    let engine = CitizenEngine::new(
        EngineComponents::new(
            Some(chain),
            Some(signer),
            Some(vault),
            None,
            None,
            Some(profiles),
            Some(history_component),
            Some(secrets),
        )
        .with_account_nonce_source(nonce_source),
    );
    engine
        .update_capabilities(transfer_probes())
        .unwrap_or_else(|error| panic!("transfer capabilities failed: {error}"));
    let profile = futures::executor::block_on(
        engine.import_wallet(
            SecretBuffer::try_new(fixture.mnemonic.as_bytes().to_vec())
                .unwrap_or_else(|error| panic!("wallet mnemonic fixture failed: {error}")),
            Zeroizing::new(fixture.password.clone()),
        ),
    )
    .unwrap_or_else(|error| panic!("wallet import fixture failed: {error}"));
    assert_eq!(profile.master_account_id(), fixture.source);
    engine
        .begin_provider_start()
        .unwrap_or_else(|error| panic!("transfer provider start failed: {error}"));
    futures::executor::block_on(engine.complete_provider_start())
        .unwrap_or_else(|error| panic!("transfer provider readiness failed: {error}"));
    TransferHarness {
        engine,
        client,
        history,
        fixture,
        cas_entered,
        allow_commit,
    }
}

fn transfer_probes() -> Vec<CapabilityProbe> {
    CapabilityName::ALL
        .into_iter()
        .map(CapabilityProbe::ready)
        .collect()
}

fn transfer_fixture() -> TransferFixture {
    let transfer_vector: JsonValue = serde_json::from_str(TRANSFER_VECTOR_JSON)
        .unwrap_or_else(|error| panic!("transfer vector failed: {error}"));
    let wallet_vector: JsonValue = serde_json::from_str(WALLET_VECTOR_JSON)
        .unwrap_or_else(|error| panic!("wallet vector failed: {error}"));
    let runtime = &transfer_vector["runtime"];
    let transfer = &transfer_vector["transfer"];
    let first_wallet_case = &wallet_vector["cases"][0];
    let source = AccountId32::from_bytes(fixed_hex(json_string(&transfer["source_account_id"])));
    let wallet_source = AccountId32::from_bytes(fixed_hex(json_string(
        &first_wallet_case["accounts"][0]["account_id"],
    )));
    assert_eq!(
        source, wallet_source,
        "wallet and transfer vectors diverged"
    );
    TransferFixture {
        best: VerifiedBlockRef::best(
            Hash32::from_bytes(fixed_hex(json_string(&runtime["best_block_hash"]))),
            json_u64(&runtime["best_block_number"]),
        ),
        runtime_version: RuntimeVersion::new(
            u32::try_from(json_u64(&runtime["spec_version"]))
                .unwrap_or_else(|_| panic!("spec version exceeds u32")),
            u32::try_from(json_u64(&runtime["transaction_version"]))
                .unwrap_or_else(|_| panic!("transaction version exceeds u32")),
        ),
        source,
        destination: AccountId32::from_bytes(fixed_hex(json_string(
            &transfer["destination_account_id"],
        ))),
        amount_fen: json_string(&transfer["amount_fen"])
            .parse()
            .unwrap_or_else(|error| panic!("transfer amount failed: {error}")),
        remark: json_string(&transfer["remark_utf8"]).to_owned(),
        nonce: json_u64(&runtime["nonce"]),
        mnemonic: json_string(&wallet_vector["mnemonic"]).to_owned(),
        password: json_string(&first_wallet_case["password"]).to_owned(),
    }
}

fn provider_extrinsic_hash(
    context: &RuntimeContext,
    extrinsic: &SignedExtrinsic,
) -> ContractResult<Hash32> {
    let mut cursor = context.metadata();
    let metadata = Metadata::decode(&mut cursor).map_err(|_| {
        ContractError::new(
            ContractErrorCode::Integrity,
            "provider could not decode transfer metadata",
        )
    })?;
    if !cursor.is_empty() {
        return Err(ContractError::new(
            ContractErrorCode::Integrity,
            "provider transfer metadata has trailing bytes",
        ));
    }
    let hasher = BlakeTwo256::new(&metadata);
    Ok(Hash32::from_bytes(
        hasher.hash(extrinsic.as_bytes()).to_fixed_bytes(),
    ))
}

fn transfer_metadata_bytes() -> Vec<u8> {
    let compact = TRANSFER_METADATA_HEX
        .trim()
        .strip_prefix("0x")
        .unwrap_or_else(|| panic!("transfer metadata fixture must use 0x prefix"));
    assert_eq!(compact.len() % 2, 0, "metadata hex length must be even");
    (0..compact.len())
        .step_by(2)
        .map(|offset| {
            u8::from_str_radix(&compact[offset..offset + 2], 16)
                .unwrap_or_else(|error| panic!("metadata hex failed at {offset}: {error}"))
        })
        .collect()
}

fn fixed_hex<const N: usize>(encoded: &str) -> [u8; N] {
    let compact = encoded.strip_prefix("0x").unwrap_or(encoded);
    assert_eq!(compact.len(), N * 2, "expected {N} bytes of hex");
    let mut output = [0_u8; N];
    for (index, byte) in output.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&compact[index * 2..index * 2 + 2], 16)
            .unwrap_or_else(|error| panic!("fixed hex failed at {index}: {error}"));
    }
    output
}

fn json_string(value: &JsonValue) -> &str {
    value
        .as_str()
        .unwrap_or_else(|| panic!("JSON fixture value is not a string"))
}

fn json_u64(value: &JsonValue) -> u64 {
    value
        .as_u64()
        .unwrap_or_else(|| panic!("JSON fixture value is not a u64"))
}

fn transfer_secret_digest(secret_ref: SecretRef) -> [u8; 32] {
    let mut digest = *secret_ref.account_id().as_bytes();
    for (target, source) in digest[..16]
        .iter_mut()
        .zip(secret_ref.generation().as_bytes())
    {
        *target ^= source;
    }
    for (target, source) in digest[16..].iter_mut().zip(secret_ref.owner().as_bytes()) {
        *target ^= source;
    }
    digest[0] ^= secret_ref.wallet_index() as u8;
    digest
}

fn assert_submission_facts(state: &TransactionHistoryState, fixture: &TransferFixture) -> Hash32 {
    let record = match state.records() {
        [record] => record,
        records => panic!("expected one submission record, got {}", records.len()),
    };
    assert_eq!(record.account_id(), fixture.source);
    assert_eq!(record.destination_account_id(), fixture.destination);
    assert_eq!(record.amount_fen(), fixture.amount_fen);
    assert_eq!(record.remark(), fixture.remark.as_str());
    assert_eq!(record.nonce(), fixture.nonce);
    record.transaction_hash()
}

fn assert_contract_error(error: EngineError, expected: ContractErrorCode) {
    match error {
        EngineError::Contract(contract) => assert_eq!(contract.code(), expected),
        other => panic!("expected {expected:?} contract error, got {other:?}"),
    }
}

#[test]
#[cfg(all(
    feature = "wallet",
    feature = "signing",
    feature = "transactions",
    feature = "history"
))]
fn wallet_transfer_commits_pending_before_watch_then_persists_explicit_rejection() {
    let mut harness = transfer_harness(HistoryWriteMode::Gated, ProviderWatchMode::Invalid);
    let entered = harness
        .cas_entered
        .take()
        .unwrap_or_else(|| panic!("gated history observer missing"));
    let release = harness
        .allow_commit
        .take()
        .unwrap_or_else(|| panic!("gated history release missing"));
    let engine = harness.engine;
    let source = harness.fixture.source;
    let destination = harness.fixture.destination;
    let amount_fen = harness.fixture.amount_fen;
    let remark = harness.fixture.remark.clone();
    let transfer = std::thread::spawn(move || {
        futures::executor::block_on(engine.transfer_with_remark(
            source,
            destination,
            amount_fen,
            remark,
        ))
    });

    let cas_was_entered = entered.recv_timeout(Duration::from_secs(5)).is_ok();
    let watches_while_cas_is_blocked = harness.client.watches.load(Ordering::SeqCst);
    let submits_while_cas_is_blocked = harness.client.submits.load(Ordering::SeqCst);
    let revision_while_cas_is_blocked = harness.history.snapshot().revision();
    let release_result = release.send(());
    let completed = transfer
        .join()
        .unwrap_or_else(|_| panic!("transfer worker panicked"))
        .unwrap_or_else(|error| panic!("wallet transfer failed: {error}"));

    assert!(
        cas_was_entered,
        "history CAS did not reach the deterministic gate"
    );
    assert!(
        release_result.is_ok(),
        "history CAS release receiver disappeared"
    );
    assert_eq!(submits_while_cas_is_blocked, 0);
    assert_eq!(watches_while_cas_is_blocked, 0);
    assert_eq!(revision_while_cas_is_blocked, 0);
    let state = harness.history.snapshot();
    let transaction_hash = assert_submission_facts(&state, &harness.fixture);
    assert!(matches!(
        state.records()[0].status(),
        HistoryTransactionStatus::PoolRejected { .. }
    ));
    assert_eq!(completed.transaction_hash(), transaction_hash);
    assert!(matches!(
        completed.resolution(),
        WalletTransferResolution::PoolRejected { .. }
    ));
    assert_eq!(harness.client.submits.load(Ordering::SeqCst), 0);
    assert_eq!(harness.client.watches.load(Ordering::SeqCst), 1);
    assert_eq!(
        *harness
            .client
            .events
            .lock()
            .unwrap_or_else(|error| panic!("order log poisoned: {error}")),
        vec![
            TransferOrderEvent::PendingCasCommitted(transaction_hash),
            TransferOrderEvent::ProviderWatchEntered(transaction_hash),
        ]
    );
}

#[test]
#[cfg(all(
    feature = "wallet",
    feature = "signing",
    feature = "transactions",
    feature = "history"
))]
fn wallet_transfer_never_broadcasts_when_pending_cas_fails_before_write() {
    let harness = transfer_harness(
        HistoryWriteMode::FailBeforeWrite,
        ProviderWatchMode::Invalid,
    );
    let error = futures::executor::block_on(harness.engine.transfer_with_remark(
        harness.fixture.source,
        harness.fixture.destination,
        harness.fixture.amount_fen,
        harness.fixture.remark.clone(),
    ))
    .err()
    .unwrap_or_else(|| panic!("history CAS failure must stop the transfer"));
    assert_contract_error(error, ContractErrorCode::Storage);
    assert_eq!(harness.client.submits.load(Ordering::SeqCst), 0);
    assert_eq!(harness.client.watches.load(Ordering::SeqCst), 0);
    let state = harness.history.snapshot();
    assert_eq!(state.revision(), 0);
    assert!(state.records().is_empty());
    assert!(harness
        .client
        .events
        .lock()
        .unwrap_or_else(|error| panic!("order log poisoned: {error}"))
        .is_empty());
}

#[test]
#[cfg(all(
    feature = "wallet",
    feature = "signing",
    feature = "transactions",
    feature = "history"
))]
fn wallet_transfer_stream_end_preserves_pending_and_same_account_gate() {
    let harness = transfer_harness(HistoryWriteMode::Immediate, ProviderWatchMode::StreamEnded);
    let error = futures::executor::block_on(harness.engine.transfer_with_remark(
        harness.fixture.source,
        harness.fixture.destination,
        harness.fixture.amount_fen,
        harness.fixture.remark.clone(),
    ))
    .err()
    .unwrap_or_else(|| panic!("提前结束的 watch 流必须返回可重试错误"));
    assert_contract_error(error, ContractErrorCode::Network);
    assert_eq!(harness.client.submits.load(Ordering::SeqCst), 0);
    assert_eq!(harness.client.watches.load(Ordering::SeqCst), 1);
    let state = harness.history.snapshot();
    let pending_hash = assert_submission_facts(&state, &harness.fixture);
    assert!(matches!(
        state.records()[0].status(),
        HistoryTransactionStatus::Pending
    ));
    assert_eq!(
        *harness
            .client
            .events
            .lock()
            .unwrap_or_else(|error| panic!("order log poisoned: {error}")),
        vec![
            TransferOrderEvent::PendingCasCommitted(pending_hash),
            TransferOrderEvent::ProviderWatchEntered(pending_hash),
        ]
    );

    let second_error = futures::executor::block_on(harness.engine.transfer_with_remark(
        harness.fixture.source,
        harness.fixture.destination,
        harness.fixture.amount_fen.saturating_add(1),
        "different transaction must remain gated".to_owned(),
    ))
    .err()
    .unwrap_or_else(|| panic!("同账户第二笔交易必须被 durable Pending 门拒绝"));
    assert_contract_error(second_error, ContractErrorCode::Conflict);
    assert_eq!(harness.client.submits.load(Ordering::SeqCst), 0);
    assert_eq!(harness.client.watches.load(Ordering::SeqCst), 1);
}
