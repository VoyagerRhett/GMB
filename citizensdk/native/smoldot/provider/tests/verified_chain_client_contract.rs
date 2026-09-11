use citizen_sdk_contracts::{
    ChainIdentity, ContractErrorCode, ExportedChainState, FinalizedBlockRef, VerifiedChainClient,
    CITIZENCHAIN_GENESIS_HASH,
};
use citizen_sdk_smoldot_provider::{
    ProviderLifecycle, SmoldotProviderConfig, SmoldotVerifiedChainClient,
};

const CHAIN_SPEC: &str = include_str!("../../../../assets/citizenchain/chainspec.json");
const INVALID_CHAIN_SPEC: &str =
    r#"{"name":"CitizenChain","id":"citizenchain","protocolId":"citizenchain"}"#;

fn assert_verified_client<T: VerifiedChainClient>() {}

fn require_ok<T, E>(result: Result<T, E>, context: &str) -> T {
    match result {
        Ok(value) => value,
        Err(_) => panic!("{context}"),
    }
}

fn require_err<T, E>(result: Result<T, E>, context: &str) -> E {
    match result {
        Err(error) => error,
        Ok(_) => panic!("{context}"),
    }
}

#[test]
fn concrete_provider_implements_the_formal_chain_contract() {
    assert_verified_client::<SmoldotVerifiedChainClient>();
}

#[test]
fn finalized_subscription_before_start_fails_once_and_ends() {
    use futures::StreamExt;
    let provider = require_ok(
        SmoldotVerifiedChainClient::new(require_ok(
            SmoldotProviderConfig::try_new(CHAIN_SPEC, "CitizenSDK test", "2.4.0"),
            "config",
        )),
        "provider",
    );
    let mut stream = provider.subscribe_finalized_heads();
    let first = futures::executor::block_on(stream.next());
    assert!(matches!(first, Some(Err(error)) if error.code() == ContractErrorCode::NotReady));
    assert!(futures::executor::block_on(stream.next()).is_none());
}

#[test]
#[allow(clippy::unwrap_used)]
fn real_smoldot_subscription_drops_and_drains_without_peers() {
    use futures::StreamExt;
    let mut spec: serde_json::Value = serde_json::from_str(CHAIN_SPEC).unwrap();
    spec["bootNodes"] = serde_json::json!([]);
    spec["lightSyncState"] = serde_json::from_str(include_str!(
        "../../../../assets/citizenchain/light_sync_state.json"
    ))
    .unwrap();
    let provider = SmoldotVerifiedChainClient::new(
        SmoldotProviderConfig::try_new(spec.to_string(), "CitizenSDK offline test", "2.4.0")
            .unwrap(),
    )
    .unwrap();
    provider.drive(provider.start()).unwrap().unwrap();
    let mut subscription = provider.subscribe_finalized_heads();
    // 有无初始通知取决于上游 runtime readiness；没有 peers 不允许自行终止订阅。
    let event = provider
        .drive(async {
            tokio::time::timeout(std::time::Duration::from_millis(300), subscription.next()).await
        })
        .unwrap();
    assert!(!matches!(event, Ok(None)));
    drop(subscription);
    provider
        .drive(provider.drain_finalized_subscriptions())
        .unwrap()
        .unwrap();
    provider.stop().unwrap();
    assert_eq!(provider.lifecycle().unwrap(), ProviderLifecycle::Stopped);
}

