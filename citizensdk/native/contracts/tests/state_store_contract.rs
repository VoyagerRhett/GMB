//! 五类数据仓储的强类型、对象安全和钱包公开状态合同。

use std::{
    future::Future,
    task::{Context, Poll, Waker},
};

use citizen_sdk_contracts::{
    citizen_ss58_address, parse_citizen_ss58_address, AccountId32, ChainDatabaseSnapshot,
    ChainDatabaseStore, ColdWalletAccount, ContractFuture, ContractResult,
    EncryptedSecretBlobSnapshot, EncryptedSecretBlobState, EncryptedSecretBlobStore,
    EncryptedSecretEnvelope, Hash32, Hash32Bytes, RuntimeCacheStore, RuntimeContext,
    RuntimeVersion, SecretOwner, SecretRef, TransactionHistoryState, TransactionHistoryStore,
    VaultGeneration, VerifiedBlockRef, WalletAccount, WalletCleanupPlan, WalletOrigin,
    WalletProfile, WalletProfileStore, WalletProvisioningPlan, WalletSignMode, WalletState,
};

fn block_on<F: Future>(future: F) -> F::Output {
    let waker = Waker::noop();
    let mut context = Context::from_waker(waker);
    let mut future = std::pin::pin!(future);
    loop {
        match future.as_mut().poll(&mut context) {
            Poll::Ready(output) => return output,
            Poll::Pending => std::thread::yield_now(),
        }
    }
}

fn value_or_panic<T>(result: ContractResult<T>) -> T {
    match result {
        Ok(value) => value,
        Err(error) => panic!("合同调用失败: {error}"),
    }
}

struct MemoryChainDatabase;

impl ChainDatabaseStore for MemoryChainDatabase {
    fn load(&self) -> ContractFuture<'_, ChainDatabaseSnapshot> {
        Box::pin(async { Ok(ChainDatabaseSnapshot::new(0, None)) })
    }

    fn compare_and_swap(
        &self,
        expected_revision: u64,
        state: Option<citizen_sdk_contracts::ExportedChainState>,
    ) -> ContractFuture<'_, ChainDatabaseSnapshot> {
        Box::pin(async move { Ok(ChainDatabaseSnapshot::new(expected_revision + 1, state)) })
    }
}

struct MemoryRuntimeCache;

impl RuntimeCacheStore for MemoryRuntimeCache {
    fn load(&self, _block_hash: Hash32) -> ContractFuture<'_, Option<RuntimeContext>> {
        Box::pin(async { Ok(None) })
    }

    fn store(&self, _context: RuntimeContext) -> ContractFuture<'_, ()> {
        Box::pin(async { Ok(()) })
    }

    fn delete(&self, _block_hash: Hash32) -> ContractFuture<'_, ()> {
        Box::pin(async { Ok(()) })
    }
}

struct MemoryWalletProfiles;

impl WalletProfileStore for MemoryWalletProfiles {
    fn load(&self) -> ContractFuture<'_, WalletState> {
        Box::pin(async { Ok(WalletState::empty()) })
    }

    fn compare_and_swap(
        &self,
        _expected_revision: u64,
        next: WalletState,
    ) -> ContractFuture<'_, WalletState> {
        Box::pin(async move { Ok(next) })
    }
}

struct MemoryHistory;

impl TransactionHistoryStore for MemoryHistory {
    fn load(&self) -> ContractFuture<'_, TransactionHistoryState> {
        Box::pin(async { TransactionHistoryState::try_new(0, Vec::new()) })
    }

    fn compare_and_swap(
        &self,
        _expected_revision: u64,
        next: TransactionHistoryState,
    ) -> ContractFuture<'_, TransactionHistoryState> {
        Box::pin(async move { Ok(next) })
    }
}

struct MemoryEncryptedBlobs;

impl EncryptedSecretBlobStore for MemoryEncryptedBlobs {
    fn load(&self, _secret_ref: SecretRef) -> ContractFuture<'_, EncryptedSecretBlobSnapshot> {
        Box::pin(async { Ok(EncryptedSecretBlobSnapshot::empty()) })
    }

    fn compare_and_swap(
        &self,
        _secret_ref: SecretRef,
        expected_revision: u64,
        next: EncryptedSecretBlobState,
    ) -> ContractFuture<'_, EncryptedSecretBlobSnapshot> {
        Box::pin(async move {
            let current = EncryptedSecretBlobSnapshot::empty();
            if current.revision() != expected_revision {
                return Err(citizen_sdk_contracts::ContractError::new(
                    citizen_sdk_contracts::ContractErrorCode::Conflict,
                    "测试 revision 冲突",
                ));
            }
            current.try_advance(next)
        })
    }
}

