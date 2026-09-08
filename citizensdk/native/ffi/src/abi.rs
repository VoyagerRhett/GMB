use std::ffi::c_void;

// These C-layout host contracts live beside their validation/tracking logic,
// but remain part of the one public ABI namespace exported by this module.
pub use crate::host_providers::{
    CitizenSdkHostBoolCompletionV1, CitizenSdkHostBoolResultV1, CitizenSdkHostBytesCompletionV1,
    CitizenSdkHostBytesKind, CitizenSdkHostBytesResultV1,
    CitizenSdkHostChainDatabaseCompareAndSwapV1, CitizenSdkHostChainDatabaseLoadV1,
    CitizenSdkHostEncryptedSecretBlobCompareAndSwapV1, CitizenSdkHostEncryptedSecretBlobLoadV1,
    CitizenSdkHostHash32, CitizenSdkHostId128, CitizenSdkHostPublicStoreV1,
    CitizenSdkHostRecordCompletionV1, CitizenSdkHostRecordDomain, CitizenSdkHostRecordResultV1,
    CitizenSdkHostRuntimeCacheDeleteV1, CitizenSdkHostRuntimeCacheLoadV1,
    CitizenSdkHostRuntimeCacheStoreV1, CitizenSdkHostSecretKind, CitizenSdkHostSecretRefV1,
    CitizenSdkHostSecretVaultV1, CitizenSdkHostSecureStoreV1, CitizenSdkHostServicesV1,
    CitizenSdkHostStatusCompletionV1, CitizenSdkHostStatusResultV1,
    CitizenSdkHostTransactionHistoryCompareAndSwapV1, CitizenSdkHostTransactionHistoryLoadV1,
    CitizenSdkHostVaultAvailability, CitizenSdkHostVaultAvailabilityCompletionV1,
    CitizenSdkHostVaultAvailabilityResultV1, CitizenSdkHostVaultAvailabilityV1,
    CitizenSdkHostVaultEnsureWalletKekV1, CitizenSdkHostVaultHasWalletKekV1,
    CitizenSdkHostVaultRetireWalletKekV1, CitizenSdkHostVaultUnwrapDekV1,
    CitizenSdkHostVaultWrapDekV1, CitizenSdkHostWalletKeyRefV1,
    CitizenSdkHostWalletProfileCompareAndSwapV1, CitizenSdkHostWalletProfileLoadV1,
    CitizenSdkMutableBytesView, CITIZENSDK_HOST_DEK_BYTES,
};

pub const CITIZENSDK_ABI_VERSION: u32 = 1;
pub const CITIZENSDK_CAPABILITY_COUNT: usize = 10;

pub type CitizenSdkHandle = u64;
pub type CitizenSdkRequestId = u64;
pub type CitizenSdkResultHandle = u64;
/// SDK-owned, single-use wallet-creation session. Dropping the registry entry
/// drops [`citizen_sdk_engine::PreparedWalletCreation`] and zeroizes its
/// mnemonic/password buffers; it is deliberately not an instance/result ID.
pub type CitizenSdkPreparedWalletHandle = u64;

#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkErrorCode {
    Ok = 0,
    InvalidArgument = 1,
    InvalidHandle = 2,
    InvalidState = 3,
    Unsupported = 4,
    Unavailable = 5,
    NotReady = 6,
    NotFound = 7,
    Conflict = 8,
    Integrity = 9,
    AuthenticationCancelled = 10,
    AuthenticationRequired = 11,
    KeyInvalidated = 12,
    PermissionDenied = 13,
    Storage = 14,
    Network = 15,
    Decode = 16,
    Timeout = 17,
    Busy = 18,
    QueueFull = 19,
    Internal = 20,
    Panic = 21,
    Cancelled = 22,
}

