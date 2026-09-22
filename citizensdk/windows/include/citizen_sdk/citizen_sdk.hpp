#ifndef CITIZENSDK_CPP_HPP
#define CITIZENSDK_CPP_HPP

#include <exception>
#include "citizensdk_qr_image.h"
#include <limits>
#include <memory>
#include <atomic>
#include <map>
#include <mutex>
#include <thread>
#include <string>
#include <utility>
#include "citizen_sdk/citizen_sdk_config.hpp"
#include "citizen_sdk/citizen_sdk_error.hpp"
#include "citizen_sdk/citizen_sdk_events.hpp"
#include "citizen_sdk/citizen_sdk_models.hpp"

namespace citizen_sdk {
namespace detail {

// 非UI Future适配只拥有异步结果和可撤销关联；真正认证仍由Host原金库执行。
struct CredentialProviderState final {
  struct Pending final {
    std::promise<void> cancelled;
    bool revoked{false};
  };
  citizensdk_host_handle_t host{};
  decltype(Config::credentialProvider) provide;
  std::mutex lock;
  std::map<uint64_t, std::shared_ptr<Pending>> pending;
};
struct CredentialProviderBox final {
  std::atomic<uint32_t> references{1};
  std::shared_ptr<CredentialProviderState> state;
};
inline void release_credential_provider(void *raw) noexcept {
  auto *box = static_cast<CredentialProviderBox *>(raw);
  if (box->references.fetch_sub(1) == 1) delete box;
}
inline void install_credential_provider(citizensdk_host_handle_t host,
                                         const Config &config) {
  if (!config.credentialProvider) return;
  auto state = std::make_shared<CredentialProviderState>();
  state->host = host;
  state->provide = config.credentialProvider;
  auto *box = new CredentialProviderBox();
  box->state = state;
  citizensdk_credential_provider_v1_t provider{
      sizeof(citizensdk_credential_provider_v1_t), 1, box,
      +[](void *raw, const citizensdk_credential_challenge_v1_t *request) {
        const auto state = static_cast<CredentialProviderBox *>(raw)->state;
        if (request == nullptr || request->struct_size != sizeof(*request) ||
            request->abi_version != 1 || request->host_operation_id == 0 ||
            request->reserved != 0 || (request->key_purpose != 1 && request->key_purpose != 2))
          throw Error(CITIZENSDK_ERROR_INTEGRITY, "Credential challenge is invalid");
        auto pending = std::make_shared<CredentialProviderState::Pending>();
        CredentialChallenge challenge;
        challenge.host_operation_id = request->host_operation_id;
        challenge.key_purpose = request->key_purpose == 1 ? "create" : "unlock";
        challenge.cancelled = pending->cancelled.get_future().share();
        {
          std::lock_guard<std::mutex> guard(state->lock);
          if (!state->pending.emplace(challenge.host_operation_id, pending).second)
            throw Error(CITIZENSDK_ERROR_CONFLICT, "Credential challenge is already active");
        }
        try {
          std::thread([state, pending, challenge] {
            struct CredentialBytes final {
              std::optional<std::vector<uint8_t>> value;
              ~CredentialBytes() {
                if (!value) return;
                volatile uint8_t *data = value->data();
                for (std::size_t i = 0; i < value->size(); ++i) data[i] = 0;
              }
            } bytes;
            bool invoke = false;
            {
              std::lock_guard<std::mutex> guard(state->lock);
              invoke = !pending->revoked;
            }
            if (invoke) {
              try { bytes.value = state->provide(challenge).get(); }
              catch (...) { bytes.value.reset(); } // 不传播可能带秘密的宿主异常文案。
            }
            bool deliver = false;
            {
              std::lock_guard<std::mutex> guard(state->lock);
              deliver = !pending->revoked;
            }
            if (deliver) {
              // 不持有适配器锁反调Host，避免关闭->idle和回包之间的锁顺序倒置。
              const uint8_t nonnull_empty = 0;
              const citizensdk_bytes_view_t view = bytes.value
                  ? citizensdk_bytes_view_t{
                      bytes.value->empty() ? &nonnull_empty : bytes.value->data(),
                      static_cast<uint64_t>(bytes.value->size())}
                  : citizensdk_bytes_view_t{nullptr, 0};
              (void)citizensdk_host_respond_credential(
                  state->host, challenge.host_operation_id, view);
            }
            // 先清零结果再报告排空；取消通知绝不伪造提供者Future完成。
            if (bytes.value) {
              volatile uint8_t *data = bytes.value->data();
              for (std::size_t i = 0; i < bytes.value->size(); ++i) data[i] = 0;
              bytes.value.reset();
            }
            std::lock_guard<std::mutex> guard(state->lock);
            state->pending.erase(challenge.host_operation_id);
          }).detach();
        } catch (...) {
          std::lock_guard<std::mutex> guard(state->lock);
          state->pending.erase(challenge.host_operation_id);
          throw;
        }
      },
      +[](void *raw, uint64_t id) {
        const auto state = static_cast<CredentialProviderBox *>(raw)->state;
        std::lock_guard<std::mutex> guard(state->lock);
        const auto found = state->pending.find(id);
        if (found == state->pending.end() || found->second->revoked) return;
        found->second->revoked = true;
        found->second->cancelled.set_value();
      },
      +[](void *raw) {
        auto *box = static_cast<CredentialProviderBox *>(raw);
        if (box->references.fetch_add(1) == std::numeric_limits<uint32_t>::max())
          std::terminate();
      },
      release_credential_provider,
      +[](void *raw) -> uint8_t {
        const auto state = static_cast<CredentialProviderBox *>(raw)->state;
        std::lock_guard<std::mutex> guard(state->lock);
        return state->pending.empty() ? 1 : 0;
      }};
  const auto code = citizensdk_host_set_credential_provider(host, &provider);
  release_credential_provider(box); // 成功时Host已经retain；失败时释放唯一所有权。
  throw_if_error(code, "CitizenSDK credential provider registration failed");
}




struct RequestBox final {
  std::atomic<uint32_t> references{1};
  std::function<citizensdk_error_code_t(citizensdk_handle_t, citizensdk_request_id_t *)> accept;
  std::function<void(citizensdk_request_id_t, citizensdk_result_handle_t)> complete;
  std::function<void(citizensdk_handle_t)> cancel;
};
inline void release_request_box(void *raw) noexcept {
  auto *box = static_cast<RequestBox *>(raw);
  const auto previous = box->references.fetch_sub(1);
  if (previous == 0) std::terminate();
  if (previous == 1) delete box;
}

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
    try { detail::install_credential_provider(host_, config); }
    catch (...) { close_noexcept(); throw; }
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