fn secret_ref(index: u32, account_byte: u8) -> SecretRef {
    SecretRef::account_mini_secret(
        0,
        VaultGeneration::from_bytes([1; 16]),
        SecretOwner::from_bytes([index as u8; 16]),
        AccountId32::from_bytes([account_byte; 32]),
    )
}

fn secret_ref_for(generation: u8, owner: u8, account_byte: u8) -> SecretRef {
    SecretRef::account_mini_secret(
        0,
        VaultGeneration::from_bytes([generation; 16]),
        SecretOwner::from_bytes([owner; 16]),
        AccountId32::from_bytes([account_byte; 32]),
    )
}

#[test]
fn encrypted_blob_persisted_parts_accept_only_reachable_revisions() {
    let envelope = value_or_panic(EncryptedSecretEnvelope::try_new(
        1,
        Hash32Bytes::from_bytes([7; 32]),
        vec![9; 48],
    ));
    assert!(EncryptedSecretBlobSnapshot::try_from_persisted_parts(
        0,
        EncryptedSecretBlobState::Vacant,
    )
    .is_ok());
    assert!(EncryptedSecretBlobSnapshot::try_from_persisted_parts(
        1,
        EncryptedSecretBlobState::Sealed {
            provisioning_operation_id: [1; 16],
            envelope,
        },
    )
    .is_ok());
    assert!(EncryptedSecretBlobSnapshot::try_from_persisted_parts(
        2,
        EncryptedSecretBlobState::Tombstone {
            cleanup_operation_id: [2; 16],
        },
    )
    .is_ok());
    assert!(EncryptedSecretBlobSnapshot::try_from_persisted_parts(
        1,
        EncryptedSecretBlobState::Vacant,
    )
    .is_err());
    assert!(EncryptedSecretBlobSnapshot::try_from_persisted_parts(
        2,
        EncryptedSecretBlobState::Sealed {
            provisioning_operation_id: [1; 16],
            envelope: value_or_panic(EncryptedSecretEnvelope::try_new(
                1,
                Hash32Bytes::from_bytes([7; 32]),
                vec![9; 48],
            )),
        },
    )
    .is_err());
    assert!(EncryptedSecretBlobSnapshot::try_from_persisted_parts(
        3,
        EncryptedSecretBlobState::Tombstone {
            cleanup_operation_id: [2; 16],
        },
    )
    .is_err());
}

fn wallet_account(index: u32, owner: u8, account_byte: u8) -> WalletAccount {
    value_or_panic(WalletAccount::try_new(
        index,
        AccountId32::from_bytes([account_byte; 32]),
        secret_ref_for(1, owner, account_byte),
        citizen_ss58_address(AccountId32::from_bytes([account_byte; 32])),
        format!("account-{index}"),
        100 + u64::from(index),
    ))
}

fn wallet_profile(accounts: Vec<WalletAccount>) -> WalletProfile {
    let master = AccountId32::from_bytes([4; 32]);
    value_or_panic(WalletProfile::try_new(
        0,
        VaultGeneration::from_bytes([1; 16]),
        master,
        WalletOrigin::Created,
        100,
        master,
        accounts,
    ))
}

#[test]
fn five_store_traits_are_separate_object_safe_boundaries() {
    let chain: Box<dyn ChainDatabaseStore> = Box::new(MemoryChainDatabase);
    let runtime: Box<dyn RuntimeCacheStore> = Box::new(MemoryRuntimeCache);
    let wallet: Box<dyn WalletProfileStore> = Box::new(MemoryWalletProfiles);
    let history: Box<dyn TransactionHistoryStore> = Box::new(MemoryHistory);
    let blobs: Box<dyn EncryptedSecretBlobStore> = Box::new(MemoryEncryptedBlobs);

    assert_eq!(value_or_panic(block_on(chain.load())).revision(), 0);
    assert!(value_or_panic(block_on(runtime.load(Hash32::from_bytes([2; 32])))).is_none());
    assert_eq!(value_or_panic(block_on(wallet.load())).revision(), 0);
    assert_eq!(value_or_panic(block_on(history.load())).revision(), 0);
    assert!(value_or_panic(block_on(blobs.load(secret_ref(3, 4))))
        .envelope()
        .is_none());
}

