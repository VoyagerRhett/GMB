#include <stddef.h>
#include "citizensdk.h"

#ifdef __cplusplus
#include <type_traits>
#define ABI_SIZE(type, expected)                                                \
  static_assert(sizeof(type) == (expected), #type " size ABI")
#define ABI_ALIGN(type, expected)                                               \
  static_assert(alignof(type) == (expected), #type " align ABI")
#define ABI_OFFSET(type, field, expected)                                       \
  static_assert(offsetof(type, field) == (expected), #type "." #field " ABI")
#define ABI_FUNCTION(name, return_type, ...)                                    \
  using name##_signature_t = return_type (*)(__VA_ARGS__);                      \
  name##_signature_t const name##_reference = &(name);                          \
  static_assert(                                                               \
      std::is_same<decltype(&(name)), name##_signature_t>::value,               \
      #name " signature ABI")
#else
#define ABI_SIZE(type, expected)                                                \
  _Static_assert(sizeof(type) == (expected), #type " size ABI")
#define ABI_ALIGN(type, expected)                                               \
  _Static_assert(_Alignof(type) == (expected), #type " align ABI")
#define ABI_OFFSET(type, field, expected)                                       \
  _Static_assert(offsetof(type, field) == (expected), #type "." #field " ABI")
#define ABI_FUNCTION(name, return_type, ...)                                    \
  typedef return_type (*name##_signature_t)(__VA_ARGS__);                       \
  name##_signature_t const name##_reference = &(name);                          \
  _Static_assert(_Generic(&(name), name##_signature_t: 1, default: 0),          \
                 #name " signature ABI")
#endif

_Static_assert(sizeof(void *) == 8, "CitizenSDK v1 ABI requires 64-bit hosts");

ABI_SIZE(citizensdk_bytes_view_t, 16);
ABI_OFFSET(citizensdk_bytes_view_t, data, 0);
ABI_OFFSET(citizensdk_bytes_view_t, len, 8);

ABI_SIZE(citizensdk_create_options_t, 88);
ABI_OFFSET(citizensdk_create_options_t, struct_size, 0);
ABI_OFFSET(citizensdk_create_options_t, abi_version, 4);
ABI_OFFSET(citizensdk_create_options_t, asset_manifest, 8);
ABI_OFFSET(citizensdk_create_options_t, chain_spec, 24);
ABI_OFFSET(citizensdk_create_options_t, light_sync_state, 40);
ABI_OFFSET(citizensdk_create_options_t, system_name, 56);
ABI_OFFSET(citizensdk_create_options_t, system_version, 72);

ABI_SIZE(citizensdk_block_ref_t, 56);
ABI_OFFSET(citizensdk_block_ref_t, struct_size, 0);
ABI_OFFSET(citizensdk_block_ref_t, abi_version, 4);
ABI_OFFSET(citizensdk_block_ref_t, hash, 8);
ABI_OFFSET(citizensdk_block_ref_t, number, 40);
ABI_OFFSET(citizensdk_block_ref_t, finality, 48);
ABI_OFFSET(citizensdk_block_ref_t, reserved, 52);

ABI_SIZE(citizensdk_capability_status_t, 16);
ABI_OFFSET(citizensdk_capability_status_t, name, 0);
ABI_OFFSET(citizensdk_capability_status_t, reason, 4);
ABI_OFFSET(citizensdk_capability_status_t, supported, 8);
ABI_OFFSET(citizensdk_capability_status_t, available, 9);
ABI_OFFSET(citizensdk_capability_status_t, enabled, 10);
ABI_OFFSET(citizensdk_capability_status_t, ready, 11);
ABI_OFFSET(citizensdk_capability_status_t, reserved, 12);

ABI_SIZE(citizensdk_capability_snapshot_t, 184);
ABI_OFFSET(citizensdk_capability_snapshot_t, struct_size, 0);
ABI_OFFSET(citizensdk_capability_snapshot_t, abi_version, 4);
ABI_OFFSET(citizensdk_capability_snapshot_t, revision, 8);
ABI_OFFSET(citizensdk_capability_snapshot_t, count, 16);
ABI_OFFSET(citizensdk_capability_snapshot_t, reserved, 20);
ABI_OFFSET(citizensdk_capability_snapshot_t, statuses, 24);

ABI_SIZE(citizensdk_event_t, 48);
ABI_OFFSET(citizensdk_event_t, struct_size, 0);
ABI_OFFSET(citizensdk_event_t, abi_version, 4);
ABI_OFFSET(citizensdk_event_t, event_type, 8);
ABI_OFFSET(citizensdk_event_t, reserved, 12);
ABI_OFFSET(citizensdk_event_t, sequence, 16);
ABI_OFFSET(citizensdk_event_t, request_id, 24);
ABI_OFFSET(citizensdk_event_t, result, 32);
ABI_OFFSET(citizensdk_event_t, capability_revision, 40);

ABI_SIZE(citizensdk_result_info_t, 32);
ABI_OFFSET(citizensdk_result_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_result_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_result_info_t, error_code, 8);
ABI_OFFSET(citizensdk_result_info_t, kind, 12);
ABI_OFFSET(citizensdk_result_info_t, payload_len, 16);
ABI_OFFSET(citizensdk_result_info_t, error_message_len, 24);

ABI_SIZE(citizensdk_runtime_context_info_t, 80);
ABI_OFFSET(citizensdk_runtime_context_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_runtime_context_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_runtime_context_info_t, block, 8);
ABI_OFFSET(citizensdk_runtime_context_info_t, spec_version, 64);
ABI_OFFSET(citizensdk_runtime_context_info_t, transaction_version, 68);
ABI_OFFSET(citizensdk_runtime_context_info_t, metadata_len, 72);

ABI_SIZE(citizensdk_watch_event_info_t, 112);
ABI_OFFSET(citizensdk_watch_event_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_watch_event_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_watch_event_info_t, status, 8);
ABI_OFFSET(citizensdk_watch_event_info_t, peer_count, 12);
ABI_OFFSET(citizensdk_watch_event_info_t, has_block, 16);
ABI_OFFSET(citizensdk_watch_event_info_t, has_replacement_hash, 17);
ABI_OFFSET(citizensdk_watch_event_info_t, reserved, 18);
ABI_OFFSET(citizensdk_watch_event_info_t, block, 24);
ABI_OFFSET(citizensdk_watch_event_info_t, replacement_hash, 80);

ABI_SIZE(citizensdk_execution_info_t, 88);
ABI_OFFSET(citizensdk_execution_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_execution_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_execution_info_t, status, 8);
ABI_OFFSET(citizensdk_execution_info_t, reason_or_dispatch_variant, 12);
ABI_OFFSET(citizensdk_execution_info_t, has_block, 16);
ABI_OFFSET(citizensdk_execution_info_t, has_extrinsic_index, 17);
ABI_OFFSET(citizensdk_execution_info_t, has_module, 18);
ABI_OFFSET(citizensdk_execution_info_t, reserved, 19);
ABI_OFFSET(citizensdk_execution_info_t, block, 24);
ABI_OFFSET(citizensdk_execution_info_t, extrinsic_index, 80);
ABI_OFFSET(citizensdk_execution_info_t, pallet_index, 84);
ABI_OFFSET(citizensdk_execution_info_t, error_index, 85);
ABI_OFFSET(citizensdk_execution_info_t, reserved_tail, 86);

ABI_SIZE(citizensdk_exported_state_info_t, 80);
ABI_OFFSET(citizensdk_exported_state_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_exported_state_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_exported_state_info_t, format_version, 8);
ABI_OFFSET(citizensdk_exported_state_info_t, reserved, 12);
ABI_OFFSET(citizensdk_exported_state_info_t, finalized, 16);
ABI_OFFSET(citizensdk_exported_state_info_t, database_len, 72);

ABI_SIZE(citizensdk_u128_t, 16);
ABI_ALIGN(citizensdk_u128_t, 8);
ABI_OFFSET(citizensdk_u128_t, low, 0);
ABI_OFFSET(citizensdk_u128_t, high, 8);

ABI_SIZE(citizensdk_account_id_t, 32);
ABI_ALIGN(citizensdk_account_id_t, 1);
ABI_OFFSET(citizensdk_account_id_t, bytes, 0);

ABI_SIZE(citizensdk_mutable_bytes_view_t, 16);
ABI_ALIGN(citizensdk_mutable_bytes_view_t, 8);
ABI_OFFSET(citizensdk_mutable_bytes_view_t, data, 0);
ABI_OFFSET(citizensdk_mutable_bytes_view_t, len, 8);

ABI_SIZE(citizensdk_host_hash32_t, 32);
ABI_ALIGN(citizensdk_host_hash32_t, 1);
ABI_OFFSET(citizensdk_host_hash32_t, bytes, 0);

ABI_SIZE(citizensdk_host_id128_t, 16);
ABI_ALIGN(citizensdk_host_id128_t, 1);
ABI_OFFSET(citizensdk_host_id128_t, bytes, 0);

ABI_SIZE(citizensdk_host_secret_ref_v1_t, 80);
ABI_ALIGN(citizensdk_host_secret_ref_v1_t, 4);
ABI_OFFSET(citizensdk_host_secret_ref_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_secret_ref_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_secret_ref_v1_t, wallet_index, 8);
ABI_OFFSET(citizensdk_host_secret_ref_v1_t, kind, 12);
ABI_OFFSET(citizensdk_host_secret_ref_v1_t, generation, 16);
ABI_OFFSET(citizensdk_host_secret_ref_v1_t, owner, 32);
ABI_OFFSET(citizensdk_host_secret_ref_v1_t, account_id, 48);

ABI_SIZE(citizensdk_host_wallet_key_ref_v1_t, 32);
ABI_ALIGN(citizensdk_host_wallet_key_ref_v1_t, 4);
ABI_OFFSET(citizensdk_host_wallet_key_ref_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_wallet_key_ref_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_wallet_key_ref_v1_t, wallet_index, 8);
ABI_OFFSET(citizensdk_host_wallet_key_ref_v1_t, reserved, 12);
ABI_OFFSET(citizensdk_host_wallet_key_ref_v1_t, generation, 16);

ABI_SIZE(citizensdk_host_record_result_v1_t, 56);
ABI_ALIGN(citizensdk_host_record_result_v1_t, 8);
ABI_OFFSET(citizensdk_host_record_result_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_record_result_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_record_result_v1_t, host_operation_id, 8);
ABI_OFFSET(citizensdk_host_record_result_v1_t, error_code, 16);
ABI_OFFSET(citizensdk_host_record_result_v1_t, domain, 20);
ABI_OFFSET(citizensdk_host_record_result_v1_t, present, 24);
ABI_OFFSET(citizensdk_host_record_result_v1_t, reserved, 25);
ABI_OFFSET(citizensdk_host_record_result_v1_t, revision, 32);
ABI_OFFSET(citizensdk_host_record_result_v1_t, record, 40);

ABI_SIZE(citizensdk_host_status_result_v1_t, 24);
ABI_ALIGN(citizensdk_host_status_result_v1_t, 8);
ABI_OFFSET(citizensdk_host_status_result_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_status_result_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_status_result_v1_t, host_operation_id, 8);
ABI_OFFSET(citizensdk_host_status_result_v1_t, error_code, 16);
ABI_OFFSET(citizensdk_host_status_result_v1_t, reserved, 20);

ABI_SIZE(citizensdk_host_bool_result_v1_t, 32);
ABI_ALIGN(citizensdk_host_bool_result_v1_t, 8);
ABI_OFFSET(citizensdk_host_bool_result_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_bool_result_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_bool_result_v1_t, host_operation_id, 8);
ABI_OFFSET(citizensdk_host_bool_result_v1_t, error_code, 16);
ABI_OFFSET(citizensdk_host_bool_result_v1_t, value, 20);
ABI_OFFSET(citizensdk_host_bool_result_v1_t, reserved, 21);

ABI_SIZE(citizensdk_host_vault_availability_result_v1_t, 24);
ABI_ALIGN(citizensdk_host_vault_availability_result_v1_t, 8);
ABI_OFFSET(citizensdk_host_vault_availability_result_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_vault_availability_result_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_vault_availability_result_v1_t, host_operation_id,
           8);
ABI_OFFSET(citizensdk_host_vault_availability_result_v1_t, error_code, 16);
ABI_OFFSET(citizensdk_host_vault_availability_result_v1_t, availability, 20);

ABI_SIZE(citizensdk_host_bytes_result_v1_t, 40);
ABI_ALIGN(citizensdk_host_bytes_result_v1_t, 8);
ABI_OFFSET(citizensdk_host_bytes_result_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_bytes_result_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_bytes_result_v1_t, host_operation_id, 8);
ABI_OFFSET(citizensdk_host_bytes_result_v1_t, error_code, 16);
ABI_OFFSET(citizensdk_host_bytes_result_v1_t, kind, 20);
ABI_OFFSET(citizensdk_host_bytes_result_v1_t, bytes, 24);

ABI_SIZE(citizensdk_host_public_store_v1_t, 72);
ABI_ALIGN(citizensdk_host_public_store_v1_t, 8);
ABI_OFFSET(citizensdk_host_public_store_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_public_store_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_public_store_v1_t, context, 8);
ABI_OFFSET(citizensdk_host_public_store_v1_t, chain_database_load, 16);
ABI_OFFSET(citizensdk_host_public_store_v1_t,
           chain_database_compare_and_swap, 24);
ABI_OFFSET(citizensdk_host_public_store_v1_t, runtime_cache_load, 32);
ABI_OFFSET(citizensdk_host_public_store_v1_t, runtime_cache_store, 40);
ABI_OFFSET(citizensdk_host_public_store_v1_t, runtime_cache_delete, 48);
ABI_OFFSET(citizensdk_host_public_store_v1_t, transaction_history_load, 56);
ABI_OFFSET(citizensdk_host_public_store_v1_t,
           transaction_history_compare_and_swap, 64);

ABI_SIZE(citizensdk_host_secure_store_v1_t, 48);
ABI_ALIGN(citizensdk_host_secure_store_v1_t, 8);
ABI_OFFSET(citizensdk_host_secure_store_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_secure_store_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_secure_store_v1_t, context, 8);
ABI_OFFSET(citizensdk_host_secure_store_v1_t, wallet_profile_load, 16);
ABI_OFFSET(citizensdk_host_secure_store_v1_t,
           wallet_profile_compare_and_swap, 24);
ABI_OFFSET(citizensdk_host_secure_store_v1_t, encrypted_secret_blob_load, 32);
ABI_OFFSET(citizensdk_host_secure_store_v1_t,
           encrypted_secret_blob_compare_and_swap, 40);

ABI_SIZE(citizensdk_host_secret_vault_v1_t, 64);
ABI_ALIGN(citizensdk_host_secret_vault_v1_t, 8);
ABI_OFFSET(citizensdk_host_secret_vault_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_secret_vault_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_secret_vault_v1_t, context, 8);
ABI_OFFSET(citizensdk_host_secret_vault_v1_t, availability, 16);
ABI_OFFSET(citizensdk_host_secret_vault_v1_t, ensure_wallet_kek, 24);
ABI_OFFSET(citizensdk_host_secret_vault_v1_t, has_wallet_kek, 32);
ABI_OFFSET(citizensdk_host_secret_vault_v1_t, wrap_dek, 40);
ABI_OFFSET(citizensdk_host_secret_vault_v1_t, unwrap_dek, 48);
ABI_OFFSET(citizensdk_host_secret_vault_v1_t, retire_wallet_kek, 56);

ABI_SIZE(citizensdk_host_services_v1_t, 32);
ABI_ALIGN(citizensdk_host_services_v1_t, 8);
ABI_OFFSET(citizensdk_host_services_v1_t, struct_size, 0);
ABI_OFFSET(citizensdk_host_services_v1_t, abi_version, 4);
ABI_OFFSET(citizensdk_host_services_v1_t, public_store, 8);
ABI_OFFSET(citizensdk_host_services_v1_t, secure_store, 16);
ABI_OFFSET(citizensdk_host_services_v1_t, secret_vault, 24);

ABI_SIZE(citizensdk_account_balance_info_t, 144);
ABI_ALIGN(citizensdk_account_balance_info_t, 8);
ABI_OFFSET(citizensdk_account_balance_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_account_balance_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_account_balance_info_t, block, 8);
ABI_OFFSET(citizensdk_account_balance_info_t, account_id, 64);
ABI_OFFSET(citizensdk_account_balance_info_t, free_fen, 96);
ABI_OFFSET(citizensdk_account_balance_info_t, reserved_fen, 112);
ABI_OFFSET(citizensdk_account_balance_info_t, total_fen, 128);

ABI_SIZE(citizensdk_account_nonce_info_t, 104);
ABI_ALIGN(citizensdk_account_nonce_info_t, 8);
ABI_OFFSET(citizensdk_account_nonce_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_account_nonce_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_account_nonce_info_t, best_block, 8);
ABI_OFFSET(citizensdk_account_nonce_info_t, account_id, 64);
ABI_OFFSET(citizensdk_account_nonce_info_t, nonce, 96);

ABI_SIZE(citizensdk_fee_snapshot_info_t, 104);
ABI_ALIGN(citizensdk_fee_snapshot_info_t, 8);
ABI_OFFSET(citizensdk_fee_snapshot_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_fee_snapshot_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_fee_snapshot_info_t, best_block, 8);
ABI_OFFSET(citizensdk_fee_snapshot_info_t, fee_rate_parts, 64);
ABI_OFFSET(citizensdk_fee_snapshot_info_t, reserved, 68);
ABI_OFFSET(citizensdk_fee_snapshot_info_t, minimum_fee_fen, 72);
ABI_OFFSET(citizensdk_fee_snapshot_info_t, existential_deposit_fen, 88);

ABI_SIZE(citizensdk_wallet_profile_info_t, 96);
ABI_ALIGN(citizensdk_wallet_profile_info_t, 8);
ABI_OFFSET(citizensdk_wallet_profile_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_wallet_profile_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_wallet_profile_info_t, present, 8);
ABI_OFFSET(citizensdk_wallet_profile_info_t, origin, 12);
ABI_OFFSET(citizensdk_wallet_profile_info_t, wallet_index, 16);
ABI_OFFSET(citizensdk_wallet_profile_info_t, account_count, 20);
ABI_OFFSET(citizensdk_wallet_profile_info_t, created_at_millis, 24);
ABI_OFFSET(citizensdk_wallet_profile_info_t, master_account_id, 32);
ABI_OFFSET(citizensdk_wallet_profile_info_t, active_account_id, 64);

ABI_SIZE(citizensdk_wallet_account_info_t, 72);
ABI_ALIGN(citizensdk_wallet_account_info_t, 8);
ABI_OFFSET(citizensdk_wallet_account_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_wallet_account_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_wallet_account_info_t, index, 8);
ABI_OFFSET(citizensdk_wallet_account_info_t, is_active, 12);
ABI_OFFSET(citizensdk_wallet_account_info_t, account_id, 16);
ABI_OFFSET(citizensdk_wallet_account_info_t, created_at_millis, 48);
ABI_OFFSET(citizensdk_wallet_account_info_t, ss58_address_len, 56);
ABI_OFFSET(citizensdk_wallet_account_info_t, name_len, 64);

ABI_SIZE(citizensdk_prepared_wallet_info_t, 16);
ABI_ALIGN(citizensdk_prepared_wallet_info_t, 8);
ABI_OFFSET(citizensdk_prepared_wallet_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_prepared_wallet_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_prepared_wallet_info_t, prepared_wallet, 8);

ABI_SIZE(citizensdk_wallet_transfer_info_t, 144);
ABI_ALIGN(citizensdk_wallet_transfer_info_t, 8);
ABI_OFFSET(citizensdk_wallet_transfer_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_wallet_transfer_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_wallet_transfer_info_t, transaction_hash, 8);
ABI_OFFSET(citizensdk_wallet_transfer_info_t, resolution, 40);
ABI_OFFSET(citizensdk_wallet_transfer_info_t, has_execution, 44);
ABI_OFFSET(citizensdk_wallet_transfer_info_t, execution, 48);
ABI_OFFSET(citizensdk_wallet_transfer_info_t, pool_rejection_reason_len, 136);

ABI_SIZE(citizensdk_history_info_t, 32);
ABI_ALIGN(citizensdk_history_info_t, 8);
ABI_OFFSET(citizensdk_history_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_history_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_history_info_t, revision, 8);
ABI_OFFSET(citizensdk_history_info_t, cursor_count, 16);
ABI_OFFSET(citizensdk_history_info_t, record_count, 20);
ABI_OFFSET(citizensdk_history_info_t, transfer_count, 24);
ABI_OFFSET(citizensdk_history_info_t, reserved, 28);

ABI_SIZE(citizensdk_history_cursor_info_t, 152);
ABI_ALIGN(citizensdk_history_cursor_info_t, 8);
ABI_OFFSET(citizensdk_history_cursor_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_history_cursor_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_history_cursor_info_t, account_id, 8);
ABI_OFFSET(citizensdk_history_cursor_info_t, tracking_start_block, 40);
ABI_OFFSET(citizensdk_history_cursor_info_t, last_synced_block, 96);

ABI_SIZE(citizensdk_history_record_info_t, 320);
ABI_ALIGN(citizensdk_history_record_info_t, 8);
ABI_OFFSET(citizensdk_history_record_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_history_record_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_history_record_info_t, account_id, 8);
ABI_OFFSET(citizensdk_history_record_info_t, transaction_hash, 40);
ABI_OFFSET(citizensdk_history_record_info_t, nonce, 72);
ABI_OFFSET(citizensdk_history_record_info_t, destination_account_id, 80);
ABI_OFFSET(citizensdk_history_record_info_t, amount_fen, 112);
ABI_OFFSET(citizensdk_history_record_info_t, status, 128);
ABI_OFFSET(citizensdk_history_record_info_t, has_block, 132);
ABI_OFFSET(citizensdk_history_record_info_t, block, 136);
ABI_OFFSET(citizensdk_history_record_info_t, has_execution, 192);
ABI_OFFSET(citizensdk_history_record_info_t, reserved, 196);
ABI_OFFSET(citizensdk_history_record_info_t, execution, 200);
ABI_OFFSET(citizensdk_history_record_info_t, created_at_millis, 288);
ABI_OFFSET(citizensdk_history_record_info_t, updated_at_millis, 296);
ABI_OFFSET(citizensdk_history_record_info_t, remark_len, 304);
ABI_OFFSET(citizensdk_history_record_info_t, pool_rejection_reason_len, 312);

ABI_SIZE(citizensdk_finalized_transfer_info_t, 216);
ABI_ALIGN(citizensdk_finalized_transfer_info_t, 8);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, struct_size, 0);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, abi_version, 4);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, tracked_account_id, 8);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, from_account_id, 40);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, to_account_id, 72);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, amount_fen, 104);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, block, 120);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, event_record_index, 176);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, has_extrinsic_index, 180);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, extrinsic_index, 184);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, direction, 188);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, source_pallet_len, 192);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, remark_display_len, 200);
ABI_OFFSET(citizensdk_finalized_transfer_info_t, remark_bytes_len, 208);

