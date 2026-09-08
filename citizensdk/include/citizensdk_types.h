#ifndef CITIZENSDK_TYPES_H
#define CITIZENSDK_TYPES_H

#include <stdint.h>

#define CITIZENSDK_ABI_VERSION UINT32_C(1)
#define CITIZENSDK_CAPABILITY_COUNT UINT32_C(10)

/* Immutable instance module selection. Transactions and history require chain.
 * Wallet may reuse crypto internally without enabling the public signing API. */
#define CITIZENSDK_MODULE_WALLET UINT32_C(1)
#define CITIZENSDK_MODULE_SIGNING UINT32_C(2)
#define CITIZENSDK_MODULE_CHAIN UINT32_C(4)
#define CITIZENSDK_MODULE_TRANSACTIONS UINT32_C(8)
#define CITIZENSDK_MODULE_HISTORY UINT32_C(16)
#define CITIZENSDK_MODULE_QR UINT32_C(32)
#define CITIZENSDK_MODULE_FULL UINT32_C(63)

typedef uint64_t citizensdk_handle_t;
typedef uint64_t citizensdk_request_id_t;
typedef uint64_t citizensdk_result_handle_t;
typedef uint64_t citizensdk_prepared_wallet_handle_t;

typedef int32_t citizensdk_error_code_t;
#define CITIZENSDK_OK INT32_C(0)
#define CITIZENSDK_ERROR_INVALID_ARGUMENT INT32_C(1)
#define CITIZENSDK_ERROR_INVALID_HANDLE INT32_C(2)
#define CITIZENSDK_ERROR_INVALID_STATE INT32_C(3)
#define CITIZENSDK_ERROR_UNSUPPORTED INT32_C(4)
#define CITIZENSDK_ERROR_UNAVAILABLE INT32_C(5)
#define CITIZENSDK_ERROR_NOT_READY INT32_C(6)
#define CITIZENSDK_ERROR_NOT_FOUND INT32_C(7)
#define CITIZENSDK_ERROR_CONFLICT INT32_C(8)
#define CITIZENSDK_ERROR_INTEGRITY INT32_C(9)
#define CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED INT32_C(10)
#define CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED INT32_C(11)
#define CITIZENSDK_ERROR_KEY_INVALIDATED INT32_C(12)
#define CITIZENSDK_ERROR_PERMISSION_DENIED INT32_C(13)
#define CITIZENSDK_ERROR_STORAGE INT32_C(14)
#define CITIZENSDK_ERROR_NETWORK INT32_C(15)
#define CITIZENSDK_ERROR_DECODE INT32_C(16)
#define CITIZENSDK_ERROR_TIMEOUT INT32_C(17)
#define CITIZENSDK_ERROR_BUSY INT32_C(18)
#define CITIZENSDK_ERROR_QUEUE_FULL INT32_C(19)
#define CITIZENSDK_ERROR_INTERNAL INT32_C(20)
#define CITIZENSDK_ERROR_PANIC INT32_C(21)
#define CITIZENSDK_ERROR_CANCELLED INT32_C(22)

typedef uint32_t citizensdk_lifecycle_t;
#define CITIZENSDK_LIFECYCLE_CREATED UINT32_C(1)
#define CITIZENSDK_LIFECYCLE_IMPORTING_STATE UINT32_C(2)
#define CITIZENSDK_LIFECYCLE_STARTING UINT32_C(3)
#define CITIZENSDK_LIFECYCLE_RUNNING UINT32_C(4)
#define CITIZENSDK_LIFECYCLE_START_FAILED UINT32_C(5)
#define CITIZENSDK_LIFECYCLE_STOPPED UINT32_C(6)
#define CITIZENSDK_LIFECYCLE_DISPOSED UINT32_C(7)

typedef uint32_t citizensdk_finality_t;
#define CITIZENSDK_FINALITY_BEST UINT32_C(1)
#define CITIZENSDK_FINALITY_FINALIZED UINT32_C(2)

