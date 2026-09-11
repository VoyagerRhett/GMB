#ifndef CITIZENSDK_LINUX_FLUTTER_CODEC_HPP
#define CITIZENSDK_LINUX_FLUTTER_CODEC_HPP

#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "citizensdk.h"

namespace citizen_sdk::flutter {

inline citizensdk_failure_stage_t flutter_default_failure_stage(
    citizensdk_error_code_t code) noexcept {
  switch (code) {
    case CITIZENSDK_ERROR_INVALID_ARGUMENT: case CITIZENSDK_ERROR_DECODE:
      return CITIZENSDK_FAILURE_STAGE_VALIDATION;
    case CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED:
    case CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED:
    case CITIZENSDK_ERROR_KEY_INVALIDATED: case CITIZENSDK_ERROR_PERMISSION_DENIED:
      return CITIZENSDK_FAILURE_STAGE_AUTHENTICATION;
    case CITIZENSDK_ERROR_STORAGE: return CITIZENSDK_FAILURE_STAGE_PERSISTENCE;
    case CITIZENSDK_ERROR_UNAVAILABLE: case CITIZENSDK_ERROR_NETWORK:
    case CITIZENSDK_ERROR_TIMEOUT: return CITIZENSDK_FAILURE_STAGE_PROVIDER;
    case CITIZENSDK_ERROR_INTEGRITY: return CITIZENSDK_FAILURE_STAGE_VERIFICATION;
    case CITIZENSDK_ERROR_CANCELLED: return CITIZENSDK_FAILURE_STAGE_CANCELLATION;
    case CITIZENSDK_ERROR_INTERNAL: case CITIZENSDK_ERROR_PANIC:
      return CITIZENSDK_FAILURE_STAGE_TEARDOWN;
    default: return CITIZENSDK_FAILURE_STAGE_ADMISSION;
  }
}

inline constexpr const char *kMethodChannel = "citizen/sdk/core/v1";
inline constexpr const char *kEventChannel = "citizen/sdk/events/v1";
inline constexpr int64_t kProtocolVersion = 1;

// Flutter 只接收固定 tuple 的公开值；禁止把秘密、裸句柄或指针混入该值树。
// Only these public values may cross the Flutter boundary. No native handle,
// pointer, prepared-wallet token or secret-bearing alternative exists here.
// Value owns its entire tree and can be moved from a Core callback to the UI
// thread; FlValue and the Flutter messenger stay on the UI thread.
struct Value final {
  using Bytes = std::vector<uint8_t>;
  using List = std::vector<Value>;
  std::variant<std::monostate, bool, int64_t, std::string, Bytes, List> data;

