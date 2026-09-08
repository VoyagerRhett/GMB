#ifndef CITIZENSDK_CPP_HPP
#define CITIZENSDK_CPP_HPP

#include <exception>
#include "citizensdk_qr_image.h"
#include <limits>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include "citizen_sdk/citizen_sdk_config.hpp"
#include "citizen_sdk/citizen_sdk_error.hpp"
#include "citizen_sdk/citizen_sdk_events.hpp"
#include "citizen_sdk/citizen_sdk_models.hpp"
#include "citizen_sdk/citizen_sdk_wallet_flow.hpp"

namespace citizen_sdk {
namespace detail {

struct EventContext final {
  std::mutex lock;
  EventObserver observer;
};

struct EventResultScope final {
  explicit EventResultScope(citizensdk_result_handle_t value) noexcept
      : value(value) {}
  EventResultScope(const EventResultScope &) = delete;
  EventResultScope &operator=(const EventResultScope &) = delete;
  ~EventResultScope() {
    if (value != 0) (void)citizensdk_result_release(value);
  }
  citizensdk_result_handle_t value{};
};

struct WalletCompletionContext final { WalletFlowCompletion completion; };

inline void event_trampoline(void *context,
                             const citizensdk_event_t *event) noexcept {
  if (event == nullptr) return;
  EventResultScope result_owner(event->result);
  if (context == nullptr) return;
  EventObserver observer;
  try {
    auto *state = static_cast<EventContext *>(context);
    {
      std::lock_guard<std::mutex> guard(state->lock);
      observer = state->observer;
    }
    if (observer) observer(*event);
  } catch (...) {}
}

inline void wallet_trampoline(
    void *context, const citizensdk_wallet_flow_result_v1_t *result) noexcept {
  std::unique_ptr<WalletCompletionContext> state(
      static_cast<WalletCompletionContext *>(context));
  if (!state) return;
  try {
    if (result == nullptr || result->struct_size < sizeof(*result) ||
        result->abi_version != CITIZENSDK_HOST_ABI_VERSION) {
      state->completion(
          {WalletFlowStatus::Failed, CITIZENSDK_ERROR_INTEGRITY});
    } else {
      state->completion({static_cast<WalletFlowStatus>(result->status),
                         result->error_code});
    }
  } catch (...) {}
}


// 只读取 Core 输出 JSON 的字符串字段，不解释 QR_V1 或重新创建待签数据。
inline std::string qr_json_string(const std::string &json, std::size_t &at) {
  if (at >= json.size() || json[at++] != '"')
    throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core QR JSON string is missing");
  std::string output;
  const auto unit = [&]() -> uint32_t {
    if (json.size() - at < 4) throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core JSON escape is truncated");
    uint32_t code = 0;
    for (unsigned index = 0; index < 4; ++index) {
      const char digit = json[at++];
      const int value = digit >= '0' && digit <= '9' ? digit - '0'
          : digit >= 'a' && digit <= 'f' ? digit - 'a' + 10
          : digit >= 'A' && digit <= 'F' ? digit - 'A' + 10 : -1;
      if (value < 0) throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core JSON escape is invalid");
      code = code * 16 + static_cast<uint32_t>(value);
    }
    return code;
  };
  while (at < json.size()) {
    const auto ch = json[at++];
    if (ch == '"') return output;
    if (static_cast<unsigned char>(ch) < 0x20)
      throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core JSON contains a control byte");
    if (ch != '\\') { output.push_back(ch); continue; }
    if (at == json.size()) break;
    switch (json[at++]) {
      case '"': output.push_back('"'); break;
      case '\\': output.push_back('\\'); break;
      case '/': output.push_back('/'); break;
      case 'b': output.push_back('\b'); break;
      case 'f': output.push_back('\f'); break;
      case 'n': output.push_back('\n'); break;
      case 'r': output.push_back('\r'); break;
      case 't': output.push_back('\t'); break;
      case 'u': {
        uint32_t code = unit();
        if (code >= 0xd800 && code <= 0xdbff) {
          if (json.size() - at < 2 || json[at++] != '\\' || json[at++] != 'u')
            throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core JSON surrogate is truncated");
          const uint32_t low = unit();
          if (low < 0xdc00 || low > 0xdfff)
            throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core JSON surrogate is invalid");
          code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00;
        } else if (code >= 0xdc00 && code <= 0xdfff)
          throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core JSON surrogate is invalid");
        if (code < 0x80) output.push_back(static_cast<char>(code));
        else {
          if (code >= 0x10000) output.push_back(static_cast<char>(0xf0 | (code >> 18)));
          if (code >= 0x800) output.push_back(static_cast<char>(
              (code >= 0x10000 ? 0x80 : 0xe0) | ((code >> 12) & 0x3f)));
          output.push_back(static_cast<char>((code >= 0x800 ? 0x80 : 0xc0) | ((code >> 6) & 0x3f)));
          output.push_back(static_cast<char>(0x80 | (code & 0x3f)));
        }
        break;
      }
      default: throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core JSON escape is invalid");
    }
  }
  throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core JSON string is truncated");
}
inline std::string qr_public_field(const std::string &json, const char *field, std::size_t maximum) {
  unsigned depth = 0;
  std::string canonical;
  bool found = false;
  for (std::size_t at = 0; at < json.size();) {
    const char ch = json[at];
    if (ch == '{' || ch == '[') { ++depth; ++at; continue; }
    if (ch == '}' || ch == ']') { if (depth == 0) break; --depth; ++at; continue; }
    if (ch != '"') { ++at; continue; }
    const auto name = qr_json_string(json, at);
    while (at < json.size() && (json[at] == ' ' || json[at] == '\n' || json[at] == '\r' || json[at] == '\t')) ++at;
    if (depth != 1 || at == json.size() || json[at] != ':' || name != field) continue;
    ++at;
    while (at < json.size() && (json[at] == ' ' || json[at] == '\n' || json[at] == '\r' || json[at] == '\t')) ++at;
    if (found) throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core QR canonical field is duplicated");
    canonical = qr_json_string(json, at); found = true;
  }
  if (!found || canonical.empty() || canonical.size() > maximum)
    throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core QR canonical field is invalid");
  return canonical;
}
inline QrImage qr_image(const std::string &text) {
  QrImage image;
  size_t required = 0;
  auto code = citizensdk_qr_image_encode_text(reinterpret_cast<const uint8_t *>(text.data()),
      text.size(), 4, nullptr, 0, &image.width, &image.height, &required);
  if (code != CITIZENSDK_QR_IMAGE_BUFFER_TOO_SMALL || required == 0 || required > 16777216)
    throw Error(CITIZENSDK_ERROR_INTEGRITY, "QR response image query failed");
  image.luminance.resize(required);
  code = citizensdk_qr_image_encode_text(reinterpret_cast<const uint8_t *>(text.data()),
      text.size(), 4, image.luminance.data(), image.luminance.size(), &image.width, &image.height, &required);
  if (code != CITIZENSDK_QR_IMAGE_OK || required != image.luminance.size())
    throw Error(CITIZENSDK_ERROR_INTEGRITY, "QR response image encoding failed");
  return image;
}
struct QrCompletionContext final { QrFlowCompletion completion; bool encode_response{}; };
inline void qr_trampoline(void *context, citizensdk_error_code_t error,
                            citizensdk_bytes_view_t document) noexcept {
  std::unique_ptr<QrCompletionContext> state(static_cast<QrCompletionContext *>(context));
  if (!state) return;
  QrFlowResult result; result.error_code = error;
  try {
    if (error == CITIZENSDK_OK) {
      if (document.data == nullptr || document.len == 0 || document.len > 65536)
        throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core QR document is invalid");
      result.document.assign(reinterpret_cast<const char *>(document.data), static_cast<std::size_t>(document.len));
      result.canonical_text = qr_public_field(result.document, "canonical_text", 2331);
      if (state->encode_response) {
        result.request_id = qr_public_field(result.document, "request_id", 128);
        result.signer_account_id = qr_public_field(result.document, "signer_account_id", 66);
        result.sign_request = qr_public_field(result.document, "sign_request", 2331);
        const auto signature = qr_public_field(result.document, "signature", 130);
        if (signature.size() != 130 || signature.compare(0, 2, "0x") != 0)
          throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core QR signature length is invalid");
        const auto nibble = [](char digit) -> uint8_t {
          if (digit >= '0' && digit <= '9') return static_cast<uint8_t>(digit - '0');
          if (digit >= 'a' && digit <= 'f') return static_cast<uint8_t>(digit - 'a' + 10);
          throw Error(CITIZENSDK_ERROR_INTEGRITY, "Core QR signature encoding is invalid");
        };
        result.signature.reserve(64);
        for (std::size_t index = 2; index < signature.size(); index += 2)
          result.signature.push_back(static_cast<uint8_t>((nibble(signature[index]) << 4) | nibble(signature[index + 1])));
        result.qr_image = qr_image(result.canonical_text);
      }
    }
  } catch (const Error &failure) { result = {}; result.error_code = failure.code(); }
    catch (...) { result = {}; result.error_code = CITIZENSDK_ERROR_INTERNAL; }
  try { state->completion(std::move(result)); } catch (...) {}
}

}  // namespace detail

/* Header-only ownership wrapper. Construction owns only Host resources; open()
 * is explicit so a Core setup error never loses the still-retryable Host
 * handle. Applications must stop and await Core before close(). */
class Host final {
 public:
  explicit Host(const Config &config) {
    const std::string storage = config.storage_root.u8string();
    const std::string assets = config.asset_root.u8string();
    citizensdk_host_config_v1_t native{};
    native.struct_size = sizeof(native);
    native.abi_version = CITIZENSDK_HOST_ABI_VERSION;
    native.storage_root_utf8 = bytes_view(storage);
    native.asset_root_utf8 = bytes_view(assets);
    native.application_id_utf8 = bytes_view(config.application_id);
    native.hwnd = config.hwnd;
    native.enable_wallet = (config.modules & (CITIZENSDK_MODULE_WALLET | CITIZENSDK_MODULE_SIGNING)) != 0 ? 1 : 0;
    throw_if_error(citizensdk_host_create_with_modules(&native, config.modules, &host_),
                   "CitizenSDK Host creation failed");
  }

