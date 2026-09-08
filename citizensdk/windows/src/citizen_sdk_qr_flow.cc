#include "citizen_sdk_qr_flow.hpp"
#include "citizen_sdk_qr_camera.hpp"
#include "citizen_sdk_wallet_flow.hpp"
#include "citizensdk_qr_image.h"
#include <atomic>
#include <cstring>
#include <mutex>
#include <optional>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>
#include <windows.h>
#include <wtsapi32.h>

namespace citizen_sdk::windows {
namespace {
constexpr uint64_t kDocumentLimit = 65536;
std::mutex qr_flows_lock;
class QrFlow;
std::unordered_map<citizensdk_wallet_flow_handle_t, std::shared_ptr<QrFlow>> qr_flows;

citizensdk_bytes_view_t qr_view(const std::string &value) {
  return {reinterpret_cast<const uint8_t *>(value.data()), static_cast<uint64_t>(value.size())};
}
template <typename Copy> std::string copy_document(Copy copy) {
  uint64_t length = 0;
  auto code = copy(nullptr, 0, &length);
  require(code == CITIZENSDK_OK, code, "二维码核心处理失败");
  require(length > 0 && length <= kDocumentLimit, CITIZENSDK_ERROR_INTEGRITY, "二维码核心结果超出上限");
  std::string value(static_cast<std::size_t>(length), '\0');
  uint64_t copied = length;
  code = copy(reinterpret_cast<uint8_t *>(value.data()), length, &copied);
  require(code == CITIZENSDK_OK, code, "二维码核心结果读取失败");
  require(copied == length, CITIZENSDK_ERROR_INTEGRITY, "二维码核心结果长度改变");
  return value;
}

// 原生只排版 Core 的已审阅 JSON，不重解 SCALE、不重建签名数据。
[[maybe_unused]] std::string display_document(const std::string &value) {
  std::string result;
  result.reserve(value.size() + 128);
  bool quoted = false, escaped = false;
  for (const char ch : value) {
    result.push_back(ch);
    if (escaped) { escaped = false; continue; }
    if (quoted && ch == '\\') { escaped = true; continue; }
    if (ch == '"') quoted = !quoted;
    if (!quoted && (ch == ',' || ch == '{' || ch == '}')) result.push_back('\n');
  }
  return result;
}

class QrFlow final : public std::enable_shared_from_this<QrFlow> {
 public:
  QrFlow(citizensdk_wallet_flow_handle_t handle, std::shared_ptr<HostBridge> host,
         uint64_t token, std::string request, void *context,
         citizensdk_qr_completion_v1_t completion)
      : handle_(handle), host_(std::move(host)), token_(token),
        sign_request_(std::move(request)), context_(context), completion_(completion) {}
  ~QrFlow() { destroy_ui(); }
  void start();
  void cancel() noexcept { cancellation_.cancel(); }
  bool belongs_to(const HostBridge *host) const noexcept { return host_.get() == host; }
  void confirm() noexcept;
  bool tick() noexcept;
 private:
  void create_ui();
  void destroy_ui() noexcept;
  void hide_ui() noexcept;
  void set_review(const std::string &value);
  void preview(const QrFrame &frame);
  void set_busy();
  bool session_safe() noexcept;
  void submit(bool signing);
  void receive_frame(QrFrame frame) noexcept;
  void receive_result(citizensdk_result_handle_t result) noexcept;
  void fail(citizensdk_error_code_t error) noexcept;
  void begin_cleanup() noexcept;
  void complete() noexcept;
  citizensdk_wallet_flow_handle_t handle_;
  std::shared_ptr<HostBridge> host_;
  uint64_t token_;
  std::string sign_request_;
  void *context_;
  citizensdk_qr_completion_v1_t completion_;
  std::unique_ptr<QrCamera> camera_;
  std::mutex lock_;
  std::optional<QrFrame> frame_;
  std::string scanned_;
  citizensdk_error_code_t failure_{CITIZENSDK_OK};
  citizensdk_result_handle_t pending_result_{};
  citizensdk_result_handle_t review_{};
  citizensdk_request_id_t request_{};
  citizensdk_request_id_t cancellation_sent_{};
  QrFlowCancellation cancellation_;
  std::atomic<bool> camera_stopped_{false};
  bool cleanup_started_{};
  bool started_{};
  bool result_ready_{};
  bool core_active_{};
  bool confirmed_{};
  bool finished_{};
  bool activated_{};
  citizensdk_error_code_t outcome_{CITIZENSDK_OK};
  std::string document_;
  HWND window_{}, text_{}, button_{}, parent_{};
  HINSTANCE module_{};
  std::wstring class_name_;
  std::vector<uint32_t> preview_pixels_;
  uint32_t preview_width_{}, preview_height_{};
  bool registered_{}, monitoring_{}, hiding_{};
  static LRESULT CALLBACK procedure(HWND window, UINT message, WPARAM wp, LPARAM lp);
};

void QrFlow::start() {
  create_ui();
  // UI 与监督已建立后才接纳底层任务；此后所有错误走同一个真实终态。
  try {
    if (sign_request_.empty()) {
      const std::weak_ptr<QrFlow> weak = shared_from_this();
      camera_ = std::make_unique<QrCamera>(
          [weak](QrFrame frame) { if (auto self = weak.lock()) self->receive_frame(std::move(frame)); },
          [weak](citizensdk_error_code_t error, std::string) {
            if (auto self = weak.lock()) self->fail(error);
          });
      camera_->start();
    } else {
      camera_stopped_.store(true);
      submit(false);
    }
  } catch (...) { fail(map_exception()); }
  // 创建/显示窗口可能泵送嵌套消息；接纳返回前禁止 timer 暴露最终 completion。
  started_ = true;
}

void QrFlow::submit(bool signing) {
  require(!core_active_ && !cancellation_.closing(), CITIZENSDK_ERROR_INVALID_STATE, "二维码任务状态无效");
  core_active_ = true;
  request_ = 0;
  const auto self = shared_from_this();
  const auto code = host_->submit_private(
      [&](citizensdk_request_id_t *out) {
        return signing ? citizensdk_sign_qr_request(host_->sdk(), review_, out)
                       : citizensdk_review_qr_sign_request(host_->sdk(), qr_view(sign_request_), out);
      }, [self](citizensdk_result_handle_t result) noexcept { self->receive_result(result); }, &request_);
  // 只有 Core 接纳之后才释放不可变审阅凭证；拒绝也必须走真实清理。
  if (signing && review_ != 0) {
    const auto release = citizensdk_result_release(review_);
    if (release == CITIZENSDK_OK) review_ = 0;
    else fail(release);
  }
  if (code != CITIZENSDK_OK) { core_active_ = false; request_ = 0; fail(code); }
}

void QrFlow::receive_result(citizensdk_result_handle_t result) noexcept {
  std::lock_guard<std::mutex> guard(lock_);
  // 一次只允许一个 Core 请求；不吞掉异常重复句柄。
  if (result_ready_) std::terminate();
  result_ready_ = true;
  pending_result_ = result;
}

void QrFlow::receive_frame(QrFrame frame) noexcept {
  if (cancellation_.closing() || cancellation_.cancelled()) return;
  try {
    // 相机输出唯一灰度缓冲，识别严格交给同一 ZXing 窄 ABI。
    size_t required = 0;
    const auto first = citizensdk_qr_image_decode_luminance(
        frame.luminance.data(), frame.luminance.size(), frame.width, frame.height,
        frame.width, nullptr, 0, &required);
    std::string parsed;
    if (first == CITIZENSDK_QR_IMAGE_BUFFER_TOO_SMALL) {
      require(required > 0 && required <= 2331, CITIZENSDK_ERROR_INTEGRITY, "扫码文本超出上限");
      std::string text(required, '\0');
      size_t copied = required;
      const auto decoded = citizensdk_qr_image_decode_luminance(
          frame.luminance.data(), frame.luminance.size(), frame.width, frame.height,
          frame.width, reinterpret_cast<uint8_t *>(text.data()), text.size(), &copied);
      require(decoded == CITIZENSDK_QR_IMAGE_OK && copied == required,
              CITIZENSDK_ERROR_INTEGRITY, "扫码结果不稳定");
      parsed = copy_document([&](uint8_t *out, uint64_t capacity, uint64_t *size) {
        return citizensdk_qr_parse(host_->sdk(), qr_view(text), out, capacity, size);
      });
    } else if (first != CITIZENSDK_QR_IMAGE_NO_CODE) {
      // 多码、非 UTF-8、错误像素都不得任意选择一个或交给另一识别器。
      citizensdk_error_code_t code = CITIZENSDK_ERROR_INTERNAL;
      switch (first) {
        case CITIZENSDK_QR_IMAGE_MULTIPLE_CODES: code = CITIZENSDK_ERROR_CONFLICT; break;
        case CITIZENSDK_QR_IMAGE_INVALID_ARGUMENT:
        case CITIZENSDK_QR_IMAGE_CAPACITY_EXCEEDED: code = CITIZENSDK_ERROR_INVALID_ARGUMENT; break;
        case CITIZENSDK_QR_IMAGE_INVALID_UTF8: code = CITIZENSDK_ERROR_DECODE; break;
        default: break;
      }
      fail(code);
      return;
    }
    std::lock_guard<std::mutex> guard(lock_);
    if (cancellation_.closing() || cancellation_.cancelled()) return;
    frame_ = std::move(frame);  // 仅保留最新一帧，防止主线程阻塞引起无限排队。
    if (!parsed.empty() && scanned_.empty()) scanned_ = std::move(parsed);
  } catch (...) { fail(map_exception()); }
}

void QrFlow::fail(citizensdk_error_code_t error) noexcept {
  std::lock_guard<std::mutex> guard(lock_);
  if (failure_ == CITIZENSDK_OK) failure_ = error == CITIZENSDK_OK ? CITIZENSDK_ERROR_INTERNAL : error;
}

void QrFlow::confirm() noexcept {
  if (confirmed_ || cancellation_.closing() || cancellation_.cancelled() || review_ == 0) return;
  try {
    require(session_safe(), CITIZENSDK_ERROR_CANCELLED, "桌面会话已离开");
    confirmed_ = true;
    set_busy();
    submit(true);
  } catch (...) { fail(map_exception()); }
}

void QrFlow::begin_cleanup() noexcept {
  if (!cancellation_.begin_cleanup()) hide_ui();
  if (review_ != 0) {
    const auto code = citizensdk_result_release(review_);
    if (code == CITIZENSDK_OK) review_ = 0;
    else if (outcome_ == CITIZENSDK_OK) outcome_ = code;
  }
  if (core_active_ && request_ != 0 && cancellation_sent_ != request_) {
    // 取消不等于终态；认证中的签名必须等普通 Core completion 真正排空。
    const auto code = citizensdk_cancel_request(host_->sdk(), request_);
    if (code == CITIZENSDK_OK || code == CITIZENSDK_ERROR_INVALID_ARGUMENT ||
        code == CITIZENSDK_ERROR_INVALID_STATE || code == CITIZENSDK_ERROR_NOT_FOUND)
      cancellation_sent_ = request_;
  }
  if (!camera_) { camera_stopped_.store(true); return; }
  if (cleanup_started_) return;
  try {
    auto self = shared_from_this();
    std::thread worker([self] {
      self->camera_->stop();
      self->camera_stopped_.store(true);
    });
    worker.detach();
    cleanup_started_ = true;
  } catch (...) {
    // 保持窗口隐藏与租约，下一 UI tick 重试；绝不在 UI 线程 join 摄像头。
    if (outcome_ == CITIZENSDK_OK) outcome_ = CITIZENSDK_ERROR_UNAVAILABLE;
  }
}

bool QrFlow::tick() noexcept {
  if (finished_) return false;
  if (!started_) return true;
  try {
    if (!cancellation_.closing() && !session_safe()) cancellation_.cancel();
    citizensdk_result_handle_t result = 0;
    bool result_ready = false;
    std::optional<QrFrame> frame;
    std::string scanned;
    {
      std::lock_guard<std::mutex> guard(lock_);
      result = std::exchange(pending_result_, 0);
      result_ready = std::exchange(result_ready_, false);
      frame = std::move(frame_); frame_.reset();
      scanned = std::move(scanned_); scanned_.clear();
      if (failure_ != CITIZENSDK_OK && outcome_ == CITIZENSDK_OK) outcome_ = failure_;
    }
    if (cancellation_.cancelled()) outcome_ = CITIZENSDK_ERROR_CANCELLED;
    if (result_ready) {
      core_active_ = false; request_ = 0;
      citizensdk_result_info_t info{};
      info.struct_size = sizeof(info); info.abi_version = 1;
      auto code = result == 0 ? CITIZENSDK_ERROR_INTEGRITY : citizensdk_result_get_info(result, &info);
      if (code == CITIZENSDK_OK) code = info.error_code;
      if (code == CITIZENSDK_OK &&
          info.kind != (confirmed_ ? CITIZENSDK_RESULT_QR_SIGNED : CITIZENSDK_RESULT_QR_REVIEW))
        code = CITIZENSDK_ERROR_INTEGRITY;
      if (code == CITIZENSDK_OK && outcome_ == CITIZENSDK_OK && !cancellation_.closing()) {
        try {
          auto value = copy_document([&](uint8_t *out, uint64_t capacity, uint64_t *size) {
            return citizensdk_result_copy_qr(result, out, capacity, size);
          });
          if (confirmed_) document_ = std::move(value);
          else {
            review_ = result; result = 0;
            set_review(value);
          }
        } catch (...) { code = map_exception(); }
      }
      if (result != 0) {
        const auto released = citizensdk_result_release(result);
        if (released != CITIZENSDK_OK) std::terminate();  // 不丢失尚未释放的 Core 句柄。
      }
      if (code != CITIZENSDK_OK && outcome_ == CITIZENSDK_OK) outcome_ = code;
    }
    if (!cancellation_.closing() && outcome_ == CITIZENSDK_OK) {
      if (frame) preview(*frame);
      if (!scanned.empty()) document_ = std::move(scanned);
    }
    if (outcome_ != CITIZENSDK_OK || !document_.empty() || cancellation_.closing()) begin_cleanup();
    if (cancellation_.closing() && !core_active_ && review_ == 0 && camera_stopped_.load()) {
      complete();
      return false;
    }
  } catch (...) {
    if (outcome_ == CITIZENSDK_OK) outcome_ = map_exception();
    begin_cleanup();
  }
  return true;
}

void QrFlow::complete() noexcept {
  if (finished_) return;
  finished_ = true;
  const auto keep_alive = shared_from_this();
  destroy_ui();
  camera_.reset();
  { std::lock_guard<std::mutex> guard(lock_); frame_.reset(); scanned_.clear(); }
  host_->finish_wallet_flow(token_);
  { std::lock_guard<std::mutex> guard(qr_flows_lock); qr_flows.erase(handle_); }
  if (cancellation_.cancelled()) outcome_ = CITIZENSDK_ERROR_CANCELLED;
  if (outcome_ != CITIZENSDK_OK) document_.clear();
  try { completion_(context_, outcome_, qr_view(document_)); } catch (...) {}
}


std::wstring qr_public_text(const std::string &value) {
  require(value.size() <= 2 * kDocumentLimit, CITIZENSDK_ERROR_INTEGRITY, "二维码审阅文本过长");
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      value.data(), static_cast<int>(value.size()), nullptr, 0);
  require(length > 0, CITIZENSDK_ERROR_INTEGRITY, "二维码审阅文本不是 UTF-8");
  std::wstring result(static_cast<std::size_t>(length), L'\0');
  require(MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), result.data(), length) == length,
      CITIZENSDK_ERROR_INTEGRITY, "二维码审阅文本转换失败");
  return result;
}