typedef uint32_t citizensdk_capability_name_t;
#define CITIZENSDK_CAPABILITY_CHAIN_READ UINT32_C(1)
#define CITIZENSDK_CAPABILITY_TRANSACTION_BUILD UINT32_C(2)
#define CITIZENSDK_CAPABILITY_TRANSACTION_SUBMIT UINT32_C(3)
#define CITIZENSDK_CAPABILITY_TRANSACTION_VERIFY UINT32_C(4)
#define CITIZENSDK_CAPABILITY_WALLET_PROFILE UINT32_C(5)
#define CITIZENSDK_CAPABILITY_LOCAL_SIGNING UINT32_C(6)
#define CITIZENSDK_CAPABILITY_HARDWARE_VAULT UINT32_C(7)
#define CITIZENSDK_CAPABILITY_USER_AUTHENTICATION UINT32_C(8)
#define CITIZENSDK_CAPABILITY_HISTORY UINT32_C(9)
#define CITIZENSDK_CAPABILITY_BACKGROUND_SYNC UINT32_C(10)

typedef uint32_t citizensdk_capability_reason_t;
#define CITIZENSDK_CAPABILITY_REASON_NONE UINT32_C(0)
#define CITIZENSDK_CAPABILITY_REASON_BUILD_UNSUPPORTED UINT32_C(1)
#define CITIZENSDK_CAPABILITY_REASON_DEVICE_UNAVAILABLE UINT32_C(2)
#define CITIZENSDK_CAPABILITY_REASON_HOST_DISABLED UINT32_C(3)
#define CITIZENSDK_CAPABILITY_REASON_ENGINE_NOT_RUNNING UINT32_C(4)
#define CITIZENSDK_CAPABILITY_REASON_DEPENDENCY_NOT_READY UINT32_C(5)
#define CITIZENSDK_CAPABILITY_REASON_USER_AUTHENTICATION_REQUIRED UINT32_C(6)
#define CITIZENSDK_CAPABILITY_REASON_VAULT_LOCKED UINT32_C(7)
#define CITIZENSDK_CAPABILITY_REASON_CHAIN_STARTING UINT32_C(8)
#define CITIZENSDK_CAPABILITY_REASON_CHAIN_UNSYNCED UINT32_C(9)
#define CITIZENSDK_CAPABILITY_REASON_STORAGE_UNAVAILABLE UINT32_C(10)

typedef uint32_t citizensdk_event_type_t;
#define CITIZENSDK_EVENT_REQUEST_COMPLETED UINT32_C(1)
#define CITIZENSDK_EVENT_WATCH_UPDATE UINT32_C(2)
#define CITIZENSDK_EVENT_CAPABILITIES_CHANGED UINT32_C(3)
#define CITIZENSDK_EVENT_LIFECYCLE_CHANGED UINT32_C(4)
/* Payloadless invalidation; request_id/result/capability_revision/reserved are zero. */
#define CITIZENSDK_EVENT_HISTORY_CHANGED UINT32_C(5)

typedef uint32_t citizensdk_result_kind_t;
#define CITIZENSDK_RESULT_EMPTY UINT32_C(0)
#define CITIZENSDK_RESULT_BLOCK_REF UINT32_C(1)
#define CITIZENSDK_RESULT_STORAGE_VALUE UINT32_C(2)
#define CITIZENSDK_RESULT_STORAGE_BATCH UINT32_C(3)
#define CITIZENSDK_RESULT_RUNTIME_CONTEXT UINT32_C(4)
#define CITIZENSDK_RESULT_EXTRINSIC_HASH UINT32_C(5)
#define CITIZENSDK_RESULT_EXECUTION_CONCLUSION UINT32_C(6)
#define CITIZENSDK_RESULT_WATCH_EVENT UINT32_C(7)
#define CITIZENSDK_RESULT_EXPORTED_STATE UINT32_C(8)
#define CITIZENSDK_RESULT_ACCOUNT_BALANCE UINT32_C(9)
#define CITIZENSDK_RESULT_ACCOUNT_NONCE UINT32_C(10)
#define CITIZENSDK_RESULT_FEE_SNAPSHOT UINT32_C(11)
#define CITIZENSDK_RESULT_WALLET_PROFILE UINT32_C(12)
#define CITIZENSDK_RESULT_WALLET_ACCOUNTS UINT32_C(13)
#define CITIZENSDK_RESULT_SIGNATURE UINT32_C(14)
#define CITIZENSDK_RESULT_PREPARED_WALLET UINT32_C(15)
#define CITIZENSDK_RESULT_WALLET_TRANSFER UINT32_C(16)
#define CITIZENSDK_RESULT_TRANSACTION_HISTORY UINT32_C(17)
#define CITIZENSDK_RESULT_ACCOUNT_BALANCES UINT32_C(18)
#define CITIZENSDK_RESULT_QR_REVIEW UINT32_C(19)
#define CITIZENSDK_RESULT_QR_SIGNED UINT32_C(20)