  Host(const Host &) = delete;
  Host &operator=(const Host &) = delete;
  Host(Host &&other) noexcept
      : host_(other.host_), sdk_(other.sdk_),
        event_context_(std::move(other.event_context_)) {
    other.host_ = 0;
    other.sdk_ = 0;
  }
  Host &operator=(Host &&other) noexcept {
    if (this != &other) {
      close_noexcept();
      host_ = other.host_;
      sdk_ = other.sdk_;
      event_context_ = std::move(other.event_context_);
      other.host_ = 0;
      other.sdk_ = 0;
    }
    return *this;
  }
  ~Host() { close_noexcept(); }

  void open() {
    if (sdk_ != 0) return;
    throw_if_error(citizensdk_host_create_sdk(host_, &sdk_),
                   "CitizenSDK Core creation failed");
  }

  citizensdk_handle_t native_handle() const noexcept { return sdk_; }
  citizensdk_host_handle_t host_handle() const noexcept { return host_; }

  void set_parent_window(void *window) {
    throw_if_error(citizensdk_host_set_parent_window(host_, window),
                   "CitizenSDK parent window update failed");
  }

  void set_event_observer(EventObserver observer) {
    if (!observer) {
      throw_if_error(citizensdk_host_set_event_callback(host_, nullptr, nullptr),
                     "CitizenSDK event observer clear failed");
      event_context_.reset();
      return;
    }
    auto state = std::make_unique<detail::EventContext>();
    state->observer = std::move(observer);
    throw_if_error(citizensdk_host_set_event_callback(
                       host_, detail::event_trampoline, state.get()),
                   "CitizenSDK event observer registration failed");
    event_context_ = std::move(state);
  }