_Static_assert(CITIZENSDK_CAPABILITY_COUNT == 10, "capability count ABI");
_Static_assert(CITIZENSDK_UNVERIFIED_PROVIDER_FAILURE == 12,
               "unverified reason ABI");
_Static_assert(CITIZENSDK_DISPATCH_ERROR_ROOT_NOT_ALLOWED == 13,
               "dispatch variant ABI");

_Static_assert(CITIZENSDK_HOST_DEK_BYTES == 32, "host DEK bytes ABI");
_Static_assert(CITIZENSDK_HOST_RECORD_CHAIN_DATABASE == 1,
               "host record domain ABI");
_Static_assert(CITIZENSDK_HOST_RECORD_RUNTIME_CACHE == 2,
               "host record domain ABI");
_Static_assert(CITIZENSDK_HOST_RECORD_WALLET_PROFILE == 3,
               "host record domain ABI");
_Static_assert(CITIZENSDK_HOST_RECORD_TRANSACTION_HISTORY == 4,
               "host record domain ABI");
_Static_assert(CITIZENSDK_HOST_RECORD_ENCRYPTED_SECRET_BLOB == 5,
               "host record domain ABI");
_Static_assert(CITIZENSDK_HOST_SECRET_ACCOUNT_MINI_SECRET == 1,
               "host secret kind ABI");
