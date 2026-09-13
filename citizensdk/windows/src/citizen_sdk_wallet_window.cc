#include "citizen_sdk_wallet_window.hpp"
#include "citizen_sdk_user_auth.hpp"

#include <atomic>
#include <windows.h>
#include <wtsapi32.h>
#include <algorithm>
#include <array>
#include <charconv>
#include <cstring>
#include <exception>
#include <limits>
#include <thread>
#include <utility>
#include <vector>
#include "citizen_sdk_host_record.hpp"
#include "citizen_sdk_input_limits.hpp"

namespace citizen_sdk::windows {
namespace {
constexpr int kMnemonic = 100;
constexpr int kPassword = 101;
constexpr int kBackup = 103;
constexpr int kSuggestions = 104;
constexpr int kWordCount = 105;
constexpr int kNextAccount = 106;
constexpr int kAccountIndices = 107;
constexpr int kSuggestionApply = 108;
constexpr int kMnemonicState = 109;
constexpr int kPrivateKey = 110;
constexpr int kAction = IDOK;
constexpr UINT kMnemonicChanged = WM_APP + 31;
constexpr std::size_t kInputUnits = input_limits::kMaximumUnlockPasswordBytes;

HINSTANCE module_for(WNDPROC procedure) {
  HINSTANCE module{};
  require(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            reinterpret_cast<LPCWSTR>(procedure), &module) != FALSE,
          CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK UI module is unavailable");
  return module;
}

void register_class(const std::wstring &name, HINSTANCE module, WNDPROC procedure) {
  WNDCLASSEXW type{};
  type.cbSize = sizeof(type);
  type.hInstance = module;
  type.lpfnWndProc = procedure;
  type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  type.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  type.lpszClassName = name.c_str();
  require(RegisterClassExW(&type) != 0, CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK UI class could not be registered");
}

// 此函数只转换非秘密状态文案；秘密始终使用下方 SensitiveInput 的有界缓冲。
std::wstring public_text(const std::string &value) {
  require(value.size() <= 65536, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "CitizenSDK status text is too large");
  if (value.empty()) return {};
  const int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      value.data(), static_cast<int>(value.size()), nullptr, 0);
  require(required > 0, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "CitizenSDK status text is not UTF-8");
  std::wstring result(static_cast<std::size_t>(required), L'\0');
  require(MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
              static_cast<int>(value.size()), result.data(), required) == required,
          CITIZENSDK_ERROR_INTERNAL, "CitizenSDK status conversion failed");
  return result;
}

HWND control(HWND parent, HINSTANCE module, const wchar_t *type,
             const wchar_t *text, DWORD style, int id, int x, int y, int w, int h) {
  HWND result = CreateWindowExW(0, type, text, WS_CHILD | WS_VISIBLE | style,
      x, y, w, h, parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), module, nullptr);
  require(result != nullptr, CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK UI control is unavailable");
  SendMessageW(result, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  return result;
}
}  // namespace

struct SensitiveInput::Impl final {
  HWND hwnd{};
  HINSTANCE module{};
  std::wstring class_name;  // 非秘密：每实例 Win32 类名，销毁后注销。
  std::thread::id ui_thread{std::this_thread::get_id()};
  std::array<wchar_t, kInputUnits + 1> text{};
  std::size_t size{};
  wchar_t high{};
  bool masked{};
  bool multiline{};
  bool read_only{};
  bool registered{};