  Capabilities capabilities() const {
    citizensdk_capability_snapshot_t snapshot{};
    snapshot.struct_size = sizeof(snapshot);
    snapshot.abi_version = CITIZENSDK_ABI_VERSION;
    const auto code = citizensdk_get_capabilities(sdk_, &snapshot);
    if (code != CITIZENSDK_OK) {
      throw Error(code, "CitizenSDK capability query failed");
    }
    if (snapshot.count != CITIZENSDK_CAPABILITY_COUNT) {
      throw Error(CITIZENSDK_ERROR_INTEGRITY,
                  "CitizenSDK capability snapshot has an incompatible size");
    }
    Capabilities result;
    result.revision = snapshot.revision;
    result.statuses.reserve(snapshot.count);
    for (uint32_t index = 0; index < snapshot.count; ++index) {
      const auto &value = snapshot.statuses[index];
      result.statuses.push_back({value.name, value.reason,
                                 value.supported != 0, value.available != 0,
                                 value.enabled != 0, value.ready != 0});
    }
    return result;
  }

  citizensdk_host_vault_availability_t vault_availability() const {
    citizensdk_host_vault_availability_t value{};
    throw_if_error(citizensdk_host_vault_availability(host_, &value),
                   "CitizenSDK vault availability query failed");
    return value;
  }