typedef uint32_t citizensdk_wallet_word_count_t;
#define CITIZENSDK_WALLET_WORDS_12 UINT32_C(12)
#define CITIZENSDK_WALLET_WORDS_18 UINT32_C(18)
#define CITIZENSDK_WALLET_WORDS_24 UINT32_C(24)

typedef uint32_t citizensdk_wallet_origin_t;
#define CITIZENSDK_WALLET_ORIGIN_CREATED UINT32_C(1)
#define CITIZENSDK_WALLET_ORIGIN_IMPORTED UINT32_C(2)

typedef uint32_t citizensdk_history_status_t;
#define CITIZENSDK_HISTORY_PENDING UINT32_C(1)
#define CITIZENSDK_HISTORY_IN_BLOCK UINT32_C(2)
#define CITIZENSDK_HISTORY_POOL_REJECTED UINT32_C(3)
#define CITIZENSDK_HISTORY_FINALIZED_SUCCESS UINT32_C(4)
#define CITIZENSDK_HISTORY_FINALIZED_FAILED UINT32_C(5)

typedef uint32_t citizensdk_transfer_resolution_t;
#define CITIZENSDK_TRANSFER_FINALIZED_SUCCESS UINT32_C(1)
#define CITIZENSDK_TRANSFER_FINALIZED_FAILED UINT32_C(2)
#define CITIZENSDK_TRANSFER_POOL_REJECTED UINT32_C(3)

typedef uint32_t citizensdk_transfer_direction_t;
#define CITIZENSDK_TRANSFER_OUTGOING UINT32_C(1)
#define CITIZENSDK_TRANSFER_INCOMING UINT32_C(2)

typedef uint32_t citizensdk_watch_status_t;
#define CITIZENSDK_WATCH_READY UINT32_C(1)
#define CITIZENSDK_WATCH_BROADCAST UINT32_C(2)
#define CITIZENSDK_WATCH_FUTURE UINT32_C(3)
#define CITIZENSDK_WATCH_IN_BLOCK UINT32_C(4)
#define CITIZENSDK_WATCH_FINALIZED UINT32_C(5)
#define CITIZENSDK_WATCH_RETRACTED UINT32_C(6)
#define CITIZENSDK_WATCH_FINALITY_TIMEOUT UINT32_C(7)
#define CITIZENSDK_WATCH_DROPPED UINT32_C(8)
#define CITIZENSDK_WATCH_INVALID UINT32_C(9)
#define CITIZENSDK_WATCH_USURPED UINT32_C(10)

typedef uint32_t citizensdk_execution_status_t;
#define CITIZENSDK_EXECUTION_SUCCESS UINT32_C(1)
#define CITIZENSDK_EXECUTION_FAILED UINT32_C(2)
#define CITIZENSDK_EXECUTION_UNVERIFIED UINT32_C(3)

/* Values in execution_info.reason_or_dispatch_variant for UNVERIFIED. */
typedef uint32_t citizensdk_unverified_reason_t;
#define CITIZENSDK_UNVERIFIED_TARGET_BLOCK_UNAVAILABLE UINT32_C(1)
#define CITIZENSDK_UNVERIFIED_RUNTIME_CONTEXT_UNAVAILABLE UINT32_C(2)
#define CITIZENSDK_UNVERIFIED_METADATA_DECODE_FAILED UINT32_C(3)
#define CITIZENSDK_UNVERIFIED_BLOCK_BODY_UNAVAILABLE UINT32_C(4)
#define CITIZENSDK_UNVERIFIED_EXTRINSIC_HASH_MISMATCH UINT32_C(5)
#define CITIZENSDK_UNVERIFIED_EXTRINSIC_NOT_FOUND UINT32_C(6)
#define CITIZENSDK_UNVERIFIED_MULTIPLE_EXTRINSIC_MATCHES UINT32_C(7)
#define CITIZENSDK_UNVERIFIED_SYSTEM_EVENTS_UNAVAILABLE UINT32_C(8)
#define CITIZENSDK_UNVERIFIED_SYSTEM_EVENTS_MALFORMED UINT32_C(9)
#define CITIZENSDK_UNVERIFIED_OUTCOME_EVENT_MISSING UINT32_C(10)
#define CITIZENSDK_UNVERIFIED_OUTCOME_EVENT_AMBIGUOUS UINT32_C(11)
#define CITIZENSDK_UNVERIFIED_PROVIDER_FAILURE UINT32_C(12)

