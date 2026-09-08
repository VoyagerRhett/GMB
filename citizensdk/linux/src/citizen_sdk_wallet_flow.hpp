#ifndef CITIZENSDK_LINUX_WALLET_FLOW_HPP
#define CITIZENSDK_LINUX_WALLET_FLOW_HPP

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>
#include "citizen_sdk_host_bridge.hpp"
#include "citizen_sdk_wallet_validation.hpp"
#include "citizen_sdk_wallet_window.hpp"

namespace citizen_sdk::linux {

class WalletFlow final : public std::enable_shared_from_this<WalletFlow> {
 public:
  using Terminal = std::function<void(citizensdk_wallet_flow_handle_t)>;
  WalletFlow(citizensdk_wallet_flow_handle_t handle,
             std::shared_ptr<HostBridge> host, uint64_t lifecycle_token,
             ValidatedWalletRequest request, void *context,
             citizensdk_wallet_flow_completion_v1_t completion,
             Terminal terminal);
  WalletFlow(const WalletFlow &) = delete;
  WalletFlow &operator=(const WalletFlow &) = delete;
  ~WalletFlow();

  void start();
  void cancel() noexcept;
  bool belongs_to(const std::shared_ptr<HostBridge> &host) const noexcept {
    return host_.get() == host.get();
  }

 private:
  friend struct WalletFlowTestPeer;
  uint64_t revoke_private_key_display() noexcept;
  void action();
  void begin_private_key_view();
  void end_private_key_view(bool cancelled, citizensdk_error_code_t error) noexcept;
  void receive_private_key_settled(uint64_t view_id, citizensdk_error_code_t error) noexcept;
  void receive_private_key_terminal(citizensdk_result_handle_t result) noexcept;
  static int32_t display_private_key(void *context, uint64_t view_id,
                                      citizensdk_bytes_view_t value) noexcept;
  static int32_t private_key_authorizing(void *context, uint64_t view_id,
                                          uint64_t host_operation_id) noexcept;
  static void private_key_settled(void *context, uint64_t view_id,
                                 int32_t error) noexcept;
  void begin_prepare();
  void commit_prepared();
  void begin_import_or_add();
  void submit_import_or_add(std::shared_ptr<SensitiveBuffer> mnemonic,
                            std::shared_ptr<SensitiveBuffer> password,
                            std::vector<uint32_t> account_indices);
  void receive_next_account(citizensdk_result_handle_t result,
                            std::shared_ptr<SensitiveBuffer> mnemonic,
                            std::shared_ptr<SensitiveBuffer> password) noexcept;
  void receive_prepare(citizensdk_result_handle_t result) noexcept;
  void receive_terminal(citizensdk_result_handle_t result) noexcept;
  void finish(citizensdk_wallet_flow_status_t status,
              citizensdk_error_code_t code) noexcept;
  void release_prepared_or_supervise(
      citizensdk_prepared_wallet_handle_t prepared,
      citizensdk_wallet_flow_status_t success_status,
      citizensdk_error_code_t success_code,
      citizensdk_error_code_t release_failure_code) noexcept;
  void supervise_prepared_release(
      citizensdk_error_code_t release_failure_code) noexcept;
  void show_error(citizensdk_error_code_t code, std::string message);

  citizensdk_wallet_flow_handle_t handle_;
  std::shared_ptr<HostBridge> host_;
  uint64_t lifecycle_token_;
  ValidatedWalletRequest request_;
  void *context_;
  citizensdk_wallet_flow_completion_v1_t completion_;
  Terminal terminal_;
  std::unique_ptr<WalletWindow> window_;
  std::atomic<bool> cancel_requested_{false};
  std::atomic<bool> irreversible_{false};
  std::atomic<bool> finished_{false};
  std::atomic<bool> finish_scheduled_{false};
  std::atomic<bool> operation_in_flight_{false};
  std::atomic<bool> cleanup_supervised_{false};
  // display 与关闭共用短锁；借用指针不跨回调，Core 终态前始终保留 context。
  std::mutex view_lock_;
  uint64_t private_view_id_{};
  uint64_t private_host_operation_id_{};
  SensitiveBuffer private_key_;
  bool private_view_closed_{};
  bool private_view_revealed_{};
  bool private_view_displayed_{};
  bool private_display_accepted_{};
  std::atomic<bool> private_finish_supervised_{false};
  std::mutex prepared_lock_;
  citizensdk_prepared_wallet_handle_t prepared_{};
};

// 钱包与二维码 UI 共用同一单调句柄分配器，取消句柄不可能碰撞。
citizensdk_wallet_flow_handle_t reserve_wallet_flow_handle();
citizensdk_error_code_t present_wallet_flow(
    const std::shared_ptr<HostBridge> &host,
    const citizensdk_wallet_flow_request_v1_t &request, void *context,
    citizensdk_wallet_flow_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_handle);
citizensdk_error_code_t view_account_private_key(
    const std::shared_ptr<HostBridge> &host,
    const citizensdk_account_id_t &account_id, void *context,
    citizensdk_wallet_flow_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_handle);
citizensdk_error_code_t cancel_wallet_flow(
    const std::shared_ptr<HostBridge> &host,
    citizensdk_wallet_flow_handle_t handle) noexcept;

}  // namespace citizen_sdk::linux

#endif
