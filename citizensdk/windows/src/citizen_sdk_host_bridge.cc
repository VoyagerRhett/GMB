#include "citizen_sdk_host_bridge.hpp"
#include "citizen_sdk_qr_flow.hpp"

#include <algorithm>
#include <cstring>
#include <exception>
#include <iterator>
#include <limits>
#include <thread>
#include <utility>
#include "citizen_sdk_input_limits.hpp"

namespace citizen_sdk::windows {
namespace {

std::array<uint8_t, 16> id16(citizensdk_host_id128_t value) {
  std::array<uint8_t, 16> result{};
  std::copy(std::begin(value.bytes), std::end(value.bytes), result.begin());
  return result;
}

std::array<uint8_t, 32> hash32(citizensdk_host_hash32_t value) {
  std::array<uint8_t, 32> result{};
  std::copy(std::begin(value.bytes), std::end(value.bytes), result.begin());
  return result;
}

WalletKey wallet_key(citizensdk_host_wallet_key_ref_v1_t value) {
  require(value.struct_size >= sizeof(value) && value.abi_version == 1 &&
              value.wallet_index == 0 && value.reserved == 0,
          CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "wallet key reference ABI is invalid");
  return {value.wallet_index, id16(value.generation)};
}

SecretIdentity secret_identity(citizensdk_host_secret_ref_v1_t value) {
  require(value.struct_size >= sizeof(value) && value.abi_version == 1 &&
              value.wallet_index == 0 &&
              value.kind == CITIZENSDK_HOST_SECRET_ACCOUNT_MINI_SECRET,
          CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "secret reference ABI is invalid");
  SecretIdentity result{};
  result.wallet_index = value.wallet_index;
  result.kind = value.kind;
  result.generation = id16(value.generation);
  result.owner = id16(value.owner);
  std::copy(std::begin(value.account_id.bytes), std::end(value.account_id.bytes),
            result.account_id.begin());
  return result;
}

void complete_record(uint64_t operation_id, void *sdk_context,
                     citizensdk_host_record_completion_v1_t completion,
                     const HostRecord &record) {
  citizensdk_host_record_result_v1_t result{};
  result.struct_size = sizeof(result);
  result.abi_version = 1;
  result.host_operation_id = operation_id;
  result.error_code = record.error_code;
  result.domain = record.domain;
  result.present = record.error_code == CITIZENSDK_OK && record.present ? 1 : 0;
  result.revision = result.present != 0 ? record.revision : 0;
  if (result.present != 0) {
    result.record = {record.record.data(),
                     static_cast<uint64_t>(record.record.size())};
  }
  completion(sdk_context, &result);
}

void complete_status(uint64_t operation_id, void *sdk_context,
                     citizensdk_host_status_completion_v1_t completion,
                     citizensdk_error_code_t code) {
  citizensdk_host_status_result_v1_t result{};
  result.struct_size = sizeof(result);
  result.abi_version = 1;
  result.host_operation_id = operation_id;
  result.error_code = code;
  completion(sdk_context, &result);
}

HostBridge &host(void *context) {
  require(context != nullptr, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "CitizenSDK Host context is missing");
  return *static_cast<HostBridge *>(context);
}

citizensdk_error_code_t chain_load(void *context, uint64_t operation_id,
    void *sdk_context, citizensdk_host_record_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { complete_record(operation_id, sdk_context, completion,
                        host(context).chain_load()); return CITIZENSDK_OK; }
  catch (...) { return map_exception(); }
}

citizensdk_error_code_t chain_cas(void *context, uint64_t operation_id,
    uint64_t expected, uint8_t present, citizensdk_bytes_view_t candidate,
    void *sdk_context, citizensdk_host_record_completion_v1_t completion) {
  if (completion == nullptr || present != 1) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { complete_record(operation_id, sdk_context, completion,
      host(context).chain_cas(expected, copy_view(candidate,
          input_limits::kMaximumChainDatabaseBytes, "chain database is too large")));
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

citizensdk_error_code_t runtime_load(void *context, uint64_t operation_id,
    citizensdk_host_hash32_t hash, void *sdk_context,
    citizensdk_host_record_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { complete_record(operation_id, sdk_context, completion,
                        host(context).runtime_load(hash32(hash)));
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

citizensdk_error_code_t runtime_store(void *context, uint64_t operation_id,
    citizensdk_host_hash32_t hash, citizensdk_bytes_view_t candidate,
    void *sdk_context, citizensdk_host_status_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { host(context).runtime_store(hash32(hash), copy_view(candidate,
          input_limits::kMaximumRuntimeCacheBytes, "runtime cache is too large"));
    complete_status(operation_id, sdk_context, completion, CITIZENSDK_OK);
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

citizensdk_error_code_t runtime_delete(void *context, uint64_t operation_id,
    citizensdk_host_hash32_t hash, void *sdk_context,
    citizensdk_host_status_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { host(context).runtime_delete(hash32(hash));
    complete_status(operation_id, sdk_context, completion, CITIZENSDK_OK);
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

citizensdk_error_code_t history_query(void *context, uint64_t operation_id,
    citizensdk_bytes_view_t query, void *sdk_context,
    citizensdk_host_record_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { complete_record(operation_id, sdk_context, completion,
      host(context).history_query(copy_view(query,
          input_limits::kTransactionHistoryQueryBytes,
          "transaction history query has invalid size"))); return CITIZENSDK_OK; }
  catch (...) { return map_exception(); }
}

citizensdk_error_code_t history_mutate(void *context, uint64_t operation_id,
    uint64_t expected, citizensdk_bytes_view_t mutation, void *sdk_context,
    citizensdk_host_record_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { complete_record(operation_id, sdk_context, completion,
      host(context).history_mutate(expected, copy_view(mutation,
          input_limits::kMaximumTransactionHistoryBytes, "transaction history is too large")));
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

citizensdk_error_code_t profile_load(void *context, uint64_t operation_id,
    void *sdk_context, citizensdk_host_record_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { complete_record(operation_id, sdk_context, completion,
                        host(context).profile_load()); return CITIZENSDK_OK; }
  catch (...) { return map_exception(); }
}

citizensdk_error_code_t profile_cas(void *context, uint64_t operation_id,
    uint64_t expected, citizensdk_bytes_view_t candidate, void *sdk_context,
    citizensdk_host_record_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { complete_record(operation_id, sdk_context, completion,
      host(context).profile_cas(expected, copy_view(candidate,
          input_limits::kMaximumWalletProfileBytes, "wallet profile is too large")));
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

citizensdk_error_code_t secret_load(void *context, uint64_t operation_id,
    citizensdk_host_secret_ref_v1_t secret, void *sdk_context,
    citizensdk_host_record_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { complete_record(operation_id, sdk_context, completion,
                        host(context).secret_load(secret_identity(secret)));
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

citizensdk_error_code_t secret_cas(void *context, uint64_t operation_id,
    citizensdk_host_secret_ref_v1_t secret, uint64_t expected,
    citizensdk_bytes_view_t candidate, void *sdk_context,
    citizensdk_host_record_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { complete_record(operation_id, sdk_context, completion,
      host(context).secret_cas(secret_identity(secret), expected,
        copy_view(candidate, input_limits::kMaximumEncryptedSecretBytes,
                  "encrypted secret blob is too large")));
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

citizensdk_error_code_t vault_availability(void *context, uint64_t operation_id,
    void *sdk_context,
    citizensdk_host_vault_availability_completion_v1_t completion) {
  if (context == nullptr || completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  citizensdk_host_vault_availability_result_v1_t result{};
  result.struct_size = sizeof(result); result.abi_version = 1;
  result.host_operation_id = operation_id; result.error_code = CITIZENSDK_OK;
  result.availability = static_cast<HostBridge *>(context)->vault_availability();
  completion(sdk_context, &result);
  return CITIZENSDK_OK;
}

citizensdk_error_code_t vault_ensure(void *context, uint64_t operation_id,
    citizensdk_host_wallet_key_ref_v1_t key,
    citizensdk_host_id128_t provisioning_id, void *sdk_context,
    citizensdk_host_status_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { host(context).vault_ensure(wallet_key(key), id16(provisioning_id));
    complete_status(operation_id, sdk_context, completion, CITIZENSDK_OK);
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

citizensdk_error_code_t vault_has(void *context, uint64_t operation_id,
    citizensdk_host_wallet_key_ref_v1_t key, void *sdk_context,
    citizensdk_host_bool_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { citizensdk_host_bool_result_v1_t result{};
    result.struct_size = sizeof(result); result.abi_version = 1;
    result.host_operation_id = operation_id; result.error_code = CITIZENSDK_OK;
    result.value = host(context).vault_has(wallet_key(key)) ? 1 : 0;
    completion(sdk_context, &result); return CITIZENSDK_OK;
  } catch (...) { return map_exception(); }
}

citizensdk_error_code_t vault_wrap(void *context, uint64_t operation_id,
    citizensdk_host_wallet_key_ref_v1_t key,
    citizensdk_host_id128_t provisioning_id, citizensdk_bytes_view_t plaintext,
    void *sdk_context, citizensdk_host_bytes_completion_v1_t completion) {
  if (completion == nullptr || plaintext.data == nullptr ||
      plaintext.len != CITIZENSDK_HOST_DEK_BYTES) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { const Bytes wrapped = host(context).vault_wrap(wallet_key(key),
      id16(provisioning_id), plaintext.data);
    citizensdk_host_bytes_result_v1_t result{};
    result.struct_size = sizeof(result); result.abi_version = 1;
    result.host_operation_id = operation_id; result.error_code = CITIZENSDK_OK;
    result.kind = CITIZENSDK_HOST_BYTES_WRAPPED_DEK;
    result.bytes = {wrapped.data(), static_cast<uint64_t>(wrapped.size())};
    completion(sdk_context, &result); return CITIZENSDK_OK;
  } catch (...) { return map_exception(); }
}

citizensdk_error_code_t vault_unwrap(void *context, uint64_t operation_id,
    citizensdk_host_wallet_key_ref_v1_t key, citizensdk_bytes_view_t wrapped,
    citizensdk_mutable_bytes_view_t output, void *sdk_context,
    citizensdk_host_status_completion_v1_t completion) {
  if (completion == nullptr || output.data == nullptr ||
      output.len != CITIZENSDK_HOST_DEK_BYTES) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { host(context).vault_unwrap(operation_id, wallet_key(key),
      copy_view(wrapped, 4096, "wrapped wallet DEK is malformed"), output.data);
    complete_status(operation_id, sdk_context, completion, CITIZENSDK_OK);
    return CITIZENSDK_OK;
  } catch (...) {
    secure_zero(output.data, static_cast<std::size_t>(output.len));
    return map_exception();
  }
}

citizensdk_error_code_t vault_retire(void *context, uint64_t operation_id,
    citizensdk_host_wallet_key_ref_v1_t key,
    citizensdk_host_id128_t cleanup_id, void *sdk_context,
    citizensdk_host_status_completion_v1_t completion) {
  if (completion == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  try { host(context).vault_retire(wallet_key(key), id16(cleanup_id));
    complete_status(operation_id, sdk_context, completion, CITIZENSDK_OK);
    return CITIZENSDK_OK; } catch (...) { return map_exception(); }
}

}  // namespace

HostBridge::HostBridge(std::filesystem::path storage_root,
                       std::filesystem::path asset_root,
                       std::string application_id, void *hwnd,
                       uint32_t modules)
    : ui_thread_(std::this_thread::get_id()),
      parent_window_(hwnd, ui_thread_, (modules & (CITIZENSDK_MODULE_WALLET | CITIZENSDK_MODULE_SIGNING | CITIZENSDK_MODULE_QR)) != 0),
      asset_root_(std::move(asset_root)),
      modules_(modules) {
  // 未选链/历史时不创建公开数据库，钱包独立运行完全不触碰链资产和存储。
  if ((modules & (CITIZENSDK_MODULE_CHAIN | CITIZENSDK_MODULE_HISTORY)) != 0) {
    public_store_ = std::make_unique<PublicStore>(
        storage_root / application_id / "citizensdk" / "v1" / "public");
  }
  const auto secure_root = storage_root / application_id / "citizensdk" / "v1" / "secure";
  if ((modules & (CITIZENSDK_MODULE_WALLET | CITIZENSDK_MODULE_SIGNING)) != 0) {
    secure_store_ = std::make_unique<SecureStore>(secure_root);
    vault_ = std::make_unique<SecretVault>(*secure_store_, parent_window_);
  }
  configure_vtables();
}

HostBridge::~HostBridge() = default;

void HostBridge::configure_vtables() noexcept {
  public_vtable_ = {sizeof(public_vtable_), 1, this, ::citizen_sdk::windows::chain_load,
    ::citizen_sdk::windows::chain_cas, ::citizen_sdk::windows::runtime_load,
    ::citizen_sdk::windows::runtime_store, ::citizen_sdk::windows::runtime_delete,
    ::citizen_sdk::windows::history_query, ::citizen_sdk::windows::history_mutate};
  // 每组回调必须完整或完全缺席；不可用模块不发布可触达的资源。
  if ((modules_ & CITIZENSDK_MODULE_CHAIN) == 0) {
    public_vtable_.chain_database_load = nullptr;
    public_vtable_.chain_database_compare_and_swap = nullptr;
    public_vtable_.runtime_cache_load = nullptr;
    public_vtable_.runtime_cache_store = nullptr;
    public_vtable_.runtime_cache_delete = nullptr;
  }
  if ((modules_ & CITIZENSDK_MODULE_HISTORY) == 0) {
    public_vtable_.transaction_history_query = nullptr;
    public_vtable_.transaction_history_mutate = nullptr;
  }
  secure_vtable_ = {sizeof(secure_vtable_), 1, this,
    ::citizen_sdk::windows::profile_load, ::citizen_sdk::windows::profile_cas,
    ::citizen_sdk::windows::secret_load, ::citizen_sdk::windows::secret_cas};
  vault_vtable_ = {sizeof(vault_vtable_), 1, this,
    ::citizen_sdk::windows::vault_availability, ::citizen_sdk::windows::vault_ensure,
    ::citizen_sdk::windows::vault_has, ::citizen_sdk::windows::vault_wrap,
    ::citizen_sdk::windows::vault_unwrap, ::citizen_sdk::windows::vault_retire};
}

citizensdk_host_services_v1_t HostBridge::services() noexcept {
  citizensdk_host_services_v1_t result{};
  result.struct_size = sizeof(result); result.abi_version = 1;
  result.public_store = public_store_ ? &public_vtable_ : nullptr;
  result.secure_store = secure_store_ ? &secure_vtable_ : nullptr;
  result.secret_vault = vault_ ? &vault_vtable_ : nullptr;
  return result;
}

citizensdk_error_code_t HostBridge::create_sdk(citizensdk_handle_t *out_sdk) {
  if (out_sdk == nullptr) return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  *out_sdk = 0;
  {
    std::lock_guard<std::recursive_mutex> guard(call_lock_);
    if (sdk_ != 0 || teardown_started_ || create_in_progress_ ||
        close_in_progress_ || services_retired_) {
      return CITIZENSDK_ERROR_INVALID_STATE;
    }
    create_in_progress_ = true;
  }
  try {
    const Assets assets = (modules_ & CITIZENSDK_MODULE_CHAIN) != 0
        ? Assets::load(asset_root_) : Assets{};
    const std::string name = "CitizenSDK";
    const std::string version = CITIZENSDK_HOST_VERSION;
    citizensdk_create_options_t options{};
    options.struct_size = sizeof(options); options.abi_version = 1;
    options.asset_manifest = {assets.manifest.data(), static_cast<uint64_t>(assets.manifest.size())};
    options.chain_spec = {assets.chain_spec.data(), static_cast<uint64_t>(assets.chain_spec.size())};
    options.light_sync_state = {assets.light_sync_state.data(), static_cast<uint64_t>(assets.light_sync_state.size())};
    options.system_name = {reinterpret_cast<const uint8_t *>(name.data()), name.size()};
    options.system_version = {reinterpret_cast<const uint8_t *>(version.data()), version.size()};
    citizensdk_host_services_v1_t host_services = services();
    citizensdk_handle_t created = 0;
    citizensdk_error_code_t code =
        citizensdk_create_with_modules(&options, &host_services, modules_, &created);
    if (code != CITIZENSDK_OK) {
      // A nonzero error handle is a destroy-only Core instance. Preserve it so
      // close()/abandon can reclaim all Rust and provider ownership safely.
      if (created != 0) {
        std::lock_guard<std::recursive_mutex> guard(call_lock_);
        sdk_ = created;
        teardown_started_ = true;
      }
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      create_in_progress_ = false;
      return code;
    }
    if (created == 0) {
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      create_in_progress_ = false;
      return CITIZENSDK_ERROR_INTEGRITY;
    }
    {
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      sdk_ = created;
    }
    code = citizensdk_set_event_callback(created, receive_core_event, this);
    if (code == CITIZENSDK_OK) {
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      callback_installed_ = true;
    }
    if (code == CITIZENSDK_OK) {
      code = citizensdk_subscribe_capability_changes(created);
      if (code == CITIZENSDK_OK) {
        std::lock_guard<std::recursive_mutex> guard(call_lock_);
        capability_subscribed_ = true;
      }
    }
    if (code != CITIZENSDK_OK) {
      bool callback_installed = false;
      {
        std::lock_guard<std::recursive_mutex> guard(call_lock_);
        teardown_started_ = true;
        callback_installed = callback_installed_;
      }
      if (callback_installed &&
          citizensdk_set_event_callback(created, nullptr, nullptr) ==
              CITIZENSDK_OK) {
        std::lock_guard<std::recursive_mutex> guard(call_lock_);
        callback_installed_ = false;
        callback_installed = false;
      }
      if (!callback_installed && citizensdk_destroy(created) == CITIZENSDK_OK) {
        std::lock_guard<std::recursive_mutex> guard(call_lock_);
        sdk_ = 0;
      }
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      create_in_progress_ = false;
      return code;
    }
    {
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      create_in_progress_ = false;
      *out_sdk = sdk_;
    }
    return CITIZENSDK_OK;
  } catch (...) {
    std::lock_guard<std::recursive_mutex> guard(call_lock_);
    create_in_progress_ = false;
    return map_exception();
  }
}

citizensdk_handle_t HostBridge::sdk() const noexcept {
  std::lock_guard<std::recursive_mutex> guard(call_lock_);
  return sdk_;
}

citizensdk_handle_t HostBridge::public_sdk() const noexcept {
  std::lock_guard<std::recursive_mutex> guard(call_lock_);
  return sdk_ != 0 && !teardown_started_ && !create_in_progress_ &&
                 !close_in_progress_ && !services_retired_ &&
                 callback_installed_ && capability_subscribed_
             ? sdk_
             : 0;
}

citizensdk_error_code_t HostBridge::set_event_callback(
    citizensdk_event_callback_t callback, void *context) {
  if (callback == nullptr) {
    std::lock_guard<std::mutex> guard(callback_lock_);
    if (callback_thread_ == std::this_thread::get_id()) {
      // A foreign setter may be waiting for this exact callback to return.
      // Self-retirement must not wait for that setter or reject the only safe
      // C++ destructor barrier. The setter owns its replacement context; an
      // abandoned Host's supervisor retires that replacement after its lease.
      public_callback_ = nullptr;
      public_callback_context_ = nullptr;
      return CITIZENSDK_OK;
    }
  }
  {
    std::lock_guard<std::recursive_mutex> call(call_lock_);
    if ((teardown_started_ || close_in_progress_ || services_retired_) &&
        callback != nullptr) {
      return CITIZENSDK_ERROR_INVALID_STATE;
    }
    if (callback_update_in_progress_) return CITIZENSDK_ERROR_BUSY;
    callback_update_in_progress_ = true;
  }
  citizensdk_error_code_t result = CITIZENSDK_OK;
  try {
    std::unique_lock<std::mutex> guard(callback_lock_);
    if (callback_thread_ == std::this_thread::get_id()) {
      if (callback != nullptr) {
        result = CITIZENSDK_ERROR_BUSY;
      } else {
        public_callback_ = nullptr;
        public_callback_context_ = nullptr;
      }
    } else {
      callback_idle_.wait(guard, [&] { return callbacks_active_ == 0; });
      public_callback_ = callback;
      public_callback_context_ = callback ? context : nullptr;
    }
  } catch (...) {
    result = map_exception();
  }
  {
    std::lock_guard<std::recursive_mutex> call(call_lock_);
    callback_update_in_progress_ = false;
  }
  return result;
}

void HostBridge::receive_core_event(void *context,
                                    const citizensdk_event_t *event) noexcept {
  if (context != nullptr && event != nullptr) {
    static_cast<HostBridge *>(context)->dispatch_core_event(*event);
  }
}

void HostBridge::dispatch_core_event(const citizensdk_event_t &event) noexcept {
  if (event.event_type == CITIZENSDK_EVENT_REQUEST_COMPLETED) {
    // Core guarantees one dedicated dispatch thread per instance. Holding an
    // early completion here preserves that thread identity while the caller
    // publishes the request route; it neither buffers nor caps events.
    completion_admission_.await_route(event.request_id);
  }
  dispatch_routed_event(event);
}

void HostBridge::dispatch_routed_event(const citizensdk_event_t &event) noexcept {
  RequestRouter::Handler private_handler;
  try {
    private_handler = private_requests_.take(event);
  } catch (...) {
    if (event.result != 0) (void)citizensdk_result_release(event.result);
    return;
  }
  if (private_handler) {
    // Ownership transfers to the registered private handler before the call.
    // All production handlers are noexcept and release exactly once. If a
    // future handler violates that contract, re-releasing here could double
    // release a handle already consumed immediately before the exception.
    try { private_handler(event.result); } catch (...) {}
    return;
  }
  citizensdk_event_callback_t callback = nullptr; void *context = nullptr;
  {
    std::lock_guard<std::mutex> guard(callback_lock_);
    callback = public_callback_; context = public_callback_context_;
    if (callback != nullptr) { ++callbacks_active_; callback_thread_ = std::this_thread::get_id(); }
  }
  if (callback != nullptr) {
    try {
      // Raw C callback ownership transfers here. It must not throw and must
      // release a nonzero result exactly once; Host cannot safely infer
      // whether a callback that violates that contract already released it.
      callback(context, &event);
    } catch (...) {}
  } else if (event.result != 0) {
    (void)citizensdk_result_release(event.result);
  }
  {
    std::lock_guard<std::mutex> guard(callback_lock_);
    if (callback != nullptr) { --callbacks_active_; callback_thread_ = {}; callback_idle_.notify_all(); }
  }
}

citizensdk_error_code_t HostBridge::set_parent_window(void *window) noexcept {
  std::lock_guard<std::recursive_mutex> call(call_lock_);
  if (teardown_started_ || create_in_progress_ || close_in_progress_ ||
      services_retired_) {
    return CITIZENSDK_ERROR_INVALID_STATE;
  }
  return parent_window_.set(window);
}
WindowLease HostBridge::acquire_parent_window() const noexcept {
  return parent_window_.acquire();
}
citizensdk_host_vault_availability_t HostBridge::vault_availability() noexcept {
  try {
    return service_call([&] {
      return vault_ ? vault_->availability() : CITIZENSDK_HOST_VAULT_UNSUPPORTED;
    });
  } catch (...) {
    return CITIZENSDK_HOST_VAULT_UNAVAILABLE;
  }
}

citizensdk_error_code_t HostBridge::close() {
  cancel_host_qr_flows(this);
  bool teardown_started = false;
  const auto cancel_close = [&](citizensdk_error_code_t code) noexcept {
    std::lock_guard<std::recursive_mutex> guard(call_lock_);
    close_in_progress_ = false;
    lifecycle_.cancel_close(teardown_started_);
    return code;
  };
  try {
    citizensdk_handle_t sdk = 0;
    bool subscribed = false;
    bool callback_installed = false;
    {
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      if (close_in_progress_ || create_in_progress_) {
        return CITIZENSDK_ERROR_BUSY;
      }
      if (!lifecycle_.begin_close()) return CITIZENSDK_OK;
      close_in_progress_ = true;
      teardown_started = teardown_started_;
      if (!completion_admission_.idle()) {
        return cancel_close(CITIZENSDK_ERROR_BUSY);
      }
      if (callback_update_in_progress_ || !private_requests_.empty() ||
          (vault_ && !vault_->idle())) {
        return cancel_close(CITIZENSDK_ERROR_BUSY);
      }
      sdk = sdk_;
      subscribed = capability_subscribed_;
      callback_installed = callback_installed_;
    }

    {
      std::lock_guard<std::mutex> callback_guard(callback_lock_);
      if (callback_thread_ == std::this_thread::get_id()) {
        return cancel_close(CITIZENSDK_ERROR_BUSY);
      }
    }
    // Root calls can synchronously or concurrently re-enter Host callbacks.
    // Never hold call_lock_ across that foreign boundary.
    if (sdk != 0 && !teardown_started) {
      citizensdk_lifecycle_t core_lifecycle = 0;
      const auto lifecycle_code = citizensdk_get_lifecycle(sdk, &core_lifecycle);
      if (lifecycle_code != CITIZENSDK_OK) {
        return cancel_close(lifecycle_code);
      }
      if (core_lifecycle == CITIZENSDK_LIFECYCLE_RUNNING ||
          core_lifecycle == CITIZENSDK_LIFECYCLE_STARTING ||
          core_lifecycle == CITIZENSDK_LIFECYCLE_IMPORTING_STATE) {
        return cancel_close(CITIZENSDK_ERROR_BUSY);
      }
    }

    // Do not clear the application's observer until the cheap lifecycle gate
    // proves teardown can progress. A BUSY close therefore leaves an otherwise
    // open Host fully observable and retryable.
    const auto public_callback_code = set_event_callback(nullptr, nullptr);
    if (public_callback_code != CITIZENSDK_OK) {
      return cancel_close(public_callback_code);
    }

    if (sdk != 0 && subscribed) {
      {
        std::lock_guard<std::recursive_mutex> guard(call_lock_);
        teardown_started_ = true;
        teardown_started = true;
      }
      const auto code = citizensdk_unsubscribe_capability_changes(sdk);
      if (code != CITIZENSDK_OK) return cancel_close(code);
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      capability_subscribed_ = false;
    }
    if (sdk != 0 && callback_installed) {
      {
        std::lock_guard<std::recursive_mutex> guard(call_lock_);
        teardown_started_ = true;
        teardown_started = true;
      }
      const auto code = citizensdk_set_event_callback(sdk, nullptr, nullptr);
      if (code != CITIZENSDK_OK) return cancel_close(code);
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      callback_installed_ = false;
    }
    if (sdk != 0) {
      {
        std::lock_guard<std::recursive_mutex> guard(call_lock_);
        teardown_started_ = true;
        teardown_started = true;
      }
      const auto code = citizensdk_destroy(sdk);
      if (code != CITIZENSDK_OK) return cancel_close(code);
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      sdk_ = 0;
    }

    // Core 已释放后仍必须等 Win32 所在线程确认 HWND 退休；BUSY 保留整个
    // Host/store/vault 所有权供 supervisor 重试，禁止跨线程 DestroyWindow。
    const auto window_code = parent_window_.retire();
    if (window_code != CITIZENSDK_OK) return cancel_close(window_code);

    {
      // A successful Core destroy guarantees its host-service borrows and
      // callbacks have ended. begin_close() has already rejected active service
      // leases and closed new service admission. The call lock now commits
      // resource retirement without ever waiting for a Win32 provider callback.
      std::lock_guard<std::recursive_mutex> guard(call_lock_);
      services_retired_ = true;
      vault_.reset();
      if (secure_store_) secure_store_->close();
      secure_store_.reset();
      if (public_store_) public_store_->close();
      close_in_progress_ = false;
      lifecycle_.commit_closed();
    }
    return CITIZENSDK_OK;
  } catch (...) {
    return cancel_close(map_exception());
  }
}

uint64_t HostBridge::reserve_wallet_flow() {
  std::lock_guard<std::recursive_mutex> guard(call_lock_);
  require(!create_in_progress_ && !close_in_progress_ && !teardown_started_ &&
              !services_retired_,
          CITIZENSDK_ERROR_INVALID_STATE,
          "CitizenSDK Host cannot start a wallet flow while closing");
  require(std::this_thread::get_id() == ui_thread_, CITIZENSDK_ERROR_BUSY,
          "CitizenSDK wallet UI must be presented on its Win32 owner thread");
  return lifecycle_.reserve_wallet_flow();
}
void HostBridge::finish_wallet_flow(uint64_t token) noexcept { lifecycle_.finish_wallet_flow(token); }

citizensdk_error_code_t HostBridge::submit_private(
    const std::function<citizensdk_error_code_t(citizensdk_request_id_t *)> &accept,
    RequestRouter::Handler handler, citizensdk_request_id_t *out_request) {
  if (!accept || !handler || out_request == nullptr) {
    return CITIZENSDK_ERROR_INVALID_ARGUMENT;
  }
  *out_request = 0;
  std::lock_guard<std::mutex> submission(private_submit_lock_);
  {
    std::lock_guard<std::recursive_mutex> call(call_lock_);
    if (sdk_ == 0 || teardown_started_ || create_in_progress_ ||
        close_in_progress_ || services_retired_) {
      return CITIZENSDK_ERROR_INVALID_STATE;
    }
  }
  try {
    private_requests_.prime(std::move(handler));
    try {
      completion_admission_.begin();
    } catch (...) {
      private_requests_.cancel_primed();
      throw;
    }
  } catch (...) {
    return map_exception();
  }
  citizensdk_request_id_t request = 0;
  citizensdk_error_code_t code = CITIZENSDK_ERROR_INTERNAL;
  try {
    code = accept(&request);
  } catch (...) {
    code = map_exception();
  }
  if (request == 0) {
    private_requests_.cancel_primed();
    completion_admission_.publish_route();
    *out_request = request;
    return code == CITIZENSDK_OK ? CITIZENSDK_ERROR_INTEGRITY : code;
  }
  // The handler was fully allocated before accept(). Binding the integer ID is
  // non-allocating, so every accepted result—including a successful prepared
  // wallet hidden inside an error-returning acceptance—has a cleanup owner.
  private_requests_.bind(request);
  completion_admission_.publish_route();
  *out_request = request;
  return code;
}

HostRecord HostBridge::chain_load() {
  return service_call([&] { return public_store_->chain_database_load(); });
}
HostRecord HostBridge::chain_cas(uint64_t expected, const Bytes &candidate) {
  return service_call([&] {
    return public_store_->chain_database_compare_and_swap(expected, candidate);
  });
}
HostRecord HostBridge::runtime_load(const std::array<uint8_t, 32> &hash) {
  return service_call([&] { return public_store_->runtime_cache_load(hash); });
}
void HostBridge::runtime_store(const std::array<uint8_t, 32> &hash,
                               const Bytes &candidate) {
  service_call([&] { public_store_->runtime_cache_store(hash, candidate); });
}
void HostBridge::runtime_delete(const std::array<uint8_t, 32> &hash) {
  service_call([&] { public_store_->runtime_cache_delete(hash); });
}
HostRecord HostBridge::history_query(const Bytes &query) {
  return service_call([&] { return public_store_->transaction_history_query(query); });
}
HostRecord HostBridge::history_mutate(uint64_t expected, const Bytes &mutation) {
  return service_call([&] {
    return public_store_->transaction_history_mutate(expected, mutation);
  });
}
HostRecord HostBridge::profile_load() {
  return service_call([&] {
    require(secure_store_ != nullptr, CITIZENSDK_ERROR_UNSUPPORTED,
            "wallet host is disabled");
    return secure_store_->wallet_profile_load();
  });
}
HostRecord HostBridge::profile_cas(uint64_t expected, const Bytes &candidate) {
  return service_call([&] {
    require(secure_store_ != nullptr, CITIZENSDK_ERROR_UNSUPPORTED,
            "wallet host is disabled");
    return secure_store_->wallet_profile_compare_and_swap(expected, candidate);
  });
}
HostRecord HostBridge::secret_load(const SecretIdentity &identity) {
  return service_call([&] {
    require(secure_store_ != nullptr, CITIZENSDK_ERROR_UNSUPPORTED,
            "wallet host is disabled");
    return secure_store_->encrypted_secret_load(identity);
  });
}
HostRecord HostBridge::secret_cas(const SecretIdentity &identity,
                                  uint64_t expected,
                                  const Bytes &candidate) {
  return service_call([&] {
    require(secure_store_ != nullptr, CITIZENSDK_ERROR_UNSUPPORTED,
            "wallet host is disabled");
    return secure_store_->encrypted_secret_compare_and_swap(identity, expected,
                                                             candidate);
  });
}
void HostBridge::vault_ensure(
    const WalletKey &key, const std::array<uint8_t, 16> &operation_id) {
  service_call([&] {
    require(vault_ != nullptr, CITIZENSDK_ERROR_UNSUPPORTED,
            "wallet host is disabled");
    vault_->ensure_wallet_kek(key, operation_id);
  });
}
bool HostBridge::vault_has(const WalletKey &key) {
  return service_call([&] {
    require(vault_ != nullptr, CITIZENSDK_ERROR_UNSUPPORTED,
            "wallet host is disabled");
    return vault_->has_wallet_kek(key);
  });
}
Bytes HostBridge::vault_wrap(
    const WalletKey &key, const std::array<uint8_t, 16> &operation_id,
    const uint8_t plaintext_dek[32]) {
  return service_call([&] {
    require(vault_ != nullptr, CITIZENSDK_ERROR_UNSUPPORTED,
            "wallet host is disabled");
    return vault_->wrap_dek(key, operation_id, plaintext_dek);
  });
}
void HostBridge::vault_unwrap(uint64_t host_operation_id, const WalletKey &key,
                              const Bytes &wrapped_dek,
                              uint8_t plaintext_dek_out[32]) {
  service_call([&] {
    require(vault_ != nullptr, CITIZENSDK_ERROR_UNSUPPORTED,
            "wallet host is disabled");
    vault_->unwrap_dek(host_operation_id, key, wrapped_dek,
                       plaintext_dek_out);
  });
}
void HostBridge::vault_retire(
    const WalletKey &key, const std::array<uint8_t, 16> &operation_id) {
  service_call([&] {
    require(vault_ != nullptr, CITIZENSDK_ERROR_UNSUPPORTED,
            "wallet host is disabled");
    vault_->retire_wallet_kek(key, operation_id);
  });
}

}  // namespace citizen_sdk::windows