#[test]
fn citizen_ss58_profile_address_matches_the_existing_wallet_golden_vector() {
    let account_id = AccountId32::from_bytes([
        0x2a, 0xfb, 0xa9, 0x27, 0x8e, 0x30, 0xcc, 0xf6, 0xa6, 0xce, 0xb3, 0xa8, 0xb6, 0xe3, 0x36,
        0xb7, 0x00, 0x68, 0xf0, 0x45, 0xc6, 0x66, 0xf2, 0xe7, 0xf4, 0xf9, 0xcc, 0x5f, 0x47, 0xdb,
        0x89, 0x72,
    ]);
    assert_eq!(
        citizen_ss58_address(account_id),
        "w5CZACAABUbK4jspzPB5be9trhtSgRCRZFafGe7kvFPvxq8M2"
    );
    let secret_ref = SecretRef::account_mini_secret(
        0,
        VaultGeneration::from_bytes([1; 16]),
        SecretOwner::from_bytes([2; 16]),
        account_id,
    );
    assert!(WalletAccount::try_new(0, account_id, secret_ref, "wrong", "", 0).is_err());

    let encoded = citizen_ss58_address(account_id);
    assert_eq!(
        value_or_panic(parse_citizen_ss58_address(&encoded)),
        account_id
    );
    assert!(parse_citizen_ss58_address(&format!("{encoded}1")).is_err());
    assert!(
        parse_citizen_ss58_address("5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXQaE4iAqYvFfu").is_err()
    );
}

#[test]
fn unified_wallet_catalog_requires_exact_unique_hot_and_cold_order() {
    let hot = wallet_profile(vec![wallet_account(0, 3, 4)]);
    let hot_id = hot.master_account_id();
    let cold_id = AccountId32::from_bytes([9; 32]);
    let cold = value_or_panic(ColdWalletAccount::try_new(
        1,
        cold_id,
        citizen_ss58_address(cold_id),
        " 冷账户 ",
        200,
    ));
    let state = value_or_panic(WalletState::try_from_catalog_parts(
        7,
        Some(hot.clone()),
        vec![cold.clone()],
        vec![cold_id, hot_id],
        2,
        None,
        None,
        Vec::new(),
    ));
    assert_eq!(state.default_account_id(), Some(cold_id));
    assert_eq!(state.account_sign_mode(hot_id), Some(WalletSignMode::Hot));
    assert_eq!(state.account_sign_mode(cold_id), Some(WalletSignMode::Cold));
    assert_eq!(state.cold_account_by_index(1), Some(&cold));
    assert_eq!(cold.name(), "冷账户");

    for invalid_order in [
        vec![hot_id],
        vec![cold_id, cold_id],
        vec![cold_id, hot_id, AccountId32::from_bytes([8; 32])],
    ] {
        assert!(WalletState::try_from_catalog_parts(
            7,
            Some(hot.clone()),
            vec![cold.clone()],
            invalid_order,
            2,
            None,
            None,
            Vec::new(),
        )
        .is_err());
    }

    let duplicates_hot = value_or_panic(ColdWalletAccount::try_new(
        1,
        hot_id,
        citizen_ss58_address(hot_id),
        "重复",
        200,
    ));
    assert!(WalletState::try_from_catalog_parts(
        7,
        Some(hot),
        vec![duplicates_hot],
        vec![hot_id],
        2,
        None,
        None,
        Vec::new(),
    )
    .is_err());

    assert!(WalletState::try_from_catalog_parts(
        7,
        None,
        vec![cold.clone()],
        vec![cold_id],
        1,
        None,
        None,
        Vec::new(),
    )
    .is_err());
    assert!(
        ColdWalletAccount::try_new(0, cold_id, citizen_ss58_address(cold_id), "非法", 200,)
            .is_err()
    );
}