/* CitizenChain's current Substrate DispatchError discriminants, returned in
 * reason_or_dispatch_variant for FAILED. */
typedef uint32_t citizensdk_dispatch_error_variant_t;
#define CITIZENSDK_DISPATCH_ERROR_OTHER UINT32_C(0)
#define CITIZENSDK_DISPATCH_ERROR_CANNOT_LOOKUP UINT32_C(1)
#define CITIZENSDK_DISPATCH_ERROR_BAD_ORIGIN UINT32_C(2)
#define CITIZENSDK_DISPATCH_ERROR_MODULE UINT32_C(3)
#define CITIZENSDK_DISPATCH_ERROR_CONSUMER_REMAINING UINT32_C(4)
#define CITIZENSDK_DISPATCH_ERROR_NO_PROVIDERS UINT32_C(5)
#define CITIZENSDK_DISPATCH_ERROR_TOO_MANY_CONSUMERS UINT32_C(6)
#define CITIZENSDK_DISPATCH_ERROR_TOKEN UINT32_C(7)
#define CITIZENSDK_DISPATCH_ERROR_ARITHMETIC UINT32_C(8)
#define CITIZENSDK_DISPATCH_ERROR_TRANSACTIONAL UINT32_C(9)
#define CITIZENSDK_DISPATCH_ERROR_EXHAUSTED UINT32_C(10)
#define CITIZENSDK_DISPATCH_ERROR_CORRUPTION UINT32_C(11)
#define CITIZENSDK_DISPATCH_ERROR_UNAVAILABLE UINT32_C(12)
#define CITIZENSDK_DISPATCH_ERROR_ROOT_NOT_ALLOWED UINT32_C(13)

typedef struct citizensdk_bytes_view {
  const uint8_t *data;
  uint64_t len;
} citizensdk_bytes_view_t;

/* Numeric value is high * 2^64 + low. This is not a byte-string encoding. */
typedef struct citizensdk_u128 {
  uint64_t low;
  uint64_t high;
} citizensdk_u128_t;

typedef struct citizensdk_account_id {
  uint8_t bytes[32];
} citizensdk_account_id_t;

#define CITIZENSDK_HOST_DEK_BYTES UINT64_C(32)

/* Rust-owned mutable memory used only by vault unwrap_dek. */
typedef struct citizensdk_mutable_bytes_view {
  uint8_t *data;
  uint64_t len;
} citizensdk_mutable_bytes_view_t;

typedef uint32_t citizensdk_host_record_domain_t;
#define CITIZENSDK_HOST_RECORD_CHAIN_DATABASE UINT32_C(1)
#define CITIZENSDK_HOST_RECORD_RUNTIME_CACHE UINT32_C(2)
#define CITIZENSDK_HOST_RECORD_WALLET_PROFILE UINT32_C(3)
#define CITIZENSDK_HOST_RECORD_TRANSACTION_HISTORY UINT32_C(4)
#define CITIZENSDK_HOST_RECORD_ENCRYPTED_SECRET_BLOB UINT32_C(5)

typedef uint32_t citizensdk_host_secret_kind_t;
#define CITIZENSDK_HOST_SECRET_ACCOUNT_MINI_SECRET UINT32_C(1)

typedef uint32_t citizensdk_host_vault_availability_t;
#define CITIZENSDK_HOST_VAULT_AVAILABLE UINT32_C(1)
#define CITIZENSDK_HOST_VAULT_NO_STRONG_USER_AUTHENTICATION UINT32_C(2)
#define CITIZENSDK_HOST_VAULT_UNSUPPORTED UINT32_C(3)
#define CITIZENSDK_HOST_VAULT_UNAVAILABLE UINT32_C(4)

typedef uint32_t citizensdk_host_bytes_kind_t;
#define CITIZENSDK_HOST_BYTES_WRAPPED_DEK UINT32_C(1)

