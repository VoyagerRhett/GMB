// 真实 Win32 消息/父窗口/取消合同；不把此测试当作真实 TPM 认证证明。
#include <windows.h>
#include <bcrypt.h>
#include <array>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cwchar>
#include <functional>
#include <thread>
#include "citizen_sdk_user_auth.hpp"

#ifdef NDEBUG
#error "CitizenSDK Windows contract assertions must remain enabled"
#endif
namespace csw = citizen_sdk::windows;
namespace {
void pump_until(const std::function<bool()> &complete) {
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (!complete()) {
    assert(std::chrono::steady_clock::now() < deadline);
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      assert(message.message != WM_QUIT);
      TranslateMessage(&message); DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 5, QS_ALLINPUT);
  }
}
HWND authentication_window() {
  HWND found{};
  EnumThreadWindows(GetCurrentThreadId(), +[](HWND hwnd, LPARAM value) -> BOOL {
    wchar_t type[128]{};
    const int count = GetClassNameW(hwnd, type, 128);
    constexpr wchar_t prefix[] = L"CitizenSDK.Authentication.";
    if (count > 0 && std::wcsncmp(type, prefix, (sizeof(prefix) / sizeof(wchar_t)) - 1) == 0) {
      *reinterpret_cast<HWND *>(value) = hwnd;
      return FALSE;
    }
    return TRUE;
  }, reinterpret_cast<LPARAM>(&found));
  return found;
}
HWND parent_window() {
  HWND parent = CreateWindowExW(0, L"STATIC", L"CitizenSDK contract owner",
      WS_OVERLAPPEDWINDOW, 0, 0, 700, 700, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  assert(parent != nullptr);
  return parent;
}
}  // namespace

int main() {
  const auto ui = std::this_thread::get_id();
  {
    csw::WindowRef inert(nullptr, ui, false);
    csw::UserAuth auth(inert);
    assert(!auth.available());
    assert(auth.unlock_vault_password(71).code == CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED);
    std::thread worker([&] { assert(inert.retire() == CITIZENSDK_OK); });
    worker.join();
  }
  HWND parent = parent_window();
  csw::WindowRef reference(parent, ui);
  assert(reference.on_ui_thread());
  {
    auto lease = reference.acquire();
    assert(lease.valid() && lease.get() == parent);
    assert(reference.set(nullptr) == CITIZENSDK_ERROR_BUSY);
    csw::WindowLease moved(std::move(lease));
    assert(!lease.valid() && moved.valid());
  }
  std::thread wrong_thread([&] {
    assert(reference.set(parent) == CITIZENSDK_ERROR_BUSY);
    assert(!reference.acquire().valid());
  });
  wrong_thread.join();
  csw::UserAuth auth(reference);
  // 原生 UI 用例要求 runner 提供交互桌面；不能将未执行的交互算作通过。
  assert(auth.available());
  assert(auth.unlock_vault_password(71).code == CITIZENSDK_ERROR_BUSY);
  csw::AuthenticationResult cancelled;
  std::atomic<bool> finished{false};
  std::thread unlock([&] {
    cancelled = auth.unlock_vault_password(71);
    finished.store(true);
  });
  HWND dialog{};
  pump_until([&] { dialog = authentication_window(); return dialog != nullptr; });
  assert(!csw::accept_private_key_authentication_window(dialog, parent, &reference, 72));
  assert(!csw::accept_private_key_authentication_window(dialog, parent, &auth, 71));
  assert(csw::accept_private_key_authentication_window(dialog, parent, &reference, 71));
  // 本次认证已归属安全查看；真实失焦即撤销，晚到确认不能重显。
  SendMessageW(dialog, WM_ACTIVATE, WA_INACTIVE, 0);
  SendMessageW(dialog, WM_COMMAND, IDCANCEL, 0);
  SendMessageW(dialog, WM_COMMAND, IDOK, 0);  // 晚到确认不能推翻已接纳的取消。
  // 完成一定在退出窗口消息栈、清除窗口和缓冲后发生。
  assert(!finished.load());
  pump_until([&] { return finished.load(); });
  unlock.join();
  assert(cancelled.code == CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED && cancelled.password.empty());
  assert(authentication_window() == nullptr);

  // 动态生成一次性输入，只存在进程内存；没有固定口令夹具、不调用 TPM、不输出内容。
  finished.store(false);
  std::thread successful_create([&] {
    cancelled = auth.create_vault_password();
    finished.store(true);
  });
  pump_until([&] { dialog = authentication_window(); return dialog != nullptr; });
  std::array<unsigned char, 32> random{};
  assert(BCryptGenRandom(nullptr, random.data(), static_cast<ULONG>(random.size()),
                         BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0);
  HWND first = GetDlgItem(dialog, 101);
  HWND second = GetDlgItem(dialog, 102);
  assert(first != nullptr && second != nullptr);
  SendMessageW(dialog, WM_COMMAND, IDOK, 0);  // 空口令仍留在原生重试界面。
  assert(!finished.load() && authentication_window() == dialog);
  for (const auto value : random) {
    SendMessageW(first, WM_CHAR, static_cast<WPARAM>(0x21U + value % 90U), 0);
  }
  SendMessageW(dialog, WM_COMMAND, IDOK, 0);  // 确认不一致必须清理本次输入并拒绝。
  assert(!finished.load() && authentication_window() == dialog);
  for (const auto value : random) {
    const WPARAM character = static_cast<WPARAM>(0x21U + value % 90U);
    SendMessageW(first, WM_CHAR, character, 0);
    SendMessageW(second, WM_CHAR, character, 0);
  }
  SecureZeroMemory(random.data(), random.size());
  SendMessageW(dialog, WM_COMMAND, IDOK, 0);
  assert(!finished.load());
  pump_until([&] { return finished.load(); });
  successful_create.join();
  assert(cancelled.code == CITIZENSDK_OK && cancelled.password.size() == random.size());
  cancelled.password.clear();
  assert(authentication_window() == nullptr);

  finished.store(false);
  std::thread create([&] {
    cancelled = auth.create_vault_password();
    finished.store(true);
  });
  pump_until([&] { dialog = authentication_window(); return dialog != nullptr; });
  assert(DestroyWindow(parent));
  parent = nullptr;
  pump_until([&] { return finished.load(); });
  create.join();
  assert(cancelled.code == CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED && cancelled.password.empty());
  assert(!reference.acquire().valid());
  assert(authentication_window() == nullptr);
  // 只有显式 set(nullptr) 才允许重新开启 rootless，而不是把销毁的 owner 偷换为空。
  assert(reference.set(nullptr) == CITIZENSDK_OK);
  {
    auto rootless = reference.acquire();
    assert(rootless.valid() && rootless.get() == nullptr);
    std::atomic<bool> invoked{false};
    std::thread worker([&] { assert(rootless.invoke([&] { invoked.store(true); })); });
    worker.join();
    assert(!invoked.load());
    pump_until([&] { return invoked.load(); });
  }
  citizensdk_error_code_t first_retire{};
  std::thread retire([&] { first_retire = reference.retire(); });
  retire.join();
  assert(first_retire == CITIZENSDK_ERROR_BUSY);
  assert(!reference.available());
  assert(reference.retire() == CITIZENSDK_OK);
  assert(reference.retire() == CITIZENSDK_OK);
  assert(!reference.invoke([] {}));
  return 0;
}
