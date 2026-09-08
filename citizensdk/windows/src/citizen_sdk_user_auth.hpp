#ifndef CITIZENSDK_WINDOWS_USER_AUTH_HPP
#define CITIZENSDK_WINDOWS_USER_AUTH_HPP

#include <mutex>
#include "citizen_sdk_sensitive_buffer.hpp"
#include "citizen_sdk_window.hpp"

namespace citizen_sdk::windows {
struct AuthenticationResult final {
  citizensdk_error_code_t code{CITIZENSDK_ERROR_INTERNAL};
  SensitiveBuffer password;
};

// 仅原生 UI 线程调用；精确匹配本 Host/本次解包，不向业务暴露认证归属。
bool accept_private_key_authentication_window(
    void *window, void *view_window, const void *owner, uint64_t host_operation_id) noexcept;

class UserAuth final {
 public:
  explicit UserAuth(WindowRef &parent);
  UserAuth(const UserAuth &) = delete;
  UserAuth &operator=(const UserAuth &) = delete;
  ~UserAuth();
  bool available() const noexcept;
  AuthenticationResult create_vault_password();
  AuthenticationResult unlock_vault_password(uint64_t host_operation_id);

 private:
  AuthenticationResult prompt(bool confirmation, uint64_t host_operation_id);
  std::mutex prompt_lock_;
  WindowRef &parent_;
};
}  // namespace citizen_sdk::windows
#endif
