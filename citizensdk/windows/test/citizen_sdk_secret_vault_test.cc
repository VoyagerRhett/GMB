// 使用真实 SecureStore 与生产 Vault 状态机；替身仅取代 TPM/交互，不冒充硬件验收。
#include <windows.h>
#include <bcrypt.h>
#include <algorithm>
#include <array>
#include <cassert>
#include <cstring>
#include <functional>
#include <map>
#include <stdexcept>
#include <string>
#include <utility>
#include "citizen_sdk_directory.hpp"
#include "citizen_sdk_secret_vault.hpp"
#include "citizen_sdk_test_support.hpp"

#ifdef NDEBUG
#error "CitizenSDK Windows contract assertions must remain enabled"
#endif

namespace {
using namespace citizen_sdk::windows;

template <class Function>
void fails(citizensdk_error_code_t expected, Function &&function) {
  bool rejected = false;
  try { function(); }
  catch (const HostError &error) { rejected = error.code() == expected; }
  assert(rejected);
}

AuthenticationResult authenticated() {
  constexpr uint8_t value[] = {'s', 'y', 'n', 't', 'h', 'e', 't', 'i', 'c'};
  return {CITIZENSDK_OK, SensitiveBuffer(value, sizeof(value))};
}

VaultObject synthetic_object(const WalletKey &key) {
  BCRYPT_RSAKEY_BLOB header{BCRYPT_RSAPUBLIC_MAGIC, 2048, 3, 256, 0, 0};
  Bytes public_blob(sizeof(header) + 3 + 256, 0);
  std::memcpy(public_blob.data(), &header, sizeof(header));
  public_blob[sizeof(header)] = 1;
  public_blob[sizeof(header) + 2] = 1;
  public_blob[sizeof(header) + 3] = 0x80;
  public_blob.back() = 1;
  return {cng_key_name(key), std::move(public_blob), Bytes{1, 2, 3, 4},
      Bytes(key.generation.begin(), key.generation.end())};
}

struct FakeSystem final {
  CngAvailability available{CngAvailability::kAvailable};
  bool authentication_available{true};
  bool cancel{false};
  bool delete_fails{false};
  bool decrypt_fails{false};
  unsigned created{};
  unsigned deleted{};
  unsigned decrypted{};
  unsigned prompted{};
  std::map<std::string, VaultObject> keys;
  std::function<void()> on_create;
  std::function<void()> on_unlock;
  std::function<void()> on_decrypt;