  // 只验签当前Core实例会话；不替换其固定transform，不消费或发起交易。
  void qr_validate_sign_response(const std::string &session_id, const std::string &response) {
    throw_if_error(citizensdk_qr_validate_sign_response(sdk_, bytes_view(session_id), bytes_view(response)),
                   "CitizenSDK QR response preflight failed");
  }


  // 一条Host终态路由保有上下文；公共观察者/Flutter界面关闭不会释放在途资源的回调。
  citizensdk_error_code_t submit_request(
      std::function<citizensdk_error_code_t(citizensdk_handle_t, citizensdk_request_id_t *)> accept,
      std::function<void(citizensdk_request_id_t, citizensdk_result_handle_t)> complete,
      std::function<void(citizensdk_handle_t)> cancel,
      citizensdk_request_id_t *out) {
    if (!accept || !complete || out == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
    *out = 0;
    auto *box = new detail::RequestBox();
    box->accept = std::move(accept);
    box->complete = std::move(complete);
    box->cancel = std::move(cancel);
    const citizensdk_host_request_v1_t callbacks{
      sizeof(citizensdk_host_request_v1_t), CITIZENSDK_HOST_ABI_VERSION, box,
      +[](void *raw, citizensdk_handle_t core, citizensdk_request_id_t *request) -> citizensdk_error_code_t {
        auto *state = static_cast<detail::RequestBox *>(raw);
        // Core已同步复制输入后立即释放接纳闭包，避免秘密输入随整个异步请求驻留。
        auto function = std::move(state->accept);
        try { return function(core, request); }
        catch (const Error &error) { return error.code(); }
        catch (...) { return CITIZENSDK_ERROR_INTERNAL; }
      },
      +[](void *raw, citizensdk_request_id_t request, citizensdk_result_handle_t result) {
        static_cast<detail::RequestBox *>(raw)->complete(request, result);
      },
      +[](void *raw, citizensdk_handle_t core) {
        auto *state = static_cast<detail::RequestBox *>(raw);
        if (state->cancel) state->cancel(core);
      },
      +[](void *raw) {
        auto *state = static_cast<detail::RequestBox *>(raw);
        if (state->references.fetch_add(1) == std::numeric_limits<uint32_t>::max()) std::terminate();
      },
      detail::release_request_box};
    const auto code = citizensdk_host_submit_request(host_, &callbacks, out);
    detail::release_request_box(box);
    return code;
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
