#include "citizen_sdk_secret_vault.hpp"

#include "citizen_sdk_host_record.hpp"

namespace citizen_sdk::linux {

SecretVault::SecretVault(SecureStore &secure_store, GtkParentRef &parent)
    : secure_store_(secure_store), user_auth_(parent) {}

citizensdk_host_vault_availability_t SecretVault::availability() const noexcept {
  const TpmAvailability tpm = tpm_.availability();
  if (tpm == TpmAvailability::kUnsupported) {
    return CITIZENSDK_HOST_VAULT_UNSUPPORTED;
  }
  if (tpm == TpmAvailability::kUnavailable) {
    return CITIZENSDK_HOST_VAULT_UNAVAILABLE;
  }
  if (!user_auth_.available()) {
    return CITIZENSDK_HOST_VAULT_NO_STRONG_USER_AUTHENTICATION;
  }
  return CITIZENSDK_HOST_VAULT_AVAILABLE;
}

void SecretVault::ensure_wallet_kek(
    const WalletKey &key, const std::array<uint8_t, 16> &operation_id) {
  std::lock_guard<std::recursive_mutex> guard(generation_lock_);
  require(key.wallet_index == 0, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "only CitizenSDK wallet index 0 is supported");
  if (availability() != CITIZENSDK_HOST_VAULT_AVAILABLE) {
    throw HostError(CITIZENSDK_ERROR_AUTHENTICATION_REQUIRED,
                    "TPM 2.0 and SDK-owned user authentication are required");
  }
  if (!secure_store_.ensure_generation(key, operation_id)) {
    throw HostError(CITIZENSDK_ERROR_KEY_INVALIDATED,
                    "wallet generation is retired or owned by another operation");
  }
  if (const auto existing = secure_store_.load_vault_object(key)) {
    (void)tpm_.validate_key(*existing);
    if (!secure_store_.generation_owned_by(key, operation_id) ||
        !secure_store_.vault_object_is_active(key, *existing)) {
      throw HostError(CITIZENSDK_ERROR_KEY_INVALIDATED,
                      "wallet TPM object is no longer owned by provisioning");
    }
    return;
  }
  AuthenticationResult authentication = user_auth_.create_vault_password();
  if (authentication.code != CITIZENSDK_OK) {
    throw HostError(authentication.code,
                    "CitizenSDK device-vault password creation was cancelled");
  }
  if (!secure_store_.generation_owned_by(key, operation_id)) {
    throw HostError(CITIZENSDK_ERROR_KEY_INVALIDATED,
                    "wallet generation was retired while authenticating");
  }
  VaultObject object = tpm_.create_key(authentication.password);
  authentication.password.clear();
  try {
    secure_store_.store_vault_object_if_owned(key, operation_id, object);
  } catch (const HostError &error) {
    if (error.code() == CITIZENSDK_ERROR_STORAGE &&
        secure_store_.load_vault_object(key).has_value()) {
      throw HostError(CITIZENSDK_ERROR_CONFLICT,
                      "wallet TPM object was provisioned concurrently");
    }
    throw;
  }
}

bool SecretVault::has_wallet_kek(const WalletKey &key) {
  std::lock_guard<std::recursive_mutex> guard(generation_lock_);
  if (!secure_store_.is_generation_active(key)) return false;
  const auto object = secure_store_.load_vault_object(key);
  if (!object) return false;
  if (!secure_store_.vault_object_is_active(key, *object)) return false;
  return tpm_.validate_key(*object);
}

Bytes SecretVault::wrap_dek(
    const WalletKey &key, const std::array<uint8_t, 16> &operation_id,
    const uint8_t plaintext_dek[32]) {
  std::lock_guard<std::recursive_mutex> guard(generation_lock_);
  require(plaintext_dek != nullptr, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "wallet DEK must be an exact Rust-owned 32-byte view");
  ensure_wallet_kek(key, operation_id);
  const auto object = secure_store_.load_vault_object(key);
  if (!object) {
    throw HostError(CITIZENSDK_ERROR_KEY_INVALIDATED,
                    "wallet TPM object is unavailable");
  }
  if (!secure_store_.vault_object_is_active(key, *object)) {
    throw HostError(CITIZENSDK_ERROR_KEY_INVALIDATED,
                    "wallet TPM object is no longer active");
  }
  return tpm_.encrypt_dek(*object, plaintext_dek);
}

void SecretVault::unwrap_dek(uint64_t host_operation_id, const WalletKey &key,
                             const Bytes &wrapped_dek,
                             uint8_t plaintext_dek_out[32]) {
  require(plaintext_dek_out != nullptr, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "wallet DEK output must be an exact Rust-owned 32-byte view");
  if (!operations_.accept(host_operation_id)) {
    throw HostError(CITIZENSDK_ERROR_CONFLICT,
                    "duplicate vault operation identity");
  }
  try {
    std::lock_guard<std::recursive_mutex> guard(generation_lock_);
    if (!secure_store_.is_generation_active(key)) {
      throw HostError(CITIZENSDK_ERROR_KEY_INVALIDATED,
                      "wallet generation is retired");
    }
    const auto object = secure_store_.load_vault_object(key);
    if (!object) {
      throw HostError(CITIZENSDK_ERROR_KEY_INVALIDATED,
                      "wallet TPM object is unavailable");
    }
    AuthenticationResult authentication = user_auth_.unlock_vault_password(host_operation_id);
    if (authentication.code != CITIZENSDK_OK) {
      throw HostError(authentication.code,
                      "CitizenSDK device-vault unlock was cancelled");
    }
    // Authentication can take minutes. Re-read both the tombstone and the
    // exact TPM blob identity before using the password, so retirement or
    // replacement during the prompt cannot authorize stale key material.
    if (!secure_store_.vault_object_is_active(key, *object)) {
      throw HostError(CITIZENSDK_ERROR_KEY_INVALIDATED,
                      "wallet TPM object was retired while authenticating");
    }
    tpm_.decrypt_dek(*object, wrapped_dek, authentication.password,
                     plaintext_dek_out);
    authentication.password.clear();
    if (!secure_store_.vault_object_is_active(key, *object)) {
      secure_zero(plaintext_dek_out, 32);
      throw HostError(CITIZENSDK_ERROR_KEY_INVALIDATED,
                      "wallet TPM object was retired while decrypting");
    }
    operations_.finish(host_operation_id);
  } catch (...) {
    secure_zero(plaintext_dek_out, 32);
    operations_.finish(host_operation_id);
    throw;
  }
}

void SecretVault::retire_wallet_kek(
    const WalletKey &key, const std::array<uint8_t, 16> &operation_id) {
  std::lock_guard<std::recursive_mutex> guard(generation_lock_);
  // The tombstone is the irreversible commit point. Physical TPM blobs are
  // removed only afterwards, so a crash can never resurrect the generation.
  secure_store_.retire_generation(key, operation_id);
  secure_store_.delete_vault_object(key);
}

bool SecretVault::idle() const noexcept { return operations_.empty(); }

}  // namespace citizen_sdk::linux
