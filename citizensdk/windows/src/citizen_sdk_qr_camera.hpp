#ifndef CITIZENSDK_WINDOWS_QR_CAMERA_HPP
#define CITIZENSDK_WINDOWS_QR_CAMERA_HPP
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>
#include "citizensdk_types.h"
namespace citizen_sdk::windows {
// 相机只输出有界灰度像素；唯一识别器是 SDK ZXing-C++，这里不解释二维码。
struct QrFrame final {
  uint32_t width{};
  uint32_t height{};
  std::vector<uint8_t> luminance;
};
class QrCamera final {
 public:
  using Frame = std::function<void(QrFrame)>;
  using Failure = std::function<void(citizensdk_error_code_t, std::string)>;
  QrCamera(Frame frame, Failure failure);
  QrCamera(const QrCamera &) = delete;
  QrCamera &operator=(const QrCamera &) = delete;
  ~QrCamera();
  void start();
  // 必须在 SDK 清理 worker 调用：停止真实采集、等待回调和线程排空后返回。
  void stop() noexcept;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}  // namespace citizen_sdk::windows
#endif
