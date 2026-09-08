#ifndef CITIZENSDK_WINDOWS_WALLET_WINDOW_HPP
#define CITIZENSDK_WINDOWS_WALLET_WINDOW_HPP

#include <functional>
#include <memory>
#include <string>
#include <vector>
#include "citizen_sdk_sensitive_buffer.hpp"
#include "citizen_sdk_wallet_validation.hpp"
#include "citizen_sdk_window.hpp"

namespace citizen_sdk::windows {

// 仅 SDK 原生界面内部使用。秘密从不存入系统 EDIT 的文本/撤销存储，
// 也不响应 WM_GETTEXT；输入与转换缓冲的实际容量均有界并主动清零。
class SensitiveInput final {
 public:
  SensitiveInput(void *parent, int identity, int x, int y, int width, int height,
                 bool masked, bool multiline);
  SensitiveInput(const SensitiveInput &) = delete;
  SensitiveInput &operator=(const SensitiveInput &) = delete;
  ~SensitiveInput();
  void *native_handle() const noexcept;
  SensitiveBuffer take_utf8();
  // Windows 安全输入没有 caret，只允许末尾输入/删除，因此候选也只替换末词。
  std::string word_suggestions() const;
  std::string mnemonic_status(citizensdk_wallet_word_count_t word_count) const;
  void replace_last_word(const std::string &word);
  void set_utf8(const SensitiveBuffer &value);
  void clear() noexcept;
  void set_read_only(bool value) noexcept;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

class WalletWindow final {
 public:
  using Action = std::function<void()>;
  WalletWindow(WindowLease parent, const ValidatedWalletRequest &request,
               Action action, Action cancel);
  WalletWindow(const WalletWindow &) = delete;
  WalletWindow &operator=(const WalletWindow &) = delete;
  ~WalletWindow();
  void show();
  void destroy() noexcept;
  void set_busy(const std::string &message);
  void set_error(const std::string &message);
  void show_prepared_mnemonic(const SensitiveBuffer &mnemonic);
  // 仅 SDK 内部调用；不向文本、剪贴板或公开回调传送秘密。
  void show_private_key(const SensitiveBuffer &private_key);
  // worker 只登记真实认证归属；不触碰 UI，不等待 UI，也不反调 Core。
  bool authorize_private_key_view(const void *owner, uint64_t host_operation_id) noexcept;
  void revoke_private_key_authorization() noexcept;
  void finish_private_key_authentication() noexcept;
  bool backup_confirmed() const noexcept;
  // 这些选择属于 SDK 安全窗口，不增加 Flutter/C 方法或秘密字段。
  citizensdk_wallet_word_count_t word_count() const;
  bool use_next_account() const noexcept;
  std::vector<uint32_t> account_indices() const;
  SensitiveBuffer take_mnemonic();
  // 返回后自管输入缓冲已清零；创建/导入的非空值只确认一次风险。
  SensitiveBuffer take_password();
  void clear_secrets() noexcept;
  bool invoke(std::function<void()> action) noexcept;
  bool on_ui_thread() const noexcept;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace citizen_sdk::windows
#endif
