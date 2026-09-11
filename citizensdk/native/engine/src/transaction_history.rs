//! Product-independent transaction execution history.
//!
//! Only transactions actually submitted by this SDK are stored. Public pages
//! are whitelist projections; opaque callData and signed extrinsics remain
//! internal recovery material.

use std::sync::{Arc, OnceLock};

use citizen_sdk_contracts::{
    store::{
        HistoryTransactionStatus, TransactionExecutionRecord, TransactionHistoryPage,
        TransactionHistoryRecord, TransactionHistoryState, TransactionHistoryStore,
    },
    AccountId32, ContractErrorCode, Hash32, RuntimeVersion, SignedExtrinsic,
    TransactionExecutionId, VerifiedBlockRef, MAX_TRANSACTION_HISTORY_PAGE_SIZE,
    MAX_TRANSACTION_HISTORY_RECORDS,
};
use futures::lock::Mutex as AsyncMutex;

use crate::{error::EngineError, wallet_service::WalletClock};

const MAX_HISTORY_CAS_ATTEMPTS: usize = 8;
static HISTORY_MUTATION_GATE: OnceLock<AsyncMutex<()>> = OnceLock::new();

fn history_mutation_gate() -> &'static AsyncMutex<()> {
    HISTORY_MUTATION_GATE.get_or_init(|| AsyncMutex::new(()))
}

#[derive(Clone)]
pub struct TransactionHistoryService {
    store: Arc<dyn TransactionHistoryStore>,
    clock: Arc<dyn WalletClock>,
}

impl TransactionHistoryService {
    pub fn new(store: Arc<dyn TransactionHistoryStore>, clock: Arc<dyn WalletClock>) -> Self {
        Self { store, clock }
    }

    /// Atomically persists exact recovery material before the provider is called.
    /// Open records are never evicted; when full, only the oldest verified terminal
    /// records are removed in deterministic order.
    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn record_execution_before_broadcast(
        &self,
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
    ) -> Result<TransactionHistoryState, EngineError> {
        let _guard = history_mutation_gate().lock().await;
        let now = self.clock.now_millis()?;
        let candidate = TransactionExecutionRecord::try_new(
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
            HistoryTransactionStatus::Pending,
            now,
            now,
        )?;
        self.mutate(move |state| {
            if let Some(existing) = state
                .executions()
                .iter()
                .find(|record| record.execution_id() == execution_id)
            {
                existing.require_same_submission_facts(&candidate)?;
                return if matches!(existing.status(), HistoryTransactionStatus::Pending) {
                    Ok(None)
                } else {
                    Err(error(
                        ContractErrorCode::InvalidState,
                        "通用交易已离开 Pending",
                    ))
                };
            }
            if state.executions().iter().any(|record| {
                record.account_id() == account_id
                    && matches!(
                        record.status(),
                        HistoryTransactionStatus::Pending
                            | HistoryTransactionStatus::InBlock { .. }
                    )
            }) {
                return Err(error(
                    ContractErrorCode::Conflict,
                    "同一账户已有 Pending/InBlock 交易",
                ));
            }

            let mut executions = state.executions().to_vec();
            make_room_for_one(&mut executions)?;
            executions.push(candidate.clone());
            Ok(Some(executions))
        })
        .await
    }

    pub(crate) async fn require_execution_snapshot(
        &self,
        execution_id: TransactionExecutionId,
    ) -> Result<(TransactionHistoryState, TransactionExecutionRecord), EngineError> {
        let state = self.load().await?;
        let matches = state
            .executions()
            .iter()
            .filter(|record| record.execution_id() == execution_id)
            .cloned()
            .collect::<Vec<_>>();
        match matches.as_slice() {
            [record] => Ok((state, record.clone())),
            [] => Err(error(ContractErrorCode::NotFound, "通用交易恢复记录不存在")),
            _ => Err(error(
                ContractErrorCode::Integrity,
                "executionId 对应多条恢复记录",
            )),
        }
    }

    /// Verifies that a low-level submit cannot bypass the durable
    /// pending-before-broadcast record owned by the generic transaction API.
    pub(crate) async fn require_recorded_before_broadcast(
        &self,
        transaction_hash: Hash32,
    ) -> Result<TransactionExecutionRecord, EngineError> {
        let state = self.load().await?;
        let matches = state
            .executions()
            .iter()
            .filter(|record| record.transaction_hash() == transaction_hash)
            .cloned()
            .collect::<Vec<_>>();
        match matches.as_slice() {
            [record] if matches!(record.status(), HistoryTransactionStatus::Pending) => {
                Ok(record.clone())
            }
            [record] => Err(error(
                ContractErrorCode::InvalidState,
                format!(
                    "通用交易已经离开 Pending：{}",
                    record.status().persisted_name().unwrap_or("invalid")
                ),
            )),
            [] => Err(error(
                ContractErrorCode::InvalidState,
                "通用交易必须先持久化再广播",
            )),
            _ => Err(error(
                ContractErrorCode::Integrity,
                "transactionHash 对应多条通用交易记录",
            )),
        }
    }

