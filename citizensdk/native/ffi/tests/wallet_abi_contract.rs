use std::{
    collections::BTreeSet,
    mem::{align_of, size_of},
};

use citizensdk::{
    CitizenSdkAccountBalanceInfo, CitizenSdkAccountId, CitizenSdkAccountNonceInfo,
    CitizenSdkFeeSnapshotInfo, CitizenSdkFinalizedTransferInfo, CitizenSdkHistoryCursorInfo,
    CitizenSdkHistoryInfo, CitizenSdkHistoryRecordInfo, CitizenSdkHostBoolResultV1,
    CitizenSdkHostBytesResultV1, CitizenSdkHostHash32, CitizenSdkHostId128,
    CitizenSdkHostPublicStoreV1, CitizenSdkHostRecordResultV1, CitizenSdkHostSecretRefV1,
    CitizenSdkHostSecretVaultV1, CitizenSdkHostSecureStoreV1, CitizenSdkHostServicesV1,
    CitizenSdkHostStatusResultV1, CitizenSdkHostVaultAvailabilityResultV1,
    CitizenSdkHostWalletKeyRefV1, CitizenSdkMutableBytesView, CitizenSdkPreparedWalletInfo,
    CitizenSdkResultKind, CitizenSdkU128, CitizenSdkWalletAccountInfo, CitizenSdkWalletProfileInfo,
    CitizenSdkWalletTransferInfo,
};

fn rust_exports(source: &str) -> BTreeSet<String> {
    let lines: Vec<_> = source.lines().collect();
    let mut exports = BTreeSet::new();
    for (index, line) in lines.iter().enumerate() {
        if line.trim() != "#[no_mangle]" {
            continue;
        }
        let declaration = lines
            .iter()
            .skip(index + 1)
            .find(|candidate| candidate.contains("fn "))
            .unwrap_or_else(|| panic!("no_mangle without function declaration"));
        let name = declaration
            .split("fn ")
            .nth(1)
            .and_then(|value| value.split(['(', '<']).next())
            .unwrap_or_else(|| panic!("cannot parse export: {declaration}"));
        if name == "$name" {
            continue; // 裁剪构建的宏模板不是额外公开符号。
        }
        assert!(exports.insert(name.to_owned()), "duplicate export {name}");
    }
    exports.retain(|name| !name.starts_with("citizensdk_internal_"));
    exports
}

fn header_functions(header: &str) -> BTreeSet<String> {
    let bytes = header.as_bytes();
    let mut functions = BTreeSet::new();
    let mut offset = 0;
    while let Some(relative) = header[offset..].find("citizensdk_") {
        let start = offset + relative;
        let mut end = start;
        while end < bytes.len()
            && (bytes[end].is_ascii_lowercase()
                || bytes[end].is_ascii_digit()
                || bytes[end] == b'_')
        {
            end += 1;
        }
        let following = header[end..].trim_start();
        if following.starts_with('(') {
            functions.insert(header[start..end].to_owned());
        }
        offset = end.max(start + 1);
    }
    functions
}

#[test]
fn base_wallet_and_qr_exports_are_exact_and_disjoint() {
    let old = rust_exports(include_str!("../src/lib.rs"));
    let wallet = rust_exports(include_str!("../src/wallet_abi.rs"));
    let qr = rust_exports(include_str!("../src/qr_abi.rs"));
    assert_eq!(old.len(), 39);
    assert_eq!(wallet.len(), 41);
    assert_eq!(qr.len(), 9);
    assert!(old.is_disjoint(&wallet));
    assert!(old.is_disjoint(&qr));
    assert!(wallet.is_disjoint(&qr));

    let expected_wallet: BTreeSet<_> = [
        "citizensdk_create_with_host",
        "citizensdk_validate_wallet_password",
        "citizensdk_validate_wallet_mnemonic",
        "citizensdk_wallet_word_suggestions",
        "citizensdk_get_genesis_hash",
        "citizensdk_get_finalized_account_balances",
        "citizensdk_get_finalized_account_balance",
        "citizensdk_get_account_nonce",
        "citizensdk_get_best_fee_snapshot",
        "citizensdk_get_wallet_profile",
        "citizensdk_prepare_wallet_creation",
        "citizensdk_prepared_wallet_copy_mnemonic",
        "citizensdk_prepared_wallet_release",
        "citizensdk_commit_wallet_creation",
        "citizensdk_import_wallet",
        "citizensdk_add_wallet_accounts",
        "citizensdk_set_active_wallet_account",
        "citizensdk_rename_wallet_account",
        "citizensdk_delete_wallet_account",
        "citizensdk_delete_wallet",
        "citizensdk_reconcile_wallet_cleanup",
        "citizensdk_sign_wallet_payload",
        "citizensdk_transfer_with_remark",
        "citizensdk_initialize_finalized_history",
        "citizensdk_sync_finalized_history_batch",
        "citizensdk_result_get_account_balance",
        "citizensdk_result_get_account_balance_count",
        "citizensdk_result_get_account_balance_at",
        "citizensdk_result_get_account_nonce",
        "citizensdk_result_get_fee_snapshot",
        "citizensdk_result_estimate_fee",
        "citizensdk_result_get_wallet_profile",
        "citizensdk_result_get_wallet_account_count",
        "citizensdk_result_get_wallet_account",
        "citizensdk_result_get_signature",
        "citizensdk_result_get_prepared_wallet",
        "citizensdk_result_get_wallet_transfer",
        "citizensdk_result_get_history_info",
        "citizensdk_result_get_history_cursor",
        "citizensdk_result_get_history_record",
        "citizensdk_result_get_finalized_transfer",
    ]
    .into_iter()
    .map(str::to_owned)
    .collect();
    assert_eq!(wallet, expected_wallet);

    let header = header_functions(include_str!("../../../include/citizensdk.h"));
    let all: BTreeSet<_> = old.union(&wallet).chain(qr.iter()).cloned().collect();
    assert_eq!(header, all);
}

