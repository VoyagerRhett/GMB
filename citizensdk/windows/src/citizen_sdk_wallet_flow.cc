#include "citizen_sdk_wallet_flow.hpp"
#include "citizen_sdk_qr_flow.hpp"
#include "citizensdk_internal.h"

#include <algorithm>
#include <chrono>
#include <exception>
#include <limits>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>
#include "citizen_sdk_input_limits.hpp"

namespace citizen_sdk::windows {
namespace {

std::mutex flows_lock;
std::unordered_map<citizensdk_wallet_flow_handle_t, std::shared_ptr<WalletFlow>> flows;
citizensdk_wallet_flow_handle_t next_flow = 1;
bool flow_identity_exhausted = false;

struct ResultOutcome final {
  citizensdk_error_code_t code;
  std::string message;
};

class ResultLease final {
 public:
  explicit ResultLease(citizensdk_result_handle_t result) noexcept
      : result_(result) {}
  ResultLease(const ResultLease &) = delete;
  ResultLease &operator=(const ResultLease &) = delete;
  ~ResultLease() {
    if (result_ != 0) (void)citizensdk_result_release(result_);
  }
  citizensdk_error_code_t release() noexcept {
    if (result_ == 0) return CITIZENSDK_OK;
    const citizensdk_result_handle_t result = result_;
    result_ = 0;
    return citizensdk_result_release(result);
  }