typedef struct citizensdk_host_hash32 {
  uint8_t bytes[32];
} citizensdk_host_hash32_t;

typedef struct citizensdk_host_id128 {
  uint8_t bytes[16];
} citizensdk_host_id128_t;

typedef struct citizensdk_host_secret_ref_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t wallet_index;
  citizensdk_host_secret_kind_t kind;
  citizensdk_host_id128_t generation;
  citizensdk_host_id128_t owner;
  citizensdk_host_hash32_t account_id;
} citizensdk_host_secret_ref_v1_t;

typedef struct citizensdk_host_wallet_key_ref_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t wallet_index;
  uint32_t reserved;
  citizensdk_host_id128_t generation;
} citizensdk_host_wallet_key_ref_v1_t;

typedef struct citizensdk_host_record_result_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t host_operation_id;
  citizensdk_error_code_t error_code;
  citizensdk_host_record_domain_t domain;
  uint8_t present;
  uint8_t reserved[7];
  uint64_t revision;
  citizensdk_bytes_view_t record;
} citizensdk_host_record_result_v1_t;

typedef struct citizensdk_host_status_result_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t host_operation_id;
  citizensdk_error_code_t error_code;
  uint32_t reserved;
} citizensdk_host_status_result_v1_t;

typedef struct citizensdk_host_bool_result_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t host_operation_id;
  citizensdk_error_code_t error_code;
  uint8_t value;
  uint8_t reserved[7];
} citizensdk_host_bool_result_v1_t;

typedef struct citizensdk_host_vault_availability_result_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t host_operation_id;
  citizensdk_error_code_t error_code;
  citizensdk_host_vault_availability_t availability;
} citizensdk_host_vault_availability_result_v1_t;

/* This byte completion is only for a non-plaintext wrapped DEK. */
typedef struct citizensdk_host_bytes_result_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t host_operation_id;
  citizensdk_error_code_t error_code;
  citizensdk_host_bytes_kind_t kind;
  citizensdk_bytes_view_t bytes;
} citizensdk_host_bytes_result_v1_t;

typedef void (*citizensdk_host_record_completion_v1_t)(
    void *sdk_context, const citizensdk_host_record_result_v1_t *result);
typedef void (*citizensdk_host_status_completion_v1_t)(
    void *sdk_context, const citizensdk_host_status_result_v1_t *result);
typedef void (*citizensdk_host_bool_completion_v1_t)(
    void *sdk_context, const citizensdk_host_bool_result_v1_t *result);
typedef void (*citizensdk_host_vault_availability_completion_v1_t)(
    void *sdk_context,
    const citizensdk_host_vault_availability_result_v1_t *result);
typedef void (*citizensdk_host_bytes_completion_v1_t)(
    void *sdk_context, const citizensdk_host_bytes_result_v1_t *result);

typedef citizensdk_error_code_t (*citizensdk_host_chain_database_load_v1_t)(
    void *host_context, uint64_t host_operation_id, void *sdk_context,
    citizensdk_host_record_completion_v1_t completion);
typedef citizensdk_error_code_t
    (*citizensdk_host_chain_database_compare_and_swap_v1_t)(
        void *host_context, uint64_t host_operation_id,
        uint64_t expected_revision, uint8_t present,
        citizensdk_bytes_view_t candidate_record, void *sdk_context,
        citizensdk_host_record_completion_v1_t completion);
typedef citizensdk_error_code_t (*citizensdk_host_runtime_cache_load_v1_t)(
    void *host_context, uint64_t host_operation_id,
    citizensdk_host_hash32_t block_hash, void *sdk_context,
    citizensdk_host_record_completion_v1_t completion);
typedef citizensdk_error_code_t (*citizensdk_host_runtime_cache_store_v1_t)(
    void *host_context, uint64_t host_operation_id,
    citizensdk_host_hash32_t block_hash,
    citizensdk_bytes_view_t candidate_record, void *sdk_context,
    citizensdk_host_status_completion_v1_t completion);
typedef citizensdk_error_code_t (*citizensdk_host_runtime_cache_delete_v1_t)(
    void *host_context, uint64_t host_operation_id,
    citizensdk_host_hash32_t block_hash, void *sdk_context,
    citizensdk_host_status_completion_v1_t completion);
