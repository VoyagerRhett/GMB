#include "citizen_sdk_user_auth.hpp"

#include <windows.h>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <exception>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include "citizen_sdk_host_record.hpp"
#include "citizen_sdk_input_limits.hpp"
#include "citizen_sdk_wallet_window.hpp"

namespace citizen_sdk::windows {
namespace {
struct PromptState final {
  std::mutex lock;
  std::condition_variable ready;
  WindowRef *parent{};
  uint64_t host_operation_id{};
  bool private_view_bound{};
  HWND private_view_window{};
  WindowLease lease;
  bool confirmation{};
  bool started{};
  bool done{};
  bool abandoned{};
  bool completion_queued{};
  bool destroying{};
  bool registered{};
  bool owner_disabled{};
  HWND hwnd{};
  HWND error{};
  HINSTANCE module{};
  std::wstring class_name;  // 非秘密 Win32 类标识。
  std::unique_ptr<SensitiveInput> password;
  std::unique_ptr<SensitiveInput> second;
  AuthenticationResult result;
  std::shared_ptr<PromptState> *window_owner{};
  ~PromptState() {
    if (hwnd != nullptr || password || second || registered || window_owner != nullptr) std::terminate();
  }
};

void clear_controls(const std::shared_ptr<PromptState> &state) noexcept {
  if (state->password) state->password->clear();
  if (state->second) state->second->clear();
}

void finish_on_ui(const std::shared_ptr<PromptState> &state) noexcept {
  if (!state->parent->on_ui_thread()) std::terminate();
  clear_controls(state);
  const bool restore_view_focus = state->private_view_bound &&
      GetForegroundWindow() == state->hwnd;
  state->destroying = true;
  if (state->hwnd != nullptr && !DestroyWindow(state->hwnd)) std::terminate();
  state->password.reset(); state->second.reset();
  if (state->registered && !UnregisterClassW(state->class_name.c_str(), state->module)) std::terminate();
  state->registered = false;
  delete state->window_owner;
  state->window_owner = nullptr;
  if (state->owner_disabled && state->lease.valid() && state->lease.get() != nullptr) {
    EnableWindow(static_cast<HWND>(state->lease.get()), TRUE);
  }
  state->owner_disabled = false;
  if (state->private_view_window != nullptr && IsWindow(state->private_view_window)) {
    EnableWindow(state->private_view_window, TRUE);
    if (restore_view_focus) SetForegroundWindow(state->private_view_window);
  }
  state->private_view_window = nullptr;
  const bool parent_lost = !state->lease.valid();
  state->lease = {};
  {
    std::lock_guard<std::mutex> guard(state->lock);
    if (state->abandoned || parent_lost) {
      state->result.password.clear();
      state->result.code = CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED;
    }
    state->done = true;
  }
  state->ready.notify_all();
}

void queue_finish(const std::shared_ptr<PromptState> &state,
                  citizensdk_error_code_t code, SensitiveBuffer password = {}) noexcept {
  try {
    {
      std::lock_guard<std::mutex> guard(state->lock);
      if (state->done || state->completion_queued) return;
      state->completion_queued = true;
      if (state->abandoned) password.clear();
      state->result = {code, std::move(password)};
    }
    // 即使源是 WM_COMMAND/WM_DESTROY，也必须退出当前 WndProc 栈后再注销类。
    auto delay = std::chrono::milliseconds(1);
    for (unsigned attempt = 0; attempt < 8; ++attempt) {
      if (state->parent->invoke([state] { finish_on_ui(state); })) return;
      std::this_thread::sleep_for(delay);
      delay *= 2;
    }
  } catch (...) {}
  // 无法安排唯一清理动作时，不能让含秘密窗口无主存活或在 worker 销毁。
  std::terminate();
}

LRESULT CALLBACK prompt_proc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) noexcept {
  auto *raw = reinterpret_cast<PromptState *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    raw = static_cast<PromptState *>(reinterpret_cast<CREATESTRUCTW *>(lp)->lpCreateParams);
    raw->hwnd = hwnd;
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(raw));
  }
  if (raw == nullptr) return DefWindowProcW(hwnd, message, wp, lp);
  const auto state = *raw->window_owner;
  try {
    if (message == WM_DESTROY) {
      RemovePropW(hwnd, L"CitizenSDK.Authentication");
      clear_controls(state);
      state->hwnd = nullptr; state->error = nullptr;
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
      if (!state->destroying) queue_finish(state, CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED);
      return 0;
    }
    if ((message == WM_ACTIVATE && LOWORD(wp) == WA_INACTIVE &&
         state->private_view_bound && !state->destroying) ||
        message == WM_CLOSE || (message == WM_COMMAND && LOWORD(wp) == IDCANCEL)) {
      clear_controls(state);
      if (message == WM_ACTIVATE) {
        std::lock_guard<std::mutex> guard(state->lock);
        // 已排队确认也不能在真实后台后继续返回成功。
        state->abandoned = true;
        state->result.password.clear();
      }
      queue_finish(state, CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED);
      return 0;
    }
    if (message == WM_COMMAND && LOWORD(wp) == IDOK) {
      {
        std::lock_guard<std::mutex> guard(state->lock);
        if (state->done || state->abandoned || state->completion_queued) return 0;
      }
      SensitiveBuffer first = state->password->take_utf8();
      SensitiveBuffer second = state->second ? state->second->take_utf8() : SensitiveBuffer();
      const bool valid = first.size() >= 12 && first.size() <= input_limits::kMaximumUnlockPasswordBytes;
      const bool matches = !state->confirmation || (first.size() == second.size() &&
          (first.empty() || std::memcmp(first.data(), second.data(), first.size()) == 0));
      if (!valid || !matches) {
        SetWindowTextW(state->error, !valid ? L"口令长度必须为 12...1024 个 UTF-8 字节，请重新输入。"
            : L"两次口令不一致，请重新输入。");
        return 0;
      }
      queue_finish(state, CITIZENSDK_OK, std::move(first));
      return 0;
    }
  } catch (...) {
    clear_controls(state);
    queue_finish(state, CITIZENSDK_ERROR_INTERNAL);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wp, lp);
}