  WalletFlow present_wallet_flow(const WalletFlowRequest &request,
                                 WalletFlowCompletion completion) {
    if (!completion) {
      throw Error(CITIZENSDK_ERROR_INVALID_ARGUMENT,
                  "wallet-flow completion is required");
    }
    citizensdk_wallet_flow_request_v1_t native{};
    native.struct_size = sizeof(native);
    native.abi_version = CITIZENSDK_HOST_ABI_VERSION;
    native.kind = static_cast<uint32_t>(request.kind);
    native.word_count = request.word_count;
    if (request.account_indices.size() >
        static_cast<std::size_t>(std::numeric_limits<uint32_t>::max())) {
      throw Error(CITIZENSDK_ERROR_INVALID_ARGUMENT,
                  "wallet-flow account index count exceeds the C ABI");
    }
    native.account_indices = request.account_indices.empty()
                                 ? nullptr : request.account_indices.data();
    native.account_index_count =
        static_cast<uint32_t>(request.account_indices.size());
    auto state = std::make_unique<detail::WalletCompletionContext>();
    state->completion = std::move(completion);
    citizensdk_wallet_flow_handle_t flow = 0;
    const auto code = citizensdk_host_present_wallet_flow(
        host_, &native, state.get(), detail::wallet_trampoline, &flow);
    if (code != CITIZENSDK_OK) {
      throw Error(code, last_host_error("CitizenSDK wallet flow failed"));
    }
    (void)state.release();
    return WalletFlow(host_, flow);
  }

  // 返回的仍是无秘密取消能力；私有 view_id 与显示缓冲仅存在于 Host 内。
  WalletFlow view_account_private_key(const citizensdk_account_id_t &account_id,
                                      WalletFlowCompletion completion) {
    if (!completion)
      throw Error(CITIZENSDK_ERROR_INVALID_ARGUMENT, "wallet-flow completion is required");
    auto state = std::make_unique<detail::WalletCompletionContext>();
    state->completion = std::move(completion);
    citizensdk_wallet_flow_handle_t flow = 0;
    const auto code = citizensdk_host_view_account_private_key(
        host_, &account_id, state.get(), detail::wallet_trampoline, &flow);
    if (code != CITIZENSDK_OK)
      throw Error(code, last_host_error("CitizenSDK private-key view failed"));
    (void)state.release();
    return WalletFlow(host_, flow);
  }


  // 原生窗口负责摄像头、审阅与设备认证；结果中只有 Core 公共 JSON 与响应图像。
  WalletFlow scan_qr(QrFlowCompletion completion) {
    return present_qr({}, std::move(completion), false);
  }
  WalletFlow sign_qr_request(const std::string &request, QrFlowCompletion completion) {
    if (request.empty() || request.size() > 2331)
      throw Error(CITIZENSDK_ERROR_INVALID_ARGUMENT, "QR sign request is empty or too large");
    return present_qr(request, std::move(completion), true);
  }