#[test]
fn static_identity_is_available_before_start_but_chain_reads_are_not() {
    let config = require_ok(
        SmoldotProviderConfig::try_new(CHAIN_SPEC, "CitizenSDK test", "1.0.0"),
        "bundled chainspec identity must be valid",
    );
    let provider = require_ok(
        SmoldotVerifiedChainClient::new(config),
        "provider runtime must start",
    );
    assert_eq!(
        require_ok(provider.lifecycle(), "lifecycle must be readable"),
        ProviderLifecycle::Created
    );

    assert_eq!(
        require_ok(
            futures::executor::block_on(provider.identity()),
            "static identity must be readable",
        ),
        ChainIdentity::citizenchain()
    );
    let error = require_err(
        futures::executor::block_on(provider.get_best_head()),
        "chain reads must require a real running smoldot instance",
    );
    assert_eq!(error.code(), ContractErrorCode::NotReady);
    let finalized_error = require_err(
        futures::executor::block_on(provider.get_finalized_block_at(0)),
        "finalized height resolution must require a real running smoldot instance",
    );
    assert_eq!(finalized_error.code(), ContractErrorCode::NotReady);
    let accepted_120_then_lifecycle = require_err(
        futures::executor::block_on(provider.get_finalized_blocks_at(1, 120)),
        "120-block range should pass the range gate then reach lifecycle",
    );
    assert_eq!(
        accepted_120_then_lifecycle.code(),
        ContractErrorCode::NotReady
    );
    let rejected_121 = require_err(
        futures::executor::block_on(provider.get_finalized_blocks_at(0, 120)),
        "121-block range must fail before provider lifecycle or network",
    );
    assert_eq!(rejected_121.code(), ContractErrorCode::InvalidArgument);
    let rejected_overflow = require_err(
        futures::executor::block_on(provider.get_finalized_blocks_at(0, u64::MAX)),
        "overflowing range must fail before provider lifecycle or network",
    );
    assert_eq!(rejected_overflow.code(), ContractErrorCode::InvalidArgument);
}

#[test]
fn import_is_exact_idempotent_and_conflicting_replacement_fails_closed() {
    let config = require_ok(
        SmoldotProviderConfig::try_new(CHAIN_SPEC, "CitizenSDK test", "1.0.0"),
        "bundled chainspec identity must be valid",
    );
    let provider = require_ok(
        SmoldotVerifiedChainClient::new(config),
        "provider runtime must start",
    );
    let finalized = FinalizedBlockRef::from_parts(CITIZENCHAIN_GENESIS_HASH, 0);
    let imported = ExportedChainState::try_new(
        ChainIdentity::citizenchain(),
        1,
        finalized,
        br#"{"genesisHash":"citizenchain"}"#.to_vec(),
    );
    let imported = require_ok(imported, "valid imported state must construct");
    let receipt = require_ok(
        futures::executor::block_on(provider.import_state(imported.clone())),
        "first import must succeed",
    );
    assert_eq!(receipt.finalized(), finalized);
    let repeated = require_ok(
        futures::executor::block_on(provider.import_state(imported)),
        "identical import must be idempotent",
    );
    assert_eq!(repeated.finalized(), finalized);

    let replacement = ExportedChainState::try_new(
        ChainIdentity::citizenchain(),
        1,
        finalized,
        br#"{"genesisHash":"replacement"}"#.to_vec(),
    );
    let replacement = require_ok(replacement, "replacement envelope itself must be valid");
    let error = require_err(
        futures::executor::block_on(provider.import_state(replacement)),
        "different pending import must not replace the accepted one",
    );
    assert_eq!(error.code(), ContractErrorCode::Conflict);
}

#[test]
fn public_source_does_not_expose_arbitrary_rpc() {
    let public_source = include_str!("../src/lib.rs");
    assert!(!public_source.contains("pub fn rpc"));
    assert!(!public_source.contains("pub async fn request"));
}

#[test]
fn controlled_executor_is_usable_without_a_tokio_context() {
    let config = require_ok(
        SmoldotProviderConfig::try_new(CHAIN_SPEC, "CitizenSDK worker", "1.0.0"),
        "bundled chainspec identity must be valid",
    );
    let provider = require_ok(
        SmoldotVerifiedChainClient::new(config),
        "provider runtime must start",
    );
    let worker = std::thread::spawn(move || provider.drive(async { "driven" }));
    let output = match worker.join() {
        Ok(output) => require_ok(output, "provider runtime must drive future"),
        Err(_) => panic!("ordinary worker must not panic"),
    };
    assert_eq!(output, "driven");
}