typedef citizensdk_host_chain_database_load_v1_t
    citizensdk_host_transaction_history_load_v1_t;
typedef citizensdk_error_code_t
    (*citizensdk_host_transaction_history_compare_and_swap_v1_t)(
        void *host_context, uint64_t host_operation_id,
        uint64_t expected_revision, citizensdk_bytes_view_t candidate_record,
        void *sdk_context, citizensdk_host_record_completion_v1_t completion);

typedef struct citizensdk_host_public_store_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  void *context;
  citizensdk_host_chain_database_load_v1_t chain_database_load;
  citizensdk_host_chain_database_compare_and_swap_v1_t
      chain_database_compare_and_swap;
  citizensdk_host_runtime_cache_load_v1_t runtime_cache_load;
  citizensdk_host_runtime_cache_store_v1_t runtime_cache_store;
  citizensdk_host_runtime_cache_delete_v1_t runtime_cache_delete;
  citizensdk_host_transaction_history_load_v1_t transaction_history_load;
  citizensdk_host_transaction_history_compare_and_swap_v1_t
      transaction_history_compare_and_swap;
} citizensdk_host_public_store_v1_t;

typedef citizensdk_host_chain_database_load_v1_t
    citizensdk_host_wallet_profile_load_v1_t;
typedef citizensdk_host_transaction_history_compare_and_swap_v1_t
    citizensdk_host_wallet_profile_compare_and_swap_v1_t;
typedef citizensdk_error_code_t
    (*citizensdk_host_encrypted_secret_blob_load_v1_t)(
        void *host_context, uint64_t host_operation_id,
        citizensdk_host_secret_ref_v1_t secret_ref, void *sdk_context,
        citizensdk_host_record_completion_v1_t completion);
typedef citizensdk_error_code_t
    (*citizensdk_host_encrypted_secret_blob_compare_and_swap_v1_t)(
        void *host_context, uint64_t host_operation_id,
        citizensdk_host_secret_ref_v1_t secret_ref,
        uint64_t expected_revision, citizensdk_bytes_view_t candidate_record,
        void *sdk_context, citizensdk_host_record_completion_v1_t completion);

typedef struct citizensdk_host_secure_store_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  void *context;
  citizensdk_host_wallet_profile_load_v1_t wallet_profile_load;
  citizensdk_host_wallet_profile_compare_and_swap_v1_t
      wallet_profile_compare_and_swap;
  citizensdk_host_encrypted_secret_blob_load_v1_t encrypted_secret_blob_load;
  citizensdk_host_encrypted_secret_blob_compare_and_swap_v1_t
      encrypted_secret_blob_compare_and_swap;
} citizensdk_host_secure_store_v1_t;

typedef citizensdk_error_code_t (*citizensdk_host_vault_availability_v1_t)(
    void *host_context, uint64_t host_operation_id, void *sdk_context,
    citizensdk_host_vault_availability_completion_v1_t completion);
typedef citizensdk_error_code_t
    (*citizensdk_host_vault_ensure_wallet_kek_v1_t)(
        void *host_context, uint64_t host_operation_id,
        citizensdk_host_wallet_key_ref_v1_t wallet_key,
        citizensdk_host_id128_t provisioning_operation_id, void *sdk_context,
        citizensdk_host_status_completion_v1_t completion);
typedef citizensdk_error_code_t (*citizensdk_host_vault_has_wallet_kek_v1_t)(
    void *host_context, uint64_t host_operation_id,
    citizensdk_host_wallet_key_ref_v1_t wallet_key, void *sdk_context,
    citizensdk_host_bool_completion_v1_t completion);
/* plaintext_dek is an exact Rust-owned 32-byte view. On acceptance it remains
 * valid until the first completion; on rejection it expires when this callback
 * returns. The host must never retain it beyond that boundary. */
typedef citizensdk_error_code_t (*citizensdk_host_vault_wrap_dek_v1_t)(
    void *host_context, uint64_t host_operation_id,
    citizensdk_host_wallet_key_ref_v1_t wallet_key,
    citizensdk_host_id128_t provisioning_operation_id,
    citizensdk_bytes_view_t plaintext_dek, void *sdk_context,
    citizensdk_host_bytes_completion_v1_t completion);