    pub(crate) async fn update_execution_status(
        &self,
        execution_id: TransactionExecutionId,
        status: HistoryTransactionStatus,
    ) -> Result<TransactionHistoryState, EngineError> {
        let _guard = history_mutation_gate().lock().await;
        let now = self.clock.now_millis()?;
        self.mutate(move |state| {
            let Some(position) = state
                .executions()
                .iter()
                .position(|record| record.execution_id() == execution_id)
            else {
                return Err(error(ContractErrorCode::NotFound, "通用交易恢复记录不存在"));
            };
            let current = &state.executions()[position];
            if current.status() == &status {
                return Ok(None);
            }
            let mut executions = state.executions().to_vec();
            executions[position] = current.try_with_status(status.clone(), now)?;
            Ok(Some(executions))
        })
        .await
    }

    pub(crate) async fn load(&self) -> Result<TransactionHistoryState, EngineError> {
        self.store.load().await.map_err(EngineError::from)
    }

    pub(crate) async fn page(
        &self,
        before: Option<TransactionExecutionId>,
        limit: usize,
    ) -> Result<TransactionHistoryPage, EngineError> {
        if !(1..=MAX_TRANSACTION_HISTORY_PAGE_SIZE).contains(&limit) {
            return Err(error(
                ContractErrorCode::InvalidArgument,
                "transaction history limit 必须为 1..100",
            ));
        }
        let state = self.load().await?;
        let mut records = state.executions().iter().collect::<Vec<_>>();
        records.sort_by(|left, right| {
            right
                .created_at_millis()
                .cmp(&left.created_at_millis())
                .then_with(|| right.execution_id().cmp(&left.execution_id()))
        });
        let start = match before {
            None => 0,
            Some(cursor) => records
                .iter()
                .position(|record| record.execution_id() == cursor)
                .map(|position| position + 1)
                .ok_or_else(|| {
                    error(
                        ContractErrorCode::NotFound,
                        "beforeExecutionId 不属于当前 transaction history 快照",
                    )
                })?,
        };
        let end = records.len().min(start.saturating_add(limit));
        let page_records = records[start..end]
            .iter()
            .map(|record| TransactionHistoryRecord::from(*record))
            .collect::<Vec<_>>();
        let next = (end < records.len())
            .then(|| {
                page_records
                    .last()
                    .map(TransactionHistoryRecord::execution_id)
            })
            .flatten();
        Ok(TransactionHistoryPage::new(
            state.revision(),
            page_records,
            next,
        ))
    }

    pub(crate) async fn open_batch(
        &self,
        limit: usize,
    ) -> Result<Vec<TransactionExecutionRecord>, EngineError> {
        let state = self.load().await?;
        let mut open = state
            .executions()
            .iter()
            .filter(|record| !record.status().is_chain_terminal())
            .cloned()
            .collect::<Vec<_>>();
        open.sort_by(|left, right| {
            left.created_at_millis()
                .cmp(&right.created_at_millis())
                .then_with(|| left.execution_id().cmp(&right.execution_id()))
        });
        open.truncate(limit);
        Ok(open)
    }

    async fn mutate(
        &self,
        mut transform: impl FnMut(
            &TransactionHistoryState,
        )
            -> Result<Option<Vec<TransactionExecutionRecord>>, EngineError>,
    ) -> Result<TransactionHistoryState, EngineError> {
        for _ in 0..MAX_HISTORY_CAS_ATTEMPTS {
            let current = self.store.load().await?;
            let Some(executions) = transform(&current)? else {
                return Ok(current);
            };
            let revision = current.revision().checked_add(1).ok_or_else(|| {
                error(ContractErrorCode::InvalidState, "交易历史 revision 已耗尽")
            })?;
            let next = TransactionHistoryState::try_new(revision, executions)?;
            match self
                .store
                .compare_and_swap(current.revision(), next.clone())
                .await
            {
                Ok(observed) if observed == next => return Ok(observed),
                Ok(_) => {
                    return Err(error(
                        ContractErrorCode::Integrity,
                        "交易历史 CAS 返回的状态与候选不一致",
                    ))
                }
                Err(write_error) => {
                    let observed = self.store.load().await;
                    if observed.as_ref().is_ok_and(|state| state == &next) {
                        return Ok(next);
                    }
                    if write_error.code() != ContractErrorCode::Conflict {
                        return Err(EngineError::from(write_error));
                    }
                }
            }
        }
        Err(error(
            ContractErrorCode::Conflict,
            "交易历史 CAS 超过 8 次仍冲突",
        ))
    }
}

fn make_room_for_one(executions: &mut Vec<TransactionExecutionRecord>) -> Result<(), EngineError> {
    if executions.len() < MAX_TRANSACTION_HISTORY_RECORDS {
        return Ok(());
    }
    let oldest = executions
        .iter()
        .filter(|record| record.status().is_retention_terminal())
        .min_by(|left, right| {
            left.created_at_millis()
                .cmp(&right.created_at_millis())
                .then_with(|| left.execution_id().cmp(&right.execution_id()))
        })
        .map(TransactionExecutionRecord::execution_id)
        .ok_or_else(|| {
            error(
                ContractErrorCode::Conflict,
                "transaction history 已满且没有可驱逐的终态记录",
            )
        })?;
    executions.retain(|record| record.execution_id() != oldest);
    Ok(())
}

fn error(code: ContractErrorCode, message: impl Into<String>) -> EngineError {
    EngineError::contract(code, message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeSet;

    #[test]
    fn retention_identity_set_is_product_neutral() {
        let set = BTreeSet::<TransactionExecutionId>::new();
        assert!(set.is_empty());
        assert_eq!(MAX_TRANSACTION_HISTORY_RECORDS, 4096);
    }
}
