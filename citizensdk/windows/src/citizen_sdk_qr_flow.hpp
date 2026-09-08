#ifndef CITIZENSDK_WINDOWS_QR_FLOW_HPP
#define CITIZENSDK_WINDOWS_QR_FLOW_HPP
#include <atomic>
#include <memory>
#include <string>
#include "citizen_sdk/citizensdk_host.h"
namespace citizen_sdk::windows {
class HostBridge;
// 相机、UI 与 Core completion 共用不可恢复的取消门；从不因晚到帧/认证恢复。
class QrFlowCancellation final {
 public:
  void cancel() noexcept { cancelled_.store(true); }
  bool cancelled() const noexcept { return cancelled_.load(); }
  bool closing() const noexcept { return closing_.load(); }
  bool accepts() const noexcept { return !cancelled() && !closing(); }
  bool begin_cleanup() noexcept { return closing_.exchange(true); }
 private:
  std::atomic<bool> cancelled_{false};
  std::atomic<bool> closing_{false};
};
// 扫码与安全签名共享既有 UI 租约与取消句柄，但不进入钱包初始化路径。
citizensdk_error_code_t present_qr_flow(
    const std::shared_ptr<HostBridge> &host, std::string sign_request,
    void *context, citizensdk_qr_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_handle);
citizensdk_error_code_t cancel_qr_flow(
    const std::shared_ptr<HostBridge> &host,
    citizensdk_wallet_flow_handle_t handle) noexcept;
void cancel_host_qr_flows(const HostBridge *host) noexcept;
}
#endif