#[test]
fn wallet_profile_rejects_duplicate_or_cross_generation_secret_refs() {
    let generation = VaultGeneration::from_bytes([1; 16]);
    let first_id = AccountId32::from_bytes([4; 32]);
    let first = value_or_panic(WalletAccount::try_new(
        0,
        first_id,
        secret_ref(1, 4),
        citizen_ss58_address(first_id),
        "first",
        100,
    ));
    let duplicate_index = value_or_panic(WalletAccount::try_new(
        0,
        AccountId32::from_bytes([5; 32]),
        secret_ref(2, 5),
        citizen_ss58_address(AccountId32::from_bytes([5; 32])),
        "second",
        101,
    ));
    assert!(WalletProfile::try_new(
        0,
        generation,
        first_id,
        WalletOrigin::Created,
        100,
        first_id,
        vec![first.clone(), duplicate_index],
    )
    .is_err());

    let foreign_ref = SecretRef::account_mini_secret(
        1,
        generation,
        SecretOwner::from_bytes([3; 16]),
        AccountId32::from_bytes([6; 32]),
    );
    let foreign = value_or_panic(WalletAccount::try_new(
        1,
        AccountId32::from_bytes([6; 32]),
        foreign_ref,
        citizen_ss58_address(AccountId32::from_bytes([6; 32])),
        "foreign",
        102,
    ));
    assert!(WalletProfile::try_new(
        0,
        generation,
        first_id,
        WalletOrigin::Created,
        100,
        first_id,
        vec![first.clone(), foreign],
    )
    .is_err());

    let foreign_generation_ref = SecretRef::account_mini_secret(
        0,
        VaultGeneration::from_bytes([2; 16]),
        SecretOwner::from_bytes([4; 16]),
        AccountId32::from_bytes([7; 32]),
    );
    let foreign_generation = value_or_panic(WalletAccount::try_new(
        1,
        AccountId32::from_bytes([7; 32]),
        foreign_generation_ref,
        citizen_ss58_address(AccountId32::from_bytes([7; 32])),
        "generation",
        103,
    ));
    assert!(WalletProfile::try_new(
        0,
        generation,
        first_id,
        WalletOrigin::Created,
        100,
        first_id,
        vec![first, foreign_generation],
    )
    .is_err());
}

#[test]
fn wallet_profile_requires_account_zero_master_and_bounded_indices() {
    let generation = VaultGeneration::from_bytes([1; 16]);
    let master = AccountId32::from_bytes([4; 32]);
    let wrong_anchor = value_or_panic(WalletAccount::try_new(
        1,
        master,
        secret_ref(1, 4),
        citizen_ss58_address(master),
        "master",
        100,
    ));
    assert!(WalletProfile::try_new(
        0,
        generation,
        master,
        WalletOrigin::Created,
        100,
        master,
        vec![wrong_anchor],
    )
    .is_err());

    let wrong_zero_id = AccountId32::from_bytes([5; 32]);
    let wrong_zero = value_or_panic(WalletAccount::try_new(
        0,
        wrong_zero_id,
        secret_ref(2, 5),
        citizen_ss58_address(wrong_zero_id),
        "wrong-zero",
        100,
    ));
    assert!(WalletProfile::try_new(
        0,
        generation,
        master,
        WalletOrigin::Created,
        100,
        wrong_zero_id,
        vec![wrong_zero],
    )
    .is_err());

    let valid_zero = value_or_panic(WalletAccount::try_new(
        0,
        master,
        secret_ref(3, 4),
        citizen_ss58_address(master),
        "master",
        100,
    ));
    let maximum_id = AccountId32::from_bytes([6; 32]);
    let maximum = value_or_panic(WalletAccount::try_new(
        1989,
        maximum_id,
        secret_ref(4, 6),
        citizen_ss58_address(maximum_id),
        "maximum",
        101,
    ));
    assert!(WalletProfile::try_new(
        0,
        generation,
        master,
        WalletOrigin::Created,
        100,
        maximum_id,
        vec![valid_zero.clone(), maximum],
    )
    .is_ok());

    let too_high = value_or_panic(WalletAccount::try_new(
        1990,
        maximum_id,
        secret_ref(5, 6),
        citizen_ss58_address(maximum_id),
        "too-high",
        100,
    ));
    assert!(WalletProfile::try_new(
        0,
        generation,
        master,
        WalletOrigin::Created,
        100,
        master,
        vec![valid_zero, too_high],
    )
    .is_err());
}

