//! CitizenSDK Core 的类型化依赖合同。
//!
//! 本 crate 不实现业务，只冻结 Engine 与轻节点、签名器、系统金库及各类持久化之间的
//! 语义边界。公开 trait 均为对象安全接口，不能把 Flutter、具体异步运行时或任意 RPC
//! 方法泄漏到 Core。

#![forbid(unsafe_code)]

use std::{future::Future, pin::Pin};

use futures_core::Stream;

pub mod account;
pub mod capability;
pub mod chain;
pub mod chain_signer;
pub mod error;
pub mod secret_vault;
pub mod store;
pub mod transaction;
pub mod transaction_build;
pub mod wallet;

pub use account::{
    AccountNonce, AccountNonceSource, FinalizedAccountBalance, OnchainFeePolicy,
    PERBILL_DENOMINATOR,
};
pub use capability::{
    CapabilityName, CapabilityReason, CapabilitySnapshot, CapabilityStatus, Modules,
};
pub use chain::{
    validated_finalized_block_range_len, AccountId32, BlockFinality, ChainIdentity,
    ExportedChainState, FinalizedBlockRef, Hash32, RuntimeContext, RuntimeVersion,
    StateImportReceipt, VerifiedBlockRef, VerifiedChainClient, CITIZENCHAIN_CHAIN_ID,
    CITIZENCHAIN_GENESIS_HASH, CITIZENCHAIN_PROTOCOL_ID, MAX_FINALIZED_BLOCKS_PER_BATCH,
};
pub use chain_signer::{
    ChainSigner, DerivationJunction, Sr25519PublicKey, Sr25519Signature, SR25519_SIGNING_CONTEXT,
};
pub use error::{ContractError, ContractErrorCode, ContractResult};
pub use secret_vault::{
    EncryptedSecretEnvelope, Hash32Bytes, SecretBuffer, SecretKind, SecretOwner, SecretRef,
    SecretVault, VaultAvailability, VaultGeneration,
};
pub use store::{
    ChainDatabaseSnapshot, ChainDatabaseStore, EncryptedSecretBlobSnapshot,
    EncryptedSecretBlobState, EncryptedSecretBlobStore, FinalizedTransferRecord,
    HistoryTransactionStatus, RuntimeCacheStore, TransactionHistoryCursor,
    TransactionHistoryRecord, TransactionHistoryState, TransactionHistoryStore, WalletProfileStore,
    MAX_FINALIZED_REMARK_DISPLAY_BYTES,
};
pub use transaction::{
    DispatchFailure, ExecutionConclusion, ExtrinsicWatchEvent, ModuleDispatchFailure,
    SignedExtrinsic, SubmittedExtrinsic, UnverifiedReason,
};
pub use transaction_build::{
    ImmortalSigningPayload, SignedTransactionBuild, TransferWithRemarkCall, IMMORTAL_ERA,
    MAX_TRANSFER_REMARK_BYTES, ONCHAIN_TRANSACTION_PALLET_INDEX, TRANSFER_WITH_REMARK_CALL_INDEX,
};
pub use wallet::{
    citizen_ss58_address, WalletAccount, WalletCleanupPlan, WalletOrigin, WalletProfile,
    WalletProvisioningPlan, WalletState, CITIZEN_SS58_PREFIX, CITIZEN_WALLET_INDEX,
    MAX_WALLET_ACCOUNT_INDEX, MAX_WALLET_ACCOUNT_NAME_SCALARS,
};

/// 对象安全合同使用的异步返回值；具体 executor 由调用者决定。
pub type ContractFuture<'a, T> = Pin<Box<dyn Future<Output = ContractResult<T>> + Send + 'a>>;

/// 对象安全合同使用的事件流；每个事件都可以独立报告 provider 错误。
pub type ContractStream<'a, T> = Pin<Box<dyn Stream<Item = ContractResult<T>> + Send + 'a>>;