  void close() {
    if (host_ == 0) return;
    // Windows 窗口退休可以晚于 Core 销毁。上次 BUSY 后不能再查询已经
    // 释放的缓存 Core handle；以仍然存活的 Host 为唯一所有权真源。
    refresh_core_handle();
    if (sdk_ != 0) {
      citizensdk_lifecycle_t lifecycle = 0;
      const auto code = citizensdk_get_lifecycle(sdk_, &lifecycle);
      if (code != CITIZENSDK_OK) throw Error(code, "CitizenSDK lifecycle query failed");
      if (lifecycle == CITIZENSDK_LIFECYCLE_RUNNING ||
          lifecycle == CITIZENSDK_LIFECYCLE_STARTING ||
          lifecycle == CITIZENSDK_LIFECYCLE_IMPORTING_STATE) {
        throw Error(CITIZENSDK_ERROR_BUSY,
                    "stop CitizenSDK and await its checkpoint before close");
      }
    }
    // Preserve the observer when close is rejected as BUSY. Once the lifecycle
    // gate passes, clearing it is the synchronization barrier that makes the
    // EventContext safe to destroy.
    if (event_context_) {
      throw_if_error(citizensdk_host_set_event_callback(host_, nullptr, nullptr),
                     "CitizenSDK event observer clear failed");
      event_context_.reset();
    }
    const auto closed = citizensdk_host_destroy(host_);
    if (closed != CITIZENSDK_OK) {
      refresh_core_handle();
      throw_if_error(closed, "CitizenSDK Host close failed");
    }
    host_ = 0;
    sdk_ = 0;
  }

 private:
  WalletFlow present_qr(const std::string &request, QrFlowCompletion completion, bool signing) {
    if (!completion) throw Error(CITIZENSDK_ERROR_INVALID_ARGUMENT, "QR completion is required");
    auto state = std::make_unique<detail::QrCompletionContext>();
    state->completion = std::move(completion); state->encode_response = signing;
    citizensdk_wallet_flow_handle_t flow = 0;
    const auto code = signing
        ? citizensdk_host_sign_qr_request(host_, bytes_view(request), state.get(), detail::qr_trampoline, &flow)
        : citizensdk_host_scan_qr(host_, state.get(), detail::qr_trampoline, &flow);
    if (code != CITIZENSDK_OK) throw Error(code, last_host_error("CitizenSDK QR flow failed"));
    (void)state.release();
    return WalletFlow(host_, flow);
  }

  void refresh_core_handle() {
    citizensdk_handle_t current = 0;
    const auto code = citizensdk_host_sdk(host_, &current);
    if (code == CITIZENSDK_OK) sdk_ = current;
    else if (code == CITIZENSDK_ERROR_NOT_READY) sdk_ = 0;
    else throw_if_error(code, "CitizenSDK Host ownership query failed");
  }

  void close_noexcept() noexcept {
    if (host_ == 0) return;
    // Clearing the Host callback is a synchronization barrier: success waits
    // for every callback frame, including a std::function copy, to retire. A
    // destructor running inside its own callback is also supported by Host.
    // A failed barrier transfers the Host to its supervisor; if ownership
    // cannot be transferred, terminate rather than leak or free a still-
    // borrowed raw context. Long-lived retries belong only to the supervisor.
    bool transferred = false;
    if (event_context_) {
      const auto clear =
          citizensdk_host_set_event_callback(host_, nullptr, nullptr);
      if (clear != CITIZENSDK_OK &&
          clear != CITIZENSDK_ERROR_INVALID_HANDLE) {
        const auto abandon = citizensdk_host_abandon(host_);
        if (abandon != CITIZENSDK_OK &&
            abandon != CITIZENSDK_ERROR_INVALID_HANDLE) {
          std::terminate();
        }
        transferred = true;
      }
      event_context_.reset();
    }
    const auto code = transferred ? CITIZENSDK_OK
                                  : citizensdk_host_destroy(host_);
    if (!transferred && code != CITIZENSDK_OK &&
        code != CITIZENSDK_ERROR_INVALID_HANDLE) {
      // abandon transfers the complete Host/Core/store/vault graph to its
      // process supervisor; it never borrows this C++ object or event context.
      const auto abandon = citizensdk_host_abandon(host_);
      if (abandon != CITIZENSDK_OK &&
          abandon != CITIZENSDK_ERROR_INVALID_HANDLE) {
        std::terminate();
      }
    }
    host_ = 0;
    sdk_ = 0;
  }

  citizensdk_host_handle_t host_{};
  citizensdk_handle_t sdk_{};
  std::unique_ptr<detail::EventContext> event_context_;
};

}  // namespace citizen_sdk

#endif
