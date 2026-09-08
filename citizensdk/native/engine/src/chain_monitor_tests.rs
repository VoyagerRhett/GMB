//! 取消、变更和排空回归：测试真实 Engine 门，不把 future 丢弃当作持久化排空。
#![allow(clippy::unwrap_used, clippy::expect_used)]
use super::*;
use crate::finalized_history_runtime_tests::{running_engine, MemoryHistoryStore};

struct EmptyProfiles;
impl WalletProfileStore for EmptyProfiles {
    fn load(
        &self,
    ) -> citizen_sdk_contracts::ContractFuture<'_, citizen_sdk_contracts::WalletState> {
        Box::pin(async { Ok(citizen_sdk_contracts::WalletState::empty()) })
    }
    fn compare_and_swap(
        &self,
        _: u64,
        _: citizen_sdk_contracts::WalletState,
    ) -> citizen_sdk_contracts::ContractFuture<'_, citizen_sdk_contracts::WalletState> {
        Box::pin(async { panic!("monitor must never mutate wallet profiles") })
    }
}

struct MutableProfiles(Mutex<citizen_sdk_contracts::WalletState>);
impl WalletProfileStore for MutableProfiles {
    fn load(
        &self,
    ) -> citizen_sdk_contracts::ContractFuture<'_, citizen_sdk_contracts::WalletState> {
        Box::pin(async { Ok(self.0.lock().unwrap().clone()) })
    }
    fn compare_and_swap(
        &self,
        _: u64,
        _: citizen_sdk_contracts::WalletState,
    ) -> citizen_sdk_contracts::ContractFuture<'_, citizen_sdk_contracts::WalletState> {
        Box::pin(async { panic!("monitor cannot write profiles") })
    }
}

fn profile_fixture(byte: u8) -> citizen_sdk_contracts::WalletState {
    use citizen_sdk_contracts::{
        citizen_ss58_address, SecretOwner, SecretRef, VaultGeneration, WalletAccount, WalletOrigin,
        WalletState,
    };
    let account = AccountId32::from_bytes([byte; 32]);
    let generation = VaultGeneration::from_bytes([byte; 16]);
    let secret = SecretRef::account_mini_secret(
        0,
        generation,
        SecretOwner::from_bytes([byte + 1; 16]),
        account,
    );
    let account_entry =
        WalletAccount::try_new(0, account, secret, citizen_ss58_address(account), "test", 1)
            .unwrap();
    let profile = WalletProfile::try_new(
        0,
        generation,
        account,
        WalletOrigin::Created,
        1,
        account,
        vec![account_entry],
    )
    .unwrap();
    WalletState::try_from_parts(1, Some(profile), None, None, vec![]).unwrap()
}

#[test]
#[cfg(feature = "history")]
fn account_set_is_reloaded_from_store_after_creation_replacement_and_deletion() {
    let mut engine = running_engine(Arc::new(MemoryHistoryStore::default()), 9);
    let profiles = Arc::new(MutableProfiles(Mutex::new(
        citizen_sdk_contracts::WalletState::empty(),
    )));
    engine.components.wallet_profiles = Some(profiles.clone());
    block_on(engine.start_chain_monitor()).unwrap();
    block_on(engine.poll_chain_monitor()).unwrap();
    for byte in [0x11, 0x22] {
        block_on(engine.with_wallet_monitor_paused(async {
            *profiles.0.lock().unwrap() = profile_fixture(byte);
            Ok(())
        }))
        .unwrap();
        let update = block_on(engine.poll_chain_monitor()).unwrap();
        assert!(update.history_changed());
        assert_eq!(
            engine.chain_monitor.lock().unwrap().accounts,
            vec![AccountId32::from_bytes([byte; 32])]
        );
        assert_eq!(update.finalized_block().unwrap().number(), 9);
    }
    block_on(engine.with_wallet_monitor_paused(async {
        *profiles.0.lock().unwrap() = citizen_sdk_contracts::WalletState::empty();
        Ok(())
    }))
    .unwrap();
    let update = block_on(engine.poll_chain_monitor()).unwrap();
    assert_eq!(update.finalized_block(), None);
    assert!(update.history_changed());
    assert!(engine.chain_monitor.lock().unwrap().accounts.is_empty());
}

#[test]
#[cfg(feature = "history")]
fn empty_profile_is_a_valid_monitor_and_does_not_create_history_cursors() {
    let mut engine = running_engine(Arc::new(MemoryHistoryStore::default()), 9);
    engine.components.wallet_profiles = Some(Arc::new(EmptyProfiles));
    block_on(engine.start_chain_monitor()).unwrap();
    let first = block_on(engine.poll_chain_monitor()).unwrap();
    assert_eq!(first.finalized_block(), None);
    assert_eq!(first.pending_count(), 0);
    assert_eq!(first.history_revision(), 0);
    assert!(first.history_changed());
    assert!(!block_on(engine.poll_chain_monitor())
        .unwrap()
        .history_changed());
    engine.stop_chain_monitor().unwrap();
    block_on(engine.drain_chain_monitor()).unwrap();
    assert!(block_on(engine.poll_chain_monitor()).is_err());
}

