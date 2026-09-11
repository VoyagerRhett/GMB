//! Product-independent durable transaction executions and public history views.
//!
//! Applications own destination, amount, remark, direction, pallet/event and
//! every other business projection. This store keeps only the exact opaque
//! authorization required to recover transactions submitted by CitizenSDK.

use std::collections::BTreeSet;

use crate::{
    AccountId32, ContractError, ContractErrorCode, ContractFuture, ContractResult,
    ExecutionConclusion, Hash32, RuntimeVersion, SignedExtrinsic, TransactionExecutionId,
    VerifiedBlockRef, MAX_TRANSACTION_CALL_DATA_BYTES, MAX_TRANSACTION_SIGNED_EXTRINSIC_BYTES,
};

pub const MAX_TRANSACTION_HISTORY_RECORDS: usize = 4096;
pub const MAX_TRANSACTION_HISTORY_PAGE_SIZE: usize = 100;
pub const MAX_TRANSACTION_HISTORY_SYNC_BATCH: usize = 32;
pub const MAX_TRANSACTION_POOL_REASON_BYTES: usize = 512;

/// Durable state of an SDK-submitted transaction. Inclusion is not success.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HistoryTransactionStatus {
    Pending,
    InBlock {
        block: VerifiedBlockRef,
    },
    PoolRejected {
        reason: String,
        replacement_hash: Option<Hash32>,
    },
    /// Only a finalized, same-index System outcome is persistable.
    Execution(ExecutionConclusion),
}

impl HistoryTransactionStatus {
    pub fn try_pool_rejected(reason: impl Into<String>) -> ContractResult<Self> {
        Self::try_pool_rejected_with_replacement(reason, None)
    }

    pub fn try_pool_rejected_with_replacement(
        reason: impl Into<String>,
        replacement_hash: Option<Hash32>,
    ) -> ContractResult<Self> {
        let reason = reason.into();
        if reason.trim().is_empty() || reason.len() > MAX_TRANSACTION_POOL_REASON_BYTES {
            return Err(ContractError::new(
                ContractErrorCode::InvalidArgument,
                "交易池拒绝原因必须包含 1..512 个 UTF-8 字节",
            ));
        }
        Ok(Self::PoolRejected {
            reason,
            replacement_hash,
        })
    }

    pub fn pool_rejection_reason(&self) -> Option<&str> {
        match self {
            Self::PoolRejected { reason, .. } => Some(reason),
            _ => None,
        }
    }

    pub const fn replacement_hash(&self) -> Option<Hash32> {
        match self {
            Self::PoolRejected {
                replacement_hash, ..
            } => *replacement_hash,
            _ => None,
        }
    }

    pub const fn is_chain_terminal(&self) -> bool {
        match self {
            Self::Execution(ExecutionConclusion::Success { block, .. })
            | Self::Execution(ExecutionConclusion::Failed { block, .. }) => block.is_finalized(),
            _ => false,
        }
    }

    pub const fn is_retention_terminal(&self) -> bool {
        self.is_chain_terminal() || matches!(self, Self::PoolRejected { .. })
    }

    pub fn persisted_name(&self) -> Option<&'static str> {
        match self {
            Self::Pending => Some("pending"),
            Self::InBlock { .. } => Some("inBlock"),
            Self::PoolRejected { reason, .. } if !reason.trim().is_empty() => Some("poolRejected"),
            Self::Execution(ExecutionConclusion::Success { block, .. }) if block.is_finalized() => {
                Some("finalizedSuccess")
            }
            Self::Execution(ExecutionConclusion::Failed { block, .. }) if block.is_finalized() => {
                Some("finalizedFailed")
            }
            _ => None,
        }
    }

    /// Evidence can only strengthen. A pool rejection may later be superseded
    /// by an exact finalized execution discovered during reconciliation.
    pub fn allows_transition_to(&self, next: &Self) -> bool {
        if self == next {
            return true;
        }
        match (self, next) {
            (
                Self::Pending,
                Self::InBlock { .. } | Self::PoolRejected { .. } | Self::Execution(_),
            )
            | (
                Self::InBlock { .. },
                Self::InBlock { .. } | Self::PoolRejected { .. } | Self::Execution(_),
            )
            | (Self::PoolRejected { .. }, Self::Execution(_)) => true,
            (Self::Execution(_), _) => false,
            _ => false,
        }
    }
}

fn status_is_persistable(status: &HistoryTransactionStatus) -> bool {
    match status {
        HistoryTransactionStatus::Execution(ExecutionConclusion::Success { block, .. })
        | HistoryTransactionStatus::Execution(ExecutionConclusion::Failed { block, .. }) => {
            block.is_finalized()
        }
        HistoryTransactionStatus::Execution(ExecutionConclusion::Unverified { .. }) => false,
        HistoryTransactionStatus::PoolRejected { reason, .. } => {
            !reason.trim().is_empty() && reason.len() <= MAX_TRANSACTION_POOL_REASON_BYTES
        }
        _ => true,
    }
}