  SecretVaultServices services() {
    return {
      [this] { return available; },
      [this] { return authentication_available; },
      [this] {
        ++prompted;
        return cancel ? AuthenticationResult{CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED, {}}
                      : authenticated();
      },
      [this](uint64_t host_operation_id) {
        assert(host_operation_id != 0);
        ++prompted;
        if (on_unlock) on_unlock();
        return cancel ? AuthenticationResult{CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED, {}}
                      : authenticated();
      },
      [this](const WalletKey &key, const SensitiveBuffer &password) {
        assert(!password.empty());
        ++created;
        const auto object = synthetic_object(key);
        keys.emplace(object.key_name, object);
        if (on_create) on_create();
        return object;
      },
      [this](const VaultObject &object) {
        return keys.count(object.key_name) == 1;
      },
      [](const VaultObject &, const uint8_t *input) {
        assert(input != nullptr);
        return Bytes(256, 0x2a);
      },
      [this](const VaultObject &object, const Bytes &wrapped,
              const SensitiveBuffer &password, uint8_t *output) {
        assert(keys.count(object.key_name) == 1 && wrapped.size() == 256 && !password.empty());
        ++decrypted;
        std::fill_n(output, 32, 0x3c);
        if (on_decrypt) on_decrypt();
        if (decrypt_fails) throw HostError(CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED, "synthetic failure");
      },
      [this](const WalletKey &key, const std::optional<VaultObject> &) {
        ++deleted;
        if (delete_fails) throw HostError(CITIZENSDK_ERROR_UNAVAILABLE, "synthetic deletion failure");
        keys.erase(cng_key_name(key));
      }
    };
  }
};

void expect(bool value) {
  if (!value) throw std::runtime_error("CitizenSDK generation serialization test failed");
}

int retire_child(int count, wchar_t **arguments) {
  if (count != 6) return 2;
  WalletKey wallet{};
  const std::wstring generation(arguments[3]);
  if (generation.size() != 32) return 2;
  for (std::size_t index = 0; index < 16; ++index) {
    const auto digit = [](wchar_t value) -> int {
      if (value >= L'0' && value <= L'9') return value - L'0';
      if (value >= L'a' && value <= L'f') return value - L'a' + 10;
      return -1;
    };
    const int high = digit(generation[index * 2]);
    const int low = digit(generation[index * 2 + 1]);
    if (high < 0 || low < 0) return 2;
    wallet.generation[index] = static_cast<uint8_t>((high << 4) | low);
  }
  UniqueHandle blocked(::OpenEventW(EVENT_MODIFY_STATE, FALSE, arguments[4]));
  UniqueHandle proceed(::OpenEventW(SYNCHRONIZE, FALSE, arguments[5]));
  if (!blocked || !proceed) return 2;
  bool busy = false;
  try { GenerationLock denied(wallet, 0); }
  catch (const HostError &error) { busy = error.code() == CITIZENSDK_ERROR_BUSY; }
  if (!busy || !::SetEvent(blocked.get()) ||
      ::WaitForSingleObject(proceed.get(), 30000) != WAIT_OBJECT_0) return 3;
  try {
    SecureStore store{std::filesystem::path(arguments[2])};
    FakeSystem system;
    auto services = system.services();
    bool deleted = false;
    services.delete_key = [&](const WalletKey &key, const std::optional<VaultObject> &object) {
      // 进入物理删除时必须已经看到父进程写完的对象与本次退休墓碑。
      expect(object.has_value() && !store.is_generation_active(key));
      deleted = true;
    };
    SecretVault vault(store, std::move(services));
    std::array<uint8_t, 16> operation{};
    operation[0] = 10;
    vault.retire_wallet_kek(wallet, operation);
    expect(deleted && !store.load_vault_object(wallet));
    return 0;
  } catch (...) { return 4; }
}

void cross_process_retirement(SecureStore &store, const std::filesystem::path &directory) {
  WalletKey wallet{};
  expect(::BCryptGenRandom(nullptr, wallet.generation.data(),
      static_cast<ULONG>(wallet.generation.size()), BCRYPT_USE_SYSTEM_PREFERRED_RNG) >= 0);
  const std::string narrow_generation = cng_key_name(wallet).substr(11);
  const std::wstring generation(narrow_generation.begin(), narrow_generation.end());
  const std::wstring event_root = L"Local\\citizensdk.test." +
      std::to_wstring(::GetCurrentProcessId()) + L"." + generation;
  const std::wstring blocked_name = event_root + L".blocked";
  const std::wstring proceed_name = event_root + L".proceed";
  UniqueHandle blocked(::CreateEventW(nullptr, TRUE, FALSE, blocked_name.c_str()));
  UniqueHandle proceed(::CreateEventW(nullptr, TRUE, FALSE, proceed_name.c_str()));
  expect(blocked && proceed);
  std::array<wchar_t, 32768> executable{};
  const DWORD length = ::GetModuleFileNameW(nullptr, executable.data(),
                                           static_cast<DWORD>(executable.size()));
  expect(length > 0 && length < executable.size());
  std::wstring command = L"\"" + std::wstring(executable.data(), length) +
      L"\" --retire \"" + directory.native() + L"\" " + generation +
      L" \"" + blocked_name + L"\" \"" + proceed_name + L"\"";
  FakeSystem system;
  SecretVault vault(store, system.services());
  UniqueHandle process;
  UniqueHandle thread;
  system.on_create = [&] {
    STARTUPINFOW startup{};
    startup.cb = static_cast<DWORD>(sizeof(startup));
    PROCESS_INFORMATION information{};
    expect(::CreateProcessW(executable.data(), command.data(), nullptr, nullptr, FALSE,
        CREATE_NO_WINDOW, nullptr, nullptr, &startup, &information));
    process.reset(information.hProcess);
    thread.reset(information.hThread);
    // 子进程确实尝试取得同一 production mutex 并返回 BUSY，而非仅依赖延时猜测。
    expect(::WaitForSingleObject(blocked.get(), 30000) == WAIT_OBJECT_0);
  };
  std::array<uint8_t, 16> operation{};
  operation[0] = 9;
  try {
    vault.ensure_wallet_kek(wallet, operation);
    expect(store.load_vault_object(wallet).has_value());
    expect(::SetEvent(proceed.get()));
    expect(::WaitForSingleObject(process.get(), 30000) == WAIT_OBJECT_0);
    DWORD exit_code = 1;
    expect(::GetExitCodeProcess(process.get(), &exit_code) && exit_code == 0);
    expect(!store.is_generation_active(wallet) && !store.load_vault_object(wallet));
  } catch (...) {
    (void)::SetEvent(proceed.get());
    if (process && ::WaitForSingleObject(process.get(), 30000) != WAIT_OBJECT_0) {
      (void)::TerminateProcess(process.get(), 5);
      (void)::WaitForSingleObject(process.get(), 30000);
    }
    throw;
  }
}

}  // namespace