#[test]
fn failed_start_is_one_way_and_fallback_requires_a_fresh_provider() {
    let config = require_ok(
        SmoldotProviderConfig::try_new(INVALID_CHAIN_SPEC, "CitizenSDK test", "1.0.0"),
        "identity-only config validation must accept the test fixture",
    );
    let provider = require_ok(
        SmoldotVerifiedChainClient::new(config.clone()),
        "provider runtime must start",
    );
    let first = require_ok(
        provider.drive(provider.start()),
        "executor must drive start",
    );
    let _first_error = require_err(first, "invalid chainspec start must fail");
    assert_eq!(
        require_ok(provider.lifecycle(), "lifecycle must be readable"),
        ProviderLifecycle::StartFailed
    );

    let second = require_ok(
        provider.drive(provider.start()),
        "executor must drive second start rejection",
    );
    let second_error = require_err(second, "StartFailed provider must not restart");
    assert_eq!(second_error.code(), ContractErrorCode::InvalidState);

    let fallback = require_ok(
        SmoldotVerifiedChainClient::new(config),
        "fallback must allocate a fresh provider",
    );
    assert_eq!(
        require_ok(fallback.lifecycle(), "fresh lifecycle must be readable"),
        ProviderLifecycle::Created
    );
}

#[test]
fn transaction_watch_uses_the_upstream_v1_surface_without_legacy_fallback() {
    let legacy = include_str!("../src/legacy.rs");
    assert!(legacy.contains("\"transactionWatch_v1_submitAndWatch\""));
    assert!(legacy.contains("\"transactionWatch_v1_unwatch\""));
    assert!(!legacy.contains("author_submitAndWatchExtrinsic"));
    assert!(!legacy.contains("author_unwatchExtrinsic"));

    let parser = include_str!("../src/verified_chain_client.rs");
    for event in [
        "validated",
        "broadcasted",
        "bestChainBlockIncluded",
        "finalized",
        "invalid",
        "dropped",
        "error",
    ] {
        assert!(parser.contains(&format!("\"{event}\"")), "missing {event}");
    }
    assert!(parser.contains("map.get(\"numPeers\")"));
    assert!(parser.contains("map.get(\"broadcasted\")"));
}

#[test]
fn typed_body_and_current_batches_have_single_native_call_sites() {
    let source = include_str!("../src/verified_chain_client.rs");
    assert_eq!(source.matches("chain_block_extrinsics(").count(), 1);
    assert!(!source.contains("\"chain_getBlock\""));
    assert_eq!(source.matches("chain_storage_values_snapshot(").count(), 1);
    assert_eq!(
        source
            .matches("chain_finalized_storage_values_snapshot(")
            .count(),
        1
    );
    assert!(source.contains("StorageBatchRoute::ExactHash"));
    assert!(source.contains("exact_storage_params(block, key)"));
    assert!(source.contains("storage_snapshot_matches_block(&snapshot, block)"));
    assert!(!source.contains("let after = storage_batch_heads"));
}

#[test]
fn finalized_resolution_uses_verified_ancestry_not_best_or_recent_cache() {
    let provider_source = include_str!("../src/verified_chain_client.rs");
    assert!(provider_source.contains(".chain_finalized_blocks_at("));
    assert!(!provider_source.contains("chain_known_block_hash("));

    let light_base = include_str!("../../pow/light-base/src/lib.rs");
    let start = light_base
        .find("pub fn chain_finalized_blocks_at(")
        .unwrap_or_else(|| panic!("typed finalized ancestry method must exist"));
    let end = light_base[start..]
        .find("pub fn chain_known_block_hash(")
        .map(|offset| start + offset)
        .unwrap_or_else(|| panic!("next typed method must delimit ancestry source"));
    let resolver = &light_base[start..end];
    assert!(resolver.contains("sync_activity_snapshot().await"));
    assert!(resolver.contains("current_verified_finalized_block_number"));
    assert!(resolver.contains("current_verified_finalized_block_hash"));
    assert!(resolver.contains("block_query_unknown_number("));
    assert!(resolver.contains("header: true"));
    assert!(resolver.contains(".accept(block_data, block_number_bytes)"));
    assert!(resolver.contains("finalized_ancestry_cache"));
    let exact_hit = resolver
        .find("anchor_cache.exact_blocks(start_number, end_number)")
        .unwrap_or_else(|| panic!("proof-derived exact cache lookup must exist"));
    let network_walk = resolver
        .find("block_query_unknown_number(")
        .unwrap_or_else(|| panic!("proof-backed network fallback must exist"));
    assert!(exact_hit < network_walk);
    assert!(resolver.contains("commit_proven_batch("));
    assert!(!resolver.contains("recent_block_cache"));
    assert!(!resolver.contains("subscribe_all"));
    assert!(!resolver.contains("best_block"));
}