LRESULT CALLBACK QrFlow::procedure(HWND window, UINT message, WPARAM wp, LPARAM lp) {
  auto *self = reinterpret_cast<QrFlow *>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<QrFlow *>(reinterpret_cast<CREATESTRUCTW *>(lp)->lpCreateParams);
    self->window_ = window;
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (self == nullptr) return DefWindowProcW(window, message, wp, lp);
  // Window registry retains the flow throughout dispatch and all late Core callbacks.
  switch (message) {
    case WM_CLOSE: self->cancel(); return 0;
    case WM_COMMAND:
      if (LOWORD(wp) == IDOK) self->confirm();
      else if (LOWORD(wp) == IDCANCEL) self->cancel();
      return 0;
    case WM_ACTIVATE:
      if (LOWORD(wp) != WA_INACTIVE) self->activated_ = true;
      else if (self->activated_ && !self->confirmed_ && !self->cancellation_.closing()) self->cancel();
      break;
    case WM_ACTIVATEAPP:
      // 正常 SDK 系统认证为本进程原生窗口，只在真正应用失活时取消。
      if (wp == FALSE && self->activated_ && !self->cancellation_.closing()) self->cancel();
      break;
    case WM_SIZE:
      if (wp == SIZE_MINIMIZED && !self->hiding_) self->cancel();
      break;
    case WM_WTSSESSION_CHANGE:
      if (wp == WTS_SESSION_LOCK || wp == WTS_SESSION_LOGOFF ||
          wp == WTS_CONSOLE_DISCONNECT || wp == WTS_REMOTE_DISCONNECT) self->cancel();
      break;
    case WM_POWERBROADCAST:
      if (wp == PBT_APMSUSPEND) self->cancel();
      break;
    case WM_QUERYENDSESSION: self->cancel(); return TRUE;
    case WM_TIMER:
      if (wp == 1) { const auto keep_alive = self->shared_from_this(); self->tick(); return 0; }
      break;
    case WM_PAINT: {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(window, &paint);
      if (!self->preview_pixels_.empty() && !self->cancellation_.closing()) {
        BITMAPINFO info{};
        info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        info.bmiHeader.biWidth = static_cast<LONG>(self->preview_width_);
        info.bmiHeader.biHeight = -static_cast<LONG>(self->preview_height_);
        info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
        StretchDIBits(dc, 20, 70, 640, 480, 0, 0, static_cast<int>(self->preview_width_),
            static_cast<int>(self->preview_height_), self->preview_pixels_.data(), &info,
            DIB_RGB_COLORS, SRCCOPY);
      }
      EndPaint(window, &paint); return 0;
    }
    case WM_NCDESTROY:
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
      self->window_ = nullptr;
      break;
    default: break;
  }
  return DefWindowProcW(window, message, wp, lp);
}