/// Complete durable authorization written before the provider is called.
///
/// `call_data` and `signed_extrinsic` are private recovery material. Public
/// history projection is an explicit field whitelist and never exposes them.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransactionExecutionRecord {
    execution_id: TransactionExecutionId,
    account_id: AccountId32,
    call_data_hash: Hash32,
    call_data: Vec<u8>,
    transaction_hash: Hash32,
    signed_extrinsic: SignedExtrinsic,
    block: VerifiedBlockRef,
    runtime_version: RuntimeVersion,
    genesis_hash: Hash32,
    nonce: u64,
    status: HistoryTransactionStatus,
    created_at_millis: u64,
    updated_at_millis: u64,
}

impl TransactionExecutionRecord {
    #[allow(clippy::too_many_arguments)]
    pub fn try_new(
        execution_id: TransactionExecutionId,
        account_id: AccountId32,
        call_data_hash: Hash32,
        call_data: Vec<u8>,
        transaction_hash: Hash32,
        signed_extrinsic: SignedExtrinsic,
        block: VerifiedBlockRef,
        runtime_version: RuntimeVersion,
        genesis_hash: Hash32,
        nonce: u64,
        status: HistoryTransactionStatus,
        created_at_millis: u64,
        updated_at_millis: u64,
    ) -> ContractResult<Self> {
        if call_data.is_empty() || call_data.len() > MAX_TRANSACTION_CALL_DATA_BYTES {
            return Err(ContractError::new(
                ContractErrorCode::InvalidArgument,
                "通用交易恢复 callData 必须包含 1..1MiB 字节",
            ));
        }
        if Hash32::from_bytes(crate::blake2_256(&call_data)?) != call_data_hash {
            return Err(ContractError::new(
                ContractErrorCode::Integrity,
                "通用交易恢复 callData hash 不一致",
            ));
        }
        if signed_extrinsic.as_bytes().len() > MAX_TRANSACTION_SIGNED_EXTRINSIC_BYTES {
            return Err(ContractError::new(
                ContractErrorCode::InvalidArgument,
                "通用交易恢复 signed extrinsic 超过固定上限",
            ));
        }
        if updated_at_millis < created_at_millis || !status_is_persistable(&status) {
            return Err(ContractError::new(
                ContractErrorCode::InvalidArgument,
                "通用交易恢复状态或时间无效",
            ));
        }
        Ok(Self {
            execution_id,
            account_id,
            call_data_hash,
            call_data,
            transaction_hash,
            signed_extrinsic,
            block,
            runtime_version,
            genesis_hash,
            nonce,
            status,
            created_at_millis,
            updated_at_millis,
        })
    }

    pub const fn execution_id(&self) -> TransactionExecutionId {
        self.execution_id
    }
    pub const fn account_id(&self) -> AccountId32 {
        self.account_id
    }
    pub const fn call_data_hash(&self) -> Hash32 {
        self.call_data_hash
    }
    pub fn call_data(&self) -> &[u8] {
        &self.call_data
    }
    pub const fn transaction_hash(&self) -> Hash32 {
        self.transaction_hash
    }
    pub const fn signed_extrinsic(&self) -> &SignedExtrinsic {
        &self.signed_extrinsic
    }
    pub const fn block(&self) -> VerifiedBlockRef {
        self.block
    }
    pub const fn runtime_version(&self) -> RuntimeVersion {
        self.runtime_version
    }
    pub const fn genesis_hash(&self) -> Hash32 {
        self.genesis_hash
    }
    pub const fn nonce(&self) -> u64 {
        self.nonce
    }
    pub const fn status(&self) -> &HistoryTransactionStatus {
        &self.status
    }
    pub const fn created_at_millis(&self) -> u64 {
        self.created_at_millis
    }
    pub const fn updated_at_millis(&self) -> u64 {
        self.updated_at_millis
    }

    pub fn require_same_submission_facts(&self, other: &Self) -> ContractResult<()> {
        if self.execution_id != other.execution_id
            || self.account_id != other.account_id
            || self.call_data_hash != other.call_data_hash
            || self.call_data != other.call_data
            || self.transaction_hash != other.transaction_hash
            || self.signed_extrinsic != other.signed_extrinsic
            || self.block != other.block
            || self.runtime_version != other.runtime_version
            || self.genesis_hash != other.genesis_hash
            || self.nonce != other.nonce
        {
            return Err(ContractError::new(
                ContractErrorCode::Integrity,
                "同一 executionId 的通用交易提交事实不一致",
            ));
        }
        Ok(())
    }

