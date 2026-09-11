//! Exact finalized reconciliation for SDK-submitted generic transactions.
//!
//! No account-wide event indexing or application pallet decoding occurs here.
//! A batch considers at most 32 durable executions, verifies exact block bodies
//! and same-index System outcomes, and may rebroadcast each unchanged signed
//! extrinsic at most once per running Engine generation.

use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

use citizen_sdk_contracts::{
    validated_finalized_block_range_len, ChainSigner, ContractErrorCode, ExecutionConclusion,
    HistoryTransactionStatus, SignedExtrinsic, TransactionExecutionId, TransactionHistoryState,
    VerifiedChainClient, MAX_FINALIZED_BLOCKS_PER_BATCH, MAX_TRANSACTION_HISTORY_SYNC_BATCH,
};

use crate::{
    account_state::{verified_identity, verified_runtime_context},
    error::EngineError,
    signed_extrinsic_hash,
    system_events::SYSTEM_EVENTS_STORAGE_KEY,
    transaction_history::TransactionHistoryService,
    transaction_outcome::{verify_transaction_outcome, TransactionEvidence},
    transaction_prepare::validate_persisted_transaction_execution,
};

/// Engine lifecycle fence; every external await is followed by this check.
pub(crate) trait FinalizedHistoryRunGuard: Send + Sync {
    fn ensure_current(&self) -> Result<(), EngineError>;
    fn poll_cancelled(&self, _: &mut std::task::Context<'_>) -> std::task::Poll<()> {
        std::task::Poll::Pending
    }
}

/// Cancellation wraps provider work only. Store CAS operations always drain.
pub(crate) async fn cancellable_chain<T>(
    future: impl std::future::Future<Output = T>,
    guard: &dyn FinalizedHistoryRunGuard,
) -> Result<T, EngineError> {
    let mut future = std::pin::pin!(future);
    std::future::poll_fn(|context| {
        if guard.poll_cancelled(context).is_ready() {
            return std::task::Poll::Ready(Err(invalid_state(
                "transaction history generation was cancelled",
            )));
        }
        future.as_mut().poll(context).map(Ok)
    })
    .await
}

pub(crate) struct FinalizedHistoryRuntime {
    chain_client: Arc<dyn VerifiedChainClient>,
    history: TransactionHistoryService,
}

impl FinalizedHistoryRuntime {
    pub(crate) const fn new(
        chain_client: Arc<dyn VerifiedChainClient>,
        history: TransactionHistoryService,
    ) -> Self {
        Self {
            chain_client,
            history,
        }
    }

    pub(crate) async fn reconcile_generic_execution_batch(
        &self,
        positions: &mut BTreeMap<TransactionExecutionId, u64>,
        rebroadcasted: &mut BTreeSet<TransactionExecutionId>,
        signer: &dyn ChainSigner,
        guard: &dyn FinalizedHistoryRunGuard,
    ) -> Result<TransactionHistoryState, EngineError> {
        guard.ensure_current()?;
        let candidates = self
            .history
            .open_batch(MAX_TRANSACTION_HISTORY_SYNC_BATCH)
            .await?;
        guard.ensure_current()?;
        let candidate_ids = candidates
            .iter()
            .map(|record| record.execution_id())
            .collect::<BTreeSet<_>>();
        positions.retain(|id, _| candidate_ids.contains(id));
        rebroadcasted.retain(|id| candidate_ids.contains(id));
        if candidates.is_empty() {
            return self.history.load().await;
        }

        let finalized_head =
            cancellable_chain(self.chain_client.get_finalized_head(), guard).await??;
        guard.ensure_current()?;
        for record in &candidates {
            let floor = match record.status() {
                HistoryTransactionStatus::InBlock { block } => block.number(),
                _ => record.block().number(),
            };
            positions.entry(record.execution_id()).or_insert(floor);
        }

        let mut reached_head = true;
        if let Some(start) = positions
            .values()
            .copied()
            .filter(|height| *height <= finalized_head.number())
            .min()
        {
            let end = finalized_head
                .number()
                .min(start.saturating_add(MAX_FINALIZED_BLOCKS_PER_BATCH - 1));
            reached_head = end == finalized_head.number();
            let blocks =
                cancellable_chain(self.chain_client.get_finalized_blocks_at(start, end), guard)
                    .await??;
            if blocks.len() != validated_finalized_block_range_len(start, end)? {
                return Err(integrity(
                    "generic execution recovery returned a partial block batch",
                ));
            }
            for (offset, block) in blocks.into_iter().enumerate() {
                let offset = u64::try_from(offset)
                    .map_err(|_| integrity("generic recovery block offset overflowed"))?;
                if block.number() != start.saturating_add(offset) {
                    return Err(integrity("generic recovery block order mismatch"));
                }
                self.reconcile_block(block, &candidate_ids, guard).await?;
                for position in positions.values_mut() {
                    if *position <= block.number() {
                        *position = block.number().saturating_add(1);
                    }
                }
            }
        }

        let state = self.history.load().await?;
        guard.ensure_current()?;
        if !reached_head {
            return Ok(state);
        }

        let identity =
            cancellable_chain(verified_identity(self.chain_client.as_ref()), guard).await??;
        for record in state.executions().iter().filter(|record| {
            candidate_ids.contains(&record.execution_id())
                && matches!(
                    record.status(),
                    HistoryTransactionStatus::Pending | HistoryTransactionStatus::InBlock { .. }
                )
        }) {
            if rebroadcasted.contains(&record.execution_id()) {
                continue;
            }
            let best = cancellable_chain(self.chain_client.get_best_head(), guard).await??;
            let runtime = cancellable_chain(
                verified_runtime_context(self.chain_client.as_ref(), best),
                guard,
            )
            .await??;
            validate_persisted_transaction_execution(record, &identity, &runtime, signer).await?;
            if signed_extrinsic_hash(&runtime, record.signed_extrinsic())?
                != record.transaction_hash()
            {
                return Err(integrity("generic recovery transaction hash changed"));
            }
            let submitted = cancellable_chain(
                self.chain_client
                    .submit_extrinsic(record.signed_extrinsic().clone()),
                guard,
            )
            .await??;
            guard.ensure_current()?;
            if submitted.hash() != record.transaction_hash() {
                return Err(integrity(
                    "provider returned a different generic recovery hash",
                ));
            }
            rebroadcasted.insert(record.execution_id());
        }
        self.history.load().await
    }