HWND prompt_control(const std::shared_ptr<PromptState> &state, const wchar_t *type,
                    const wchar_t *text, DWORD style, int identity,
                    int x, int y, int width, int height) {
  HWND value = CreateWindowExW(0, type, text, WS_CHILD | WS_VISIBLE | style,
      x, y, width, height, state->hwnd,
      reinterpret_cast<HMENU>(static_cast<INT_PTR>(identity)), state->module, nullptr);
  require(value != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK authentication control is unavailable");
  SendMessageW(value, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  return value;
}

void build_prompt(const std::shared_ptr<PromptState> &state) noexcept {
  try {
    {
      std::lock_guard<std::mutex> guard(state->lock);
      state->started = true;
      if (state->abandoned || state->completion_queued) {
        state->ready.notify_all();
        return;
      }
    }
    state->ready.notify_all();
    state->lease = state->parent->acquire();
    require(state->lease.valid(), CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED,
            "CitizenSDK authentication parent window was destroyed");
    require(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                  GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                              reinterpret_cast<LPCWSTR>(&prompt_proc), &state->module) != FALSE,
            CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK authentication module is unavailable");
    state->class_name = L"CitizenSDK.Authentication." + std::to_wstring(reinterpret_cast<UINT_PTR>(state.get()));
    WNDCLASSEXW type{};
    type.cbSize = sizeof(type); type.hInstance = state->module;
    type.lpfnWndProc = prompt_proc; type.lpszClassName = state->class_name.c_str();
    type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    type.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    require(RegisterClassExW(&type) != 0, CITIZENSDK_ERROR_UNAVAILABLE,
            "CitizenSDK authentication class is unavailable");
    state->registered = true;
    state->window_owner = new std::shared_ptr<PromptState>(state);
    state->hwnd = CreateWindowExW(WS_EX_DLGMODALFRAME, state->class_name.c_str(),
        state->confirmation ? L"创建 CitizenSDK 设备金库口令" : L"解锁 CitizenSDK 设备金库",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, 580, 360,
        static_cast<HWND>(state->lease.get()), nullptr, state->module, state.get());
    require(state->hwnd != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK authentication window is unavailable");
    require(SetPropW(state->hwnd, L"CitizenSDK.Authentication", state.get()) != FALSE,
            CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK authentication identity is unavailable");
    require(SetWindowDisplayAffinity(state->hwnd, WDA_EXCLUDEFROMCAPTURE) != FALSE,
            CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK sensitive display protection is unavailable");
    prompt_control(state, L"STATIC", L"此口令只用于本设备 TPM 金库，不是助记词派生密码。\n口令不会返回应用业务层。", SS_LEFT, 0, 20, 15, 530, 60);
    state->password = std::make_unique<SensitiveInput>(state->hwnd, 101, 20, 85, 530, 45, true, false);
    if (state->confirmation) {
      state->second = std::make_unique<SensitiveInput>(state->hwnd, 102, 20, 145, 530, 45, true, false);
    }
    state->error = prompt_control(state, L"STATIC", L"", SS_LEFT, 0, 20, 202, 530, 35);
    prompt_control(state, L"BUTTON", L"取消", BS_PUSHBUTTON | WS_TABSTOP, IDCANCEL, 20, 258, 150, 40);
    prompt_control(state, L"BUTTON", L"继续", BS_DEFPUSHBUTTON | WS_TABSTOP, IDOK, 370, 258, 180, 40);
    HWND owner = static_cast<HWND>(state->lease.get());
    if (owner != nullptr && IsWindowEnabled(owner)) {
      EnableWindow(owner, FALSE); state->owner_disabled = true;
    }
    ShowWindow(state->hwnd, SW_SHOW);
    SetFocus(static_cast<HWND>(state->password->native_handle()));
  } catch (const HostError &error) { queue_finish(state, error.code()); }
  catch (...) { queue_finish(state, CITIZENSDK_ERROR_INTERNAL); }
}
}  // namespace

bool accept_private_key_authentication_window(
    void *window, void *view_window, const void *owner, uint64_t host_operation_id) noexcept {
  if (window == nullptr || view_window == nullptr || owner == nullptr ||
      host_operation_id == 0) return false;
  const HWND hwnd = static_cast<HWND>(window);
  DWORD process = 0;
  if (GetWindowThreadProcessId(hwnd, &process) != GetCurrentThreadId() ||
      process != GetCurrentProcessId()) return false;
  auto *state = static_cast<PromptState *>(GetPropW(hwnd, L"CitizenSDK.Authentication"));
  if (state == nullptr || state->parent != owner || state->hwnd != hwnd ||
      state->host_operation_id != host_operation_id) return false;
  const HWND view = static_cast<HWND>(view_window);
  if (GetWindowThreadProcessId(view, nullptr) != GetCurrentThreadId()) return false;
  SetLastError(ERROR_SUCCESS);
  if (SetWindowLongPtrW(hwnd, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(view)) == 0 &&
      GetLastError() != ERROR_SUCCESS) return false;
  state->private_view_window = view;
  state->private_view_bound = true;
  EnableWindow(view, FALSE);
  return true;
}

UserAuth::UserAuth(WindowRef &parent) : parent_(parent) {}
UserAuth::~UserAuth() = default;
bool UserAuth::available() const noexcept { return parent_.available(); }
AuthenticationResult UserAuth::create_vault_password() { return prompt(true, 0); }
AuthenticationResult UserAuth::unlock_vault_password(uint64_t host_operation_id) {
  return prompt(false, host_operation_id);
}

AuthenticationResult UserAuth::prompt(bool confirmation, uint64_t host_operation_id) {
  if (!available()) return {CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED, {}};
  if (parent_.on_ui_thread()) return {CITIZENSDK_ERROR_BUSY, {}};
  // 沿用 Linux 接纳与等待语义；只能阻塞 Core worker，不能阻塞窗口消息线程。
  std::lock_guard<std::mutex> admission(prompt_lock_);
  auto state = std::make_shared<PromptState>();
  state->parent = &parent_;
  state->host_operation_id = host_operation_id;
  state->confirmation = confirmation;
  if (!parent_.invoke([state] { build_prompt(state); })) {
    return {CITIZENSDK_ERROR_UNAVAILABLE, {}};
  }
  std::unique_lock<std::mutex> guard(state->lock);
  if (!state->ready.wait_for(guard, std::chrono::seconds(5), [&] { return state->started; })) {
    state->abandoned = true;
    guard.unlock();
    queue_finish(state, CITIZENSDK_ERROR_UNAVAILABLE);
    return {CITIZENSDK_ERROR_UNAVAILABLE, {}};
  }
  if (!state->ready.wait_for(guard, std::chrono::minutes(5), [&] { return state->done; })) {
    state->abandoned = true;
    guard.unlock();
    queue_finish(state, CITIZENSDK_ERROR_TIMEOUT);
    return {CITIZENSDK_ERROR_TIMEOUT, {}};
  }
  return std::move(state->result);
}
}  // namespace citizen_sdk::windows