  ~Impl() {
    if (std::this_thread::get_id() != ui_thread) std::terminate();
    clear();
    if (hwnd != nullptr && !DestroyWindow(hwnd)) std::terminate();
    if (registered && !UnregisterClassW(class_name.c_str(), module)) std::terminate();
  }
  void clear() noexcept {
    secure_zero(text.data(), sizeof(text));
    secure_zero(&high, sizeof(high));
    size = 0;
    if (hwnd != nullptr) InvalidateRect(hwnd, nullptr, TRUE);
  }
  void append(wchar_t value) noexcept {
    if (read_only || value == 0) return;
    if (value >= 0xd800 && value <= 0xdbff) {
      high = value;
      return;
    }
    wchar_t pair[2]{};
    std::size_t count = 1;
    if (value >= 0xdc00 && value <= 0xdfff) {
      if (high == 0) return;
      pair[0] = high; pair[1] = value; count = 2;
    } else {
      pair[0] = value;
    }
    secure_zero(&high, sizeof(high));
    if (size + count <= kInputUnits) {
      for (std::size_t i = 0; i < count; ++i) text[size + i] = pair[i];
      const int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
          text.data(), static_cast<int>(size + count), nullptr, 0, nullptr, nullptr);
      if (bytes > 0 && static_cast<std::size_t>(bytes) <= input_limits::kMaximumUnlockPasswordBytes) {
        size += count;
      } else {
        secure_zero(text.data() + size, count * sizeof(wchar_t));
      }
    }
    secure_zero(pair, sizeof(pair));
    InvalidateRect(hwnd, nullptr, TRUE);
  }
  static LRESULT CALLBACK procedure(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) noexcept {
    auto *self = reinterpret_cast<Impl *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = static_cast<Impl *>(reinterpret_cast<CREATESTRUCTW *>(lp)->lpCreateParams);
      self->hwnd = hwnd;
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (self == nullptr) return DefWindowProcW(hwnd, message, wp, lp);
    switch (message) {
      case WM_GETTEXT: case WM_GETTEXTLENGTH: case WM_SETTEXT:
      case WM_COPY: case WM_CUT: case WM_PASTE: case WM_CLEAR:
      case WM_UNDO: case EM_GETLINE: case EM_GETHANDLE:
      case EM_SETHANDLE: case EM_REPLACESEL:
        // 不给窗口消息或系统剪贴板提供秘密读写捷径。
        return 0;
      case WM_GETDLGCODE:
        return DLGC_WANTCHARS | DLGC_WANTARROWS;
      case WM_LBUTTONDOWN:
        SetFocus(hwnd); return 0;
      case WM_SETFOCUS:
        InvalidateRect(hwnd, nullptr, FALSE); return 0;
      case WM_KILLFOCUS:
        secure_zero(&self->high, sizeof(self->high));
        InvalidateRect(hwnd, nullptr, FALSE); return 0;
      case WM_KEYDOWN:
        if (wp == VK_TAB) {
          HWND next = GetNextDlgTabItem(GetParent(hwnd), hwnd,
              (GetKeyState(VK_SHIFT) & 0x8000) != 0);
          if (next != nullptr) SetFocus(next);
          return 0;
        }
        if (wp == VK_ESCAPE) {
          PostMessageW(GetParent(hwnd), WM_COMMAND, IDCANCEL, 0); return 0;
        }
        break;
      case WM_CHAR:
        if (self->read_only) return 0;
        if (wp == L'\b') {
          secure_zero(&self->high, sizeof(self->high));
          if (self->size != 0) {
            std::size_t count = 1;
            if (self->size >= 2 && self->text[self->size - 1] >= 0xdc00 &&
                self->text[self->size - 1] <= 0xdfff) count = 2;
            self->size -= count;
            secure_zero(self->text.data() + self->size, count * sizeof(wchar_t));
            InvalidateRect(hwnd, nullptr, TRUE);
            if (GetDlgCtrlID(hwnd) == kMnemonic)
              PostMessageW(GetParent(hwnd), kMnemonicChanged, 0, 0);
          }
          return 0;
        }
        if (wp == L'\r') {
          if (self->multiline) {
            self->append(L'\n');
            // 回车同样会改变助记词分词；必须刷新词数、校验和与末词候选。
            if (GetDlgCtrlID(hwnd) == kMnemonic)
              PostMessageW(GetParent(hwnd), kMnemonicChanged, 0, 0);
          } else {
            PostMessageW(GetParent(hwnd), WM_COMMAND, IDOK, 0);
          }
          return 0;
        }
        if (wp >= 0x20 && wp <= 0xffff) {
          self->append(static_cast<wchar_t>(wp));
          if (GetDlgCtrlID(hwnd) == kMnemonic)
            PostMessageW(GetParent(hwnd), kMnemonicChanged, 0, 0);
        }
        return 0;
      case WM_UNICHAR:
        if (wp == UNICODE_NOCHAR) return TRUE;
        if (self->read_only) return 0;
        if (wp >= 0x20 && wp < 0xd800) self->append(static_cast<wchar_t>(wp));
        else if (wp > 0xdfff && wp <= 0xffff) self->append(static_cast<wchar_t>(wp));
        else if (wp >= 0x10000 && wp <= 0x10ffff) {
          const auto scalar = static_cast<uint32_t>(wp - 0x10000);
          self->append(static_cast<wchar_t>(0xd800 + (scalar >> 10)));
          self->append(static_cast<wchar_t>(0xdc00 + (scalar & 0x3ff)));
        }
        if (GetDlgCtrlID(hwnd) == kMnemonic)
          PostMessageW(GetParent(hwnd), kMnemonicChanged, 0, 0);
        return 0;
      case WM_PAINT: {
        PAINTSTRUCT paint{};
        HDC dc = BeginPaint(hwnd, &paint);
        if (dc == nullptr) return 0;
        RECT area{};
        GetClientRect(hwnd, &area);
        FillRect(dc, &area, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));
        FrameRect(dc, &area, reinterpret_cast<HBRUSH>(GetStockObject(GRAY_BRUSH)));
        InflateRect(&area, -8, -8);
        auto old = SelectObject(dc, GetStockObject(DEFAULT_GUI_FONT));
        SetBkMode(dc, TRANSPARENT);
        if (self->masked) {
          std::array<wchar_t, kInputUnits> mask{};
          std::fill_n(mask.data(), self->size, L'\x2022');
          DrawTextW(dc, mask.data(), static_cast<int>(self->size), &area, DT_LEFT | DT_WORDBREAK | DT_NOPREFIX);
        } else {
          DrawTextW(dc, self->text.data(), static_cast<int>(self->size), &area,
                    DT_LEFT | DT_WORDBREAK | DT_NOPREFIX);
        }
        if (GetFocus() == hwnd) DrawFocusRect(dc, &area);
        SelectObject(dc, old);
        EndPaint(hwnd, &paint);
        return 0;
      }
      case WM_DESTROY:
        self->clear();
        self->hwnd = nullptr;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        return 0;
      default: break;
    }
    return DefWindowProcW(hwnd, message, wp, lp);
  }
};

SensitiveInput::SensitiveInput(void *parent, int identity, int x, int y,
                               int width, int height, bool masked, bool multiline)
    : impl_(std::make_unique<Impl>()) {
  impl_->masked = masked;
  impl_->multiline = multiline;
  impl_->module = module_for(Impl::procedure);
  impl_->class_name = L"CitizenSDK.Input." + std::to_wstring(reinterpret_cast<UINT_PTR>(impl_.get()));
  register_class(impl_->class_name, impl_->module, Impl::procedure);
  impl_->registered = true;
  impl_->hwnd = CreateWindowExW(0, impl_->class_name.c_str(), L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP,
      x, y, width, height, static_cast<HWND>(parent),
      reinterpret_cast<HMENU>(static_cast<INT_PTR>(identity)), impl_->module, impl_.get());
  require(impl_->hwnd != nullptr, CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK sensitive input is unavailable");
}
SensitiveInput::~SensitiveInput() = default;
void *SensitiveInput::native_handle() const noexcept { return impl_->hwnd; }
void SensitiveInput::clear() noexcept {
  if (std::this_thread::get_id() != impl_->ui_thread) std::terminate();
  impl_->clear();
}
void SensitiveInput::set_read_only(bool value) noexcept {
  if (std::this_thread::get_id() != impl_->ui_thread) std::terminate();
  impl_->read_only = value;
}
SensitiveBuffer SensitiveInput::take_utf8() {
  require(std::this_thread::get_id() == impl_->ui_thread && impl_->hwnd != nullptr,
          CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK sensitive input is unavailable");
  try {
    require(impl_->high == 0, CITIZENSDK_ERROR_INVALID_ARGUMENT, "input contains incomplete Unicode");
    if (impl_->size == 0) { clear(); return {}; }
    const int required = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        impl_->text.data(), static_cast<int>(impl_->size), nullptr, 0, nullptr, nullptr);
    require(required > 0 && static_cast<std::size_t>(required) <= input_limits::kMaximumUnlockPasswordBytes,
            CITIZENSDK_ERROR_INVALID_ARGUMENT, "sensitive input exceeds its UTF-8 limit");
    SensitiveBuffer result(static_cast<std::size_t>(required));
    require(WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, impl_->text.data(),
                static_cast<int>(impl_->size), reinterpret_cast<char *>(result.data()),
                required, nullptr, nullptr) == required,
            CITIZENSDK_ERROR_INTERNAL, "sensitive input conversion failed");
    clear();
    return result;
  } catch (...) { clear(); throw; }
}