/* plaintext_dek_out is exact Rust-owned mutable memory, exclusively borrowed
 * by the accepted operation until its first completion. */
typedef citizensdk_error_code_t (*citizensdk_host_vault_unwrap_dek_v1_t)(
    void *host_context, uint64_t host_operation_id,
    citizensdk_host_wallet_key_ref_v1_t wallet_key,
    citizensdk_bytes_view_t wrapped_dek,
    citizensdk_mutable_bytes_view_t plaintext_dek_out, void *sdk_context,
    citizensdk_host_status_completion_v1_t completion);
typedef citizensdk_error_code_t
    (*citizensdk_host_vault_retire_wallet_kek_v1_t)(
        void *host_context, uint64_t host_operation_id,
        citizensdk_host_wallet_key_ref_v1_t wallet_key,
        citizensdk_host_id128_t cleanup_operation_id, void *sdk_context,
        citizensdk_host_status_completion_v1_t completion);

typedef struct citizensdk_host_secret_vault_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  void *context;
  citizensdk_host_vault_availability_v1_t availability;
  citizensdk_host_vault_ensure_wallet_kek_v1_t ensure_wallet_kek;
  citizensdk_host_vault_has_wallet_kek_v1_t has_wallet_kek;
  citizensdk_host_vault_wrap_dek_v1_t wrap_dek;
  citizensdk_host_vault_unwrap_dek_v1_t unwrap_dek;
  citizensdk_host_vault_retire_wallet_kek_v1_t retire_wallet_kek;
} citizensdk_host_secret_vault_v1_t;

/* Vtable pointers are borrowed only during create_with_host and copied by SDK. */
typedef struct citizensdk_host_services_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  const citizensdk_host_public_store_v1_t *public_store;
  const citizensdk_host_secure_store_v1_t *secure_store;
  const citizensdk_host_secret_vault_v1_t *secret_vault;
} citizensdk_host_services_v1_t;

typedef struct citizensdk_create_options {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_bytes_view_t asset_manifest;
  citizensdk_bytes_view_t chain_spec;
  citizensdk_bytes_view_t light_sync_state;
  citizensdk_bytes_view_t system_name;
  citizensdk_bytes_view_t system_version;
} citizensdk_create_options_t;

typedef struct citizensdk_block_ref {
  uint32_t struct_size;
  uint32_t abi_version;
  uint8_t hash[32];
  uint64_t number;
  citizensdk_finality_t finality;
  uint32_t reserved;
} citizensdk_block_ref_t;

typedef struct citizensdk_capability_status {
  citizensdk_capability_name_t name;
  citizensdk_capability_reason_t reason;
  uint8_t supported;
  uint8_t available;
  uint8_t enabled;
  uint8_t ready;
  uint8_t reserved[4];
} citizensdk_capability_status_t;

typedef struct citizensdk_capability_snapshot {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t revision;
  uint32_t count;
  uint32_t reserved;
  citizensdk_capability_status_t statuses[CITIZENSDK_CAPABILITY_COUNT];
} citizensdk_capability_snapshot_t;

typedef struct citizensdk_event {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_event_type_t event_type;
  uint32_t reserved;
  uint64_t sequence;
  citizensdk_request_id_t request_id;
  citizensdk_result_handle_t result;
  uint64_t capability_revision;
} citizensdk_event_t;

typedef void (*citizensdk_event_callback_t)(void *context,
                                            const citizensdk_event_t *event);

typedef struct citizensdk_result_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_error_code_t error_code;
  citizensdk_result_kind_t kind;
  uint64_t payload_len;
  uint64_t error_message_len;
} citizensdk_result_info_t;

typedef struct citizensdk_runtime_context_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_block_ref_t block;
  uint32_t spec_version;
  uint32_t transaction_version;
  uint64_t metadata_len;
} citizensdk_runtime_context_info_t;

typedef struct citizensdk_watch_event_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_watch_status_t status;
  uint32_t peer_count;
  uint8_t has_block;
  uint8_t has_replacement_hash;
  uint8_t reserved[6];
  citizensdk_block_ref_t block;
  uint8_t replacement_hash[32];
} citizensdk_watch_event_info_t;

