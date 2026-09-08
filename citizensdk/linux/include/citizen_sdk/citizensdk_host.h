#ifndef CITIZENSDK_HOST_H
#define CITIZENSDK_HOST_H

#include <stdint.h>
#include "citizensdk.h"

#if defined(__GNUC__)
#define CITIZENSDK_HOST_API __attribute__((visibility("default")))
#else
#define CITIZENSDK_HOST_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define CITIZENSDK_HOST_ABI_VERSION UINT32_C(1)

typedef uint64_t citizensdk_host_handle_t;
typedef uint64_t citizensdk_wallet_flow_handle_t;

typedef struct citizensdk_host_config_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_bytes_view_t storage_root_utf8;
  citizensdk_bytes_view_t asset_root_utf8;
  citizensdk_bytes_view_t application_id_utf8;
  void *gtk_parent_window;
  uint8_t enable_wallet;
  uint8_t reserved[7];
} citizensdk_host_config_v1_t;

typedef uint32_t citizensdk_wallet_flow_kind_t;
#define CITIZENSDK_WALLET_FLOW_CREATE UINT32_C(1)
#define CITIZENSDK_WALLET_FLOW_IMPORT UINT32_C(2)
#define CITIZENSDK_WALLET_FLOW_ADD_ACCOUNTS UINT32_C(3)

typedef struct citizensdk_wallet_flow_request_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_wallet_flow_kind_t kind;
  citizensdk_wallet_word_count_t word_count;
  const uint32_t *account_indices;
  uint32_t account_index_count;
} citizensdk_wallet_flow_request_v1_t;

typedef uint32_t citizensdk_wallet_flow_status_t;
#define CITIZENSDK_WALLET_FLOW_COMPLETED UINT32_C(1)
#define CITIZENSDK_WALLET_FLOW_CANCELLED UINT32_C(2)
#define CITIZENSDK_WALLET_FLOW_FAILED UINT32_C(3)

typedef struct citizensdk_wallet_flow_result_v1 {
  uint32_t struct_size;
  uint32_t abi_version;
  citizensdk_wallet_flow_status_t status;
  citizensdk_error_code_t error_code;
} citizensdk_wallet_flow_result_v1_t;

typedef void (*citizensdk_wallet_flow_completion_v1_t)(
    void *context, const citizensdk_wallet_flow_result_v1_t *result);

/* 只借用非秘密的 Core JSON，最多 65536 字节；回调返回前复制。
 * 完成只发生在相机停止或真实 Core 认证/签名请求排空之后。 */
typedef void (*citizensdk_qr_completion_v1_t)(
    void *context, citizensdk_error_code_t error_code,
    citizensdk_bytes_view_t document);
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_scan_qr(
    citizensdk_host_handle_t host, void *context,
    citizensdk_qr_completion_v1_t completion, citizensdk_wallet_flow_handle_t *out_flow);
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_sign_qr_request(
    citizensdk_host_handle_t host, citizensdk_bytes_view_t sign_request,
    void *context, citizensdk_qr_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_flow);

CITIZENSDK_HOST_API uint32_t citizensdk_host_abi_version(void);
CITIZENSDK_HOST_API uint32_t citizensdk_host_config_size(void);
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_create(
    const citizensdk_host_config_v1_t *config,
    citizensdk_host_handle_t *out_host);

/* 显式模块创建不改变 ABI1 结构布局。enable_wallet 必须准确投影 wallet/signing
 * 是否需要设备安全资源；模块依赖由 Rust 唯一校验。 */
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_create_with_modules(
    const citizensdk_host_config_v1_t *config, uint32_t modules,
    citizensdk_host_handle_t *out_host);

/* The Host owns the returned Core instance. Applications may invoke the root
 * C ABI with this borrowed handle but must not replace its event callback or
 * call citizensdk_destroy directly. Destruction is committed through Host. */
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_create_sdk(
    citizensdk_host_handle_t host, citizensdk_handle_t *out_sdk);
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_sdk(
    citizensdk_host_handle_t host, citizensdk_handle_t *out_sdk);
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_set_event_callback(
    citizensdk_host_handle_t host, citizensdk_event_callback_t callback,
    void *context);
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_set_parent_window(
    citizensdk_host_handle_t host, void *gtk_parent_window);
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_vault_availability(
    citizensdk_host_handle_t host,
    citizensdk_host_vault_availability_t *out_availability);

CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_present_wallet_flow(
    citizensdk_host_handle_t host,
    const citizensdk_wallet_flow_request_v1_t *request, void *context,
    citizensdk_wallet_flow_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_flow);
/* 只打开 SDK 自有账户私钥安全视图；完成结果不含任何秘密或显示回调。
 * 取消及关闭沿用 WalletFlow 的真实排空语义，账户只作为公开控制输入。 */
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_view_account_private_key(
    citizensdk_host_handle_t host, const citizensdk_account_id_t *account_id,
    void *context, citizensdk_wallet_flow_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_flow);
CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_cancel_wallet_flow(
    citizensdk_host_handle_t host, citizensdk_wallet_flow_handle_t flow);

/* Fails with BUSY while requests, results, callbacks, or wallet UI remain.
 * Success destroys Core first, closes stores, zeroizes vault state, and makes
 * the host handle permanently invalid. */
CITIZENSDK_HOST_API citizensdk_error_code_t
citizensdk_host_destroy(citizensdk_host_handle_t host);

/* Transfers an otherwise unreachable Host to the process supervisor. The
 * supervisor requests a checkpointed stop when needed and retries monotonic
 * teardown with bounded backoff. The caller must never use the handle again. */
CITIZENSDK_HOST_API citizensdk_error_code_t
citizensdk_host_abandon(citizensdk_host_handle_t host);

CITIZENSDK_HOST_API citizensdk_error_code_t citizensdk_host_last_error_copy(
    uint8_t *buffer, uint64_t capacity, uint64_t *out_required);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* CITIZENSDK_HOST_H */