#[test]
fn new_export_names_contain_no_rpc_key_or_raw_transaction_escape_hatch() {
    let wallet = rust_exports(include_str!("../src/wallet_abi.rs"));
    for symbol in wallet {
        for forbidden in [
            "rpc",
            "private_key",
            "mini_secret",
            "raw_signer",
            "signed_extrinsic",
        ] {
            assert!(!symbol.contains(forbidden), "forbidden export {symbol}");
        }
    }
}

#[test]
fn appended_result_values_and_portable_product_layouts_are_frozen() {
    assert_eq!(CitizenSdkResultKind::AccountBalance as u32, 9);
    assert_eq!(CitizenSdkResultKind::AccountNonce as u32, 10);
    assert_eq!(CitizenSdkResultKind::FeeSnapshot as u32, 11);
    assert_eq!(CitizenSdkResultKind::WalletProfile as u32, 12);
    assert_eq!(CitizenSdkResultKind::WalletAccounts as u32, 13);
    assert_eq!(CitizenSdkResultKind::Signature as u32, 14);
    assert_eq!(CitizenSdkResultKind::PreparedWallet as u32, 15);
    assert_eq!(CitizenSdkResultKind::WalletTransfer as u32, 16);
    assert_eq!(CitizenSdkResultKind::TransactionHistory as u32, 17);
    assert_eq!(CitizenSdkResultKind::AccountBalances as u32, 18);
    assert_eq!(CitizenSdkResultKind::QrReview as u32, 19);
    assert_eq!(CitizenSdkResultKind::QrSigned as u32, 20);
    assert!(include_str!("../../../include/citizensdk_types.h")
        .contains("#define CITIZENSDK_RESULT_ACCOUNT_BALANCES UINT32_C(18)"));

    assert_eq!(size_of::<CitizenSdkU128>(), 16);
    assert_eq!(align_of::<CitizenSdkU128>(), 8);
    assert_eq!(size_of::<CitizenSdkAccountId>(), 32);
    assert_eq!(size_of::<CitizenSdkAccountBalanceInfo>(), 144);
    assert_eq!(size_of::<CitizenSdkAccountNonceInfo>(), 104);
    assert_eq!(size_of::<CitizenSdkFeeSnapshotInfo>(), 104);
    assert_eq!(size_of::<CitizenSdkWalletProfileInfo>(), 96);
    assert_eq!(size_of::<CitizenSdkWalletAccountInfo>(), 72);
    assert_eq!(size_of::<CitizenSdkPreparedWalletInfo>(), 16);
    assert_eq!(size_of::<CitizenSdkWalletTransferInfo>(), 144);
    assert_eq!(size_of::<CitizenSdkHistoryInfo>(), 32);
    assert_eq!(size_of::<CitizenSdkHistoryCursorInfo>(), 152);
    assert_eq!(size_of::<CitizenSdkHistoryRecordInfo>(), 320);
    assert_eq!(size_of::<CitizenSdkFinalizedTransferInfo>(), 216);
}