  static Value null() { return {}; }
  static Value boolean(bool value) { return Value{value}; }
  static Value integer(int64_t value) { return Value{value}; }
  static Value string(std::string value) { return Value{std::move(value)}; }
  static Value bytes(Bytes value) { return Value{std::move(value)}; }
  static Value list(List value) { return Value{std::move(value)}; }
};

enum class Method {
  open, start, stop, close, get_capabilities, get_finalized_head,
  get_sync_status, get_best_head, get_finalized_block_at,
  resolve_finalized_block, get_block_header, get_block_body,
  get_runtime_context, get_storage, get_storage_batch, get_system_events,
  export_state, import_state, get_genesis_hash,
  get_account_balance, get_account_balances, get_account_nonce, get_fee_snapshot, get_wallet_profile, view_account_private_key,
  get_wallet_state, import_cold_account_id, import_cold_account_ss58,
  reorder_wallet_accounts_without_default_change, rename_account, delete_account,
  create_wallet, import_wallet, add_wallet_accounts, set_active_wallet_account,
  rename_wallet_account, delete_wallet_account, delete_wallet,
  reconcile_wallet_cleanup, sign_wallet_payload, begin_signing,
  consume_external_signature, cancel_signing, begin_default_account_change,
  consume_default_account_change, verify_signature, prepare_transaction,
  cancel_prepared_transaction, execute_prepared_transaction,
  consume_prepared_transaction_qr_response, cancel_prepared_transaction_execution,
  get_transaction_history, sync_transaction_history,
  qr_parse, qr_create_sign_request,
  qr_consume_sign_response, qr_cancel_sign_request, qr_encode_account_id,
  qr_decode_luminance, qr_encode, qr_scan, sign_qr_request,
};

const char *method_name(Method method) noexcept;

// Fields are copied from a validated fixed-position tuple. Signing payload and
// payload bytes are public messages, never secret material. Unused fields
// remain empty; method is the closed discriminant used by sessions.
struct DecodedRequest final {
  Method method{Method::open};
  std::string session;
  int64_t sequence{};
  uint32_t modules{CITIZENSDK_MODULE_FULL};
  citizensdk_block_ref_t block{};
  uint64_t block_number{};
  uint32_t state_format_version{};
  std::vector<std::vector<uint8_t>> storage_keys;
  std::vector<uint8_t> state_database;
  citizensdk_account_id_t account_id{};
  uint32_t word_count{};
  std::vector<uint32_t> indices;
  std::string name;
  std::vector<uint8_t> payload;
  std::vector<uint8_t> signature;
  citizensdk_signing_transform_t signing_transform{};
  citizensdk_external_signer_transport_t external_signer_transport{};
  std::vector<uint8_t> signing_domain;
  uint16_t signing_action{};
  uint64_t signing_ttl{};
  std::string signing_session_id;
  std::string signing_response;
  std::string preparation_id;
  citizensdk_transaction_execution_id_t execution_id{};
  std::optional<citizensdk_transaction_execution_id_t> before_execution_id;
  uint32_t history_limit{100};
  std::vector<citizensdk_account_id_t> account_ids;
  uint64_t wallet_revision{};
  uint16_t qr_action{};
  uint64_t qr_ttl{};
  std::string qr_text;
  std::string qr_request_id;
  uint32_t qr_width{};
  uint32_t qr_height{};
  uint32_t qr_stride{};
  uint32_t qr_scale{};
};

class ContractFailure final : public std::runtime_error {
 public:
  ContractFailure(citizensdk_error_code_t code, std::string message,
                  std::optional<std::string> session = {},
                  std::optional<int64_t> sequence = {},
                  citizensdk_failure_stage_t stage = 0);
  citizensdk_error_code_t code;
  std::optional<std::string> session;
  std::optional<int64_t> sequence;
  citizensdk_failure_stage_t stage;
};

struct FlValueDeleter {
  void operator()(FlValue *value) const noexcept {
    if (value != nullptr) fl_value_unref(value);
  }
};
using FlValuePtr = std::unique_ptr<FlValue, FlValueDeleter>;

// 线协议仍是标准 tag 7；内部有长度的字符串只修复 Linux 对嵌入 NUL 的截断。
// The wire is the existing Flutter StandardMethodCodec, not a new protocol.
// Its official message-codec extension preserves embedded NUL in standard
// string tag 7; stock Linux FlValue strings otherwise silently truncate it.
// Returned GObject has one owned reference; caller must g_object_unref it.
FlStandardMethodCodec *new_method_codec();
FlValuePtr to_fl_value(const Value &value);
Value from_fl_value(FlValue *value);
DecodedRequest decode_request(const std::string &method, FlValue *arguments);
bool decode_subscription(FlValue *arguments);

Value response(const std::string &session, int64_t sequence, Value value);
Value event(const std::string &session, int64_t sequence,
            const std::string &type, Value payload);
Value error_details(citizensdk_error_code_t code, const std::string &message,
                    std::optional<std::string> session = {},
                    std::optional<int64_t> sequence = {},
                    const std::string &method = "open",
                    citizensdk_failure_stage_t stage = 0);
const char *error_name(citizensdk_error_code_t code) noexcept;

Value lifecycle(citizensdk_lifecycle_t value);
Value block(const citizensdk_block_ref_t &value);
Value capabilities(const citizensdk_capability_snapshot_t &value);

// Synchronously copy only public result data while the observer's borrowed
// result is alive. These functions never retain/release or publish its handle.
// sessions supplies lifecycle after start/stop and fetches a profile after the
// private native wallet UI completes; those operations do not expose tokens.
// 创世身份同步读取，不借用异步 result，也不启动链或访问金库。
Value copy_genesis_hash(citizensdk_handle_t sdk);
Value copy_public_result(Method method, citizensdk_result_handle_t result);

// 生产复制路径先运行语义后置校验，再交付 Dart；测试仅注入公开夹具，不伪造 Core 句柄。
// Production result projections invoke these semantic validators before a
// value can reach Dart. They are exposed only from the private src header so
// contract tests can inject malformed public fixtures without forging Core
// result handles.
void validate_public_value(Method method, const Value &value);
// 批量余额必须完整回显输入数量、顺序与重复项，不能返回部分或错配事实。
void validate_account_balances(const DecodedRequest &request, const Value &value);

// Decimal strings preserve u64/u128 exactly across Dart/StandardMessageCodec.
// Parsing rejects signs, leading zeroes, whitespace and arithmetic overflow.
citizensdk_u128_t parse_u128(const std::string &text);
std::string decimal_u128(citizensdk_u128_t value);
bool valid_utf8(const std::string &text) noexcept;

}  // namespace citizen_sdk::flutter

#endif