std::string SensitiveInput::word_suggestions() const {
  require(std::this_thread::get_id() == impl_->ui_thread && impl_->hwnd != nullptr,
          CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK sensitive input is unavailable");
  std::size_t begin = impl_->size;
  while (begin != 0 && impl_->text[begin - 1] != L' ' &&
         impl_->text[begin - 1] != L'\n' && impl_->text[begin - 1] != L'\t') --begin;
  if (begin == impl_->size) return {};
  const std::size_t count = impl_->size - begin;
  if (count > input_limits::kMaximumUnlockPasswordBytes) return {};
  SensitiveBuffer prefix(count);
  for (std::size_t index = 0; index < count; ++index) {
    const wchar_t value = impl_->text[begin + index];
    if (value < L'a' || value > L'z') return {};
    prefix.data()[index] = static_cast<uint8_t>(value);
  }
  const citizensdk_bytes_view_t view{prefix.data(), count};
  uint64_t required = 0;
  if (citizensdk_wallet_word_suggestions(view, nullptr, 0, &required) !=
          CITIZENSDK_OK || required == 0 || required > 256) return {};
  std::string result(static_cast<std::size_t>(required), '\0');
  if (citizensdk_wallet_word_suggestions(
          view, reinterpret_cast<uint8_t *>(result.data()), result.size(),
          &required) != CITIZENSDK_OK || required != result.size()) return {};
  for (char &value : result) if (value == '\n') value = ' ';
  return result;
}

std::string SensitiveInput::mnemonic_status(
    citizensdk_wallet_word_count_t word_count) const {
  require(std::this_thread::get_id() == impl_->ui_thread && impl_->hwnd != nullptr,
          CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK sensitive input is unavailable");
  uint32_t words = 0;
  bool separated = true;
  for (std::size_t index = 0; index < impl_->size; ++index) {
    const wchar_t value = impl_->text[index];
    const bool whitespace = value == L' ' || value == L'\n' ||
                            value == L'\t' || value == L'\r';
    if (!whitespace && separated) ++words;
    separated = whitespace;
  }
  SensitiveBuffer utf8;
  if (impl_->size != 0) {
    const int required = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
        impl_->text.data(), static_cast<int>(impl_->size), nullptr, 0, nullptr, nullptr);
    require(required > 0 && static_cast<std::size_t>(required) <=
                input_limits::kMaximumUnlockPasswordBytes,
            CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "CitizenSDK mnemonic input is invalid");
    utf8 = SensitiveBuffer(static_cast<std::size_t>(required));
    require(WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
                impl_->text.data(), static_cast<int>(impl_->size),
                reinterpret_cast<char *>(utf8.data()), required, nullptr, nullptr) == required,
            CITIZENSDK_ERROR_INTERNAL,
            "CitizenSDK mnemonic input conversion failed");
  }
  const bool checksum = words == word_count &&
      citizensdk_validate_wallet_mnemonic(
          {utf8.data(), static_cast<uint64_t>(utf8.size())}, word_count) == CITIZENSDK_OK;
  return "当前 " + std::to_string(words) + " / 选择 " +
      std::to_string(word_count) + (checksum ? "；校验和有效" : "；校验和尚未通过");
}