    pub fn try_with_status(
        &self,
        status: HistoryTransactionStatus,
        updated_at_millis: u64,
    ) -> ContractResult<Self> {
        if !self.status.allows_transition_to(&status) {
            return Err(ContractError::new(
                ContractErrorCode::InvalidState,
                "通用交易状态不能倒退或改写终态",
            ));
        }
        Self::try_new(
            self.execution_id,
            self.account_id,
            self.call_data_hash,
            self.call_data.clone(),
            self.transaction_hash,
            self.signed_extrinsic.clone(),
            self.block,
            self.runtime_version,
            self.genesis_hash,
            self.nonce,
            status,
            self.created_at_millis,
            updated_at_millis,
        )
    }
}

/// Safe public whitelist projection of one durable execution.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransactionHistoryRecord {
    execution_id: TransactionExecutionId,
    source_account_id: AccountId32,
    call_data_hash: Hash32,
    transaction_hash: Hash32,
    status: HistoryTransactionStatus,
    created_at_millis: u64,
    updated_at_millis: u64,
}

impl From<&TransactionExecutionRecord> for TransactionHistoryRecord {
    fn from(record: &TransactionExecutionRecord) -> Self {
        Self {
            execution_id: record.execution_id(),
            source_account_id: record.account_id(),
            call_data_hash: record.call_data_hash(),
            transaction_hash: record.transaction_hash(),
            status: record.status().clone(),
            created_at_millis: record.created_at_millis(),
            updated_at_millis: record.updated_at_millis(),
        }
    }
}

impl TransactionHistoryRecord {
    pub const fn execution_id(&self) -> TransactionExecutionId {
        self.execution_id
    }
    pub const fn source_account_id(&self) -> AccountId32 {
        self.source_account_id
    }
    pub const fn call_data_hash(&self) -> Hash32 {
        self.call_data_hash
    }
    pub const fn transaction_hash(&self) -> Hash32 {
        self.transaction_hash
    }
    pub const fn status(&self) -> &HistoryTransactionStatus {
        &self.status
    }
    pub const fn created_at_millis(&self) -> u64 {
        self.created_at_millis
    }
    pub const fn updated_at_millis(&self) -> u64 {
        self.updated_at_millis
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransactionHistoryPage {
    revision: u64,
    records: Vec<TransactionHistoryRecord>,
    next_before_execution_id: Option<TransactionExecutionId>,
}

impl TransactionHistoryPage {
    pub fn new(
        revision: u64,
        records: Vec<TransactionHistoryRecord>,
        next_before_execution_id: Option<TransactionExecutionId>,
    ) -> Self {
        Self {
            revision,
            records,
            next_before_execution_id,
        }
    }
    pub const fn revision(&self) -> u64 {
        self.revision
    }
    pub fn records(&self) -> &[TransactionHistoryRecord] {
        &self.records
    }
    pub const fn next_before_execution_id(&self) -> Option<TransactionExecutionId> {
        self.next_before_execution_id
    }
}

/// Atomic execution-only store state. No account scan cursor or business event
/// collection is permitted in this schema.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TransactionHistoryState {
    revision: u64,
    executions: Vec<TransactionExecutionRecord>,
}

impl TransactionHistoryState {
    pub fn try_new(
        revision: u64,
        executions: Vec<TransactionExecutionRecord>,
    ) -> ContractResult<Self> {
        if executions.len() > MAX_TRANSACTION_HISTORY_RECORDS {
            return Err(ContractError::new(
                ContractErrorCode::InvalidArgument,
                "通用交易历史超过 4096 条固定上限",
            ));
        }
        let ids: BTreeSet<_> = executions
            .iter()
            .map(|record| record.execution_id())
            .collect();
        let hashes: BTreeSet<_> = executions
            .iter()
            .map(|record| record.transaction_hash())
            .collect();
        if ids.len() != executions.len() || hashes.len() != executions.len() {
            return Err(ContractError::new(
                ContractErrorCode::InvalidArgument,
                "通用交易 executionId 或 transactionHash 重复",
            ));
        }
        Ok(Self {
            revision,
            executions,
        })
    }

    pub const fn revision(&self) -> u64 {
        self.revision
    }
    pub fn executions(&self) -> &[TransactionExecutionRecord] {
        &self.executions
    }
}

pub trait TransactionHistoryStore: Send + Sync {
    fn load(&self) -> ContractFuture<'_, TransactionHistoryState>;

    fn compare_and_swap(
        &self,
        expected_revision: u64,
        next: TransactionHistoryState,
    ) -> ContractFuture<'_, TransactionHistoryState>;
}