void QrFlow::create_ui() {
  auto parent = host_->acquire_parent_window();
  require(parent.valid(), CITIZENSDK_ERROR_UNAVAILABLE, "二维码父窗口不可用");
  parent_ = static_cast<HWND>(parent.get());
  require(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
      GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, reinterpret_cast<LPCWSTR>(&QrFlow::procedure),
      &module_) != FALSE, CITIZENSDK_ERROR_UNAVAILABLE, "二维码窗口模块不可用");
  class_name_ = L"CitizenSDK.QR." + std::to_wstring(handle_);
  WNDCLASSEXW type{};
  type.cbSize = sizeof(type); type.hInstance = module_; type.lpfnWndProc = &QrFlow::procedure;
  type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  type.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  type.lpszClassName = class_name_.c_str();
  require(RegisterClassExW(&type) != 0, CITIZENSDK_ERROR_UNAVAILABLE, "二维码窗口类注册失败");
  registered_ = true;
  window_ = CreateWindowExW(WS_EX_DLGMODALFRAME, class_name_.c_str(),
      sign_request_.empty() ? L"CitizenSDK 扫码" : L"CitizenSDK 安全签名审阅",
      WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
      CW_USEDEFAULT, CW_USEDEFAULT, 780, 710, nullptr, nullptr, module_, this);
  require(window_ != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "二维码窗口创建失败");
  const auto control = [&](const wchar_t *kind, const wchar_t *label, DWORD style,
                            int x, int y, int width, int height, int identity) {
    HWND item = CreateWindowExW(0, kind, label, WS_CHILD | WS_VISIBLE | style,
        x, y, width, height, window_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(identity)),
        module_, nullptr);
    require(item != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "二维码窗口控件不可用");
    SendMessageW(item, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
    return item;
  };
  control(L"STATIC", sign_request_.empty() ? L"将一个二维码放入画面。解析与有效期由 Core 校验。"
      : L"核对 Core 验证的网络、签名账户、操作与全部参数。确认后才进行设备认证。",
      0, 20, 18, 725, 44, 10);
  if (!sign_request_.empty()) {
    text_ = control(L"EDIT", L"正在读取经验证的最终区块 metadata…",
        ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL | WS_VSCROLL | WS_BORDER,
        20, 70, 720, 490, 11);
    // 只读公共审阅文本上限，完整内容可滚动查看，不截断签名操作参数。
    SendMessageW(text_, EM_SETLIMITTEXT, static_cast<WPARAM>(2 * kDocumentLimit), 0);
    button_ = control(L"BUTTON", L"我已完整核对，确认签名", BS_PUSHBUTTON,
        20, 580, 470, 36, IDOK);
    EnableWindow(button_, FALSE);
  }
  control(L"BUTTON", L"取消", BS_PUSHBUTTON, 530, 580, 210, 36, IDCANCEL);
  require(WTSRegisterSessionNotification(window_, NOTIFY_FOR_THIS_SESSION) != FALSE,
          CITIZENSDK_ERROR_UNAVAILABLE, "无法建立 Windows 锁屏监督");
  monitoring_ = true;
  require(session_safe(), CITIZENSDK_ERROR_UNAVAILABLE, "Windows 会话不可用或已锁屏");
  require(SetTimer(window_, 1, 33, nullptr) != 0, CITIZENSDK_ERROR_UNAVAILABLE, "二维码生命周期监督不可用");
  ShowWindow(window_, SW_SHOW);
  SetForegroundWindow(window_);
}