void SensitiveInput::replace_last_word(const std::string &word) {
  require(std::this_thread::get_id() == impl_->ui_thread && impl_->hwnd != nullptr,
          CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK sensitive input is unavailable");
  require(!impl_->read_only && !word.empty() && word.size() <= 64,
          CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "CitizenSDK mnemonic suggestion is invalid");
  for (const char value : word)
    require(value >= 'a' && value <= 'z', CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "CitizenSDK mnemonic suggestion is invalid");
  std::size_t begin = impl_->size;
  while (begin != 0 && impl_->text[begin - 1] != L' ' &&
         impl_->text[begin - 1] != L'\n' && impl_->text[begin - 1] != L'\t') --begin;
  require(begin + word.size() <= kInputUnits, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "CitizenSDK mnemonic suggestion exceeds the input limit");
  secure_zero(impl_->text.data() + begin,
              (impl_->size - begin) * sizeof(wchar_t));
  for (std::size_t index = 0; index < word.size(); ++index)
    impl_->text[begin + index] = static_cast<wchar_t>(word[index]);
  impl_->size = begin + word.size();
  InvalidateRect(impl_->hwnd, nullptr, TRUE);
  PostMessageW(GetParent(impl_->hwnd), kMnemonicChanged, 0, 0);
}

void SensitiveInput::set_utf8(const SensitiveBuffer &value) {
  require(std::this_thread::get_id() == impl_->ui_thread && impl_->hwnd != nullptr,
          CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK sensitive input is unavailable");
  clear();
  try {
    require(value.size() <= input_limits::kMaximumUnlockPasswordBytes,
            CITIZENSDK_ERROR_INVALID_ARGUMENT, "sensitive display exceeds its limit");
    if (value.empty()) return;
    require(std::memchr(value.data(), 0, value.size()) == nullptr,
            CITIZENSDK_ERROR_INVALID_ARGUMENT, "sensitive display contains NUL");
    const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
        reinterpret_cast<const char *>(value.data()), static_cast<int>(value.size()),
        impl_->text.data(), static_cast<int>(kInputUnits));
    require(count > 0, CITIZENSDK_ERROR_INVALID_ARGUMENT, "sensitive display is not UTF-8");
    impl_->size = static_cast<std::size_t>(count);
    InvalidateRect(impl_->hwnd, nullptr, TRUE);
    if (GetDlgCtrlID(impl_->hwnd) == kMnemonic)
      PostMessageW(GetParent(impl_->hwnd), kMnemonicChanged, 0, 0);
  } catch (...) { clear(); throw; }
}

struct WalletWindow::Impl final {
  WindowLease parent;
  HWND hwnd{};
  HWND status{};
  HWND suggestions{};
  HWND suggestion_apply{};
  HWND mnemonic_state{};
  HWND word_count{};
  HWND next_account{};
  HWND account_indices{};
  HWND backup{};
  HWND action_button{};
  HINSTANCE module{};
  std::wstring class_name;
  std::unique_ptr<SensitiveInput> mnemonic;
  std::unique_ptr<SensitiveInput> password;
  std::unique_ptr<SensitiveInput> private_key;
  std::atomic<const void *> private_auth_owner{nullptr};
  std::atomic<uint64_t> private_auth_operation{0};
  std::atomic<bool> private_authorization_closed{false};
  bool private_key_mode{};
  bool private_key_visible{};
  bool session_registered{};
  DWORD session_id{};
  Action action;
  Action cancel;
  citizensdk_wallet_flow_kind_t kind{};
  bool registered{};
  bool destroying{};
  bool owner_disabled{};
  bool busy{};
  bool password_reentry_required{};
  ~Impl() {
    if ((hwnd != nullptr || registered || mnemonic || password) &&
        !parent.on_ui_thread()) std::terminate();
    if (hwnd != nullptr || mnemonic || password) destroy();
    password.reset(); mnemonic.reset(); private_key.reset();
    if (registered && !UnregisterClassW(class_name.c_str(), module)) std::terminate();
  }
  void clear() noexcept {
    private_key_visible = false;
    if (private_key) private_key->clear();
    if (mnemonic) mnemonic->clear();
    if (password) password->clear();
  }
  bool session_safe() const noexcept {
    if (!session_registered) return false;
    LPWSTR value = nullptr;
    DWORD size = 0;
    if (!WTSQuerySessionInformationW(WTS_CURRENT_SERVER_HANDLE, session_id,
                                     WTSInfoEx, &value, &size)) return false;
    const auto *info = reinterpret_cast<const WTSINFOEXW *>(value);
    const bool safe = value != nullptr && size >= sizeof(WTSINFOEXW) &&
        info->Level == 1 && info->Data.WTSInfoExLevel1.SessionState == WTSActive &&
        info->Data.WTSInfoExLevel1.SessionFlags == WTS_SESSIONSTATE_UNLOCK;
    if (value != nullptr) WTSFreeMemory(value);
    return safe;
  }
  void restore_owner() noexcept {
    if (owner_disabled && parent.valid() && parent.get() != nullptr) {
      EnableWindow(static_cast<HWND>(parent.get()), TRUE);
    }
    owner_disabled = false;
  }
  void destroy() noexcept {
    private_authorization_closed.store(true);
    private_auth_operation.store(0);
    if (!parent.on_ui_thread()) std::terminate();
    destroying = true;
    clear();
    if (session_registered && hwnd != nullptr) WTSUnRegisterSessionNotification(hwnd);
    session_registered = false;
    if (hwnd != nullptr && !DestroyWindow(hwnd)) std::terminate();
    restore_owner();
    destroying = false;
  }
  static LRESULT CALLBACK procedure(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) noexcept {
    auto *self = reinterpret_cast<Impl *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = static_cast<Impl *>(reinterpret_cast<CREATESTRUCTW *>(lp)->lpCreateParams);
      self->hwnd = hwnd;
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (self == nullptr) return DefWindowProcW(hwnd, message, wp, lp);
    try {
      if (self->private_key_mode &&
          ((message == WM_ACTIVATE && LOWORD(wp) == WA_INACTIVE && !self->destroying &&
               (self->private_key_visible || self->private_authorization_closed.load() ||
                !accept_private_key_authentication_window(reinterpret_cast<void *>(lp), hwnd,
                    self->private_auth_owner.load(), self->private_auth_operation.load()))) ||
           (message == WM_SIZE && wp == SIZE_MINIMIZED) ||
           (message == WM_SHOWWINDOW && wp == FALSE && !self->destroying) ||
           (message == WM_POWERBROADCAST && wp == PBT_APMSUSPEND) ||
           (message == WM_WTSSESSION_CHANGE &&
               (wp == WTS_SESSION_LOCK || wp == WTS_SESSION_LOGOFF ||
                wp == WTS_CONSOLE_DISCONNECT || wp == WTS_REMOTE_DISCONNECT)))) {
        self->private_authorization_closed.store(true);
        self->private_auth_operation.store(0);
        self->clear();
        const auto callback = self->cancel;
        callback();
        return 0;
      }
      if (message == WM_COMMAND) {
        const int identity = LOWORD(wp);
        if (identity == IDCANCEL) { const auto callback = self->cancel; callback(); return 0; }
        if (identity == kAction && !self->busy) { const auto callback = self->action; callback(); return 0; }
        if (identity == kNextAccount && self->account_indices != nullptr) {
          const bool next = SendMessageW(self->next_account, BM_GETCHECK, 0, 0) == BST_CHECKED;
          EnableWindow(self->account_indices, next ? FALSE : TRUE);
          return 0;
        }
        if (identity == kSuggestionApply && self->mnemonic && self->suggestions) {
          const LRESULT selected = SendMessageW(self->suggestions, CB_GETCURSEL, 0, 0);
          if (selected != CB_ERR) {
            const LRESULT length = SendMessageW(self->suggestions, CB_GETLBTEXTLEN,
                                                selected, 0);
            if (length > 0 && length <= 64) {
              std::wstring word(static_cast<std::size_t>(length) + 1, L'\0');
              SendMessageW(self->suggestions, CB_GETLBTEXT, selected,
                           reinterpret_cast<LPARAM>(word.data()));
              std::string ascii;
              ascii.reserve(static_cast<std::size_t>(length));
              for (int index = 0; index < length; ++index)
                ascii.push_back(static_cast<char>(word[static_cast<std::size_t>(index)]));
              self->mnemonic->replace_last_word(ascii);
            }
          }
          return 0;
        }
        if (identity == kWordCount && self->mnemonic)
          PostMessageW(hwnd, kMnemonicChanged, 0, 0);
      }
      if (message == kMnemonicChanged && self->suggestions != nullptr && self->mnemonic) {
        const LRESULT selected_words = SendMessageW(self->word_count, CB_GETCURSEL, 0, 0);
        const citizensdk_wallet_word_count_t count = selected_words == 1
            ? CITIZENSDK_WALLET_WORDS_18
            : selected_words == 2 ? CITIZENSDK_WALLET_WORDS_24
                                  : CITIZENSDK_WALLET_WORDS_12;
        const std::wstring state = public_text(self->mnemonic->mnemonic_status(count));
        SetWindowTextW(self->mnemonic_state, state.c_str());
        const std::string candidates = self->mnemonic->word_suggestions();
        SendMessageW(self->suggestions, CB_RESETCONTENT, 0, 0);
        std::size_t begin = 0;
        while (begin < candidates.size()) {
          const std::size_t end = candidates.find(' ', begin);
          const std::string word = candidates.substr(begin, end - begin);
          const std::wstring wide = public_text(word);
          SendMessageW(self->suggestions, CB_ADDSTRING, 0,
                       reinterpret_cast<LPARAM>(wide.c_str()));
          if (end == std::string::npos) break;
          begin = end + 1;
        }
        if (!candidates.empty()) SendMessageW(self->suggestions, CB_SETCURSEL, 0, 0);
        EnableWindow(self->suggestion_apply, candidates.empty() ? FALSE : TRUE);
        return 0;
      }
      if (message == WM_CLOSE) { const auto callback = self->cancel; callback(); return 0; }
      if (message == WM_DESTROY) {
        self->private_authorization_closed.store(true);
        self->private_auth_operation.store(0);
        self->clear();
        if (self->session_registered) WTSUnRegisterSessionNotification(hwnd);
        self->session_registered = false;
        const bool notify = !self->destroying;
        const auto callback = self->cancel;
        self->hwnd = nullptr;
        self->status = nullptr; self->suggestions = nullptr;
        self->suggestion_apply = nullptr;
        self->mnemonic_state = nullptr;
        self->word_count = nullptr;
        self->next_account = nullptr; self->account_indices = nullptr;
        self->backup = nullptr; self->action_button = nullptr;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
        self->restore_owner();
        // callback 可完成 flow 并销毁当前 C++ 对象；此后绝不再读取 self。
        if (notify) callback();
        return 0;
      }
    } catch (...) { std::terminate(); }
    return DefWindowProcW(hwnd, message, wp, lp);
  }
};

WalletWindow::WalletWindow(WindowLease parent, const ValidatedWalletRequest &request,
                           Action action, Action cancel)
    : impl_(std::make_unique<Impl>()) {
  impl_->parent = std::move(parent);
  require(impl_->parent.valid(), CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK parent window was destroyed");
  impl_->kind = request.kind;
  impl_->private_key_mode = request.account_id.has_value();
  impl_->action = std::move(action); impl_->cancel = std::move(cancel);
  impl_->module = module_for(Impl::procedure);
  impl_->class_name = L"CitizenSDK.Wallet." + std::to_wstring(reinterpret_cast<UINT_PTR>(impl_.get()));
  register_class(impl_->class_name, impl_->module, Impl::procedure);
  impl_->registered = true;
  const wchar_t *window_title = impl_->private_key_mode ? L"查看私钥" :
      request.kind == CITIZENSDK_WALLET_FLOW_CREATE ? L"创建钱包" :
      request.kind == CITIZENSDK_WALLET_FLOW_IMPORT ? L"输入助记词" : L"添加账户";
  impl_->hwnd = CreateWindowExW(WS_EX_DLGMODALFRAME, impl_->class_name.c_str(), window_title,
      WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, 620, 800,
      static_cast<HWND>(impl_->parent.get()), nullptr, impl_->module, impl_.get());
  require(impl_->hwnd != nullptr, CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK wallet window is unavailable");
  require(SetWindowDisplayAffinity(impl_->hwnd, WDA_EXCLUDEFROMCAPTURE) != FALSE,
          CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK sensitive display protection is unavailable");
  impl_->status = control(impl_->hwnd, impl_->module, L"STATIC", L"", SS_LEFT, 0, 20, 18, 570, 90);
  if (impl_->private_key_mode) {
    SetWindowTextW(impl_->hwnd, L"查看私钥");
    SetWindowTextW(impl_->status,
        L"私钥泄露将导致该账户资产被盗（仅该账户，不影响本钱包其他账户）。\r\n\r\n"
        L"确认要查看吗？");
    // 仅公开账户审阅文本；秘密仍只进入下方可擦除自绘缓冲。
    std::wstring account_text = L"账户：0x";
    constexpr wchar_t account_digits[] = L"0123456789abcdef";
    for (const uint8_t byte : request.account_id->bytes) {
      account_text += account_digits[byte >> 4];
      account_text += account_digits[byte & 15];
    }
    control(impl_->hwnd, impl_->module, L"STATIC", account_text.c_str(),
        SS_LEFT, 0, 20, 105, 570, 40);
    impl_->private_key = std::make_unique<SensitiveInput>(
        impl_->hwnd, kPrivateKey, 20, 155, 570, 140, false, true);
    impl_->private_key->set_read_only(true);
    impl_->action_button = control(impl_->hwnd, impl_->module, L"BUTTON",
        L"查看", BS_DEFPUSHBUTTON | WS_TABSTOP, kAction,
        250, 350, 340, 40);
    control(impl_->hwnd, impl_->module, L"BUTTON", L"取消",
        BS_PUSHBUTTON | WS_TABSTOP, IDCANCEL, 20, 350, 130, 40);
    require(ProcessIdToSessionId(GetCurrentProcessId(), &impl_->session_id) &&
                WTSRegisterSessionNotification(impl_->hwnd, NOTIFY_FOR_THIS_SESSION),
            CITIZENSDK_ERROR_UNAVAILABLE, "无法建立当前设备锁屏监督");
    impl_->session_registered = true;
    require(impl_->session_safe(), CITIZENSDK_ERROR_UNAVAILABLE,
            "设备会话已锁屏或无法确认锁屏监督");
  } else {
  impl_->mnemonic = std::make_unique<SensitiveInput>(impl_->hwnd, kMnemonic, 20, 115, 570, 180, false, true);
  impl_->mnemonic_state = control(impl_->hwnd, impl_->module, L"STATIC",
      L"当前 0 / 选择 12；校验和尚未通过", SS_LEFT, kMnemonicState,
      20, 300, 570, 24);
  impl_->suggestions = control(impl_->hwnd, impl_->module, L"COMBOBOX", L"",
      CBS_DROPDOWNLIST | WS_TABSTOP, kSuggestions, 20, 330, 360, 150);
  impl_->suggestion_apply = control(impl_->hwnd, impl_->module, L"BUTTON",
      L"使用所选候选", BS_PUSHBUTTON | WS_TABSTOP, kSuggestionApply,
      395, 330, 195, 34);
  EnableWindow(impl_->suggestion_apply, FALSE);
  control(impl_->hwnd, impl_->module, L"STATIC", L"助记词数量", SS_LEFT, 0, 20, 370, 120, 24);
  impl_->word_count = control(impl_->hwnd, impl_->module, L"COMBOBOX", L"",
      CBS_DROPDOWNLIST | WS_TABSTOP, kWordCount, 150, 365, 120, 120);
  const std::vector<const wchar_t *> counts = request.kind == CITIZENSDK_WALLET_FLOW_CREATE
      ? std::vector<const wchar_t *>{L"12 · 推荐", L"24"}
      : std::vector<const wchar_t *>{L"12", L"18", L"24"};
  for (const wchar_t *count : counts)
    SendMessageW(impl_->word_count, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(count));
  const uint32_t selected_words = request.kind == CITIZENSDK_WALLET_FLOW_CREATE &&
      request.word_count == 18 ? 12 : request.word_count == 0 ? 12 : request.word_count;
  const int selected = request.kind == CITIZENSDK_WALLET_FLOW_CREATE
      ? selected_words == 12 ? 0 : selected_words == 24 ? 1 : -1
      : selected_words == 12 ? 0 : selected_words == 18 ? 1 : selected_words == 24 ? 2 : -1;
  require(selected >= 0, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "CitizenSDK wallet word count is unsupported");
  SendMessageW(impl_->word_count, CB_SETCURSEL, selected, 0);
  const auto initial_state = public_text(impl_->mnemonic->mnemonic_status(selected_words));
  SetWindowTextW(impl_->mnemonic_state, initial_state.c_str());
  control(impl_->hwnd, impl_->module, L"STATIC", L"钱包密码（选填）", SS_LEFT, 0, 20, 410, 570, 24);
  impl_->password = std::make_unique<SensitiveInput>(impl_->hwnd, kPassword, 20, 438, 570, 45, true, false);
  impl_->next_account = control(impl_->hwnd, impl_->module, L"BUTTON",
      L"自动添加下一个可用账户索引", BS_AUTOCHECKBOX | WS_TABSTOP,
      kNextAccount, 20, 495, 570, 30);
  impl_->account_indices = control(impl_->hwnd, impl_->module, L"EDIT", L"",
      WS_BORDER | WS_TABSTOP | ES_AUTOHSCROLL, kAccountIndices, 20, 530, 570, 34);
  std::wstring initial_indices;
  for (std::size_t index = 0; index < request.account_indices.size(); ++index) {
    if (index != 0) initial_indices += L',';
    initial_indices += std::to_wstring(request.account_indices[index]);
  }
  SetWindowTextW(impl_->account_indices, initial_indices.c_str());
  impl_->backup = control(impl_->hwnd, impl_->module, L"BUTTON", L"我已在离线安全位置备份助记词",
      BS_AUTOCHECKBOX | WS_TABSTOP, kBackup, 20, 595, 570, 30);
  impl_->action_button = control(impl_->hwnd, impl_->module, L"BUTTON", L"", BS_DEFPUSHBUTTON | WS_TABSTOP,
      kAction, 340, 680, 250, 40);
  control(impl_->hwnd, impl_->module, L"BUTTON", L"取消", BS_PUSHBUTTON | WS_TABSTOP, IDCANCEL, 20, 680, 130, 40);
  if (request.kind == CITIZENSDK_WALLET_FLOW_CREATE) {
    std::wstring host_application = L"当前应用";
    const HWND owner = static_cast<HWND>(impl_->parent.get());
    const int title_size = owner == nullptr ? 0 : GetWindowTextLengthW(owner);
    if (title_size > 0 && title_size <= 256) {
      host_application.assign(static_cast<std::size_t>(title_size) + 1, L'\0');
      if (GetWindowTextW(owner, host_application.data(), title_size + 1) == title_size) {
        host_application.resize(static_cast<std::size_t>(title_size));
        if (host_application.size() < 3 ||
            host_application.compare(host_application.size() - 3, 3, L"App") != 0)
          host_application += L"App";
      } else {
        host_application = L"当前应用";
      }
    }
    const std::wstring intro = L"钱包账户是 " + host_application +
        L" 唯一的账户，请务必妥善保存助记词和钱包密码（如设置），若丢失或遗忘将永久无法找回。";
    SetWindowTextW(impl_->status, intro.c_str());
    SetWindowTextW(impl_->action_button, L"创建钱包");
    ShowWindow(static_cast<HWND>(impl_->mnemonic->native_handle()), SW_HIDE);
    ShowWindow(impl_->mnemonic_state, SW_HIDE);
    ShowWindow(impl_->suggestions, SW_HIDE);
    ShowWindow(impl_->suggestion_apply, SW_HIDE);
  } else {
    SetWindowTextW(impl_->status, request.kind == CITIZENSDK_WALLET_FLOW_IMPORT ? L"" :
        L"无根设备不保存助记词或密码，追加账户需重新录入两者校验归属。");
    SetWindowTextW(impl_->action_button,
        request.kind == CITIZENSDK_WALLET_FLOW_IMPORT ? L"确认导入" : L"确认添加");
  }
  if (request.kind != CITIZENSDK_WALLET_FLOW_ADD_ACCOUNTS) {
    ShowWindow(impl_->next_account, SW_HIDE);
    ShowWindow(impl_->account_indices, SW_HIDE);
  }
  ShowWindow(impl_->backup, SW_HIDE);
  }
}
WalletWindow::~WalletWindow() = default;
bool WalletWindow::on_ui_thread() const noexcept { return impl_->parent.on_ui_thread(); }
void WalletWindow::show() {
  require(on_ui_thread() && impl_->hwnd != nullptr && impl_->parent.valid(),
          CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK wallet window is unavailable");
  HWND owner = static_cast<HWND>(impl_->parent.get());
  if (owner != nullptr && IsWindowEnabled(owner)) {
    EnableWindow(owner, FALSE); impl_->owner_disabled = true;
  }
  ShowWindow(impl_->hwnd, SW_SHOW);
  if (impl_->private_key_mode) {
    SetFocus(impl_->action_button);
    return;
  }
  SetFocus(static_cast<HWND>((impl_->kind == CITIZENSDK_WALLET_FLOW_CREATE ?
      impl_->password : impl_->mnemonic)->native_handle()));
}
void WalletWindow::destroy() noexcept { impl_->destroy(); }
void WalletWindow::set_busy(const std::string &message) {
  require(on_ui_thread(), CITIZENSDK_ERROR_BUSY, "wallet UI requires its owner thread");
  if (impl_->hwnd == nullptr) return;
  const auto text = public_text(message);
  SetWindowTextW(impl_->status, text.c_str());
  EnableWindow(impl_->action_button, FALSE);
  impl_->busy = true;
}
void WalletWindow::set_error(const std::string &message) {
  require(on_ui_thread(), CITIZENSDK_ERROR_BUSY, "wallet UI requires its owner thread");
  if (impl_->hwnd == nullptr) return;
  const auto text = public_text(message);
  SetWindowTextW(impl_->status, text.c_str());
  EnableWindow(impl_->action_button, TRUE);
  impl_->busy = false;
  // 错误重试若仍为空，必须由用户明确确认，不能把清空/未输入静默当作选择。
  impl_->password_reentry_required = true;
}
void WalletWindow::show_prepared_mnemonic(const SensitiveBuffer &mnemonic) {
  require(on_ui_thread() && impl_->hwnd != nullptr && impl_->parent.valid(),
          CITIZENSDK_ERROR_UNAVAILABLE, "wallet window was destroyed before preparation completed");
  impl_->mnemonic->set_utf8(mnemonic);
  impl_->mnemonic->set_read_only(true);
  ShowWindow(static_cast<HWND>(impl_->mnemonic->native_handle()), SW_SHOW);
  ShowWindow(impl_->mnemonic_state, SW_SHOW);
  SendMessageW(impl_->backup, BM_SETCHECK, BST_CHECKED, 0);
  ShowWindow(impl_->backup, SW_HIDE);
  ShowWindow(static_cast<HWND>(impl_->password->native_handle()), SW_HIDE);
  ShowWindow(impl_->word_count, SW_HIDE);
  ShowWindow(impl_->suggestions, SW_HIDE);
  ShowWindow(impl_->suggestion_apply, SW_HIDE);
  ShowWindow(impl_->next_account, SW_HIDE);
  ShowWindow(impl_->account_indices, SW_HIDE);
  SetWindowTextW(impl_->action_button, L"我已备份");
  SetWindowTextW(impl_->status,
      L"公民不保存助记词，关闭本弹窗后将无法再次显示。\r\n"
      L"请立即手抄备份，或在「公民钱包」中妥善保管——这是恢复钱包与追加其他账户的唯一凭证。"
      L"设置过钱包密码时，还必须单独备份密码。\r\n不支持复制，不支持截屏。");
  EnableWindow(impl_->action_button, TRUE);
  impl_->busy = false;
}
bool WalletWindow::authorize_private_key_view(
    const void *owner, uint64_t host_operation_id) noexcept {
  if (owner == nullptr || host_operation_id == 0 ||
      impl_->private_authorization_closed.load()) return false;
  impl_->private_auth_owner.store(owner);
  impl_->private_auth_operation.store(host_operation_id);
  return !impl_->private_authorization_closed.load();
}

void WalletWindow::revoke_private_key_authorization() noexcept {
  impl_->private_authorization_closed.store(true);
  impl_->private_auth_operation.store(0);
}

void WalletWindow::finish_private_key_authentication() noexcept {
  impl_->private_auth_operation.store(0);
}

void WalletWindow::show_private_key(const SensitiveBuffer &private_key) {
  require(on_ui_thread() && impl_->private_key_mode && impl_->hwnd != nullptr &&
              impl_->parent.valid() && impl_->private_key && private_key.size() == 32 &&
              !impl_->private_authorization_closed.load() &&
              impl_->session_safe() && GetForegroundWindow() == impl_->hwnd,
          CITIZENSDK_ERROR_UNAVAILABLE, "安全查看窗口不再可显示");
  SensitiveBuffer text(67);
  text.data()[0] = '0'; text.data()[1] = 'x';
  constexpr char digits[] = "0123456789abcdef";
  for (std::size_t index = 0; index < 32; ++index) {
    text.data()[2 + index * 2] = static_cast<uint8_t>(digits[private_key.data()[index] >> 4]);
    text.data()[3 + index * 2] = static_cast<uint8_t>(digits[private_key.data()[index] & 15]);
  }
  // 自绘控件内部有界复制并清零；不经过 std::string/EDIT/窗口文本消息。
  SensitiveBuffer visible(text.data(), 66);
  impl_->private_key->set_utf8(visible);
  visible.clear(); text.clear();
  impl_->private_key_visible = true;
  SetWindowTextW(impl_->status,
      L"请手抄备份，不支持复制；导出即等于该账户控制权");
  SetWindowTextW(impl_->action_button, L"关闭");
  EnableWindow(impl_->action_button, TRUE);
  impl_->busy = false;
}

bool WalletWindow::backup_confirmed() const noexcept {
  return on_ui_thread() && impl_->backup != nullptr &&
      SendMessageW(impl_->backup, BM_GETCHECK, 0, 0) == BST_CHECKED;
}
citizensdk_wallet_word_count_t WalletWindow::word_count() const {
  require(on_ui_thread() && impl_->word_count != nullptr,
          CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK wallet word count control is unavailable");
  const LRESULT selected = SendMessageW(impl_->word_count, CB_GETCURSEL, 0, 0);
  if (selected == 0) return CITIZENSDK_WALLET_WORDS_12;
  if (impl_->kind == CITIZENSDK_WALLET_FLOW_CREATE && selected == 1)
    return CITIZENSDK_WALLET_WORDS_24;
  if (selected == 1) return CITIZENSDK_WALLET_WORDS_18;
  if (selected == 2) return CITIZENSDK_WALLET_WORDS_24;
  throw HostError(CITIZENSDK_ERROR_INVALID_ARGUMENT,
                  "请选择 12、18 或 24 个助记词");
}
bool WalletWindow::use_next_account() const noexcept {
  return on_ui_thread() && impl_->next_account != nullptr &&
      SendMessageW(impl_->next_account, BM_GETCHECK, 0, 0) == BST_CHECKED;
}
std::vector<uint32_t> WalletWindow::account_indices() const {
  require(on_ui_thread() && impl_->account_indices != nullptr,
          CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK account index control is unavailable");
  const int length = GetWindowTextLengthW(impl_->account_indices);
  require(length >= 0 && length <= 32768, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "指定账户索引输入过长");
  std::wstring text(static_cast<std::size_t>(length) + 1, L'\0');
  require(GetWindowTextW(impl_->account_indices, text.data(), length + 1) == length,
          CITIZENSDK_ERROR_UNAVAILABLE,
          "CitizenSDK account index control is unavailable");
  std::vector<uint32_t> values;
  const wchar_t *cursor = text.data();
  while (*cursor != L'\0') {
    const wchar_t *end = cursor;
    while (*end != L'\0' && *end != L',') ++end;
    uint32_t value = 0;
    // wchar_t 不是 char，逐字符收敛到 ASCII 后再解析，禁止区域设置放宽格式。
    std::string ascii;
    ascii.reserve(static_cast<std::size_t>(end - cursor));
    for (const wchar_t *item = cursor; item != end; ++item) {
      require(*item >= L'0' && *item <= L'9', CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "指定账户索引必须是以逗号分隔的 1...1989 整数");
      ascii.push_back(static_cast<char>(*item));
    }
    const auto exact = std::from_chars(ascii.data(), ascii.data() + ascii.size(), value);
    require(exact.ec == std::errc{} && exact.ptr == ascii.data() + ascii.size(),
            CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "指定账户索引必须是以逗号分隔的 1...1989 整数");
    values.push_back(value);
    if (*end == L',') {
      require(end[1] != L'\0', CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "指定账户索引不能以逗号结尾");
      cursor = end + 1;
    } else {
      cursor = end;
    }
  }
  input_limits::validate_wallet_indices(values.data(),
      static_cast<uint32_t>(values.size()));
  return values;
}
SensitiveBuffer WalletWindow::take_mnemonic() {
  auto value = impl_->mnemonic->take_utf8();
  require(!value.empty(), CITIZENSDK_ERROR_INVALID_ARGUMENT, "wallet mnemonic input is empty");
  return value;
}
SensitiveBuffer WalletWindow::take_password() {
  auto first = impl_->password->take_utf8();
  const citizensdk_error_code_t validation = citizensdk_validate_wallet_password(
      {first.data(), static_cast<uint64_t>(first.size())});
  require(validation == CITIZENSDK_OK, validation,
          "钱包密码不符合 CitizenSDK 派生规则");
  if (!first.empty()) {
    if (impl_->kind != CITIZENSDK_WALLET_FLOW_ADD_ACCOUNTS) {
      const int response = MessageBoxW(impl_->hwnd,
          L"非空钱包密码不会被保存；忘记它或输入不同密码会得到不同账户。是否继续？",
          L"确认非空钱包密码风险", MB_ICONWARNING | MB_YESNO | MB_DEFBUTTON2);
      require(impl_->hwnd != nullptr, CITIZENSDK_ERROR_UNAVAILABLE,
              "钱包窗口已在风险确认期间关闭");
      require(response == IDYES,
              CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "已取消使用非空钱包密码");
    }
  } else if (impl_->password_reentry_required) {
    const int response = MessageBoxW(impl_->hwnd,
        L"当前钱包密码为空。确认本次明确使用空钱包密码继续重试？",
        L"确认空钱包密码", MB_ICONQUESTION | MB_YESNO | MB_DEFBUTTON2);
    require(impl_->hwnd != nullptr, CITIZENSDK_ERROR_UNAVAILABLE,
            "钱包窗口已在空密码确认期间关闭");
    require(response == IDYES, CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "请重新输入钱包密码，或明确确认使用空钱包密码");
  }
  impl_->password_reentry_required = false;
  return first;
}
void WalletWindow::clear_secrets() noexcept { impl_->clear(); }
bool WalletWindow::invoke(std::function<void()> action) noexcept {
  return impl_->parent.invoke(std::move(action));
}

}  // namespace citizen_sdk::windows