 private:
  citizensdk_result_handle_t result_{};
};

ResultOutcome inspect_result(citizensdk_result_handle_t result) {
  if (result == 0) return {CITIZENSDK_ERROR_INTEGRITY, "Core returned an empty result"};
  citizensdk_result_info_t info{};
  info.struct_size = sizeof(info); info.abi_version = 1;
  citizensdk_error_code_t code = citizensdk_result_get_info(result, &info);
  if (code != CITIZENSDK_OK) return {code, "Core result metadata is invalid"};
  if (info.error_code == CITIZENSDK_OK) return {CITIZENSDK_OK, {}};
  uint64_t required = 0;
  std::string message = "CitizenSDK wallet operation failed";
  if (citizensdk_result_copy_error_message(result, nullptr, 0, &required) == CITIZENSDK_OK &&
      required > 0 && required <= 65536) {
    std::vector<uint8_t> bytes(static_cast<std::size_t>(required));
    if (citizensdk_result_copy_error_message(result, bytes.data(), required,
                                             &required) == CITIZENSDK_OK) {
      message.assign(bytes.begin(), bytes.end());
    }
  }
  return {info.error_code, std::move(message)};
}

citizensdk_bytes_view_t view(const SensitiveBuffer &buffer) {
  return {buffer.data(), static_cast<uint64_t>(buffer.size())};
}

std::string last_error_or(const char *fallback) {
  uint64_t required = 0;
  if (citizensdk_last_error_copy(nullptr, 0, &required) != CITIZENSDK_OK ||
      required == 0 || required > 65536) return fallback;
  std::vector<uint8_t> bytes(static_cast<std::size_t>(required));
  if (citizensdk_last_error_copy(bytes.data(), bytes.size(), &required) !=
          CITIZENSDK_OK || required != bytes.size()) return fallback;
  return std::string(bytes.begin(), bytes.end());
}

void validate_mnemonic(const SensitiveBuffer &mnemonic,
                       citizensdk_wallet_word_count_t word_count) {
  const citizensdk_error_code_t code =
      citizensdk_validate_wallet_mnemonic(view(mnemonic), word_count);
  if (code != CITIZENSDK_OK)
    throw HostError(code, last_error_or("助记词或校验和不正确"));
}

}  // namespace

WalletFlow::WalletFlow(citizensdk_wallet_flow_handle_t handle,
                       std::shared_ptr<HostBridge> host,
                       uint64_t lifecycle_token,
                       ValidatedWalletRequest request, void *context,
                       citizensdk_wallet_flow_completion_v1_t completion,
                       Terminal terminal)
    : handle_(handle), host_(std::move(host)), lifecycle_token_(lifecycle_token),
      request_(std::move(request)), context_(context), completion_(completion),
      terminal_(std::move(terminal)) {}

WalletFlow::~WalletFlow() {
  if (window_ && !window_->on_ui_thread()) std::terminate();
  if (window_) window_->clear_secrets();
  {
    std::lock_guard<std::mutex> guard(prepared_lock_);
    // A prepared handle may leave the flow only after Core confirms release or
    // accepts commit ownership. Destructor best-effort release would make a
    // failure unreachable and permanently block Core destruction.
    if (prepared_ != 0) std::terminate();
  }
}

void WalletFlow::start() {
  const std::weak_ptr<WalletFlow> weak = shared_from_this();
  // 原样保留 Core 钱包状态机；Windows 租约仅替换原生窗口与调度所有权。
  WindowLease parent = host_->acquire_parent_window();
  window_ = std::make_unique<WalletWindow>(
      std::move(parent), request_,
      [weak] { if (const auto flow = weak.lock()) flow->action(); },
      [weak] { if (const auto flow = weak.lock()) flow->cancel(); });
  window_->show();
  if (request_.account_id) begin_private_key_view();
}

void WalletFlow::action() {
  if (finished_.load()) return;
  try {
    if (request_.account_id) {
      if (private_view_displayed_) {
        end_private_key_view(false, CITIZENSDK_OK);
        return;
      }
      if (private_view_revealed_) return;
      private_view_revealed_ = true;
      window_->set_busy("正在进行设备认证，请勿离开安全查看窗口…");
      uint64_t view_id = 0;
      { std::lock_guard<std::mutex> guard(view_lock_); view_id = private_view_id_; }
      const auto code = citizensdk_internal_private_key_view_reveal(host_->sdk(), view_id);
      if (code != CITIZENSDK_OK) end_private_key_view(true, code);
      return;
    }
    if (request_.kind == CITIZENSDK_WALLET_FLOW_CREATE) {
      citizensdk_prepared_wallet_handle_t prepared = 0;
      {
        std::lock_guard<std::mutex> guard(prepared_lock_);
        prepared = prepared_;
      }
      if (prepared == 0) begin_prepare();
      else commit_prepared();
    } else {
      begin_import_or_add();
    }
  } catch (const HostError &error) {
    show_error(error.code(), error.what());
  } catch (...) {
    show_error(CITIZENSDK_ERROR_INTERNAL,
               "CitizenSDK wallet interface failed");
  }
}

void WalletFlow::begin_private_key_view() {
  const auto self = shared_from_this();
  citizensdk_internal_private_key_view_v1_t view{};
  view.struct_size = sizeof(view); view.abi_version = 1;
  view.context = this;
  view.display = display_private_key;
  view.settled = private_key_settled;
  view.authorizing = private_key_authorizing;
  uint64_t view_id = 0;
  citizensdk_request_id_t request = 0;
  operation_in_flight_.store(true);
  const auto code = host_->submit_private(
      [&](citizensdk_request_id_t *out) {
        return citizensdk_internal_private_key_view_open(
            host_->sdk(), &*request_.account_id, &view, &view_id, out);
      },
      [self](citizensdk_result_handle_t result) noexcept {
        self->receive_private_key_terminal(result);
      }, &request);
  {
    std::lock_guard<std::mutex> guard(view_lock_);
    if (private_view_id_ != 0 && private_view_id_ != view_id) std::terminate();
    private_view_id_ = view_id;
  }
  if (code == CITIZENSDK_OK && view_id != 0 && request != 0) return;
  if (request == 0) {
    operation_in_flight_.store(false);
    throw HostError(code == CITIZENSDK_OK ? CITIZENSDK_ERROR_INTEGRITY : code,
                    "CitizenSDK private-key view was not accepted");
  }
  // 接纳之后即使路由返回错误也不能释放 context；清屏确认后等待真实终态。
  end_private_key_view(true, code);
}

int32_t WalletFlow::display_private_key(
    void *context, uint64_t view_id, citizensdk_bytes_view_t value) noexcept {
  auto *self = static_cast<WalletFlow *>(context);
  if (self == nullptr || view_id == 0 || value.data == nullptr || value.len != 32)
    return CITIZENSDK_ERROR_INTEGRITY;
  try {
    std::lock_guard<std::mutex> guard(self->view_lock_);
    if (self->private_view_closed_ || self->cancel_requested_.load())
      return CITIZENSDK_ERROR_CANCELLED;
    if (self->private_view_id_ != 0 && self->private_view_id_ != view_id)
      return CITIZENSDK_ERROR_INVALID_HANDLE;
    if (self->private_display_accepted_) return CITIZENSDK_ERROR_INVALID_STATE;
    self->private_view_id_ = view_id;
    // 借用只在此短锁内复制，不派发 UI、不等待 UI、也不反调 Core。
    self->private_key_ = SensitiveBuffer(value.data, 32);
    self->private_display_accepted_ = true;
    return CITIZENSDK_OK;
  } catch (...) { return map_exception(); }
}

int32_t WalletFlow::private_key_authorizing(
    void *context, uint64_t view_id, uint64_t host_operation_id) noexcept {
  auto *self = static_cast<WalletFlow *>(context);
  if (self == nullptr || view_id == 0 || host_operation_id == 0)
    return CITIZENSDK_ERROR_INTEGRITY;
  try {
    std::lock_guard<std::mutex> guard(self->view_lock_);
    if (self->private_view_closed_ || self->cancel_requested_.load())
      return CITIZENSDK_ERROR_CANCELLED;
    if ((self->private_view_id_ != 0 && self->private_view_id_ != view_id) ||
        self->private_host_operation_id_ != 0 || !self->window_ || !self->host_)
      return CITIZENSDK_ERROR_INTEGRITY;
    self->private_view_id_ = view_id;
    self->private_host_operation_id_ = host_operation_id;
    return self->window_->authorize_private_key_view(
        self->host_->authentication_owner(), host_operation_id)
        ? CITIZENSDK_OK : CITIZENSDK_ERROR_CANCELLED;
  } catch (...) { return map_exception(); }
}

void WalletFlow::private_key_settled(
    void *context, uint64_t view_id, int32_t error) noexcept {
  auto *self = static_cast<WalletFlow *>(context);
  if (self == nullptr) std::terminate();
  self->receive_private_key_settled(view_id, error);
}

void WalletFlow::receive_private_key_settled(
    uint64_t view_id, citizensdk_error_code_t error) noexcept {
  try {
    const auto self = shared_from_this();
    {
      std::lock_guard<std::mutex> guard(view_lock_);
      if (private_view_id_ != 0 && private_view_id_ != view_id) std::terminate();
      private_view_id_ = view_id;
    }
    if (!window_->invoke([self, error] {
          if (self->finished_.load()) return;
          self->window_->finish_private_key_authentication();
          SensitiveBuffer secret;
          bool closed = false;
          {
            std::lock_guard<std::mutex> guard(self->view_lock_);
            closed = self->private_view_closed_ || self->cancel_requested_.load();
            secret = std::move(self->private_key_);
          }
          if (closed || error != CITIZENSDK_OK) {
            secret.clear();
            self->end_private_key_view(true, error);
            return;
          }
          try {
            self->window_->show_private_key(secret);
            secret.clear();
            self->private_view_displayed_ = true;
          } catch (...) {
            secret.clear();
            self->end_private_key_view(true, map_exception());
          }
        })) {
      finish(CITIZENSDK_WALLET_FLOW_FAILED, CITIZENSDK_ERROR_UNAVAILABLE);
    }
  } catch (...) {
    finish(CITIZENSDK_WALLET_FLOW_FAILED, CITIZENSDK_ERROR_INTERNAL);
  }
}

uint64_t WalletFlow::revoke_private_key_display() noexcept {
  std::lock_guard<std::mutex> guard(view_lock_);
  private_view_closed_ = true;
  if (window_) window_->revoke_private_key_authorization();
  private_key_.clear();
  return private_view_id_;
}

void WalletFlow::end_private_key_view(
    bool cancelled, citizensdk_error_code_t error) noexcept {
  if (!window_ || !window_->on_ui_thread()) std::terminate();
  if (cancelled) cancel_requested_.store(true);
  const uint64_t view_id = revoke_private_key_display();
  // 先清原生控件与自管缓冲，再向 Core 确认；窗口对象保留给最终回调调度。
  window_->clear_secrets();
  window_->destroy();
  if (view_id == 0) {
    if (operation_in_flight_.load()) std::terminate();
    finish(CITIZENSDK_WALLET_FLOW_FAILED, error);
    return;
  }
  if (cancelled)
    (void)citizensdk_internal_private_key_view_cancel(host_->sdk(), view_id);
  const auto code = citizensdk_internal_private_key_view_finish(host_->sdk(), view_id);
  if (code == CITIZENSDK_OK || code == CITIZENSDK_ERROR_INVALID_HANDLE) return;
  if (private_finish_supervised_.exchange(true)) return;
  // 不能丢弃尚未接受的清屏确认；只监督短控制重试，不伪造请求完成。
  const auto self = shared_from_this();
  try {
    std::thread([self, view_id]() noexcept {
      auto delay = std::chrono::milliseconds(10);
      for (;;) {
        if (!self->operation_in_flight_.load()) return;
        const auto retry = citizensdk_internal_private_key_view_finish(self->host_->sdk(), view_id);
        if (retry == CITIZENSDK_OK || retry == CITIZENSDK_ERROR_INVALID_HANDLE) return;
        try { std::this_thread::sleep_for(delay); } catch (...) {}
        delay = std::min(delay * 2, std::chrono::milliseconds(5000));
      }
    }).detach();
  } catch (...) { std::terminate(); }
}

void WalletFlow::receive_private_key_terminal(
    citizensdk_result_handle_t result) noexcept {
  ResultLease owner(result);
  citizensdk_error_code_t code = CITIZENSDK_ERROR_INTERNAL;
  try {
    code = inspect_result(result).code;
    if (code == CITIZENSDK_OK) {
      citizensdk_result_info_t info{};
      info.struct_size = sizeof(info); info.abi_version = 1;
      if (citizensdk_result_get_info(result, &info) != CITIZENSDK_OK ||
          info.kind != CITIZENSDK_RESULT_EMPTY) code = CITIZENSDK_ERROR_INTEGRITY;
    }
  } catch (...) { code = map_exception(); }
  if (owner.release() != CITIZENSDK_OK) code = CITIZENSDK_ERROR_INTEGRITY;
  {
    std::lock_guard<std::mutex> guard(view_lock_);
    private_view_closed_ = true;
    private_key_.clear();
    private_view_id_ = 0;
  }
  operation_in_flight_.store(false);
  finish(code == CITIZENSDK_OK ? CITIZENSDK_WALLET_FLOW_COMPLETED
         : code == CITIZENSDK_ERROR_CANCELLED ? CITIZENSDK_WALLET_FLOW_CANCELLED
                                             : CITIZENSDK_WALLET_FLOW_FAILED, code);
}

void WalletFlow::begin_prepare() {
  SensitiveBuffer password = window_->take_password();
  const citizensdk_wallet_word_count_t word_count = window_->word_count();
  window_->set_busy("正在本设备生成钱包…");
  const auto self = shared_from_this();
  citizensdk_request_id_t request = 0;
  operation_in_flight_.store(true);
  const citizensdk_error_code_t code = host_->submit_private(
      [&](citizensdk_request_id_t *out) {
        return citizensdk_prepare_wallet_creation(host_->sdk(), word_count,
                                                   view(password), out);
      },
      [self](citizensdk_result_handle_t result) noexcept {
        self->receive_prepare(result);
      },
      &request);
  password.clear();
  if (code != CITIZENSDK_OK) {
    operation_in_flight_.store(false);
    if (request != 0) {
      finish(CITIZENSDK_WALLET_FLOW_FAILED, code);
      return;
    }
    throw HostError(code, "CitizenSDK wallet preparation was rejected");
  }
}

void WalletFlow::receive_prepare(citizensdk_result_handle_t result) noexcept {
  ResultLease result_owner(result);
  citizensdk_prepared_wallet_handle_t prepared = 0;
  SensitiveBuffer mnemonic;
  citizensdk_error_code_t code = CITIZENSDK_ERROR_INTERNAL;
  try {
    const ResultOutcome outcome = inspect_result(result);
    code = outcome.code;
    if (code == CITIZENSDK_OK) {
      citizensdk_prepared_wallet_info_t info{};
      info.struct_size = sizeof(info); info.abi_version = 1;
      code = citizensdk_result_get_prepared_wallet(result, &info);
      prepared = info.prepared_wallet;
      uint64_t required = 0;
      if (code == CITIZENSDK_OK) {
        code = citizensdk_prepared_wallet_copy_mnemonic(
            host_->sdk(), prepared, nullptr, 0, &required);
      }
      if (code == CITIZENSDK_OK && required > 0 && required <= 4096) {
        mnemonic = SensitiveBuffer(static_cast<std::size_t>(required));
        code = citizensdk_prepared_wallet_copy_mnemonic(
            host_->sdk(), prepared, mnemonic.data(), mnemonic.size(),
            &required);
        if (code == CITIZENSDK_OK && required != mnemonic.size()) {
          mnemonic.clear();
          code = CITIZENSDK_ERROR_INTEGRITY;
        }
      } else if (code == CITIZENSDK_OK) {
        code = CITIZENSDK_ERROR_INTEGRITY;
      }
    }
  } catch (...) {
    code = map_exception();
  }
  const citizensdk_error_code_t release_code = result_owner.release();
  if (release_code != CITIZENSDK_OK) {
    code = CITIZENSDK_ERROR_INTEGRITY;
  }
  try {
    const auto self = shared_from_this();
    auto secret = std::make_shared<SensitiveBuffer>(std::move(mnemonic));
    const bool scheduled = window_->invoke(
        [self, prepared, code, secret]() mutable {
    self->operation_in_flight_.store(false);
    if (self->finished_.load()) {
      secret->clear();
      if (prepared != 0) {
        self->release_prepared_or_supervise(
            prepared, CITIZENSDK_WALLET_FLOW_FAILED,
            CITIZENSDK_ERROR_INVALID_STATE, CITIZENSDK_ERROR_INTEGRITY);
      }
      return;
    }
    if (code != CITIZENSDK_OK) {
      citizensdk_error_code_t final_code = code;
      secret->clear();
      if (prepared != 0) {
        self->release_prepared_or_supervise(
            prepared, CITIZENSDK_WALLET_FLOW_FAILED, final_code,
            CITIZENSDK_ERROR_INTEGRITY);
        return;
      }
      if (self->cancel_requested_.load()) {
        self->finish(CITIZENSDK_WALLET_FLOW_CANCELLED, CITIZENSDK_OK);
      } else {
        self->show_error(final_code,
            "钱包生成准备失败；钱包密码已清除，请重新选择空密码或重新输入");
      }
      return;
    }
    if (self->cancel_requested_.load()) {
      secret->clear();
      self->release_prepared_or_supervise(
          prepared, CITIZENSDK_WALLET_FLOW_CANCELLED, CITIZENSDK_OK,
          CITIZENSDK_ERROR_INTEGRITY);
      return;
    }
    {
      std::lock_guard<std::mutex> guard(self->prepared_lock_);
      self->prepared_ = prepared;
    }
    self->window_->show_prepared_mnemonic(*secret);
    secret->clear();
        });
    if (!scheduled) {
      operation_in_flight_.store(false);
      secret->clear();
      if (prepared != 0) {
        release_prepared_or_supervise(
            prepared, CITIZENSDK_WALLET_FLOW_FAILED,
            CITIZENSDK_ERROR_UNAVAILABLE, CITIZENSDK_ERROR_INTEGRITY);
      } else {
        finish(CITIZENSDK_WALLET_FLOW_FAILED, CITIZENSDK_ERROR_UNAVAILABLE);
      }
    }
  } catch (...) {
    operation_in_flight_.store(false);
    mnemonic.clear();
    citizensdk_error_code_t final_code = map_exception();
    if (prepared != 0) {
      release_prepared_or_supervise(prepared, CITIZENSDK_WALLET_FLOW_FAILED,
                                    final_code, CITIZENSDK_ERROR_INTEGRITY);
    } else {
      finish(CITIZENSDK_WALLET_FLOW_FAILED, final_code);
    }
  }
}

void WalletFlow::commit_prepared() {
  require(window_->backup_confirmed(), CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "请先确认助记词已经离线备份");
  window_->clear_secrets();
  window_->set_busy("正在把钱包写入本设备安全存储…");
  irreversible_.store(true);
  const auto self = shared_from_this();
  citizensdk_prepared_wallet_handle_t prepared = 0;
  {
    std::lock_guard<std::mutex> guard(prepared_lock_);
    prepared = prepared_;
    require(prepared != 0, CITIZENSDK_ERROR_INVALID_STATE,
            "CitizenSDK prepared wallet handle is unavailable");
    // Transfer is staged before Core admission so an early completion can
    // never observe Host as still owning a handle already accepted by commit.
    // A true pre-admission rejection restores this exact handle below.
    prepared_ = 0;
  }
  citizensdk_request_id_t request = 0;
  operation_in_flight_.store(true);
  const citizensdk_error_code_t code = host_->submit_private(
      [&](citizensdk_request_id_t *out) {
        return citizensdk_commit_wallet_creation(host_->sdk(), prepared, out);
      },
      [self](citizensdk_result_handle_t result) noexcept {
        self->receive_terminal(result);
      },
      &request);
  if (code != CITIZENSDK_OK) {
    operation_in_flight_.store(false);
    if (request != 0) {
      finish(CITIZENSDK_WALLET_FLOW_FAILED, code);
      return;
    }
    {
      std::lock_guard<std::mutex> guard(prepared_lock_);
      if (prepared_ != 0) std::terminate();
      prepared_ = prepared;
    }
    irreversible_.store(false);
    throw HostError(code, "CitizenSDK wallet commit was rejected");
  }
}

void WalletFlow::begin_import_or_add() {
  SensitiveBuffer mnemonic = window_->take_mnemonic();
  validate_mnemonic(mnemonic, window_->word_count());
  SensitiveBuffer password = window_->take_password();
  auto owned_mnemonic = std::make_shared<SensitiveBuffer>(std::move(mnemonic));
  auto owned_password = std::make_shared<SensitiveBuffer>(std::move(password));
  if (request_.kind != CITIZENSDK_WALLET_FLOW_ADD_ACCOUNTS ||
      !window_->use_next_account()) {
    std::vector<uint32_t> indices;
    if (request_.kind == CITIZENSDK_WALLET_FLOW_ADD_ACCOUNTS)
      indices = window_->account_indices();
    submit_import_or_add(std::move(owned_mnemonic), std::move(owned_password),
                         std::move(indices));
    return;
  }

  window_->set_busy("正在读取钱包账户以选择下一个索引…");
  operation_in_flight_.store(true);
  const auto self = shared_from_this();
  citizensdk_request_id_t request = 0;
  const citizensdk_error_code_t code = host_->submit_private(
      [&](citizensdk_request_id_t *out) {
        return citizensdk_get_wallet_profile(host_->sdk(), out);
      },
      [self, owned_mnemonic, owned_password](
          citizensdk_result_handle_t result) noexcept {
        self->receive_next_account(result, owned_mnemonic, owned_password);
      },
      &request);
  if (code != CITIZENSDK_OK) {
    operation_in_flight_.store(false);
    owned_mnemonic->clear(); owned_password->clear();
    if (request != 0) {
      finish(CITIZENSDK_WALLET_FLOW_FAILED, code);
      return;
    }
    show_error(code, "无法读取钱包账户；助记词与钱包密码已清除，请重新输入");
  }
}

void WalletFlow::submit_import_or_add(
    std::shared_ptr<SensitiveBuffer> mnemonic,
    std::shared_ptr<SensitiveBuffer> password,
    std::vector<uint32_t> account_indices) {
  if (request_.kind == CITIZENSDK_WALLET_FLOW_ADD_ACCOUNTS) {
    input_limits::validate_wallet_indices(account_indices.data(),
        static_cast<uint32_t>(account_indices.size()));
  }
  window_->set_busy(request_.kind == CITIZENSDK_WALLET_FLOW_IMPORT
                        ? "正在本设备导入钱包…" : "正在本设备添加账户…");
  irreversible_.store(true);
  const auto self = shared_from_this();
  citizensdk_request_id_t request = 0;
  operation_in_flight_.store(true);
  const citizensdk_error_code_t code = host_->submit_private(
      [&](citizensdk_request_id_t *out) {
        if (request_.kind == CITIZENSDK_WALLET_FLOW_IMPORT) {
          return citizensdk_import_wallet(host_->sdk(), view(*mnemonic),
                                          view(*password), out);
        }
        return citizensdk_add_wallet_accounts(
            host_->sdk(), view(*mnemonic), view(*password),
            account_indices.data(), static_cast<uint32_t>(account_indices.size()), out);
      },
      [self](citizensdk_result_handle_t result) noexcept {
        self->receive_terminal(result);
      },
      &request);
  mnemonic->clear();
  password->clear();
  if (code != CITIZENSDK_OK) {
    operation_in_flight_.store(false);
    if (request != 0) {
      finish(CITIZENSDK_WALLET_FLOW_FAILED, code);
      return;
    }
    irreversible_.store(false);
    show_error(code, "钱包操作被拒绝；助记词与钱包密码已清除，请重新输入");
  }
}

void WalletFlow::receive_next_account(
    citizensdk_result_handle_t result,
    std::shared_ptr<SensitiveBuffer> mnemonic,
    std::shared_ptr<SensitiveBuffer> password) noexcept {
  ResultLease result_owner(result);
  ResultOutcome outcome{CITIZENSDK_ERROR_INTERNAL, "无法读取钱包账户"};
  uint32_t next = 0;
  try {
    outcome = inspect_result(result);
    if (outcome.code == CITIZENSDK_OK) {
      citizensdk_wallet_profile_info_t profile{};
      profile.struct_size = sizeof(profile); profile.abi_version = 1;
      outcome.code = citizensdk_result_get_wallet_profile(result, &profile);
      if (outcome.code == CITIZENSDK_OK && profile.present == 0)
        outcome = {CITIZENSDK_ERROR_NOT_READY, "当前设备尚未创建或导入钱包"};
      uint32_t count = 0;
      if (outcome.code == CITIZENSDK_OK)
        outcome.code = citizensdk_result_get_wallet_account_count(result, &count);
      if (outcome.code == CITIZENSDK_OK && count != profile.account_count)
        outcome = {CITIZENSDK_ERROR_INTEGRITY,
                   "钱包资料与账户列表数量不一致"};
      bool anchor = false;
      uint32_t maximum = 0;
      for (uint32_t index = 0; outcome.code == CITIZENSDK_OK && index < count; ++index) {
        citizensdk_wallet_account_info_t account{};
        account.struct_size = sizeof(account); account.abi_version = 1;
        uint64_t ss58 = 0, name = 0;
        outcome.code = citizensdk_result_get_wallet_account(
            result, index, &account, nullptr, 0, &ss58, nullptr, 0, &name);
        if (outcome.code == CITIZENSDK_OK) {
          anchor = anchor || account.index == 0;
          maximum = std::max(maximum, account.index);
        }
      }
      if (outcome.code == CITIZENSDK_OK && (!anchor || maximum >= 1989))
        outcome = {CITIZENSDK_ERROR_INVALID_STATE,
                   "钱包账户索引已损坏或没有可用的下一个索引"};
      if (outcome.code == CITIZENSDK_OK) next = maximum + 1;
    }
  } catch (...) {
    outcome.code = map_exception();
  }
  if (result_owner.release() != CITIZENSDK_OK)
    outcome = {CITIZENSDK_ERROR_INTEGRITY, "钱包账户结果无法安全释放"};
  try {
    const auto self = shared_from_this();
    if (!window_->invoke([self, outcome, next, mnemonic, password] {
          self->operation_in_flight_.store(false);
          if (self->finished_.load()) { mnemonic->clear(); password->clear(); return; }
          if (self->cancel_requested_.load()) {
            mnemonic->clear(); password->clear();
            self->finish(CITIZENSDK_WALLET_FLOW_CANCELLED, CITIZENSDK_OK);
            return;
          }
          if (outcome.code != CITIZENSDK_OK) {
            mnemonic->clear(); password->clear();
            if (outcome.code == CITIZENSDK_ERROR_INTEGRITY) {
              self->finish(CITIZENSDK_WALLET_FLOW_FAILED, outcome.code);
              return;
            }
            self->show_error(outcome.code, outcome.message +
                "；助记词与钱包密码已清除，请重新输入");
            return;
          }
          self->submit_import_or_add(mnemonic, password, {next});
        })) {
      operation_in_flight_.store(false);
      mnemonic->clear(); password->clear();
      finish(CITIZENSDK_WALLET_FLOW_FAILED, CITIZENSDK_ERROR_UNAVAILABLE);
    }
  } catch (...) {
    operation_in_flight_.store(false);
    mnemonic->clear(); password->clear();
    finish(CITIZENSDK_WALLET_FLOW_FAILED, map_exception());
  }
}

void WalletFlow::receive_terminal(citizensdk_result_handle_t result) noexcept {
  ResultLease result_owner(result);
  ResultOutcome outcome{CITIZENSDK_ERROR_INTERNAL,
                        "CitizenSDK wallet operation failed"};
  try {
    outcome = inspect_result(result);
  } catch (...) {
    outcome.code = map_exception();
  }
  if (result_owner.release() != CITIZENSDK_OK) {
    outcome = {CITIZENSDK_ERROR_INTEGRITY,
               "CitizenSDK Core result could not be released exactly once"};
  }
  try {
    const auto self = shared_from_this();
    if (!window_->invoke([self, outcome] {
          self->operation_in_flight_.store(false);
          if (self->finished_.load()) return;
          if (outcome.code == CITIZENSDK_OK) {
            self->finish(CITIZENSDK_WALLET_FLOW_COMPLETED, CITIZENSDK_OK);
          } else if (self->request_.kind != CITIZENSDK_WALLET_FLOW_CREATE &&
                     outcome.code != CITIZENSDK_ERROR_INTEGRITY) {
            self->irreversible_.store(false);
            if (self->cancel_requested_.load()) {
              self->finish(CITIZENSDK_WALLET_FLOW_CANCELLED, CITIZENSDK_OK);
            } else {
              self->show_error(outcome.code, outcome.message +
                  "；助记词与钱包密码已清除，请重新输入");
            }
          } else {
            self->finish(CITIZENSDK_WALLET_FLOW_FAILED, outcome.code);
          }
        })) {
      operation_in_flight_.store(false);
      finish(CITIZENSDK_WALLET_FLOW_FAILED, CITIZENSDK_ERROR_UNAVAILABLE);
    }
  } catch (...) {
    operation_in_flight_.store(false);
    finish(CITIZENSDK_WALLET_FLOW_FAILED, map_exception());
  }
}

void WalletFlow::cancel() noexcept {
  try {
    if (finished_.load()) return;
    cancel_requested_.store(true);
    if (request_.account_id) (void)revoke_private_key_display();
    const auto self = shared_from_this();
    if (!window_->invoke([self] {
    if (self->finished_.load()) return;
    if (self->request_.account_id) {
      self->end_private_key_view(true, CITIZENSDK_ERROR_CANCELLED);
      return;
    }
    self->window_->clear_secrets();
    citizensdk_prepared_wallet_handle_t prepared = 0;
    {
      std::lock_guard<std::mutex> guard(self->prepared_lock_);
      prepared = self->prepared_;
    }
    if (prepared != 0) {
      self->release_prepared_or_supervise(
          prepared, CITIZENSDK_WALLET_FLOW_CANCELLED, CITIZENSDK_OK,
          CITIZENSDK_ERROR_INTEGRITY);
    } else if (!self->irreversible_.load() &&
               !self->operation_in_flight_.load()) {
      self->finish(CITIZENSDK_WALLET_FLOW_CANCELLED, CITIZENSDK_OK);
    } else {
      self->window_->set_busy("正在安全结束当前钱包操作…");
    }
        })) {
      finish(CITIZENSDK_WALLET_FLOW_FAILED, CITIZENSDK_ERROR_UNAVAILABLE);
    }
  } catch (...) {
    finish(CITIZENSDK_WALLET_FLOW_FAILED, map_exception());
  }
}

void WalletFlow::show_error(citizensdk_error_code_t code, std::string message) {
  if (cancel_requested_.load() && !irreversible_.load()) {
    finish(CITIZENSDK_WALLET_FLOW_FAILED, code);
    return;
  }
  window_->set_error(message.empty() ? "CitizenSDK 钱包操作失败" : message);
  (void)code;
}

void WalletFlow::release_prepared_or_supervise(
    citizensdk_prepared_wallet_handle_t prepared,
    citizensdk_wallet_flow_status_t success_status,
    citizensdk_error_code_t success_code,
    citizensdk_error_code_t release_failure_code) noexcept {
  if (prepared == 0) {
    finish(success_status, success_code);
    return;
  }
  {
    std::lock_guard<std::mutex> guard(prepared_lock_);
    if (prepared_ != 0 && prepared_ != prepared) std::terminate();
    prepared_ = prepared;
  }
  const citizensdk_handle_t sdk = host_->sdk();
  const citizensdk_error_code_t release =
      sdk == 0 ? release_failure_code
               : citizensdk_prepared_wallet_release(sdk, prepared);
  if (release == CITIZENSDK_OK) {
    {
      std::lock_guard<std::mutex> guard(prepared_lock_);
      prepared_ = 0;
    }
    finish(success_status, success_code);
    return;
  }
  supervise_prepared_release(release);
}

void WalletFlow::supervise_prepared_release(
    citizensdk_error_code_t release_failure_code) noexcept {
  const auto self = weak_from_this().lock();
  if (!self) std::terminate();
  if (window_ && !window_->on_ui_thread()) {
    if (!window_->invoke([self, release_failure_code] {
          self->supervise_prepared_release(release_failure_code);
        })) {
      std::terminate();
    }
    return;
  }
  if (cleanup_supervised_.exchange(true)) return;
  const bool owns_terminal = !finished_.exchange(true);
  if (owns_terminal) {
    if (window_) {
      window_->clear_secrets();
      window_->destroy();
      window_.reset();
    }
    citizensdk_wallet_flow_result_v1_t result{};
    result.struct_size = sizeof(result);
    result.abi_version = 1;
    result.status = CITIZENSDK_WALLET_FLOW_FAILED;
    result.error_code = release_failure_code;
    try { completion_(context_, &result); } catch (...) {}
  }
  std::thread supervisor;
  try {
    supervisor = std::thread([self, owns_terminal]() noexcept {
      auto delay = std::chrono::milliseconds(10);
      for (;;) {
        citizensdk_prepared_wallet_handle_t prepared = 0;
        {
          std::lock_guard<std::mutex> guard(self->prepared_lock_);
          prepared = self->prepared_;
        }
        if (prepared == 0) break;
        const citizensdk_handle_t sdk = self->host_->sdk();
        if (sdk != 0 &&
            citizensdk_prepared_wallet_release(sdk, prepared) ==
                CITIZENSDK_OK) {
          std::lock_guard<std::mutex> guard(self->prepared_lock_);
          if (self->prepared_ == prepared) self->prepared_ = 0;
          break;
        }
        try { std::this_thread::sleep_for(delay); } catch (...) {}
        delay = std::min(delay * 2, std::chrono::milliseconds(5000));
      }
      if (owns_terminal) {
        self->host_->finish_wallet_flow(self->lifecycle_token_);
        try { self->terminal_(self->handle_); } catch (...) { std::terminate(); }
      }
    });
    supervisor.detach();
  } catch (...) {
    if (supervisor.joinable()) std::terminate();
    std::terminate();
  }
}

void WalletFlow::finish(citizensdk_wallet_flow_status_t status,
                        citizensdk_error_code_t code) noexcept {
  const auto keep_alive = weak_from_this().lock();
  if (!keep_alive) return;
  citizensdk_prepared_wallet_handle_t retained = 0;
  {
    std::lock_guard<std::mutex> guard(prepared_lock_);
    retained = prepared_;
  }
  if (retained != 0) {
    // Never erase the only owner of a Core prepared handle on a release
    // failure. The dedicated cleanup path reports failure once and retains
    // ownership until Core accepts release.
    supervise_prepared_release(code == CITIZENSDK_OK
                                   ? CITIZENSDK_ERROR_INTEGRITY
                                   : code);
    return;
  }
  if (window_ && !window_->on_ui_thread()) {
    if (finish_scheduled_.exchange(true)) return;
    const auto supervise = [keep_alive, status, code]() noexcept {
      auto delay = std::chrono::milliseconds(1);
      // Source construction/attachment failure is normally transient resource
      // pressure. Retry a bounded number of times. If no cleanup action can be
      // admitted, terminating is safer than either running Win32 destruction on
      // a worker or retaining mnemonic/password widget buffers indefinitely.
      for (unsigned attempt = 0; attempt < 8; ++attempt) {
        if (keep_alive->window_->invoke([keep_alive, status, code] {
              keep_alive->finish_scheduled_.store(false);
              keep_alive->finish(status, code);
            })) {
          return;
        }
        try { std::this_thread::sleep_for(delay); } catch (...) {}
        delay = std::min(delay * 2, std::chrono::milliseconds(100));
      }
      std::terminate();
    };
    std::thread supervisor;
    try {
      supervisor = std::thread(supervise);
      supervisor.detach();
    } catch (...) {
      if (supervisor.joinable()) supervisor.join();
      else supervise();
    }
    return;
  }
  if (request_.account_id && operation_in_flight_.load()) {
    end_private_key_view(true, code == CITIZENSDK_OK ? CITIZENSDK_ERROR_CANCELLED : code);
    return;
  }
  if (finished_.exchange(true)) return;
  if (window_) {
    try { window_->clear_secrets(); window_->destroy(); } catch (...) {}
  }
  host_->finish_wallet_flow(lifecycle_token_);
  try { terminal_(handle_); } catch (...) { std::terminate(); }
  citizensdk_wallet_flow_result_v1_t result{};
  result.struct_size = sizeof(result); result.abi_version = 1;
  result.status = status; result.error_code = code;
  try { completion_(context_, &result); } catch (...) {}
}

citizensdk_wallet_flow_handle_t reserve_wallet_flow_handle() {
  std::lock_guard<std::mutex> guard(flows_lock);
  require(!flow_identity_exhausted, CITIZENSDK_ERROR_UNAVAILABLE, "UI 句柄已耗尽");
  const auto handle = next_flow;
  if (next_flow == std::numeric_limits<citizensdk_wallet_flow_handle_t>::max())
    flow_identity_exhausted = true;
  else ++next_flow;
  return handle;
}

static citizensdk_error_code_t register_wallet_flow(
    const std::shared_ptr<HostBridge> &host,
    const ValidatedWalletRequest &validated, void *context,
    citizensdk_wallet_flow_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_handle) {
  if (!host || completion == nullptr || out_handle == nullptr) {
    return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  }
  *out_handle = 0;
  // 独立签名也拥有金库，但不得因此开放未启用的钱包管理界面。
  if ((host->modules() & CITIZENSDK_MODULE_WALLET) == 0)
    return CITIZENSDK_ERROR_UNSUPPORTED;
  if (host->public_sdk() == 0) return CITIZENSDK_ERROR_NOT_READY;
  const auto vault = host->vault_availability();
  if (vault == CITIZENSDK_HOST_VAULT_UNSUPPORTED) {
    return CITIZENSDK_ERROR_UNSUPPORTED;
  }
  if (vault != CITIZENSDK_HOST_VAULT_AVAILABLE) {
    return CITIZENSDK_ERROR_UNAVAILABLE;
  }
  uint64_t token = 0;
  try {
    token = host->reserve_wallet_flow();
    const auto handle = reserve_wallet_flow_handle();
    std::shared_ptr<WalletFlow> flow;
    {
      std::lock_guard<std::mutex> guard(flows_lock);
      auto terminal = [](citizensdk_wallet_flow_handle_t completed) {
        std::lock_guard<std::mutex> lock(flows_lock);
        flows.erase(completed);
      };
      flow = std::make_shared<WalletFlow>(
          handle, host, token, validated, context, completion, terminal);
      flows.emplace(handle, flow);
    }
    try {
      flow->start();
    } catch (...) {
      std::lock_guard<std::mutex> guard(flows_lock);
      flows.erase(handle);
      throw;
    }
    // Ownership of the lifecycle token is now held by the registered flow.
    token = 0;
    *out_handle = handle;
    return CITIZENSDK_OK;
  } catch (...) {
    if (token != 0) host->finish_wallet_flow(token);
    return map_exception();
  }
}

citizensdk_error_code_t present_wallet_flow(
    const std::shared_ptr<HostBridge> &host,
    const citizensdk_wallet_flow_request_v1_t &request, void *context,
    citizensdk_wallet_flow_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_handle) {
  if (out_handle != nullptr) *out_handle = 0;
  try {
    return register_wallet_flow(host, validate_wallet_request(request), context,
                                completion, out_handle);
  } catch (...) { return map_exception(); }
}

citizensdk_error_code_t view_account_private_key(
    const std::shared_ptr<HostBridge> &host,
    const citizensdk_account_id_t &account_id, void *context,
    citizensdk_wallet_flow_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_handle) {
  ValidatedWalletRequest request;
  request.account_id = account_id;
  return register_wallet_flow(host, request, context, completion, out_handle);
}

citizensdk_error_code_t cancel_wallet_flow(
    const std::shared_ptr<HostBridge> &host,
    citizensdk_wallet_flow_handle_t handle) noexcept {
  try {
    std::shared_ptr<WalletFlow> flow;
    {
      std::lock_guard<std::mutex> guard(flows_lock);
      const auto found = flows.find(handle);
      if (found != flows.end()) flow = found->second;
    }
    if (!flow) return cancel_qr_flow(host, handle);
    if (!flow->belongs_to(host)) return CITIZENSDK_ERROR_INVALID_HANDLE;
    flow->cancel();
    return CITIZENSDK_OK;
  } catch (...) {
    return map_exception();
  }
}

}  // namespace citizen_sdk::windows