bool QrFlow::session_safe() noexcept {
  if (!monitoring_) return false;
  if (parent_ != nullptr && !IsWindow(parent_)) return false;
  LPWSTR buffer = nullptr; DWORD bytes = 0;
  if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, WTS_CURRENT_SESSION,
                                  WTSSessionInfoEx, &buffer, &bytes)) return false;
  const auto *info = reinterpret_cast<const WTSINFOEXW *>(buffer);
  const bool safe = bytes >= sizeof(WTSINFOEXW) && info->Level == 1 &&
      info->Data.WTSInfoExLevel1.SessionState == WTSActive &&
      info->Data.WTSInfoExLevel1.SessionFlags == WTS_SESSIONSTATE_UNLOCK;
  WTSFreeMemory(buffer);
  return safe;
}
void QrFlow::hide_ui() noexcept {
  hiding_ = true;
  if (window_ != nullptr) ShowWindow(window_, SW_HIDE);
  preview_pixels_.clear();
}
void QrFlow::destroy_ui() noexcept {
  hiding_ = true;
  if (window_ != nullptr) {
    KillTimer(window_, 1);
    if (monitoring_) WTSUnRegisterSessionNotification(window_);
    monitoring_ = false;
    DestroyWindow(window_);
  }
  if (registered_) { UnregisterClassW(class_name_.c_str(), module_); registered_ = false; }
  preview_pixels_.clear(); text_ = button_ = nullptr;
}
void QrFlow::set_review(const std::string &value) {
  const auto text = qr_public_text(display_document(value));
  require(SetWindowTextW(text_, text.c_str()) != FALSE, CITIZENSDK_ERROR_UNAVAILABLE, "无法显示完整审阅内容");
  EnableWindow(button_, TRUE);
}
void QrFlow::set_busy() {
  EnableWindow(button_, FALSE);
  SetWindowTextW(button_, L"正在进行设备认证与签名…");
}
void QrFlow::preview(const QrFrame &frame) {
  preview_width_ = frame.width; preview_height_ = frame.height;
  preview_pixels_.resize(frame.luminance.size());
  for (std::size_t index = 0; index < frame.luminance.size(); ++index) {
    const auto value = static_cast<uint32_t>(frame.luminance[index]);
    preview_pixels_[index] = value | (value << 8) | (value << 16);
  }
  InvalidateRect(window_, nullptr, FALSE);
}

}  // namespace