impl CitizenSdkErrorCode {
    pub const fn as_i32(self) -> i32 {
        self as i32
    }
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkLifecycle {
    Created = 1,
    ImportingState = 2,
    Starting = 3,
    Running = 4,
    StartFailed = 5,
    Stopped = 6,
    Disposed = 7,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkFinality {
    Best = 1,
    Finalized = 2,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkCapabilityName {
    ChainRead = 1,
    TransactionBuild = 2,
    TransactionSubmit = 3,
    TransactionVerify = 4,
    WalletProfile = 5,
    LocalSigning = 6,
    HardwareVault = 7,
    UserAuthentication = 8,
    History = 9,
    BackgroundSync = 10,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkCapabilityReason {
    None = 0,
    BuildUnsupported = 1,
    DeviceUnavailable = 2,
    HostDisabled = 3,
    EngineNotRunning = 4,
    DependencyNotReady = 5,
    UserAuthenticationRequired = 6,
    VaultLocked = 7,
    ChainStarting = 8,
    ChainUnsynced = 9,
    StorageUnavailable = 10,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkEventType {
    RequestCompleted = 1,
    WatchUpdate = 2,
    CapabilitiesChanged = 3,
    LifecycleChanged = 4,
    /// 无 payload 的历史失效通知，接收者通过已有历史 API 读取最新状态。
    HistoryChanged = 5,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkResultKind {
    Empty = 0,
    BlockRef = 1,
    StorageValue = 2,
    StorageBatch = 3,
    RuntimeContext = 4,
    ExtrinsicHash = 5,
    ExecutionConclusion = 6,
    WatchEvent = 7,
    ExportedState = 8,
    AccountBalance = 9,
    AccountNonce = 10,
    FeeSnapshot = 11,
    WalletProfile = 12,
    WalletAccounts = 13,
    Signature = 14,
    PreparedWallet = 15,
    WalletTransfer = 16,
    TransactionHistory = 17,
    AccountBalances = 18,
    QrReview = 19,
    QrSigned = 20,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkWalletWordCount {
    Words12 = 12,
    Words18 = 18,
    Words24 = 24,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkWalletOrigin {
    Created = 1,
    Imported = 2,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkHistoryStatus {
    Pending = 1,
    InBlock = 2,
    PoolRejected = 3,
    FinalizedSuccess = 4,
    FinalizedFailed = 5,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkTransferResolution {
    FinalizedSuccess = 1,
    FinalizedFailed = 2,
    PoolRejected = 3,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkTransferDirection {
    Outgoing = 1,
    Incoming = 2,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkWatchStatus {
    Ready = 1,
    Broadcast = 2,
    Future = 3,
    InBlock = 4,
    Finalized = 5,
    Retracted = 6,
    FinalityTimeout = 7,
    Dropped = 8,
    Invalid = 9,
    Usurped = 10,
}

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CitizenSdkExecutionStatus {
    Success = 1,
    Failed = 2,
    Unverified = 3,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct CitizenSdkBytesView {
    pub data: *const u8,
    pub len: u64,
}

/// Portable C representation of one unsigned 128-bit CitizenChain amount.
/// Its numeric value is `high * 2^64 + low`; it is not host-endian byte text.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct CitizenSdkU128 {
    pub low: u64,
    pub high: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, Hash, PartialEq)]
pub struct CitizenSdkAccountId {
    pub bytes: [u8; 32],
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct CitizenSdkCreateOptions {
    pub struct_size: u32,
    pub abi_version: u32,
    pub asset_manifest: CitizenSdkBytesView,
    pub chain_spec: CitizenSdkBytesView,
    pub light_sync_state: CitizenSdkBytesView,
    pub system_name: CitizenSdkBytesView,
    pub system_version: CitizenSdkBytesView,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkBlockRef {
    pub struct_size: u32,
    pub abi_version: u32,
    pub hash: [u8; 32],
    pub number: u64,
    pub finality: u32,
    pub reserved: u32,
}

impl Default for CitizenSdkBlockRef {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            hash: [0; 32],
            number: 0,
            finality: 0,
            reserved: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct CitizenSdkCapabilityStatus {
    pub name: u32,
    pub reason: u32,
    pub supported: u8,
    pub available: u8,
    pub enabled: u8,
    pub ready: u8,
    pub reserved: [u8; 4],
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkCapabilitySnapshot {
    pub struct_size: u32,
    pub abi_version: u32,
    pub revision: u64,
    pub count: u32,
    pub reserved: u32,
    pub statuses: [CitizenSdkCapabilityStatus; CITIZENSDK_CAPABILITY_COUNT],
}

impl Default for CitizenSdkCapabilitySnapshot {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            revision: 0,
            count: CITIZENSDK_CAPABILITY_COUNT as u32,
            reserved: 0,
            statuses: [CitizenSdkCapabilityStatus::default(); CITIZENSDK_CAPABILITY_COUNT],
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkEvent {
    pub struct_size: u32,
    pub abi_version: u32,
    pub event_type: u32,
    pub reserved: u32,
    pub sequence: u64,
    pub request_id: CitizenSdkRequestId,
    pub result: CitizenSdkResultHandle,
    pub capability_revision: u64,
}

pub type CitizenSdkEventCallback =
    Option<unsafe extern "C" fn(context: *mut c_void, event: *const CitizenSdkEvent)>;

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkResultInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub error_code: i32,
    pub kind: u32,
    pub payload_len: u64,
    pub error_message_len: u64,
}

impl Default for CitizenSdkResultInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            error_code: CitizenSdkErrorCode::Ok.as_i32(),
            kind: CitizenSdkResultKind::Empty as u32,
            payload_len: 0,
            error_message_len: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkRuntimeContextInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub block: CitizenSdkBlockRef,
    pub spec_version: u32,
    pub transaction_version: u32,
    pub metadata_len: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkWatchEventInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub status: u32,
    pub peer_count: u32,
    pub has_block: u8,
    pub has_replacement_hash: u8,
    pub reserved: [u8; 6],
    pub block: CitizenSdkBlockRef,
    pub replacement_hash: [u8; 32],
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkExecutionInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub status: u32,
    pub reason_or_dispatch_variant: u32,
    pub has_block: u8,
    pub has_extrinsic_index: u8,
    pub has_module: u8,
    pub reserved: [u8; 5],
    pub block: CitizenSdkBlockRef,
    pub extrinsic_index: u32,
    pub pallet_index: u8,
    pub error_index: u8,
    pub reserved_tail: [u8; 2],
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkExportedStateInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub format_version: u32,
    pub reserved: u32,
    pub finalized: CitizenSdkBlockRef,
    pub database_len: u64,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkAccountBalanceInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub block: CitizenSdkBlockRef,
    pub account_id: CitizenSdkAccountId,
    pub free_fen: CitizenSdkU128,
    pub reserved_fen: CitizenSdkU128,
    pub total_fen: CitizenSdkU128,
}

impl Default for CitizenSdkAccountBalanceInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            block: CitizenSdkBlockRef::default(),
            account_id: CitizenSdkAccountId::default(),
            free_fen: CitizenSdkU128::default(),
            reserved_fen: CitizenSdkU128::default(),
            total_fen: CitizenSdkU128::default(),
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkAccountNonceInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub best_block: CitizenSdkBlockRef,
    pub account_id: CitizenSdkAccountId,
    pub nonce: u64,
}

impl Default for CitizenSdkAccountNonceInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            best_block: CitizenSdkBlockRef::default(),
            account_id: CitizenSdkAccountId::default(),
            nonce: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkFeeSnapshotInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub best_block: CitizenSdkBlockRef,
    pub fee_rate_parts: u32,
    pub reserved: u32,
    pub minimum_fee_fen: CitizenSdkU128,
    pub existential_deposit_fen: CitizenSdkU128,
}

impl Default for CitizenSdkFeeSnapshotInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            best_block: CitizenSdkBlockRef::default(),
            fee_rate_parts: 0,
            reserved: 0,
            minimum_fee_fen: CitizenSdkU128::default(),
            existential_deposit_fen: CitizenSdkU128::default(),
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkWalletProfileInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub present: u32,
    pub origin: u32,
    pub wallet_index: u32,
    pub account_count: u32,
    pub created_at_millis: u64,
    pub master_account_id: CitizenSdkAccountId,
    pub active_account_id: CitizenSdkAccountId,
}

impl Default for CitizenSdkWalletProfileInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            present: 0,
            origin: 0,
            wallet_index: 0,
            account_count: 0,
            created_at_millis: 0,
            master_account_id: CitizenSdkAccountId::default(),
            active_account_id: CitizenSdkAccountId::default(),
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkWalletAccountInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub index: u32,
    pub is_active: u32,
    pub account_id: CitizenSdkAccountId,
    pub created_at_millis: u64,
    pub ss58_address_len: u64,
    pub name_len: u64,
}

impl Default for CitizenSdkWalletAccountInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            index: 0,
            is_active: 0,
            account_id: CitizenSdkAccountId::default(),
            created_at_millis: 0,
            ss58_address_len: 0,
            name_len: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkPreparedWalletInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub prepared_wallet: CitizenSdkPreparedWalletHandle,
}

impl Default for CitizenSdkPreparedWalletInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            prepared_wallet: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkWalletTransferInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub transaction_hash: [u8; 32],
    pub resolution: u32,
    pub has_execution: u32,
    pub execution: CitizenSdkExecutionInfo,
    pub pool_rejection_reason_len: u64,
}

impl Default for CitizenSdkWalletTransferInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            transaction_hash: [0; 32],
            resolution: 0,
            has_execution: 0,
            execution: CitizenSdkExecutionInfo {
                struct_size: std::mem::size_of::<CitizenSdkExecutionInfo>() as u32,
                abi_version: CITIZENSDK_ABI_VERSION,
                status: 0,
                reason_or_dispatch_variant: 0,
                has_block: 0,
                has_extrinsic_index: 0,
                has_module: 0,
                reserved: [0; 5],
                block: CitizenSdkBlockRef::default(),
                extrinsic_index: 0,
                pallet_index: 0,
                error_index: 0,
                reserved_tail: [0; 2],
            },
            pool_rejection_reason_len: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkHistoryInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub revision: u64,
    pub cursor_count: u32,
    pub record_count: u32,
    pub transfer_count: u32,
    pub reserved: u32,
}

impl Default for CitizenSdkHistoryInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            revision: 0,
            cursor_count: 0,
            record_count: 0,
            transfer_count: 0,
            reserved: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkHistoryCursorInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub account_id: CitizenSdkAccountId,
    pub tracking_start_block: CitizenSdkBlockRef,
    pub last_synced_block: CitizenSdkBlockRef,
}

impl Default for CitizenSdkHistoryCursorInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            account_id: CitizenSdkAccountId::default(),
            tracking_start_block: CitizenSdkBlockRef::default(),
            last_synced_block: CitizenSdkBlockRef::default(),
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkHistoryRecordInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub account_id: CitizenSdkAccountId,
    pub transaction_hash: [u8; 32],
    pub nonce: u64,
    pub destination_account_id: CitizenSdkAccountId,
    pub amount_fen: CitizenSdkU128,
    pub status: u32,
    pub has_block: u32,
    pub block: CitizenSdkBlockRef,
    pub has_execution: u32,
    pub reserved: u32,
    pub execution: CitizenSdkExecutionInfo,
    pub created_at_millis: u64,
    pub updated_at_millis: u64,
    pub remark_len: u64,
    pub pool_rejection_reason_len: u64,
}

impl Default for CitizenSdkHistoryRecordInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            account_id: CitizenSdkAccountId::default(),
            transaction_hash: [0; 32],
            nonce: 0,
            destination_account_id: CitizenSdkAccountId::default(),
            amount_fen: CitizenSdkU128::default(),
            status: 0,
            has_block: 0,
            block: CitizenSdkBlockRef::default(),
            has_execution: 0,
            reserved: 0,
            execution: CitizenSdkWalletTransferInfo::default().execution,
            created_at_millis: 0,
            updated_at_millis: 0,
            remark_len: 0,
            pool_rejection_reason_len: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CitizenSdkFinalizedTransferInfo {
    pub struct_size: u32,
    pub abi_version: u32,
    pub tracked_account_id: CitizenSdkAccountId,
    pub from_account_id: CitizenSdkAccountId,
    pub to_account_id: CitizenSdkAccountId,
    pub amount_fen: CitizenSdkU128,
    pub block: CitizenSdkBlockRef,
    pub event_record_index: u32,
    pub has_extrinsic_index: u32,
    pub extrinsic_index: u32,
    pub direction: u32,
    pub source_pallet_len: u64,
    pub remark_display_len: u64,
    pub remark_bytes_len: u64,
}

impl Default for CitizenSdkFinalizedTransferInfo {
    fn default() -> Self {
        Self {
            struct_size: std::mem::size_of::<Self>() as u32,
            abi_version: CITIZENSDK_ABI_VERSION,
            tracked_account_id: CitizenSdkAccountId::default(),
            from_account_id: CitizenSdkAccountId::default(),
            to_account_id: CitizenSdkAccountId::default(),
            amount_fen: CitizenSdkU128::default(),
            block: CitizenSdkBlockRef::default(),
            event_record_index: 0,
            has_extrinsic_index: 0,
            extrinsic_index: 0,
            direction: 0,
            source_pallet_len: 0,
            remark_display_len: 0,
            remark_bytes_len: 0,
        }
    }
}
