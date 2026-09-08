#ifndef CITIZENSDK_WINDOWS_FLUTTER_CODEC_HPP
#define CITIZENSDK_WINDOWS_FLUTTER_CODEC_HPP

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>

#include <cstddef>
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

inline constexpr const char *kMethodChannel = "citizen/sdk/core/v1";
inline constexpr const char *kEventChannel = "citizen/sdk/events/v1";
inline constexpr int64_t kProtocolVersion = 1;

// Flutter 只接收固定 tuple 的公开值；禁止把秘密、裸句柄或指针混入该值树。
// Only these public values may cross the Flutter boundary. No native handle,
// pointer, prepared-wallet token or secret-bearing alternative exists here.
// Value owns its entire tree and can be moved from a Core callback to the UI
// thread; EncodableValue and the Flutter messenger stay on the UI thread.
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
  open, start, stop, close, get_capabilities, get_finalized_head, get_genesis_hash,
  get_account_balance, get_account_balances, get_account_nonce, get_fee_snapshot, get_wallet_profile, view_account_private_key,
  create_wallet, import_wallet, add_wallet_accounts, set_active_wallet_account,
  rename_wallet_account, delete_wallet_account, delete_wallet,
  reconcile_wallet_cleanup, sign_wallet_payload, verify_signature, transfer_with_remark,
  initialize_finalized_history, sync_finalized_history,
  qr_parse, qr_create_sign_request,
  qr_consume_sign_response, qr_cancel_sign_request, qr_encode_account_id,
  qr_encode_user_transfer, qr_decode_luminance, qr_encode, qr_scan, sign_qr_request,
};

const char *method_name(Method method) noexcept;

// Fields are copied from a validated fixed-position tuple. Signing payload and
// transfer remark are public messages, never secret material. Unused fields
// remain empty; method is the closed discriminant used by sessions.
struct DecodedRequest final {
  Method method{Method::open};
  std::string session;
  int64_t sequence{};
  uint32_t modules{CITIZENSDK_MODULE_FULL};
  citizensdk_account_id_t account_id{};
  citizensdk_account_id_t destination{};
  uint32_t word_count{};
  std::vector<uint32_t> indices;
  std::string name;
  std::vector<uint8_t> payload;
  std::vector<uint8_t> signature;
  std::vector<uint8_t> remark;
  citizensdk_u128_t amount{};
  std::vector<citizensdk_account_id_t> account_ids;
  uint16_t qr_action{};
  uint64_t qr_expires_at{};
  uint64_t qr_ttl{};
  std::string qr_text;
  std::string qr_request_id;
  std::string qr_amount;
  std::string qr_symbol;
  std::string qr_memo;
  std::string qr_bank_cid;
  uint32_t qr_width{};
  uint32_t qr_height{};
  uint32_t qr_stride{};
  uint32_t qr_scale{};
};

class ContractFailure final : public std::runtime_error {
 public:
  ContractFailure(citizensdk_error_code_t code, std::string message,
                  std::optional<std::string> session = {},
                  std::optional<int64_t> sequence = {});
  citizensdk_error_code_t code;
  std::optional<std::string> session;
  std::optional<int64_t> sequence;
};

// Windows 使用官方 StandardMethodCodec；std::string 自带长度，不需要 Linux 的
// GLib NUL 适配层。只在 UI 线程转换，跨线程仍传递完整拥有内存的 Value。
// 原始请求先做无分配的格式/资源预检，再由官方 codec 解码；不是另一套解码协议。
std::unique_ptr<::flutter::MethodCall<::flutter::EncodableValue>> decode_method_call(
    const uint8_t *message, std::size_t size);
::flutter::EncodableValue to_encodable_value(const Value &value);
Value from_encodable_value(const ::flutter::EncodableValue &value);
DecodedRequest decode_request(const std::string &method,
                              const ::flutter::EncodableValue *arguments);
bool decode_subscription(const ::flutter::EncodableValue *arguments);

Value response(const std::string &session, int64_t sequence, Value value);
Value event(const std::string &session, int64_t sequence,
            const std::string &type, Value payload);
Value error_details(citizensdk_error_code_t code, const std::string &message,
                    std::optional<std::string> session = {},
                    std::optional<int64_t> sequence = {});
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
Value watch_payload(citizensdk_result_handle_t result,
                    int64_t request_sequence);

// 生产复制路径先运行语义后置校验，再交付 Dart；测试仅注入公开夹具，不伪造 Core 句柄。
// Production result projections invoke these semantic validators before a
// value can reach Dart. They are exposed only from the private src header so
// contract tests can inject malformed public fixtures without forging Core
// result handles.
void validate_public_value(Method method, const Value &value);
// 批量余额必须完整回显输入数量、顺序与重复项，不能返回部分或错配事实。
void validate_account_balances(const DecodedRequest &request, const Value &value);
void validate_watch_value(const Value &value);

// Decimal strings preserve u64/u128 exactly across Dart/StandardMessageCodec.
// Parsing rejects signs, leading zeroes, whitespace and arithmetic overflow.
citizensdk_u128_t parse_u128(const std::string &text);
std::string decimal_u128(citizensdk_u128_t value);
bool valid_utf8(const std::string &text) noexcept;

}  // namespace citizen_sdk::flutter

#endif