#[test]
fn wallet_state_accepts_exact_create_and_append_provisioning() {
    let account_zero = wallet_account(0, 3, 4);
    let created_profile = wallet_profile(vec![account_zero.clone()]);
    let create = value_or_panic(WalletProvisioningPlan::try_new(
        [1; 16],
        0,
        VaultGeneration::from_bytes([1; 16]),
        None,
        vec![account_zero.secret_ref()],
        true,
    ));
    assert!(WalletState::try_from_parts(
        1,
        Some(created_profile.clone()),
        Some(create),
        None,
        Vec::new(),
    )
    .is_ok());

    let added = wallet_account(1, 2, 5);
    let expanded_profile = wallet_profile(vec![account_zero, added.clone()]);
    let append = value_or_panic(WalletProvisioningPlan::try_new(
        [2; 16],
        0,
        VaultGeneration::from_bytes([1; 16]),
        Some(created_profile),
        vec![added.secret_ref()],
        false,
    ));
    assert!(
        WalletState::try_from_parts(2, Some(expanded_profile), Some(append), None, Vec::new(),)
            .is_ok()
    );
}

#[test]
fn wallet_state_accepts_exact_import_provisioning() {
    let account_zero = wallet_account(0, 3, 4);
    let master = AccountId32::from_bytes([4; 32]);
    let imported_profile = value_or_panic(WalletProfile::try_new(
        0,
        VaultGeneration::from_bytes([1; 16]),
        master,
        WalletOrigin::Imported,
        100,
        master,
        vec![account_zero.clone()],
    ));
    assert_eq!(imported_profile.origin(), WalletOrigin::Imported);

    let import = value_or_panic(WalletProvisioningPlan::try_new(
        [3; 16],
        0,
        VaultGeneration::from_bytes([1; 16]),
        None,
        vec![account_zero.secret_ref()],
        true,
    ));
    assert!(
        WalletState::try_from_parts(1, Some(imported_profile), Some(import), None, Vec::new(),)
            .is_ok()
    );
}

#[test]
fn wallet_state_rejects_incomplete_or_misattributed_provisioning() {
    let account_zero = wallet_account(0, 3, 4);
    let created_profile = wallet_profile(vec![account_zero.clone()]);
    let no_wallet_key_rollback = value_or_panic(WalletProvisioningPlan::try_new(
        [1; 16],
        0,
        VaultGeneration::from_bytes([1; 16]),
        None,
        vec![account_zero.secret_ref()],
        false,
    ));
    assert!(WalletState::try_from_parts(
        1,
        Some(created_profile.clone()),
        Some(no_wallet_key_rollback),
        None,
        Vec::new(),
    )
    .is_err());

    let added = wallet_account(1, 2, 5);
    let expanded_profile = wallet_profile(vec![account_zero.clone(), added.clone()]);
    let previous_is_not_a_strict_prefix = value_or_panic(WalletProvisioningPlan::try_new(
        [2; 16],
        0,
        VaultGeneration::from_bytes([1; 16]),
        Some(expanded_profile.clone()),
        vec![added.secret_ref()],
        false,
    ));
    assert!(WalletState::try_from_parts(
        2,
        Some(expanded_profile.clone()),
        Some(previous_is_not_a_strict_prefix),
        None,
        Vec::new(),
    )
    .is_err());

    let wrong_secret_set = value_or_panic(WalletProvisioningPlan::try_new(
        [3; 16],
        0,
        VaultGeneration::from_bytes([1; 16]),
        Some(created_profile),
        vec![account_zero.secret_ref(), added.secret_ref()],
        false,
    ));
    assert!(WalletState::try_from_parts(
        2,
        Some(expanded_profile),
        Some(wrong_secret_set),
        None,
        Vec::new(),
    )
    .is_err());
}