int wmain(int count, wchar_t **arguments) {
  if (count > 1 && std::wstring(arguments[1]) == L"--retire") return retire_child(count, arguments);
  using namespace citizen_sdk::windows;
  citizen_sdk::windows::test::TempDirectory temporary("secret-vault");
  SecureStore store(temporary.path() / "state");
  SecureStore other_store(temporary.path() / "state");
  FakeSystem system;
  SecretVault vault(store, system.services());
  SecretVault other(other_store, system.services());
  std::array<uint8_t, 16> operation{};
  operation[0] = 7;
  auto competing = operation;
  competing[0] = 8;
  WalletKey wallet{};
  wallet.generation[0] = 1;
  std::array<uint8_t, 32> output{};
  const auto zero = [&] {
    return std::all_of(output.begin(), output.end(), [](uint8_t byte) { return byte == 0; });
  };

  assert(vault.availability() == CITIZENSDK_HOST_VAULT_AVAILABLE);
  system.authentication_available = false;
  assert(vault.availability() == CITIZENSDK_HOST_VAULT_NO_STRONG_USER_AUTHENTICATION);
  fails(CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED, [&] { vault.ensure_wallet_kek(wallet, operation); });
  assert(system.created == 0);
  system.authentication_available = true;
  system.available = CngAvailability::kUnsupported;
  assert(vault.availability() == CITIZENSDK_HOST_VAULT_UNSUPPORTED);
  system.available = CngAvailability::kUnavailable;
  assert(vault.availability() == CITIZENSDK_HOST_VAULT_UNAVAILABLE);
  system.available = CngAvailability::kAvailable;
  assert(!vault.has_wallet_kek(wallet));
  output.fill(0xa5);
  fails(CITIZENSDK_ERROR_KEY_INVALIDATED, [&] { vault.unwrap_dek(1, wallet, Bytes(256), output.data()); });
  assert(zero() && vault.idle());

  system.cancel = true;
  fails(CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED, [&] { vault.ensure_wallet_kek(wallet, operation); });
  assert(system.created == 0 && !store.load_vault_object(wallet));
  system.cancel = false;
  vault.ensure_wallet_kek(wallet, operation);
  assert(vault.has_wallet_kek(wallet) && system.created == 1);
  const unsigned prompts = system.prompted;
  fails(CITIZENSDK_ERROR_KEY_INVALIDATED, [&] { other.ensure_wallet_kek(wallet, competing); });
  assert(system.created == 1 && system.deleted == 0 && system.prompted == prompts);
  vault.ensure_wallet_kek(wallet, operation);
  assert(system.created == 1);

  const Bytes wrapped = vault.wrap_dek(wallet, operation, output.data());
  assert(wrapped.size() == 256);
  vault.unwrap_dek(2, wallet, wrapped, output.data());
  assert(output[0] == 0x3c && vault.idle());
  system.cancel = true;
  fails(CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED, [&] { vault.unwrap_dek(3, wallet, wrapped, output.data()); });
  assert(zero() && vault.idle());
  system.cancel = false;
  system.decrypt_fails = true;
  fails(CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED, [&] { vault.unwrap_dek(4, wallet, wrapped, output.data()); });
  assert(zero() && vault.idle());
  system.decrypt_fails = false;

  // 同一操作重入不能消费/结束原操作的租约；拒绝路径仍清空它自己的输出。
  system.on_unlock = [&] {
    std::array<uint8_t, 32> another_output{};
    another_output.fill(0xa5);
    fails(CITIZENSDK_ERROR_CONFLICT, [&] { vault.unwrap_dek(5, wallet, wrapped, another_output.data()); });
    assert(!vault.idle() && std::all_of(another_output.begin(), another_output.end(),
        [](uint8_t byte) { return byte == 0; }));
  };
  vault.unwrap_dek(5, wallet, wrapped, output.data());
  system.on_unlock = {};
  assert(vault.idle());

  // 合成认证回调同步重入另一实例退休：禁止解封旧 key，墓碑阻止再次 ensure。
  const unsigned decryptions = system.decrypted;
  system.on_unlock = [&] { other.retire_wallet_kek(wallet, competing); };
  fails(CITIZENSDK_ERROR_KEY_INVALIDATED, [&] { vault.unwrap_dek(6, wallet, wrapped, output.data()); });
  system.on_unlock = {};
  assert(zero() && system.decrypted == decryptions && vault.idle() && !vault.has_wallet_kek(wallet));
  fails(CITIZENSDK_ERROR_KEY_INVALIDATED, [&] { vault.ensure_wallet_kek(wallet, operation); });

  wallet.generation[0] = 2;
  vault.ensure_wallet_kek(wallet, operation);
  system.on_decrypt = [&] { other.retire_wallet_kek(wallet, competing); };
  fails(CITIZENSDK_ERROR_KEY_INVALIDATED, [&] { vault.unwrap_dek(7, wallet, wrapped, output.data()); });
  system.on_decrypt = {};
  assert(zero() && vault.idle());

  wallet.generation[0] = 3;
  vault.ensure_wallet_kek(wallet, operation);
  system.delete_fails = true;
  fails(CITIZENSDK_ERROR_UNAVAILABLE, [&] { vault.retire_wallet_kek(wallet, operation); });
  assert(!store.is_generation_active(wallet) && store.load_vault_object(wallet) &&
      system.keys.count(cng_key_name(wallet)) == 1 && !vault.has_wallet_kek(wallet));
  system.delete_fails = false;
  vault.retire_wallet_kek(wallet, operation);
  assert(!store.load_vault_object(wallet) && system.keys.count(cng_key_name(wallet)) == 0);
  vault.retire_wallet_kek(wallet, operation);

  // 模拟 PCP 已持久化但对象行尚未写入便崩溃；generation 定址仍能清理。
  wallet.generation[0] = 4;
  assert(store.ensure_generation(wallet, operation));
  const auto orphan = synthetic_object(wallet);
  system.keys.emplace(orphan.key_name, orphan);
  vault.retire_wallet_kek(wallet, operation);
  assert(system.keys.count(orphan.key_name) == 0 && !store.ensure_generation(wallet, operation));

  // 对象已被同操作写入：生产 CAS 重复/写后错误路径确认同一提交，不删除成功方。
  wallet.generation[0] = 5;
  const unsigned deletions = system.deleted;
  system.on_create = [&] { other_store.store_vault_object_if_owned(wallet, operation, synthetic_object(wallet)); };
  vault.ensure_wallet_kek(wallet, operation);
  system.on_create = {};
  assert(vault.has_wallet_kek(wallet) && system.deleted == deletions);
  vault.retire_wallet_kek(wallet, operation);

  // CNG 返回后 ownership 被撤销：条件写入失败，不能在失败方路径擅自删 key。
  wallet.generation[0] = 6;
  system.on_create = [&] { other_store.retire_generation(wallet, competing); };
  const unsigned before_failure = system.deleted;
  fails(CITIZENSDK_ERROR_KEY_INVALIDATED, [&] { vault.ensure_wallet_kek(wallet, operation); });
  system.on_create = {};
  assert(system.deleted == before_failure && system.keys.count(cng_key_name(wallet)) == 1);
  vault.retire_wallet_kek(wallet, operation);
  assert(system.keys.empty() && vault.idle() && other.idle());
  try { cross_process_retirement(store, temporary.path() / "state"); }
  catch (...) { return 1; }
  return 0;
}