typedef struct citizensdk_execution_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_execution_status_t status;
  uint32_t reason_or_dispatch_variant;
  uint8_t has_block;
  uint8_t has_extrinsic_index;
  uint8_t has_module;
  uint8_t reserved[5];
  citizensdk_block_ref_t block;
  uint32_t extrinsic_index;
  uint8_t pallet_index;
  uint8_t error_index;
  uint8_t reserved_tail[2];
} citizensdk_execution_info_t;

typedef struct citizensdk_exported_state_info {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t format_version;
  uint32_t reserved;
  citizensdk_block_ref_t finalized;
  uint64_t database_len;
} citizensdk_exported_state_info_t;

typedef struct citizensdk_account_balance_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_block_ref_t block;
  citizensdk_account_id_t account_id;
  citizensdk_u128_t free_fen;
  citizensdk_u128_t reserved_fen;
  citizensdk_u128_t total_fen;
} citizensdk_account_balance_info_t;

typedef struct citizensdk_account_nonce_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_block_ref_t best_block;
  citizensdk_account_id_t account_id;
  uint64_t nonce;
} citizensdk_account_nonce_info_t;

typedef struct citizensdk_fee_snapshot_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_block_ref_t best_block;
  uint32_t fee_rate_parts;
  uint32_t reserved;
  citizensdk_u128_t minimum_fee_fen;
  citizensdk_u128_t existential_deposit_fen;
} citizensdk_fee_snapshot_info_t;

typedef struct citizensdk_wallet_profile_info {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t present;
  citizensdk_wallet_origin_t origin;
  uint32_t wallet_index;
  uint32_t account_count;
  uint64_t created_at_millis;
  citizensdk_account_id_t master_account_id;
  citizensdk_account_id_t active_account_id;
} citizensdk_wallet_profile_info_t;

typedef struct citizensdk_wallet_account_info {
  uint32_t struct_size;
  uint32_t abi_version;
  uint32_t index;
  uint32_t is_active;
  citizensdk_account_id_t account_id;
  uint64_t created_at_millis;
  uint64_t ss58_address_len;
  uint64_t name_len;
} citizensdk_wallet_account_info_t;

typedef struct citizensdk_prepared_wallet_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_prepared_wallet_handle_t prepared_wallet;
} citizensdk_prepared_wallet_info_t;

typedef struct citizensdk_wallet_transfer_info {
  uint32_t struct_size;
  uint32_t abi_version;
  uint8_t transaction_hash[32];
  citizensdk_transfer_resolution_t resolution;
  uint32_t has_execution;
  citizensdk_execution_info_t execution;
  uint64_t pool_rejection_reason_len;
} citizensdk_wallet_transfer_info_t;

typedef struct citizensdk_history_info {
  uint32_t struct_size;
  uint32_t abi_version;
  uint64_t revision;
  uint32_t cursor_count;
  uint32_t record_count;
  uint32_t transfer_count;
  uint32_t reserved;
} citizensdk_history_info_t;

typedef struct citizensdk_history_cursor_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_account_id_t account_id;
  citizensdk_block_ref_t tracking_start_block;
  citizensdk_block_ref_t last_synced_block;
} citizensdk_history_cursor_info_t;

typedef struct citizensdk_history_record_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_account_id_t account_id;
  uint8_t transaction_hash[32];
  uint64_t nonce;
  citizensdk_account_id_t destination_account_id;
  citizensdk_u128_t amount_fen;
  citizensdk_history_status_t status;
  uint32_t has_block;
  citizensdk_block_ref_t block;
  uint32_t has_execution;
  uint32_t reserved;
  citizensdk_execution_info_t execution;
  uint64_t created_at_millis;
  uint64_t updated_at_millis;
  uint64_t remark_len;
  uint64_t pool_rejection_reason_len;
} citizensdk_history_record_info_t;

typedef struct citizensdk_finalized_transfer_info {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_account_id_t tracked_account_id;
  citizensdk_account_id_t from_account_id;
  citizensdk_account_id_t to_account_id;
  citizensdk_u128_t amount_fen;
  citizensdk_block_ref_t block;
  uint32_t event_record_index;
  uint32_t has_extrinsic_index;
  uint32_t extrinsic_index;
  citizensdk_transfer_direction_t direction;
  uint64_t source_pallet_len;
  uint64_t remark_display_len;
  uint64_t remark_bytes_len;
} citizensdk_finalized_transfer_info_t;

#endif /* CITIZENSDK_TYPES_H */
