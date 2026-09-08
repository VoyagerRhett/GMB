// 验证 Vault 只管理 generation KEK/随机 DEK，并在缺失能力时失败关闭。
#include <algorithm>
#include <array>
#include <cassert>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <thread>

#include "citizen_sdk_secret_vault.hpp"
#include "citizen_sdk_test_support.hpp"

#ifndef CITIZENSDK_LINUX_TEST_SOURCE_DIR
#error "CITIZENSDK_LINUX_TEST_SOURCE_DIR must point at the Linux source root"
#endif
#ifdef NDEBUG
#error "CitizenSDK Linux contract assertions must remain enabled"
#endif

int main() {
  using namespace citizen_sdk::linux;

  citizen_sdk::linux::test::TempDirectory temporary("secret-vault");
  const auto directory = temporary.path() / "state";
  {
    SecureStore store(directory);
    GtkParentRef parent(nullptr, std::this_thread::get_id());
    SecretVault vault(store, parent);
    const auto availability = vault.availability();
    assert(availability == CITIZENSDK_HOST_VAULT_AVAILABLE ||
           availability ==
               CITIZENSDK_HOST_VAULT_NO_STRONG_USER_AUTHENTICATION ||
           availability == CITIZENSDK_HOST_VAULT_UNSUPPORTED ||
           availability == CITIZENSDK_HOST_VAULT_UNAVAILABLE);

    WalletKey invalid{};
    invalid.wallet_index = 1;
    std::array<uint8_t, 16> operation{};
    operation[0] = 1;
    bool wrong_wallet_rejected = false;
    try {
      vault.ensure_wallet_kek(invalid, operation);
    } catch (const HostError &error) {
      wrong_wallet_rejected =
          error.code() == CITIZENSDK_ERROR_INVALID_ARGUMENT;
    }
    assert(wrong_wallet_rejected);

    WalletKey missing{};
    missing.generation[0] = 2;
    assert(!vault.has_wallet_kek(missing));
    std::array<uint8_t, 32> output{};
    output.fill(0xa5);
    bool missing_rejected = false;
    try {
      vault.unwrap_dek(9, missing, Bytes{1, 2}, output.data());
    } catch (const HostError &error) {
      missing_rejected = error.code() == CITIZENSDK_ERROR_KEY_INVALIDATED;
    }
    assert(missing_rejected);
    assert(std::all_of(output.begin(), output.end(),
                       [](uint8_t byte) { return byte == 0; }));
    assert(vault.idle());

    vault.retire_wallet_kek(missing, operation);
    assert(!vault.has_wallet_kek(missing));
    assert(!store.ensure_generation(missing, operation));
  }

  const std::string source_path =
      std::string(CITIZENSDK_LINUX_TEST_SOURCE_DIR) +
      "/src/citizen_sdk_secret_vault.cc";
  std::ifstream stream(source_path, std::ios::binary);
  assert(stream.good());
  const std::string source((std::istreambuf_iterator<char>(stream)),
                           std::istreambuf_iterator<char>());
  const auto provision = source.find("SecretVault::ensure_wallet_kek");
  const auto provision_lock = source.find("generation_lock_", provision);
  const auto generation_admission =
      source.find("secure_store_.ensure_generation", provision_lock);
  const auto conditional_insert =
      source.find("secure_store_.store_vault_object_if_owned", provision);
  const auto unwrap = source.find("SecretVault::unwrap_dek");
  const auto unwrap_lock = source.find("generation_lock_", unwrap);
  const auto prompt =
      source.find("user_auth_.unlock_vault_password(host_operation_id)", unwrap_lock);
  const auto post_prompt_check =
      source.find("secure_store_.vault_object_is_active(key, *object)", prompt);
  const auto decrypt = source.find("tpm_.decrypt_dek", post_prompt_check);
  const auto post_decrypt_check =
      source.find("secure_store_.vault_object_is_active(key, *object)",
                  decrypt);
  const auto clear_after_retire =
      source.find("secure_zero(plaintext_dek_out, 32)", post_decrypt_check);
  const auto retire = source.find("SecretVault::retire_wallet_kek");
  const auto retire_lock = source.find("generation_lock_", retire);
  const auto tombstone =
      source.find("secure_store_.retire_generation", retire_lock);
  const auto physical_delete =
      source.find("secure_store_.delete_vault_object", tombstone);
  assert(provision != std::string::npos &&
         provision_lock != std::string::npos &&
         generation_admission != std::string::npos &&
         conditional_insert != std::string::npos &&
         provision < provision_lock && provision_lock < generation_admission &&
         generation_admission < conditional_insert);
  assert(unwrap != std::string::npos && unwrap_lock != std::string::npos &&
         prompt != std::string::npos && post_prompt_check != std::string::npos &&
         decrypt != std::string::npos &&
         post_decrypt_check != std::string::npos &&
         clear_after_retire != std::string::npos && unwrap < unwrap_lock &&
         unwrap_lock < prompt && prompt < post_prompt_check &&
         post_prompt_check < decrypt && decrypt < post_decrypt_check &&
         post_decrypt_check < clear_after_retire);
  assert(retire != std::string::npos && retire_lock != std::string::npos &&
         tombstone != std::string::npos && physical_delete != std::string::npos &&
         retire < retire_lock && retire_lock < tombstone &&
         tombstone < physical_delete);

  const std::string bridge_path =
      std::string(CITIZENSDK_LINUX_TEST_SOURCE_DIR) +
      "/src/citizen_sdk_host_bridge.hpp";
  std::ifstream bridge_stream(bridge_path, std::ios::binary);
  assert(bridge_stream.good());
  const std::string bridge((std::istreambuf_iterator<char>(bridge_stream)),
                            std::istreambuf_iterator<char>());
  const auto service = bridge.find("auto service_call(Function function)");
  const auto lease = bridge.find("ServiceLease lease(*this)", service);
  const auto invoke = bridge.find("return function()", lease);
  assert(service != std::string::npos && lease != std::string::npos &&
         invoke != std::string::npos && service < lease && lease < invoke);
  assert(bridge.substr(service, invoke - service).find("lock_guard") ==
         std::string::npos);
  assert(bridge.find("host_.lifecycle_.begin_service()") != std::string::npos);
  assert(bridge.find("~ServiceLease() { host_.lifecycle_.finish_service(); }") !=
         std::string::npos);
  return 0;
}