#[test]
#[cfg(feature = "history")]
fn idle_wallet_only_reads_local_state_until_finalized_notification_or_new_pending() {
    let (mut engine, reads) =
        crate::finalized_history_runtime_tests::running_engine_with_read_counter(
            Arc::new(MemoryHistoryStore::default()),
            9,
        );
    engine.components.wallet_profiles =
        Some(Arc::new(MutableProfiles(Mutex::new(profile_fixture(0x11)))));
    block_on(engine.start_chain_monitor()).unwrap();
    let first = block_on(engine.poll_chain_monitor()).unwrap();
    // 计数真实 fake-provider 调用，而不只检查缓存标记；空闲不得发出 finalized 读取。
    let count = reads.load(std::sync::atomic::Ordering::SeqCst);
    let before = engine.chain_monitor.lock().unwrap().synced_chain_revision;
    let idle = block_on(engine.poll_chain_monitor()).unwrap();
    assert_eq!(reads.load(std::sync::atomic::Ordering::SeqCst), count);
    assert!(!idle.history_changed());
    assert_eq!(idle.finalized_block(), first.finalized_block());
    assert!(!engine.chain_monitor.lock().unwrap().needs_catchup);
    engine.invalidate_chain_read_cache().unwrap();
    assert!(engine.chain_monitor.lock().unwrap().chain_revision > before);
    block_on(engine.poll_chain_monitor()).unwrap();
    assert!(reads.load(std::sync::atomic::Ordering::SeqCst) > count);
    let state = engine.chain_monitor.lock().unwrap();
    assert_eq!(state.chain_revision, state.synced_chain_revision);
}
use futures::{executor::block_on, FutureExt};

#[test]
#[cfg(feature = "history")]
fn cancellation_wakes_pending_chain_read_without_polling_network() {
    let engine = running_engine(Arc::new(MemoryHistoryStore::default()), 9);
    let (_, guard) = engine
        .prepare_finalized_history_runtime(&[CapabilityName::History])
        .unwrap();
    let mut read = Box::pin(crate::finalized_history_runtime::cancellable_chain(
        std::future::pending::<()>(),
        &guard,
    ));
    assert!(read.as_mut().now_or_never().is_none());
    engine.stop_chain_monitor().unwrap();
    assert!(block_on(read).is_err());
    assert!(engine.drain_chain_monitor().now_or_never().is_none());
    drop(guard);
    block_on(engine.drain_chain_monitor()).unwrap();
}

#[test]
#[cfg(feature = "history")]
fn transfer_cancellation_is_isolated_and_keeps_its_lease_until_drained() {
    let engine = running_engine(Arc::new(MemoryHistoryStore::default()), 9);
    let (_, mut guard) = engine
        .prepare_finalized_history_runtime(&[CapabilityName::History])
        .unwrap();
    let (_, other) = engine
        .prepare_finalized_history_runtime(&[CapabilityName::History])
        .unwrap();
    let token = WalletTransferCancellation::default();
    guard.request_cancellation = Some(token.clone());
    let mut read = Box::pin(crate::finalized_history_runtime::cancellable_chain(
        std::future::pending::<()>(),
        &guard,
    ));
    assert!(read.as_mut().now_or_never().is_none());
    token.cancel();
    assert!(block_on(read).is_err());
    assert!(guard.ensure_current().is_err());
    assert!(other.ensure_current().is_ok());
    assert!(!engine.state.lock().unwrap().history_paused);
    drop(other);
    assert!(
        engine.mark_provider_stopped().is_err(),
        "取消信号不是 lease 退休"
    );
    drop(guard);
    engine.mark_provider_stopped().unwrap();
}

#[test]
#[cfg(feature = "history")]
fn cancelled_wallet_mutation_cannot_reopen_an_explicit_stop() {
    let engine = running_engine(Arc::new(MemoryHistoryStore::default()), 9);
    block_on(engine.start_chain_monitor()).unwrap();
    let (send, receive) = futures::channel::oneshot::channel();
    let mut change = Box::pin(engine.with_wallet_monitor_paused(async {
        receive.await.unwrap();
        Ok(())
    }));
    assert!(change.as_mut().now_or_never().is_none());
    engine.stop_chain_monitor().unwrap();
    send.send(()).unwrap();
    block_on(change).unwrap();
    assert!(engine.state.lock().unwrap().history_paused);
    assert!(!engine.chain_monitor.lock().unwrap().running);
}

#[test]
fn failed_wallet_mutation_reopens_only_its_own_generation() {
    let engine = running_engine(Arc::new(MemoryHistoryStore::default()), 9);
    let old = Arc::clone(&engine.state.lock().unwrap().history_cancel);
    let result: Result<(), EngineError> = block_on(
        engine.with_wallet_monitor_paused(async { Err(lifecycle_error("storage failure")) }),
    );
    assert!(result.is_err());
    let state = engine.state.lock().unwrap();
    assert!(!state.history_paused);
    assert!(old.is_cancelled());
    assert!(!Arc::ptr_eq(&old, &state.history_cancel));
}

#[test]
#[cfg(feature = "history")]
fn wallet_mutation_waits_for_all_old_history_leases() {
    let engine = running_engine(Arc::new(MemoryHistoryStore::default()), 9);
    let (_, guard) = engine
        .prepare_finalized_history_runtime(&[CapabilityName::History])
        .unwrap();
    let entered = std::sync::atomic::AtomicBool::new(false);
    let mut change = Box::pin(engine.with_wallet_monitor_paused(async {
        entered.store(true, std::sync::atomic::Ordering::SeqCst);
        Ok(())
    }));
    assert!(change.as_mut().now_or_never().is_none());
    assert!(!entered.load(std::sync::atomic::Ordering::SeqCst));
    assert!(guard.ensure_current().is_err());
    drop(guard);
    block_on(change).unwrap();
    assert!(entered.load(std::sync::atomic::Ordering::SeqCst));
}