#[test]
fn cleanup_never_targets_current_wallet_and_physical_targets_do_not_overlap() {
    let current = wallet_profile(vec![wallet_account(0, 3, 4)]);
    let current_secret = current.accounts()[0].secret_ref();
    let targets_current_secret = value_or_panic(WalletCleanupPlan::try_new(
        [1; 16],
        0,
        VaultGeneration::from_bytes([1; 16]),
        vec![current_secret],
        false,
    ));
    assert!(WalletState::try_from_parts(
        1,
        Some(current.clone()),
        None,
        Some(targets_current_secret),
        Vec::new(),
    )
    .is_err());

    let old_ref = secret_ref_for(2, 8, 8);
    let non_current_same_generation_ref = secret_ref_for(1, 8, 8);
    let deletes_current_wallet_key = value_or_panic(WalletCleanupPlan::try_new(
        [2; 16],
        0,
        VaultGeneration::from_bytes([1; 16]),
        vec![non_current_same_generation_ref],
        true,
    ));
    assert!(WalletState::try_from_parts(
        1,
        Some(current.clone()),
        None,
        Some(deletes_current_wallet_key),
        Vec::new(),
    )
    .is_err());

    let first = value_or_panic(WalletCleanupPlan::try_new(
        [3; 16],
        0,
        VaultGeneration::from_bytes([2; 16]),
        vec![old_ref],
        true,
    ));
    let duplicate_target = value_or_panic(WalletCleanupPlan::try_new(
        [4; 16],
        0,
        VaultGeneration::from_bytes([2; 16]),
        vec![old_ref],
        false,
    ));
    assert!(WalletState::try_from_parts(
        1,
        Some(current.clone()),
        None,
        Some(first.clone()),
        vec![duplicate_target],
    )
    .is_err());
    assert!(WalletState::try_from_parts(1, Some(current), None, Some(first), Vec::new()).is_ok());
}

#[test]
fn cleanup_contract_requires_exact_nonempty_bounded_plans() {
    assert!(WalletCleanupPlan::try_new(
        [1; 16],
        0,
        VaultGeneration::from_bytes([2; 16]),
        Vec::new(),
        true,
    )
    .is_err());

    let without_wallet_key = value_or_panic(WalletCleanupPlan::try_new(
        [2; 16],
        0,
        VaultGeneration::from_bytes([2; 16]),
        vec![secret_ref_for(2, 2, 2)],
        false,
    ));
    assert!(
        WalletState::try_from_parts(1, None, None, Some(without_wallet_key), Vec::new(),).is_err()
    );

    let queue: Vec<_> = (1_u8..=65)
        .map(|id| {
            value_or_panic(WalletCleanupPlan::try_new(
                [id; 16],
                0,
                VaultGeneration::from_bytes([2; 16]),
                vec![secret_ref_for(2, id, id)],
                false,
            ))
        })
        .collect();
    assert!(WalletState::try_from_parts(1, None, None, None, queue).is_err());
}

#[test]
fn runtime_cache_value_carries_its_exact_block_identity() {
    let block = VerifiedBlockRef::finalized(Hash32::from_bytes([9; 32]), 88);
    let context = value_or_panic(RuntimeContext::try_new(
        block,
        RuntimeVersion::new(17, 3),
        vec![1, 2, 3],
    ));
    assert_eq!(context.block(), block);
    assert_eq!(context.version().spec_version(), 17);
}

#[test]
fn encrypted_secret_tombstone_is_a_permanent_late_writer_fence() {
    let envelope = value_or_panic(EncryptedSecretEnvelope::try_new(
        1,
        Hash32Bytes::from_bytes([0x11; 32]),
        vec![0x22; 32],
    ));
    let sealed = value_or_panic(EncryptedSecretBlobSnapshot::empty().try_advance(
        EncryptedSecretBlobState::Sealed {
            provisioning_operation_id: [0x33; 16],
            envelope: envelope.clone(),
        },
    ));
    assert_eq!(sealed.envelope(), Some(&envelope));
    assert!(sealed
        .try_advance(EncryptedSecretBlobState::Sealed {
            provisioning_operation_id: [0x44; 16],
            envelope: envelope.clone(),
        })
        .is_err());

    let tombstone = value_or_panic(sealed.try_advance(EncryptedSecretBlobState::Tombstone {
        cleanup_operation_id: [0x55; 16],
    }));
    assert!(tombstone.is_tombstone());
    assert!(tombstone
        .try_advance(EncryptedSecretBlobState::Sealed {
            provisioning_operation_id: [0x33; 16],
            envelope,
        })
        .is_err());
}