#[test]
fn chain_query_sources_keep_one_engine_path_and_no_wallet_probe_or_secret_dependency() {
    let source = include_str!("../src/wallet_abi.rs");
    let genesis = source
        .split("pub unsafe extern \"C\" fn citizensdk_get_genesis_hash(")
        .nth(1)
        .unwrap_or_else(|| panic!("missing genesis entry"))
        .split("#[no_mangle]")
        .next()
        .unwrap_or_default();
    assert!(genesis.contains("runtime.engine().genesis_hash()?"));
    assert!(!genesis.contains("refresh_provider_capabilities"));
    assert!(!genesis.contains("accept_and_write"));
    let balances = source
        .split("pub unsafe extern \"C\" fn citizensdk_get_finalized_account_balances(")
        .nth(1)
        .unwrap_or_else(|| panic!("missing batch entry"))
        .split("#[no_mangle]")
        .next()
        .unwrap_or_default();
    assert!(balances.contains("accept_and_write(runtime, out_request_id"));
    assert!(balances.contains("runtime.engine().finalized_account_balances(accounts)"));
    assert!(balances.contains("account_count == 0"));
    assert!(balances.contains("if !accounts.is_empty()"));
    assert!(balances.contains("runtime.refresh_chain_readiness()?"));
    for forbidden in [
        "refresh_provider_capabilities",
        "wallet_profile",
        "secret_vault",
        "get_storage",
        "requests::accept(",
    ] {
        assert!(
            !balances.contains(forbidden),
            "batch entry must not bypass Engine: {forbidden}"
        );
    }
    for (symbol, accessor) in [
        (
            "citizensdk_result_get_account_balance_count",
            "ownership::account_balance_count(result)?",
        ),
        (
            "citizensdk_result_get_account_balance_at",
            "ownership::account_balance_at(result, index)?",
        ),
    ] {
        let declaration = format!("pub unsafe extern \"C\" fn {symbol}(");
        let projection = source
            .split(declaration.as_str())
            .nth(1)
            .unwrap_or_else(|| panic!("missing batch projection"))
            .split("#[no_mangle]")
            .next()
            .unwrap_or_default();
        assert!(projection.contains(accessor));
        assert!(
            !projection.contains("ownership::get("),
            "per-item read must not clone the complete batch"
        );
    }
}

#[test]
fn host_v1_layout_matches_the_c_header_contract() {
    assert_eq!(size_of::<CitizenSdkMutableBytesView>(), 16);
    assert_eq!(size_of::<CitizenSdkHostHash32>(), 32);
    assert_eq!(size_of::<CitizenSdkHostId128>(), 16);
    assert_eq!(size_of::<CitizenSdkHostSecretRefV1>(), 80);
    assert_eq!(size_of::<CitizenSdkHostWalletKeyRefV1>(), 32);
    assert_eq!(size_of::<CitizenSdkHostRecordResultV1>(), 56);
    assert_eq!(size_of::<CitizenSdkHostStatusResultV1>(), 24);
    assert_eq!(size_of::<CitizenSdkHostBoolResultV1>(), 32);
    assert_eq!(size_of::<CitizenSdkHostVaultAvailabilityResultV1>(), 24);
    assert_eq!(size_of::<CitizenSdkHostBytesResultV1>(), 40);
    assert_eq!(size_of::<CitizenSdkHostPublicStoreV1>(), 72);
    assert_eq!(size_of::<CitizenSdkHostSecureStoreV1>(), 48);
    assert_eq!(size_of::<CitizenSdkHostSecretVaultV1>(), 64);
    assert_eq!(size_of::<CitizenSdkHostServicesV1>(), 32);
}

#[test]
fn header_exposes_mutable_dek_output_but_no_plaintext_completion_kind() {
    let types = include_str!("../../../include/citizensdk_types.h");
    assert!(types.contains("citizensdk_mutable_bytes_view_t plaintext_dek_out"));
    assert!(types.contains("CITIZENSDK_HOST_BYTES_WRAPPED_DEK"));
    assert!(!types.contains("HOST_BYTES_PLAINTEXT_DEK"));
    assert!(!types.contains("host_sign"));
}