_Static_assert(CITIZENSDK_HOST_VAULT_AVAILABLE == 1,
               "host vault availability ABI");
_Static_assert(CITIZENSDK_HOST_VAULT_NO_STRONG_USER_AUTHENTICATION == 2,
               "host vault availability ABI");
_Static_assert(CITIZENSDK_HOST_VAULT_UNSUPPORTED == 3,
               "host vault availability ABI");
_Static_assert(CITIZENSDK_HOST_VAULT_UNAVAILABLE == 4,
               "host vault availability ABI");
_Static_assert(CITIZENSDK_HOST_BYTES_WRAPPED_DEK == 1,
               "host bytes kind ABI");
_Static_assert(CITIZENSDK_RESULT_ACCOUNT_BALANCE == 9, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_ACCOUNT_NONCE == 10, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_FEE_SNAPSHOT == 11, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_WALLET_PROFILE == 12, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_WALLET_ACCOUNTS == 13, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_SIGNATURE == 14, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_PREPARED_WALLET == 15, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_WALLET_TRANSFER == 16, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_TRANSACTION_HISTORY == 17,
               "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_ACCOUNT_BALANCES == 18, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_QR_REVIEW == 19, "result kind ABI");
_Static_assert(CITIZENSDK_RESULT_QR_SIGNED == 20, "result kind ABI");
_Static_assert(CITIZENSDK_WALLET_WORDS_12 == 12, "wallet word count ABI");
_Static_assert(CITIZENSDK_WALLET_WORDS_18 == 18, "wallet word count ABI");
_Static_assert(CITIZENSDK_WALLET_WORDS_24 == 24, "wallet word count ABI");
_Static_assert(CITIZENSDK_WALLET_ORIGIN_CREATED == 1, "wallet origin ABI");
_Static_assert(CITIZENSDK_WALLET_ORIGIN_IMPORTED == 2, "wallet origin ABI");
_Static_assert(CITIZENSDK_HISTORY_PENDING == 1, "history status ABI");
_Static_assert(CITIZENSDK_HISTORY_IN_BLOCK == 2, "history status ABI");
_Static_assert(CITIZENSDK_HISTORY_POOL_REJECTED == 3, "history status ABI");
_Static_assert(CITIZENSDK_HISTORY_FINALIZED_SUCCESS == 4,
               "history status ABI");
_Static_assert(CITIZENSDK_HISTORY_FINALIZED_FAILED == 5,
               "history status ABI");
_Static_assert(CITIZENSDK_TRANSFER_FINALIZED_SUCCESS == 1,
               "transfer resolution ABI");
_Static_assert(CITIZENSDK_TRANSFER_FINALIZED_FAILED == 2,
               "transfer resolution ABI");
_Static_assert(CITIZENSDK_TRANSFER_POOL_REJECTED == 3,
               "transfer resolution ABI");
_Static_assert(CITIZENSDK_TRANSFER_OUTGOING == 1, "transfer direction ABI");
_Static_assert(CITIZENSDK_TRANSFER_INCOMING == 2, "transfer direction ABI");

ABI_FUNCTION(citizensdk_abi_version, uint32_t, void);
ABI_FUNCTION(citizensdk_create_options_size, uint32_t, void);
ABI_FUNCTION(citizensdk_validate_modules, citizensdk_error_code_t, uint32_t);
ABI_FUNCTION(citizensdk_create_with_modules, citizensdk_error_code_t,
             const citizensdk_create_options_t *,
             const citizensdk_host_services_v1_t *, uint32_t, citizensdk_handle_t *);
ABI_FUNCTION(citizensdk_verify_signature, citizensdk_error_code_t,
             const citizensdk_account_id_t *, citizensdk_bytes_view_t,
             citizensdk_bytes_view_t, uint8_t *);
ABI_FUNCTION(citizensdk_create, citizensdk_error_code_t,
             const citizensdk_create_options_t *, citizensdk_handle_t *);
ABI_FUNCTION(citizensdk_create_with_host, citizensdk_error_code_t,
             const citizensdk_create_options_t *,
             const citizensdk_host_services_v1_t *, citizensdk_handle_t *);
ABI_FUNCTION(citizensdk_destroy, citizensdk_error_code_t, citizensdk_handle_t);
ABI_FUNCTION(citizensdk_set_event_callback, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_event_callback_t, void *);
ABI_FUNCTION(citizensdk_get_capabilities, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_capability_snapshot_t *);
ABI_FUNCTION(citizensdk_get_lifecycle, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_lifecycle_t *);
ABI_FUNCTION(citizensdk_subscribe_capability_changes, citizensdk_error_code_t,
             citizensdk_handle_t);
ABI_FUNCTION(citizensdk_unsubscribe_capability_changes,
             citizensdk_error_code_t, citizensdk_handle_t);
ABI_FUNCTION(citizensdk_start, citizensdk_error_code_t, citizensdk_handle_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_stop, citizensdk_error_code_t, citizensdk_handle_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_cancel_request, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_request_id_t);
ABI_FUNCTION(citizensdk_refresh_capabilities, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_get_best_head, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_get_finalized_head, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_get_storage_at, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_block_ref_t *,
             citizensdk_bytes_view_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_get_storage_batch_at, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_block_ref_t *,
             const citizensdk_bytes_view_t *, uint32_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_get_runtime_context_at, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_block_ref_t *,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_get_finalized_account_balance,
             citizensdk_error_code_t, citizensdk_handle_t,
             const citizensdk_account_id_t *, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_get_genesis_hash, citizensdk_error_code_t,
             citizensdk_handle_t, uint8_t *);
ABI_FUNCTION(citizensdk_get_finalized_account_balances, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_account_id_t *, uint32_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_get_account_nonce, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_account_id_t *,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_get_best_fee_snapshot, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_qr_parse, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_bytes_view_t,
             uint8_t *, uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_qr_create_sign_request, citizensdk_error_code_t,
             citizensdk_handle_t, uint16_t, const citizensdk_account_id_t *,
             citizensdk_bytes_view_t, uint64_t, uint8_t *, uint64_t,
             uint64_t *);
ABI_FUNCTION(citizensdk_review_qr_sign_request, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_bytes_view_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_sign_qr_request, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_result_handle_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_result_copy_qr, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint8_t *, uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_qr_consume_sign_response, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_bytes_view_t, uint8_t *);
ABI_FUNCTION(citizensdk_qr_cancel_sign_request, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_bytes_view_t, uint8_t *);
ABI_FUNCTION(citizensdk_qr_encode_account_id, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_account_id_t *, uint8_t *,
             uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_qr_encode_user_transfer, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_bytes_view_t, uint64_t,
             const citizensdk_account_id_t *, citizensdk_bytes_view_t,
             citizensdk_bytes_view_t, citizensdk_bytes_view_t,
             citizensdk_bytes_view_t, uint8_t *, uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_get_wallet_profile, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_validate_wallet_password, citizensdk_error_code_t,
             citizensdk_bytes_view_t);
ABI_FUNCTION(citizensdk_validate_wallet_mnemonic, citizensdk_error_code_t,
             citizensdk_bytes_view_t, citizensdk_wallet_word_count_t);
ABI_FUNCTION(citizensdk_wallet_word_suggestions, citizensdk_error_code_t,
             citizensdk_bytes_view_t, uint8_t *, uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_prepare_wallet_creation, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_wallet_word_count_t,
             citizensdk_bytes_view_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_prepared_wallet_copy_mnemonic,
             citizensdk_error_code_t, citizensdk_handle_t,
             citizensdk_prepared_wallet_handle_t, uint8_t *, uint64_t,
             uint64_t *);
ABI_FUNCTION(citizensdk_prepared_wallet_release, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_prepared_wallet_handle_t);
ABI_FUNCTION(citizensdk_commit_wallet_creation, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_prepared_wallet_handle_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_import_wallet, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_bytes_view_t,
             citizensdk_bytes_view_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_add_wallet_accounts, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_bytes_view_t,
             citizensdk_bytes_view_t, const uint32_t *, uint32_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_set_active_wallet_account, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_account_id_t *,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_rename_wallet_account, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_account_id_t *,
             citizensdk_bytes_view_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_delete_wallet_account, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_account_id_t *,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_delete_wallet, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_reconcile_wallet_cleanup, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_sign_wallet_payload, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_account_id_t *,
             citizensdk_bytes_view_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_transfer_with_remark, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_account_id_t *,
             const citizensdk_account_id_t *, citizensdk_u128_t,
             citizensdk_bytes_view_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_initialize_finalized_history,
             citizensdk_error_code_t, citizensdk_handle_t,
             const citizensdk_account_id_t *, uint32_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_sync_finalized_history_batch,
             citizensdk_error_code_t, citizensdk_handle_t,
             const citizensdk_account_id_t *, uint32_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_submit_extrinsic, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_bytes_view_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_watch_extrinsic, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_bytes_view_t,
             citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_verify_transaction_at, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_block_ref_t *,
             citizensdk_bytes_view_t, const uint8_t *, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_export_state, citizensdk_error_code_t,
             citizensdk_handle_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_import_state, citizensdk_error_code_t,
             citizensdk_handle_t, const citizensdk_block_ref_t *, uint32_t,
             citizensdk_bytes_view_t, citizensdk_request_id_t *);
ABI_FUNCTION(citizensdk_result_get_info, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_result_info_t *);
ABI_FUNCTION(citizensdk_result_copy_error_message, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint8_t *, uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_result_get_block_ref, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_block_ref_t *);
ABI_FUNCTION(citizensdk_result_copy_storage, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint8_t *, uint8_t *, uint64_t,
             uint64_t *);
ABI_FUNCTION(citizensdk_result_get_storage_batch_count,
             citizensdk_error_code_t, citizensdk_result_handle_t, uint32_t *);
ABI_FUNCTION(citizensdk_result_copy_storage_batch_item,
             citizensdk_error_code_t, citizensdk_result_handle_t, uint32_t,
             uint8_t *, uint8_t *, uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_result_get_runtime_context,
             citizensdk_error_code_t, citizensdk_result_handle_t,
             citizensdk_runtime_context_info_t *, uint8_t *, uint64_t,
             uint64_t *);
ABI_FUNCTION(citizensdk_result_get_hash, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint8_t *);
ABI_FUNCTION(citizensdk_result_get_execution, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_execution_info_t *);
ABI_FUNCTION(citizensdk_result_get_watch_event, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_watch_event_info_t *);
ABI_FUNCTION(citizensdk_result_get_exported_state, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_exported_state_info_t *,
             uint8_t *, uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_result_get_account_balance, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_account_balance_info_t *);
ABI_FUNCTION(citizensdk_result_get_account_balance_count, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint32_t *);
ABI_FUNCTION(citizensdk_result_get_account_balance_at, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint32_t, citizensdk_account_balance_info_t *);
ABI_FUNCTION(citizensdk_result_get_account_nonce, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_account_nonce_info_t *);
ABI_FUNCTION(citizensdk_result_get_fee_snapshot, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_fee_snapshot_info_t *);
ABI_FUNCTION(citizensdk_result_estimate_fee, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_u128_t,
             citizensdk_u128_t *, citizensdk_u128_t *);
ABI_FUNCTION(citizensdk_result_get_wallet_profile, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_wallet_profile_info_t *);
ABI_FUNCTION(citizensdk_result_get_wallet_account_count,
             citizensdk_error_code_t, citizensdk_result_handle_t, uint32_t *);
ABI_FUNCTION(citizensdk_result_get_wallet_account, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint32_t,
             citizensdk_wallet_account_info_t *, uint8_t *, uint64_t,
             uint64_t *, uint8_t *, uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_result_get_signature, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint8_t *);
ABI_FUNCTION(citizensdk_result_get_prepared_wallet,
             citizensdk_error_code_t, citizensdk_result_handle_t,
             citizensdk_prepared_wallet_info_t *);
ABI_FUNCTION(citizensdk_result_get_wallet_transfer,
             citizensdk_error_code_t, citizensdk_result_handle_t,
             citizensdk_wallet_transfer_info_t *, uint8_t *, uint64_t,
             uint64_t *);
ABI_FUNCTION(citizensdk_result_get_history_info, citizensdk_error_code_t,
             citizensdk_result_handle_t, citizensdk_history_info_t *);
ABI_FUNCTION(citizensdk_result_get_history_cursor, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint32_t,
             citizensdk_history_cursor_info_t *);
ABI_FUNCTION(citizensdk_result_get_history_record, citizensdk_error_code_t,
             citizensdk_result_handle_t, uint32_t,
             citizensdk_history_record_info_t *, uint8_t *, uint64_t,
             uint64_t *, uint8_t *, uint64_t, uint64_t *);
ABI_FUNCTION(citizensdk_result_get_finalized_transfer,
             citizensdk_error_code_t, citizensdk_result_handle_t, uint32_t,
             citizensdk_finalized_transfer_info_t *, uint8_t *, uint64_t,
             uint64_t *, uint8_t *, uint64_t, uint64_t *, uint8_t *, uint64_t,
             uint64_t *);
ABI_FUNCTION(citizensdk_result_release, citizensdk_error_code_t,
             citizensdk_result_handle_t);
ABI_FUNCTION(citizensdk_last_error_copy, citizensdk_error_code_t, uint8_t *,
             uint64_t, uint64_t *);

int main(void) { return citizensdk_abi_version() == CITIZENSDK_ABI_VERSION ? 0 : 1; }