    async fn reconcile_block(
        &self,
        block: citizen_sdk_contracts::FinalizedBlockRef,
        candidates: &BTreeSet<TransactionExecutionId>,
        guard: &dyn FinalizedHistoryRunGuard,
    ) -> Result<(), EngineError> {
        guard.ensure_current()?;
        let runtime = cancellable_chain(
            self.chain_client.get_finalized_runtime_context_at(block),
            guard,
        )
        .await??;
        let body = cancellable_chain(
            self.chain_client.get_finalized_block_extrinsics_at(block),
            guard,
        )
        .await??;
        let events = cancellable_chain(
            self.chain_client
                .get_finalized_storage_at(block, SYSTEM_EVENTS_STORAGE_KEY.to_vec()),
            guard,
        )
        .await??;
        guard.ensure_current()?;

        let mut decoded_body = Vec::with_capacity(body.len());
        for bytes in &body {
            let extrinsic = SignedExtrinsic::try_new(bytes.clone())?;
            decoded_body.push((signed_extrinsic_hash(&runtime, &extrinsic)?, extrinsic));
        }
        let snapshot = self.history.load().await?;
        for record in snapshot.executions().iter().filter(|record| {
            candidates.contains(&record.execution_id()) && !record.status().is_chain_terminal()
        }) {
            let matches = decoded_body
                .iter()
                .enumerate()
                .filter_map(|(index, (hash, extrinsic))| {
                    (*hash == record.transaction_hash()).then_some((index, extrinsic))
                })
                .collect::<Vec<_>>();
            match matches.as_slice() {
                [] => {}
                [(index, extrinsic)] => {
                    let conclusion = verify_transaction_outcome(TransactionEvidence {
                        block: block.verified(),
                        runtime_context: &runtime,
                        signed_extrinsic: extrinsic,
                        submitted_hash: record.transaction_hash(),
                        block_extrinsics: &body,
                        system_events: events.as_deref(),
                    });
                    if !matches!(
                        conclusion,
                        ExecutionConclusion::Success { .. } | ExecutionConclusion::Failed { .. }
                    ) {
                        return Err(EngineError::InvalidEvents(format!(
                            "generic execution matched finalized extrinsic index {index} without exact System outcome"
                        )));
                    }
                    self.history
                        .update_execution_status(
                            record.execution_id(),
                            HistoryTransactionStatus::Execution(conclusion),
                        )
                        .await?;
                }
                _ => {
                    return Err(integrity(
                        "generic transaction hash matched multiple extrinsics",
                    ))
                }
            }
        }
        Ok(())
    }
}

fn invalid_state(message: impl Into<String>) -> EngineError {
    EngineError::contract(ContractErrorCode::InvalidState, message)
}

fn integrity(message: impl Into<String>) -> EngineError {
    EngineError::contract(ContractErrorCode::Integrity, message)
}