citizensdk_error_code_t present_qr_flow(
    const std::shared_ptr<HostBridge> &host, std::string sign_request,
    void *context, citizensdk_qr_completion_v1_t completion,
    citizensdk_wallet_flow_handle_t *out_handle) {
  if (out_handle != nullptr) *out_handle = 0;
  if (!host || completion == nullptr || out_handle == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  if ((host->modules() & CITIZENSDK_MODULE_QR) == 0) return CITIZENSDK_ERROR_UNSUPPORTED;
  if (host->public_sdk() == 0) return CITIZENSDK_ERROR_NOT_READY;
  uint64_t token = 0;
  citizensdk_wallet_flow_handle_t handle = 0;
  try {
    if (!sign_request.empty()) {
      require(sign_request.size() <= 2331, CITIZENSDK_ERROR_INVALID_ARGUMENT, "签名请求超过上限");
      require((host->modules() & (CITIZENSDK_MODULE_CHAIN | CITIZENSDK_MODULE_SIGNING)) ==
              (CITIZENSDK_MODULE_CHAIN | CITIZENSDK_MODULE_SIGNING),
              CITIZENSDK_ERROR_UNSUPPORTED, "安全扫码签名需要链和签名模块");
    }
    token = host->reserve_wallet_flow();
    handle = reserve_wallet_flow_handle();
    auto flow = std::make_shared<QrFlow>(handle, host, token, std::move(sign_request), context, completion);
    { std::lock_guard<std::mutex> guard(qr_flows_lock); qr_flows.emplace(handle, flow); }
    flow->start();
    token = 0; *out_handle = handle;
    return CITIZENSDK_OK;
  } catch (...) {
    { std::lock_guard<std::mutex> guard(qr_flows_lock); qr_flows.erase(handle); }
    if (token != 0) host->finish_wallet_flow(token);
    return map_exception();
  }
}

citizensdk_error_code_t cancel_qr_flow(
    const std::shared_ptr<HostBridge> &host, citizensdk_wallet_flow_handle_t handle) noexcept {
  std::lock_guard<std::mutex> guard(qr_flows_lock);
  const auto found = qr_flows.find(handle);
  if (found == qr_flows.end() || !found->second->belongs_to(host.get()))
    return CITIZENSDK_ERROR_INVALID_HANDLE;
  found->second->cancel();
  return CITIZENSDK_OK;
}
void cancel_host_qr_flows(const HostBridge *host) noexcept {
  std::lock_guard<std::mutex> guard(qr_flows_lock);
  for (const auto &entry : qr_flows) if (entry.second->belongs_to(host)) entry.second->cancel();
}
}  // namespace citizen_sdk::windows