#[test]
fn module_validation_rejects_invalid_or_uncompiled_combinations() {
    use citizen_sdk_contracts::Modules;
    use citizensdk::{citizensdk_validate_modules, CitizenSdkErrorCode};
    for bits in [
        0,
        64,
        Modules::ALL | 64,
        Modules::TRANSACTIONS,
        Modules::HISTORY,
    ] {
        assert_eq!(
            citizensdk_validate_modules(bits),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
    }
    let compiled = (if cfg!(feature = "wallet") {
        Modules::WALLET
    } else {
        0
    }) | (if cfg!(feature = "signing") {
        Modules::SIGNING
    } else {
        0
    }) | (if cfg!(feature = "chain") {
        Modules::CHAIN
    } else {
        0
    }) | (if cfg!(feature = "transactions") {
        Modules::TRANSACTIONS
    } else {
        0
    }) | (if cfg!(feature = "history") {
        Modules::HISTORY
    } else {
        0
    }) | (if cfg!(feature = "qr") {
        Modules::QR
    } else {
        0
    });
    for bits in [
        Modules::WALLET,
        Modules::SIGNING,
        Modules::CHAIN,
        Modules::CHAIN | Modules::TRANSACTIONS,
        Modules::CHAIN | Modules::HISTORY,
        Modules::QR,
        Modules::QR | Modules::SIGNING | Modules::CHAIN,
        Modules::ALL,
    ] {
        let expected = if bits & !compiled == 0 {
            CitizenSdkErrorCode::Ok
        } else {
            CitizenSdkErrorCode::Unsupported
        };
        assert_eq!(citizensdk_validate_modules(bits), expected.as_i32());
    }
}

#[cfg(feature = "signing")]
#[test]
fn pure_signature_verification_needs_no_wallet_vault_or_chain_instance() {
    use citizensdk::{citizensdk_verify_signature, CitizenSdkBytesView, CitizenSdkErrorCode};
    fn bytes(value: &str) -> Vec<u8> {
        value
            .as_bytes()
            .chunks_exact(2)
            .map(|pair| {
                let pair = std::str::from_utf8(pair).expect("公开金标为ASCII");
                u8::from_str_radix(pair, 16).expect("公开金标为hex")
            })
            .collect()
    }
    fn view(value: &[u8]) -> CitizenSdkBytesView {
        CitizenSdkBytesView {
            data: value.as_ptr(),
            len: value.len() as u64,
        }
    }
    // 只读取既有公开交易金标的公钥、消息和签名，不导入或生成私钥。
    let vector: serde_json::Value = serde_json::from_str(include_str!(
        "../../../test/transaction/citizenchain-transfer-build-v1.json"
    ))
    .expect("公开金标JSON");
    let public_key = bytes(vector["transfer"]["source_account_id"].as_str().unwrap());
    let account = CitizenSdkAccountId {
        bytes: public_key.try_into().expect("32字节公钥"),
    };
    let signature = bytes(
        vector["public_test_signature"]["signature"]
            .as_str()
            .unwrap(),
    );
    let mut message = bytes(vector["expected"]["signing_message"].as_str().unwrap());
    let mut valid = 0;
    // SAFETY: the fixture views and output remain live through each synchronous call.
    unsafe {
        assert_eq!(
            citizensdk_verify_signature(&account, view(&signature), view(&message), &mut valid),
            CitizenSdkErrorCode::Ok.as_i32()
        );
        assert_eq!(valid, 1);
        message[0] ^= 1;
        assert_eq!(
            citizensdk_verify_signature(&account, view(&signature), view(&message), &mut valid),
            CitizenSdkErrorCode::Ok.as_i32()
        );
        assert_eq!(valid, 0);
        assert_eq!(
            citizensdk_verify_signature(
                &account,
                view(&signature[..63]),
                view(&message),
                &mut valid
            ),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
    }
}

#[cfg(feature = "signing")]
#[test]
fn local_signing_create_rejects_absent_or_partial_secure_resources() {
    use citizen_sdk_contracts::Modules;
    use citizensdk::{
        citizensdk_create_with_modules, CitizenSdkCreateOptions, CitizenSdkErrorCode,
    };
    let empty = citizensdk::CitizenSdkBytesView {
        data: std::ptr::null(),
        len: 0,
    };
    let options = CitizenSdkCreateOptions {
        struct_size: size_of::<CitizenSdkCreateOptions>() as u32,
        abi_version: citizensdk::CITIZENSDK_ABI_VERSION,
        asset_manifest: empty,
        chain_spec: empty,
        light_sync_state: empty,
        system_name: empty,
        system_version: empty,
    };
    let mut handle = 0;
    // SAFETY: options and output are valid; the null host explicitly supplies no resources.
    unsafe {
        assert_eq!(
            citizensdk_create_with_modules(
                &options,
                std::ptr::null(),
                Modules::SIGNING,
                &mut handle
            ),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
    }
    assert_eq!(handle, 0);
    let secure = CitizenSdkHostSecureStoreV1::default();
    let services = CitizenSdkHostServicesV1 {
        secure_store: &secure,
        ..CitizenSdkHostServicesV1::default()
    };
    // SAFETY: all provided vtables remain readable; absent callbacks must be rejected, never called.
    unsafe {
        assert_eq!(
            citizensdk_create_with_modules(&options, &services, Modules::SIGNING, &mut handle),
            CitizenSdkErrorCode::InvalidArgument.as_i32()
        );
    }
    assert_eq!(handle, 0);
}
