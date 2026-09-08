#include "citizensdk_jni_support.hpp"

#include <algorithm>
#include <array>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "citizensdk_host_bridge.hpp"
#include "citizensdk_internal.h"
#include "citizensdk_qr_image.h"

namespace citizen::sdk::jni {
namespace {

constexpr uint32_t kWireVersion = 1;
constexpr int32_t kOk = CITIZENSDK_OK;
constexpr jsize kMaxWalletSecretBytes = 1024;
constexpr jsize kMaxTransferRemarkBytes = 99;
constexpr jsize kMaxWalletAccountIndices = 1989;
constexpr size_t kMaxQrTextBytes = 2331;
constexpr size_t kMaxQrReviewBytes = 1920;
constexpr size_t kMaxQrImageBytes = 16U * 1024U * 1024U;
std::mutex g_bridges_mutex;
std::unordered_map<intptr_t, std::shared_ptr<CitizenSdkHostBridge>> g_bridges;

// 私有显示 context 不进入公开头或普通结果编码；只在 Core 全生命周期请求结束后释放。
struct PrivateKeyViewContext {
  JavaVM *vm;
  jobject owner;
  jmethodID display;
  jmethodID settled;
  jmethodID authorizing;
};

class PrivateKeyViewEnv final {
 public:
  explicit PrivateKeyViewEnv(JavaVM *vm) : vm_(vm) {
    const jint code = vm_->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
    if (code == JNI_EDETACHED) attached_ = vm_->AttachCurrentThread(&env, nullptr) == JNI_OK;
    else if (code != JNI_OK) env = nullptr;
  }
  ~PrivateKeyViewEnv() { if (attached_) vm_->DetachCurrentThread(); }
  JNIEnv *env = nullptr;
 private:
  JavaVM *vm_;
  bool attached_ = false;
};

int32_t private_key_display(void *raw, uint64_t view_id, citizensdk_bytes_view_t bytes) {
  auto *context = static_cast<PrivateKeyViewContext *>(raw);
  if (bytes.len != 32 || bytes.data == nullptr) return CITIZENSDK_ERROR_INTEGRITY;
  PrivateKeyViewEnv scope(context->vm);
  if (scope.env == nullptr) return CITIZENSDK_ERROR_UNAVAILABLE;
  // direct buffer 仅在同步调用期间借用 Rust 内存；JVM 立即转入 SDK 自有可擦字符数组。
  auto buffer = scope.env->NewDirectByteBuffer(const_cast<uint8_t *>(bytes.data), 32);
  if (buffer == nullptr) { scope.env->ExceptionClear(); return CITIZENSDK_ERROR_INTERNAL; }
  const jint code = scope.env->CallIntMethod(context->owner, context->display,
                                            static_cast<jlong>(view_id), buffer);
  scope.env->DeleteLocalRef(buffer);
  if (scope.env->ExceptionCheck()) { scope.env->ExceptionClear(); return CITIZENSDK_ERROR_INTERNAL; }
  return code;
}

void private_key_settled(void *raw, uint64_t view_id, int32_t code) {
  auto *context = static_cast<PrivateKeyViewContext *>(raw);
  PrivateKeyViewEnv scope(context->vm);
  if (scope.env == nullptr) return;
  scope.env->CallVoidMethod(context->owner, context->settled, static_cast<jlong>(view_id), code);
  if (scope.env->ExceptionCheck()) scope.env->ExceptionClear();
}

int32_t private_key_authorizing(void *raw, uint64_t view_id, uint64_t operation_id) {
  auto *context = static_cast<PrivateKeyViewContext *>(raw);
  PrivateKeyViewEnv scope(context->vm);
  if (scope.env == nullptr) return CITIZENSDK_ERROR_UNAVAILABLE;
  const jint code = scope.env->CallIntMethod(context->owner, context->authorizing,
      static_cast<jlong>(view_id), static_cast<jlong>(operation_id));
  if (scope.env->ExceptionCheck()) { scope.env->ExceptionClear(); return CITIZENSDK_ERROR_INTERNAL; }
  return code;
}

std::shared_ptr<CitizenSdkHostBridge> bridge_from(JNIEnv *env, jlong raw) {
  const intptr_t key = static_cast<intptr_t>(raw);
  std::lock_guard<std::mutex> lock(g_bridges_mutex);
  const auto found = g_bridges.find(key);
  if (key == 0 || found == g_bridges.end()) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_HANDLE,
              "CitizenSDK native session is closed");
    return {};
  }
  return found->second;
}

citizensdk_bytes_view_t view(const std::vector<uint8_t> &bytes) {
  return {bytes.empty() ? nullptr : bytes.data(),
          static_cast<uint64_t>(bytes.size())};
}

void secure_zero(std::vector<uint8_t> *bytes) {
  volatile uint8_t *cursor = bytes->data();
  for (size_t index = 0; index < bytes->size(); ++index) cursor[index] = 0;
  bytes->clear();
}

/** Owns a JNI secret copy and clears it on every success/error return path. */
class SensitiveBytes final {
 public:
  SensitiveBytes() = default;
  ~SensitiveBytes() { secure_zero(&value_); }
  SensitiveBytes(const SensitiveBytes &) = delete;
  SensitiveBytes &operator=(const SensitiveBytes &) = delete;

  std::vector<uint8_t> *out() { return &value_; }
  const std::vector<uint8_t> &value() const { return value_; }

 private:
  std::vector<uint8_t> value_;
};

bool take_wallet_secret(JNIEnv *env, jbyteArray source,
                        std::vector<uint8_t> *out) {
  if (source == nullptr) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "Wallet secret must not be null");
    return false;
  }
  const jsize length = env->GetArrayLength(source);
  if (env->ExceptionCheck()) return false;
  if (length < 0 || length > kMaxWalletSecretBytes) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "Wallet secret exceeds 1024 UTF-8 bytes");
    return false;
  }
  out->resize(static_cast<size_t>(length));
  if (length != 0) {
    env->GetByteArrayRegion(source, 0, length,
                            reinterpret_cast<jbyte *>(out->data()));
  }
  return !env->ExceptionCheck();
}

template <typename Info>
Info info_value() {
  Info value{};
  value.struct_size = sizeof(Info);
  value.abi_version = CITIZENSDK_ABI_VERSION;
  return value;
}

bool copy_error(citizensdk_result_handle_t result,
                std::vector<uint8_t> *message) {
  uint64_t required = 0;
  int32_t code = citizensdk_result_copy_error_message(result, nullptr, 0,
                                                       &required);
  if (code != kOk || required > 64 * 1024) return false;
  message->resize(static_cast<size_t>(required));
  return citizensdk_result_copy_error_message(
             result, message->empty() ? nullptr : message->data(), required,
             &required) == kOk;
}

bool copy_wallet_account(citizensdk_result_handle_t result, uint32_t index,
                         citizensdk_wallet_account_info_t *info,
                         std::vector<uint8_t> *ss58,
                         std::vector<uint8_t> *name) {
  uint64_t ss58_required = 0;
  uint64_t name_required = 0;
  *info = info_value<citizensdk_wallet_account_info_t>();
  int32_t code = citizensdk_result_get_wallet_account(
      result, index, info, nullptr, 0, &ss58_required, nullptr, 0,
      &name_required);
  if (code != kOk || ss58_required > 1024 || name_required > 1024) return false;
  ss58->resize(static_cast<size_t>(ss58_required));
  name->resize(static_cast<size_t>(name_required));
  *info = info_value<citizensdk_wallet_account_info_t>();
  return citizensdk_result_get_wallet_account(
             result, index, info, ss58->empty() ? nullptr : ss58->data(),
             ss58_required, &ss58_required,
             name->empty() ? nullptr : name->data(), name_required,
             &name_required) == kOk;
}

bool write_wallet_account(citizensdk_result_handle_t result, uint32_t index,
                          WireWriter *payload) {
  citizensdk_wallet_account_info_t account{};
  std::vector<uint8_t> ss58;
  std::vector<uint8_t> name;
  if (!copy_wallet_account(result, index, &account, &ss58, &name)) return false;
  payload->u32(account.index);
  payload->fixed(account.account_id.bytes, 32);
  payload->text(ss58);
  payload->u8(name.empty() ? 0 : 1);
  if (!name.empty()) payload->text(name);
  payload->u64(account.created_at_millis);
  payload->u8(account.is_active == 0 ? 0 : 1);
  return true;
}

bool write_wallet_profile(citizensdk_result_handle_t result,
                          WireWriter *payload) {
  auto info = info_value<citizensdk_wallet_profile_info_t>();
  if (citizensdk_result_get_wallet_profile(result, &info) != kOk) return false;
  payload->u8(info.present == 0 ? 0 : 1);
  if (info.present == 0) return true;
  uint32_t count = 0;
  if (citizensdk_result_get_wallet_account_count(result, &count) != kOk ||
      count != info.account_count || count > 1990) {
    return false;
  }
  payload->u32(info.origin);
  payload->u32(info.wallet_index);
  payload->u64(info.created_at_millis);
  payload->fixed(info.master_account_id.bytes, 32);
  payload->fixed(info.active_account_id.bytes, 32);
  payload->u32(count);
  for (uint32_t index = 0; index < count; ++index) {
    if (!write_wallet_account(result, index, payload)) return false;
  }
  return true;
}

bool write_wallet_accounts(citizensdk_result_handle_t result,
                           WireWriter *payload) {
  uint32_t count = 0;
  if (citizensdk_result_get_wallet_account_count(result, &count) != kOk ||
      count > 1990) {
    return false;
  }
  payload->u32(count);
  for (uint32_t index = 0; index < count; ++index) {
    if (!write_wallet_account(result, index, payload)) return false;
  }
  return true;
}

bool copy_wallet_transfer(citizensdk_result_handle_t result,
                          WireWriter *payload) {
  auto info = info_value<citizensdk_wallet_transfer_info_t>();
  uint64_t required = 0;
  int32_t code = citizensdk_result_get_wallet_transfer(
      result, &info, nullptr, 0, &required);
  if (code != kOk || required > 64 * 1024) return false;
  std::vector<uint8_t> reason(static_cast<size_t>(required));
  info = info_value<citizensdk_wallet_transfer_info_t>();
  if (citizensdk_result_get_wallet_transfer(
          result, &info, reason.empty() ? nullptr : reason.data(), required,
          &required) != kOk) {
    return false;
  }
  payload->fixed(info.transaction_hash, 32);
  payload->u32(info.resolution);
  payload->u8(info.has_execution == 0 ? 0 : 1);
  if (info.has_execution != 0) write_execution(payload, info.execution);
  payload->u8(reason.empty() ? 0 : 1);
  if (!reason.empty()) payload->text(reason);
  return true;
}

bool copy_history_record(citizensdk_result_handle_t result, uint32_t index,
                         WireWriter *payload) {
  auto info = info_value<citizensdk_history_record_info_t>();
  uint64_t remark_required = 0;
  uint64_t reason_required = 0;
  int32_t code = citizensdk_result_get_history_record(
      result, index, &info, nullptr, 0, &remark_required, nullptr, 0,
      &reason_required);
  if (code != kOk || remark_required > 64 * 1024 ||
      reason_required > 64 * 1024) return false;
  std::vector<uint8_t> remark(static_cast<size_t>(remark_required));
  std::vector<uint8_t> reason(static_cast<size_t>(reason_required));
  info = info_value<citizensdk_history_record_info_t>();
  if (citizensdk_result_get_history_record(
          result, index, &info, remark.empty() ? nullptr : remark.data(),
          remark_required, &remark_required,
          reason.empty() ? nullptr : reason.data(), reason_required,
          &reason_required) != kOk) {
    return false;
  }
  payload->fixed(info.account_id.bytes, 32);
  payload->fixed(info.transaction_hash, 32);
  payload->u64(info.nonce);
  payload->fixed(info.destination_account_id.bytes, 32);
  payload->u64(info.amount_fen.low);
  payload->u64(info.amount_fen.high);
  payload->u32(info.status);
  payload->u8(info.has_block == 0 ? 0 : 1);
  if (info.has_block != 0) write_block(payload, info.block);
  payload->u8(info.has_execution == 0 ? 0 : 1);
  if (info.has_execution != 0) write_execution(payload, info.execution);
  payload->u64(info.created_at_millis);
  payload->u64(info.updated_at_millis);
  payload->bytes(remark.data(), remark.size());
  payload->u8(reason.empty() ? 0 : 1);
  if (!reason.empty()) payload->text(reason);
  return true;
}

bool copy_finalized_transfer(citizensdk_result_handle_t result, uint32_t index,
                             WireWriter *payload) {
  auto info = info_value<citizensdk_finalized_transfer_info_t>();
  uint64_t pallet_required = 0;
  uint64_t display_required = 0;
  uint64_t remark_required = 0;
  int32_t code = citizensdk_result_get_finalized_transfer(
      result, index, &info, nullptr, 0, &pallet_required, nullptr, 0,
      &display_required, nullptr, 0, &remark_required);
  if (code != kOk || pallet_required > 1024 || display_required > 64 * 1024 ||
      remark_required > 64 * 1024) return false;
  std::vector<uint8_t> pallet(static_cast<size_t>(pallet_required));
  std::vector<uint8_t> display(static_cast<size_t>(display_required));
  std::vector<uint8_t> remark(static_cast<size_t>(remark_required));
  info = info_value<citizensdk_finalized_transfer_info_t>();
  if (citizensdk_result_get_finalized_transfer(
          result, index, &info, pallet.empty() ? nullptr : pallet.data(),
          pallet_required, &pallet_required,
          display.empty() ? nullptr : display.data(), display_required,
          &display_required, remark.empty() ? nullptr : remark.data(),
          remark_required, &remark_required) != kOk) {
    return false;
  }
  payload->fixed(info.tracked_account_id.bytes, 32);
  payload->fixed(info.from_account_id.bytes, 32);
  payload->fixed(info.to_account_id.bytes, 32);
  payload->u64(info.amount_fen.low);
  payload->u64(info.amount_fen.high);
  write_block(payload, info.block);
  payload->u32(info.event_record_index);
  payload->u8(info.has_extrinsic_index == 0 ? 0 : 1);
  if (info.has_extrinsic_index != 0) payload->u32(info.extrinsic_index);
  payload->u32(info.direction);
  payload->text(pallet);
  payload->text(display);
  payload->bytes(remark.data(), remark.size());
  return true;
}

bool write_history(citizensdk_result_handle_t result, WireWriter *payload) {
  auto info = info_value<citizensdk_history_info_t>();
  if (citizensdk_result_get_history_info(result, &info) != kOk ||
      info.cursor_count > 1990 || info.record_count > 100000 ||
      info.transfer_count > 100000) return false;
  payload->u64(info.revision);
  payload->u32(info.cursor_count);
  for (uint32_t index = 0; index < info.cursor_count; ++index) {
    auto cursor = info_value<citizensdk_history_cursor_info_t>();
    if (citizensdk_result_get_history_cursor(result, index, &cursor) != kOk)
      return false;
    payload->fixed(cursor.account_id.bytes, 32);
    write_block(payload, cursor.tracking_start_block);
    write_block(payload, cursor.last_synced_block);
  }
  payload->u32(info.record_count);
  for (uint32_t index = 0; index < info.record_count; ++index) {
    if (!copy_history_record(result, index, payload)) return false;
  }
  payload->u32(info.transfer_count);
  for (uint32_t index = 0; index < info.transfer_count; ++index) {
    if (!copy_finalized_transfer(result, index, payload)) return false;
  }
  return true;
}

void write_failure(WireWriter *writer, int32_t code, uint32_t kind,
                   const std::vector<uint8_t> &message) {
  writer->u32(kWireVersion);
  writer->i32(code);
  writer->u32(kind);
  writer->text(message);
}

void write_internal_decode_failure(WireWriter *writer) {
  static const std::vector<uint8_t> message = {
      'J','N','I',' ','c','o','u','l','d',' ','n','o','t',' ','d','e','c','o','d','e',' ',
      't','h','e',' ','C','o','r','e',' ','r','e','s','u','l','t'};
  write_failure(writer, CITIZENSDK_ERROR_INTEGRITY, 0, message);
}

template <typename Call>
jlong begin_request(JNIEnv *env,
                    const std::shared_ptr<CitizenSdkHostBridge> &bridge,
                    Call call) {
  citizensdk_request_id_t request = 0;
  const int32_t code = call(bridge->handle(), &request);
  if (code != kOk || request == 0 ||
      request > static_cast<uint64_t>(std::numeric_limits<jlong>::max())) {
    if (code == kOk && request != 0) {
      // The Core accepted the work but its identity cannot cross the Java
      // boundary. Cancel that exact request instead of creating an orphan.
      citizensdk_cancel_request(bridge->handle(), request);
    }
    throw_sdk(env, code == kOk ? CITIZENSDK_ERROR_INTERNAL : code,
              "CitizenSDK request was rejected");
    return 0;
  }
  return static_cast<jlong>(request);
}

bool account(JNIEnv *env, jbyteArray source, citizensdk_account_id_t *out) {
  std::vector<uint8_t> bytes;
  if (!take_bytes(env, source, &bytes) || bytes.size() != 32) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "CitizenChain AccountId must contain 32 bytes");
    return false;
  }
  std::memcpy(out->bytes, bytes.data(), 32);
  return true;
}

bool accounts(JNIEnv *env, jbyteArray source, jint count,
              std::vector<citizensdk_account_id_t> *out, bool allow_empty = false) {
  std::vector<uint8_t> bytes;
  if (count < 0 || (!allow_empty && count == 0) || count > 1990 || !take_bytes(env, source, &bytes) ||
      bytes.size() != static_cast<size_t>(count) * 32) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "CitizenChain account array is invalid");
    return false;
  }
  out->resize(static_cast<size_t>(count));
  if (!bytes.empty()) std::memcpy(out->data(), bytes.data(), bytes.size());
  return true;
}

// JNI methods ----------------------------------------------------------------

jlong native_create(JNIEnv *env, jobject, jobject host_services,
                    jbyteArray manifest, jbyteArray chain_spec,
                    jbyteArray sync_state, jint modules) {
  std::vector<uint8_t> manifest_bytes;
  std::vector<uint8_t> chain_bytes;
  std::vector<uint8_t> sync_bytes;
  if (host_services == nullptr || !take_bytes(env, manifest, &manifest_bytes) ||
      !take_bytes(env, chain_spec, &chain_bytes) ||
      !take_bytes(env, sync_state, &sync_bytes)) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "CitizenSDK assets or host services are invalid");
    return 0;
  }
  JavaVM *vm = nullptr;
  if (env->GetJavaVM(&vm) != JNI_OK) return 0;
  auto bridge = std::shared_ptr<CitizenSdkHostBridge>(
      new (std::nothrow) CitizenSdkHostBridge(vm, env, host_services));
  if (!bridge) {
    throw_sdk(env, CITIZENSDK_ERROR_INTERNAL, "CitizenSDK JNI allocation failed");
    return 0;
  }
  if (!bridge->create(env, manifest_bytes, chain_bytes, sync_bytes, static_cast<uint32_t>(modules))) {
    return 0;
  }
  {
    std::lock_guard<std::mutex> lock(g_bridges_mutex);
    g_bridges.emplace(reinterpret_cast<intptr_t>(bridge.get()), bridge);
  }
  return static_cast<jlong>(reinterpret_cast<intptr_t>(bridge.get()));
}

void native_bind(JNIEnv *env, jobject owner, jlong raw) {
  if (auto bridge = bridge_from(env, raw)) bridge->bind(env, owner);
}

jint native_lifecycle(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  if (bridge == nullptr) return 0;
  citizensdk_lifecycle_t lifecycle = 0;
  const int32_t code = citizensdk_get_lifecycle(bridge->handle(), &lifecycle);
  if (code != kOk) {
    throw_sdk(env, code, "CitizenSDK lifecycle query failed");
    return 0;
  }
  return static_cast<jint>(lifecycle);
}

jbyteArray native_capabilities(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  if (bridge == nullptr) return nullptr;
  WireWriter writer;
  if (!encode_capabilities(bridge->handle(), &writer)) {
    throw_sdk(env, CITIZENSDK_ERROR_INTERNAL,
              "CitizenSDK capability query failed");
    return nullptr;
  }
  return to_byte_array(env, writer.data());
}

jlong native_refresh_capabilities(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  return bridge == nullptr ? 0 : begin_request(
      env, bridge, [](auto handle, auto *out) {
        return citizensdk_refresh_capabilities(handle, out);
      });
}

jlong native_start(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  return bridge == nullptr ? 0 : begin_request(
      env, bridge, [](auto handle, auto *out) { return citizensdk_start(handle, out); });
}

jlong native_stop(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  return bridge == nullptr ? 0 : begin_request(
      env, bridge, [](auto handle, auto *out) { return citizensdk_stop(handle, out); });
}

jboolean native_cancel(JNIEnv *env, jobject, jlong raw, jlong request_id) {
  auto bridge = bridge_from(env, raw);
  if (bridge == nullptr || request_id <= 0) return JNI_FALSE;
  const int32_t code = citizensdk_cancel_request(
      bridge->handle(), static_cast<uint64_t>(request_id));
  if (code == kOk) return JNI_TRUE;
  if (code == CITIZENSDK_ERROR_NOT_FOUND || code == CITIZENSDK_ERROR_INVALID_STATE)
    return JNI_FALSE;
  throw_sdk(env, code, "CitizenSDK request cannot be cancelled");
  return JNI_FALSE;
}

jlong native_finalized_head(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  return bridge == nullptr ? 0 : begin_request(
      env, bridge, [](auto handle, auto *out) { return citizensdk_get_finalized_head(handle, out); });
}

jbyteArray native_genesis_hash(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  if (bridge == nullptr) return nullptr;
  std::vector<uint8_t> output(32);
  const int32_t code = citizensdk_get_genesis_hash(bridge->handle(), output.data());
  if (code != kOk) {
    throw_sdk(env, code, "CitizenSDK genesis hash query failed");
    return nullptr;
  }
  return to_byte_array(env, output);
}

jlong native_balance(JNIEnv *env, jobject, jlong raw, jbyteArray account_bytes) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t value{};
  if (bridge == nullptr || !account(env, account_bytes, &value)) return 0;
  return begin_request(env, bridge, [&value](auto handle, auto *out) {
    return citizensdk_get_finalized_account_balance(handle, &value, out);
  });
}

jlong native_balances(JNIEnv *env, jobject, jlong raw, jbyteArray account_bytes, jint count) {
  auto bridge = bridge_from(env, raw);
  std::vector<citizensdk_account_id_t> values;
  if (bridge == nullptr || !accounts(env, account_bytes, count, &values, true)) return 0;
  // 空列表也提交 Core，让模块与生命周期校验沿同一入口执行。
  return begin_request(env, bridge, [&values](auto handle, auto *out) {
    return citizensdk_get_finalized_account_balances(
        handle, values.data(), static_cast<uint32_t>(values.size()), out);
  });
}

jlong native_nonce(JNIEnv *env, jobject, jlong raw, jbyteArray account_bytes) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t value{};
  if (bridge == nullptr || !account(env, account_bytes, &value)) return 0;
  return begin_request(env, bridge, [&value](auto handle, auto *out) {
    return citizensdk_get_account_nonce(handle, &value, out);
  });
}

jlong native_fee(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  return bridge == nullptr ? 0 : begin_request(env, bridge, [](auto handle, auto *out) {
    return citizensdk_get_best_fee_snapshot(handle, out);
  });
}

jlong native_wallet_profile(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  return bridge == nullptr ? 0 : begin_request(env, bridge, [](auto handle, auto *out) {
    return citizensdk_get_wallet_profile(handle, out);
  });
}

jlongArray native_open_private_key_view(JNIEnv *env, jobject, jlong raw,
                                       jbyteArray account_bytes, jobject owner) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t value{};
  if (!bridge || owner == nullptr || !account(env, account_bytes, &value)) return nullptr;
  auto output = env->NewLongArray(3);
  if (output == nullptr) return nullptr;
  auto type = env->GetObjectClass(owner);
  auto display = env->GetMethodID(type, "display", "(JLjava/nio/ByteBuffer;)I");
  auto settled = env->GetMethodID(type, "settled", "(JI)V");
  auto authorizing = env->GetMethodID(type, "authorizing", "(JJ)I");
  env->DeleteLocalRef(type);
  if (env->ExceptionCheck()) return nullptr;
  auto context = std::unique_ptr<PrivateKeyViewContext>(new (std::nothrow) PrivateKeyViewContext{
      bridge->vm(), env->NewGlobalRef(owner), display, settled, authorizing});
  if (!context || context->owner == nullptr) return nullptr;
  citizensdk_internal_private_key_view_v1_t view{};
  view.struct_size = sizeof(view); view.abi_version = 1; view.context = context.get();
  view.display = private_key_display; view.settled = private_key_settled;
  view.authorizing = private_key_authorizing;
  uint64_t view_id = 0;
  citizensdk_request_id_t request_id = 0;
  const int32_t code = citizensdk_internal_private_key_view_open(
      bridge->handle(), &value, &view, &view_id, &request_id);
  if (code != CITIZENSDK_OK) {
    env->DeleteGlobalRef(context->owner);
    throw_sdk(env, code, "Private key view admission failed");
    return nullptr;
  }
  const jlong identities[] = {static_cast<jlong>(request_id), static_cast<jlong>(view_id),
      static_cast<jlong>(reinterpret_cast<intptr_t>(context.release()))};
  env->SetLongArrayRegion(output, 0, 3, identities);
  return output;
}

void native_reveal_private_key_view(JNIEnv *env, jobject, jlong raw, jlong view_id) {
  auto bridge = bridge_from(env, raw);
  if (!bridge) return;
  const int32_t code = citizensdk_internal_private_key_view_reveal(bridge->handle(), view_id);
  if (code != CITIZENSDK_OK) throw_sdk(env, code, "Private key view reveal failed");
}
void native_cancel_private_key_view(JNIEnv *env, jobject, jlong raw, jlong view_id) {
  auto bridge = bridge_from(env, raw);
  if (!bridge) return;
  const int32_t code = citizensdk_internal_private_key_view_cancel(bridge->handle(), view_id);
  if (code != CITIZENSDK_OK) throw_sdk(env, code, "Private key view cancellation failed");
}
void native_finish_private_key_view(JNIEnv *env, jobject, jlong raw, jlong view_id) {
  auto bridge = bridge_from(env, raw);
  if (!bridge) return;
  const int32_t code = citizensdk_internal_private_key_view_finish(bridge->handle(), view_id);
  if (code != CITIZENSDK_OK) throw_sdk(env, code, "Private key view finish failed");
}
void native_release_private_key_view_context(JNIEnv *env, jobject, jlong raw) {
  auto context = std::unique_ptr<PrivateKeyViewContext>(reinterpret_cast<PrivateKeyViewContext *>(raw));
  if (context) env->DeleteGlobalRef(context->owner);
}

jlong native_set_active(JNIEnv *env, jobject, jlong raw, jbyteArray account_bytes) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t value{};
  if (bridge == nullptr || !account(env, account_bytes, &value)) return 0;
  return begin_request(env, bridge, [&value](auto handle, auto *out) {
    return citizensdk_set_active_wallet_account(handle, &value, out);
  });
}

jlong native_rename(JNIEnv *env, jobject, jlong raw, jbyteArray account_bytes,
                    jbyteArray name_bytes) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t value{};
  std::vector<uint8_t> name;
  if (bridge == nullptr || !account(env, account_bytes, &value) ||
      !take_bytes(env, name_bytes, &name)) return 0;
  return begin_request(env, bridge, [&value, &name](auto handle, auto *out) {
    return citizensdk_rename_wallet_account(handle, &value, view(name), out);
  });
}

jlong native_delete_account(JNIEnv *env, jobject, jlong raw,
                            jbyteArray account_bytes) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t value{};
  if (bridge == nullptr || !account(env, account_bytes, &value)) return 0;
  return begin_request(env, bridge, [&value](auto handle, auto *out) {
    return citizensdk_delete_wallet_account(handle, &value, out);
  });
}

jlong native_delete_wallet(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  return bridge == nullptr ? 0 : begin_request(env, bridge, [](auto handle, auto *out) {
    return citizensdk_delete_wallet(handle, out);
  });
}

jlong native_reconcile(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  return bridge == nullptr ? 0 : begin_request(env, bridge, [](auto handle, auto *out) {
    return citizensdk_reconcile_wallet_cleanup(handle, out);
  });
}

jlong native_sign(JNIEnv *env, jobject, jlong raw, jbyteArray account_bytes,
                  jbyteArray message_bytes) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t value{};
  std::vector<uint8_t> message;
  if (message_bytes == nullptr ||
      env->GetArrayLength(message_bytes) > 16 * 1024 * 1024) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "Sign payload exceeds 16 MiB");
    return 0;
  }
  if (bridge == nullptr || !account(env, account_bytes, &value) ||
      !take_bytes(env, message_bytes, &message)) return 0;
  return begin_request(env, bridge, [&value, &message](auto handle, auto *out) {
    return citizensdk_sign_wallet_payload(handle, &value, view(message), out);
  });
}

void native_validate_modules(JNIEnv *env, jclass, jint modules) {
  const int32_t code = citizensdk_validate_modules(static_cast<uint32_t>(modules));
  if (code != CITIZENSDK_OK) throw_sdk(env, code, "Invalid CitizenSDK modules");
}

// 验签无实例和金库依赖；JNI 只做有界公开输入复制与结果投影。
jboolean native_verify(JNIEnv *env, jclass, jbyteArray account_bytes,
                       jbyteArray signature_bytes, jbyteArray message_bytes) {
  citizensdk_account_id_t value{};
  std::vector<uint8_t> signature;
  std::vector<uint8_t> message;
  if (signature_bytes == nullptr || env->GetArrayLength(signature_bytes) != 64 ||
      message_bytes == nullptr || env->GetArrayLength(message_bytes) > 16 * 1024 * 1024) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT, "Verification input length is invalid");
    return JNI_FALSE;
  }
  if (!account(env, account_bytes, &value) ||
      !take_bytes(env, signature_bytes, &signature) || !take_bytes(env, message_bytes, &message)) return JNI_FALSE;
  uint8_t valid = 0;
  const int32_t code = citizensdk_verify_signature(&value, view(signature), view(message), &valid);
  if (code != CITIZENSDK_OK) {
    throw_sdk(env, code, "CitizenSDK signature verification failed");
    return JNI_FALSE;
  }
  if (valid > 1) {
    throw_sdk(env, CITIZENSDK_ERROR_INTEGRITY, "Invalid Core verification result");
    return JNI_FALSE;
  }
  return valid == 1 ? JNI_TRUE : JNI_FALSE;
}

jlong native_transfer(JNIEnv *env, jobject, jlong raw, jbyteArray source_bytes,
                      jbyteArray destination_bytes, jlong low, jlong high,
                      jbyteArray remark_bytes) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t source{};
  citizensdk_account_id_t destination{};
  std::vector<uint8_t> remark;
  if (remark_bytes == nullptr ||
      env->GetArrayLength(remark_bytes) > kMaxTransferRemarkBytes) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "Transfer remark exceeds 99 UTF-8 bytes");
    return 0;
  }
  if (bridge == nullptr || !account(env, source_bytes, &source) ||
      !account(env, destination_bytes, &destination) ||
      !take_bytes(env, remark_bytes, &remark)) return 0;
  citizensdk_u128_t amount{static_cast<uint64_t>(low), static_cast<uint64_t>(high)};
  return begin_request(env, bridge,
                       [&source, &destination, amount, &remark](auto handle, auto *out) {
    return citizensdk_transfer_with_remark(handle, &source, &destination,
                                           amount, view(remark), out);
  });
}

jlong native_history(JNIEnv *env, jlong raw, jbyteArray account_bytes,
                     jint count, bool initialize) {
  auto bridge = bridge_from(env, raw);
  std::vector<citizensdk_account_id_t> values;
  if (bridge == nullptr || !accounts(env, account_bytes, count, &values)) return 0;
  return begin_request(env, bridge, [&values, initialize](auto handle, auto *out) {
    return initialize
               ? citizensdk_initialize_finalized_history(
                     handle, values.data(), static_cast<uint32_t>(values.size()), out)
               : citizensdk_sync_finalized_history_batch(
                     handle, values.data(), static_cast<uint32_t>(values.size()), out);
  });
}

jlong native_history_initialize(JNIEnv *env, jobject, jlong raw,
                                jbyteArray values, jint count) {
  return native_history(env, raw, values, count, true);
}

jlong native_history_sync(JNIEnv *env, jobject, jlong raw, jbyteArray values,
                          jint count) {
  return native_history(env, raw, values, count, false);
}

// 输入检查无持久化副作用，错误消息来自 Core 固定模板，不回显秘密。
void wallet_input_error(JNIEnv *env, int32_t code) {
  if (code == kOk) return;
  uint64_t required = 0;
  std::vector<uint8_t> message;
  if (citizensdk_last_error_copy(nullptr, 0, &required) == kOk && required < 4096) {
    message.resize(static_cast<size_t>(required) + 1, 0);
    if (citizensdk_last_error_copy(message.data(), required, &required) == kOk) {
      throw_sdk(env, code, reinterpret_cast<const char *>(message.data()));
      return;
    }
  }
  throw_sdk(env, code, "Wallet input validation failed");
}

void native_validate_password(JNIEnv *env, jobject, jbyteArray input) {
  SensitiveBytes bytes;
  if (!take_wallet_secret(env, input, bytes.out())) return;
  wallet_input_error(env, citizensdk_validate_wallet_password(view(bytes.value())));
}

void native_validate_mnemonic(JNIEnv *env, jobject, jbyteArray input, jint words) {
  SensitiveBytes bytes;
  if (!take_wallet_secret(env, input, bytes.out())) return;
  wallet_input_error(env, citizensdk_validate_wallet_mnemonic(view(bytes.value()), static_cast<uint32_t>(words)));
}

jbyteArray native_word_suggestions(JNIEnv *env, jobject, jbyteArray input) {
  SensitiveBytes bytes;
  if (!take_wallet_secret(env, input, bytes.out())) return nullptr;
  uint64_t required = 0;
  auto code = citizensdk_wallet_word_suggestions(view(bytes.value()), nullptr, 0, &required);
  if (code != kOk) { wallet_input_error(env, code); return nullptr; }
  if (required > 128) { throw_sdk(env, CITIZENSDK_ERROR_INTEGRITY, "Wallet suggestions exceed limit"); return nullptr; }
  SensitiveBytes output;
  output.out()->resize(static_cast<size_t>(required));
  code = citizensdk_wallet_word_suggestions(view(bytes.value()), output.out()->data(), required, &required);
  if (code != kOk) { wallet_input_error(env, code); return nullptr; }
  auto result = env->NewByteArray(static_cast<jsize>(required));
  if (result != nullptr && required != 0) env->SetByteArrayRegion(result, 0, static_cast<jsize>(required), reinterpret_cast<const jbyte *>(output.value().data()));
  return result;
}

jlong native_prepare(JNIEnv *env, jobject, jlong raw, jint words,
                     jbyteArray password_bytes) {
  auto bridge = bridge_from(env, raw);
  SensitiveBytes password;
  if (bridge == nullptr || !take_wallet_secret(env, password_bytes, password.out())) return 0;
  return begin_request(env, bridge, [&password, words](auto handle, auto *out) {
    return citizensdk_prepare_wallet_creation(handle, static_cast<uint32_t>(words),
                                              view(password.value()), out);
  });
}

jlong native_import(JNIEnv *env, jobject, jlong raw, jbyteArray mnemonic_bytes,
                    jbyteArray password_bytes) {
  auto bridge = bridge_from(env, raw);
  SensitiveBytes mnemonic;
  SensitiveBytes password;
  if (bridge == nullptr ||
      !take_wallet_secret(env, mnemonic_bytes, mnemonic.out()) ||
      !take_wallet_secret(env, password_bytes, password.out())) return 0;
  return begin_request(env, bridge,
                                     [&mnemonic, &password](auto handle, auto *out) {
    return citizensdk_import_wallet(handle, view(mnemonic.value()),
                                    view(password.value()), out);
  });
}

jlong native_add_accounts(JNIEnv *env, jobject, jlong raw,
                          jbyteArray mnemonic_bytes, jbyteArray password_bytes,
                          jintArray index_values) {
  auto bridge = bridge_from(env, raw);
  SensitiveBytes mnemonic;
  SensitiveBytes password;
  std::vector<uint32_t> indices;
  if (bridge == nullptr ||
      !take_wallet_secret(env, mnemonic_bytes, mnemonic.out()) ||
      !take_wallet_secret(env, password_bytes, password.out()) ||
      !take_ints(env, index_values, &indices)) return 0;
  return begin_request(
      env, bridge, [&mnemonic, &password, &indices](auto handle, auto *out) {
        return citizensdk_add_wallet_accounts(
            handle, view(mnemonic.value()), view(password.value()), indices.data(),
            static_cast<uint32_t>(indices.size()), out);
      });
}

jbyteArray native_copy_prepared(JNIEnv *env, jobject, jlong raw, jlong token) {
  auto bridge = bridge_from(env, raw);
  citizensdk_prepared_wallet_handle_t prepared = 0;
  if (bridge == nullptr || !bridge->prepared(static_cast<uint64_t>(token), &prepared)) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_HANDLE,
              "Prepared wallet is unknown or consumed");
    return nullptr;
  }
  uint64_t required = 0;
  int32_t code = citizensdk_prepared_wallet_copy_mnemonic(
      bridge->handle(), prepared, nullptr, 0, &required);
  if (code != kOk || required > 1024) {
    throw_sdk(env, code == kOk ? CITIZENSDK_ERROR_INTEGRITY : code,
              "Prepared recovery phrase is invalid");
    return nullptr;
  }
  std::vector<uint8_t> bytes(static_cast<size_t>(required));
  code = citizensdk_prepared_wallet_copy_mnemonic(
      bridge->handle(), prepared, bytes.data(), required, &required);
  if (code != kOk) {
    secure_zero(&bytes);
    throw_sdk(env, code, "Prepared recovery phrase could not be copied");
    return nullptr;
  }
  jbyteArray result = to_byte_array(env, bytes);
  secure_zero(&bytes);
  return result;
}

jlong native_commit_prepared(JNIEnv *env, jobject, jlong raw, jlong token) {
  auto bridge = bridge_from(env, raw);
  citizensdk_prepared_wallet_handle_t prepared = 0;
  if (bridge == nullptr || !bridge->prepared(static_cast<uint64_t>(token), &prepared)) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_HANDLE,
              "Prepared wallet is unknown or consumed");
    return 0;
  }
  citizensdk_request_id_t request = 0;
  const int32_t code = citizensdk_commit_wallet_creation(
      bridge->handle(), prepared, &request);
  if (code != kOk) {
    throw_sdk(env, code, "Prepared wallet commit was rejected");
    return 0;
  }
  citizensdk_prepared_wallet_handle_t removed = 0;
  bridge->forget_prepared(static_cast<uint64_t>(token), &removed);
  if (request == 0 ||
      request > static_cast<citizensdk_request_id_t>(
                    std::numeric_limits<jlong>::max())) {
    if (request != 0) citizensdk_cancel_request(bridge->handle(), request);
    throw_sdk(env, CITIZENSDK_ERROR_INTERNAL,
              "Core returned a request ID outside the Android contract");
    return 0;
  }
  return static_cast<jlong>(request);
}

void native_release_prepared(JNIEnv *env, jobject, jlong raw, jlong token) {
  auto bridge = bridge_from(env, raw);
  citizensdk_prepared_wallet_handle_t prepared = 0;
  if (bridge == nullptr ||
      !bridge->forget_prepared(static_cast<uint64_t>(token), &prepared)) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_HANDLE,
              "Prepared wallet is unknown or consumed");
    return;
  }
  const int32_t code = citizensdk_prepared_wallet_release(bridge->handle(), prepared);
  if (code != kOk) {
    // A rejected release did not consume the Core handle. Restore the opaque
    // facade token so the caller can retry instead of orphaning the secret.
    bridge->remember_prepared(static_cast<uint64_t>(token), prepared);
    throw_sdk(env, code, "Prepared wallet release failed");
  }
}

template <typename Call>
jbyteArray qr_core_bytes(JNIEnv *env,
                         const std::shared_ptr<CitizenSdkHostBridge> &bridge,
                         Call call, size_t prefix = 0, size_t maximum = kMaxQrTextBytes) {
  (void)bridge;  // 保持 Host/Core 租约贯穿两次变长输出调用。
  uint64_t required = 0;
  int32_t code = call(nullptr, 0, &required);
  if (code != kOk || required == 0 || required > maximum || prefix > 32) {
    throw_sdk(env, code == kOk ? CITIZENSDK_ERROR_INTEGRITY : code,
              "CitizenSDK QR output query failed");
    return nullptr;
  }
  std::vector<uint8_t> output(prefix + static_cast<size_t>(required));
  code = call(output.data() + prefix, required, &required);
  if (code != kOk || prefix + required != output.size()) {
    throw_sdk(env, code == kOk ? CITIZENSDK_ERROR_INTEGRITY : code,
              "CitizenSDK QR output copy failed");
    return nullptr;
  }
  return to_byte_array(env, output);
}

bool qr_input(JNIEnv *env, jbyteArray source, size_t maximum,
              std::vector<uint8_t> *out, const char *message) {
  if (source == nullptr || env->GetArrayLength(source) <= 0 ||
      static_cast<size_t>(env->GetArrayLength(source)) > maximum ||
      !take_bytes(env, source, out)) {
    if (!env->ExceptionCheck())
      throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT, message);
    return false;
  }
  return true;
}

jbyteArray native_qr_parse(JNIEnv *env, jobject, jlong raw, jbyteArray text_bytes) {
  auto bridge = bridge_from(env, raw);
  std::vector<uint8_t> text;
  if (!bridge ||
      !qr_input(env, text_bytes, kMaxQrTextBytes, &text, "QR text is invalid")) return nullptr;
  return qr_core_bytes(env, bridge,
      [&](uint8_t *output, uint64_t capacity, uint64_t *required) {
        return citizensdk_qr_parse(bridge->handle(), view(text), output, capacity, required);
      }, 0, 65536);
}

jbyteArray native_qr_create_request(JNIEnv *env, jobject, jlong raw, jint action,
                                    jbyteArray account_bytes, jbyteArray payload_bytes,
                                    jlong ttl) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t signer{};
  std::vector<uint8_t> payload;
  if (!bridge || action <= 0 || action > 0xffff || ttl <= 0 || ttl > 300 ||
      !account(env, account_bytes, &signer) ||
      !qr_input(env, payload_bytes, kMaxQrReviewBytes, &payload, "QR review payload is invalid")) return nullptr;
  return qr_core_bytes(env, bridge,
      [&](uint8_t *output, uint64_t capacity, uint64_t *required) {
        return citizensdk_qr_create_sign_request(
            bridge->handle(), static_cast<uint16_t>(action), &signer, view(payload),
            static_cast<uint64_t>(ttl), output, capacity, required);
      });
}

jlong native_review_qr_request(JNIEnv *env, jobject, jlong raw, jbyteArray text_bytes) {
  auto bridge = bridge_from(env, raw);
  std::vector<uint8_t> text;
  if (!bridge || !qr_input(env, text_bytes, kMaxQrTextBytes, &text, "QR sign request is invalid")) return 0;
  return begin_request(env, bridge, [&text](auto handle, auto *out) {
    return citizensdk_review_qr_sign_request(handle, view(text), out);
  });
}

jlong native_sign_qr_request(JNIEnv *env, jobject, jlong raw, jlong token) {
  auto bridge = bridge_from(env, raw);
  if (!bridge) return 0;
  if (token <= 0 || !bridge->has_qr_review(static_cast<uint64_t>(token))) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT, "QR review is not owned by this SDK");
    return 0;
  }
  return begin_request(env, bridge, [token](auto handle, auto *out) {
    return citizensdk_sign_qr_request(handle, static_cast<uint64_t>(token), out);
  });
}

void native_release_qr_review(JNIEnv *env, jobject, jlong raw, jlong token) {
  auto bridge = bridge_from(env, raw);
  if (bridge && token > 0) bridge->release_qr_review(static_cast<uint64_t>(token));
}

jbyteArray native_qr_consume_response(JNIEnv *env, jobject, jlong raw, jbyteArray text_bytes) {
  auto bridge = bridge_from(env, raw);
  std::vector<uint8_t> text;
  if (!bridge || !qr_input(env, text_bytes, kMaxQrTextBytes, &text, "QR sign response is invalid")) return nullptr;
  std::vector<uint8_t> signature(64);
  const auto code = citizensdk_qr_consume_sign_response(
      bridge->handle(), view(text), signature.data());
  if (code != kOk) { throw_sdk(env, code, "QR sign response was rejected"); return nullptr; }
  return to_byte_array(env, signature);
}

jboolean native_qr_cancel_request(JNIEnv *env, jobject, jlong raw,
                                  jbyteArray request_bytes) {
  auto bridge = bridge_from(env, raw);
  std::vector<uint8_t> request;
  if (!bridge || !qr_input(env, request_bytes, 128, &request, "QR request ID is invalid")) return JNI_FALSE;
  uint8_t cancelled = 0;
  const auto code = citizensdk_qr_cancel_sign_request(bridge->handle(), view(request), &cancelled);
  if (code != kOk || cancelled > 1) {
    throw_sdk(env, code == kOk ? CITIZENSDK_ERROR_INTEGRITY : code, "QR request cancellation failed");
    return JNI_FALSE;
  }
  return cancelled == 1 ? JNI_TRUE : JNI_FALSE;
}

jbyteArray native_qr_encode_account(JNIEnv *env, jobject, jlong raw,
                                    jbyteArray account_bytes) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t account_id{};
  if (!bridge || !account(env, account_bytes, &account_id)) return nullptr;
  return qr_core_bytes(env, bridge,
      [&](uint8_t *output, uint64_t capacity, uint64_t *required) {
        return citizensdk_qr_encode_account_id(bridge->handle(), &account_id,
                                               output, capacity, required);
      });
}

jbyteArray native_qr_encode_transfer(JNIEnv *env, jobject, jlong raw,
    jbyteArray request_bytes, jlong expires, jbyteArray account_bytes,
    jbyteArray amount_bytes, jbyteArray symbol_bytes, jbyteArray memo_bytes,
    jbyteArray bank_bytes) {
  auto bridge = bridge_from(env, raw);
  citizensdk_account_id_t account_id{};
  std::vector<uint8_t> request, amount, symbol, memo, bank;
  if (!bridge || expires <= 0 || !account(env, account_bytes, &account_id) ||
      !qr_input(env, request_bytes, 128, &request, "QR request ID is invalid") ||
      !qr_input(env, amount_bytes, 64, &amount, "QR amount is invalid") ||
      !qr_input(env, symbol_bytes, 16, &symbol, "QR symbol is invalid") ||
      memo_bytes == nullptr || env->GetArrayLength(memo_bytes) > 256 || !take_bytes(env, memo_bytes, &memo) ||
      !qr_input(env, bank_bytes, 32, &bank, "QR bank CID is invalid")) return nullptr;
  return qr_core_bytes(env, bridge,
      [&](uint8_t *output, uint64_t capacity, uint64_t *required) {
        return citizensdk_qr_encode_user_transfer(bridge->handle(), view(request),
            static_cast<uint64_t>(expires), &account_id, view(amount), view(symbol),
            view(memo), view(bank), output, capacity, required);
      });
}

citizensdk_error_code_t qr_image_error(citizensdk_qr_image_status_t status) {
  switch (status) {
    case CITIZENSDK_QR_IMAGE_INVALID_ARGUMENT:
    case CITIZENSDK_QR_IMAGE_CAPACITY_EXCEEDED: return CITIZENSDK_ERROR_INVALID_ARGUMENT;
    case CITIZENSDK_QR_IMAGE_NO_CODE: return CITIZENSDK_ERROR_NOT_FOUND;
    case CITIZENSDK_QR_IMAGE_MULTIPLE_CODES: return CITIZENSDK_ERROR_CONFLICT;
    case CITIZENSDK_QR_IMAGE_INVALID_UTF8: return CITIZENSDK_ERROR_DECODE;
    default: return CITIZENSDK_ERROR_INTERNAL;
  }
}

jbyteArray native_qr_decode_luminance(JNIEnv *env, jobject, jlong raw,
    jbyteArray data_bytes, jint width, jint height, jint stride) {
  auto bridge = bridge_from(env, raw);
  std::vector<uint8_t> data;
  if (!bridge || width <= 0 || height <= 0 || stride <= 0 ||
      data_bytes == nullptr || env->GetArrayLength(data_bytes) <= 0 ||
      env->GetArrayLength(data_bytes) > static_cast<jsize>(kMaxQrImageBytes) ||
      !take_bytes(env, data_bytes, &data)) return nullptr;
  size_t required = 0;
  auto status = citizensdk_qr_image_decode_luminance(data.data(), data.size(),
      static_cast<uint32_t>(width), static_cast<uint32_t>(height), static_cast<uint32_t>(stride),
      nullptr, 0, &required);
  if (status != CITIZENSDK_QR_IMAGE_BUFFER_TOO_SMALL || required == 0 || required > kMaxQrTextBytes) {
    throw_sdk(env, qr_image_error(status), "ZXing-C++ QR decode failed"); return nullptr;
  }
  std::vector<uint8_t> output(required);
  status = citizensdk_qr_image_decode_luminance(data.data(), data.size(),
      static_cast<uint32_t>(width), static_cast<uint32_t>(height), static_cast<uint32_t>(stride),
      output.data(), output.size(), &required);
  if (status != CITIZENSDK_QR_IMAGE_OK) {
    throw_sdk(env, qr_image_error(status), "ZXing-C++ QR decode failed"); return nullptr;
  }
  return to_byte_array(env, output);
}

jbyteArray native_qr_encode_image(JNIEnv *env, jobject, jlong raw,
                                  jbyteArray text_bytes, jint scale) {
  auto bridge = bridge_from(env, raw);
  std::vector<uint8_t> text;
  if (!bridge || scale < 1 || scale > 16 ||
      !qr_input(env, text_bytes, kMaxQrTextBytes, &text, "QR text is invalid")) {
    if (!env->ExceptionCheck() && (scale < 1 || scale > 16))
      throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT, "QR scale must be 1..16");
    return nullptr;
  }
  uint32_t width = 0, height = 0;
  size_t required = 0;
  auto status = citizensdk_qr_image_encode_text(text.data(), text.size(),
      static_cast<uint32_t>(scale), nullptr, 0, &width, &height, &required);
  if (status != CITIZENSDK_QR_IMAGE_BUFFER_TOO_SMALL || required == 0 || required > kMaxQrImageBytes) {
    throw_sdk(env, qr_image_error(status), "ZXing-C++ QR encode failed"); return nullptr;
  }
  std::vector<uint8_t> output(required + 8);
  for (uint32_t index = 0; index < 4; ++index) {
    output[index] = static_cast<uint8_t>(width >> (index * 8));
    output[index + 4] = static_cast<uint8_t>(height >> (index * 8));
  }
  status = citizensdk_qr_image_encode_text(text.data(), text.size(),
      static_cast<uint32_t>(scale), output.data() + 8, required, &width, &height, &required);
  if (status != CITIZENSDK_QR_IMAGE_OK) {
    throw_sdk(env, qr_image_error(status), "ZXing-C++ QR encode failed"); return nullptr;
  }
  return to_byte_array(env, output);
}

void native_destroy(JNIEnv *env, jobject, jlong raw) {
  auto bridge = bridge_from(env, raw);
  if (bridge == nullptr || !bridge->destroy(env)) return;
  {
    std::lock_guard<std::mutex> lock(g_bridges_mutex);
    g_bridges.erase(static_cast<intptr_t>(raw));
  }
}

void native_complete_unwrap(JNIEnv *env, jclass, jlong raw,
                            jlong operation_id, jint error_code) {
  if (auto bridge = bridge_from(env, raw)) {
    bridge->complete_unwrap(static_cast<uint64_t>(operation_id), error_code);
  }
}

const JNINativeMethod kMethods[] = {
    {const_cast<char *>("validateModules"), const_cast<char *>("(I)V"), reinterpret_cast<void *>(native_validate_modules)},
    {const_cast<char *>("verifySignature"), const_cast<char *>("([B[B[B)Z"), reinterpret_cast<void *>(native_verify)},
    {const_cast<char *>("nativeCreate"),
     const_cast<char *>("(Lorg/citizen/sdk/internal/CitizenSdkHostServices;[B[B[BI)J"),
     reinterpret_cast<void *>(native_create)},
    {const_cast<char *>("nativeBind"), const_cast<char *>("(J)V"), reinterpret_cast<void *>(native_bind)},
    {const_cast<char *>("nativeLifecycle"), const_cast<char *>("(J)I"), reinterpret_cast<void *>(native_lifecycle)},
    {const_cast<char *>("nativeCapabilities"), const_cast<char *>("(J)[B"), reinterpret_cast<void *>(native_capabilities)},
    {const_cast<char *>("nativeRefreshCapabilities"), const_cast<char *>("(J)J"), reinterpret_cast<void *>(native_refresh_capabilities)},
    {const_cast<char *>("nativeStart"), const_cast<char *>("(J)J"), reinterpret_cast<void *>(native_start)},
    {const_cast<char *>("nativeStop"), const_cast<char *>("(J)J"), reinterpret_cast<void *>(native_stop)},
    {const_cast<char *>("nativeCancel"), const_cast<char *>("(JJ)Z"), reinterpret_cast<void *>(native_cancel)},
    {const_cast<char *>("nativeGetFinalizedHead"), const_cast<char *>("(J)J"), reinterpret_cast<void *>(native_finalized_head)},
    {const_cast<char *>("nativeGetGenesisHash"), const_cast<char *>("(J)[B"), reinterpret_cast<void *>(native_genesis_hash)},
    {const_cast<char *>("nativeGetAccountBalance"), const_cast<char *>("(J[B)J"), reinterpret_cast<void *>(native_balance)},
    {const_cast<char *>("nativeGetAccountBalances"), const_cast<char *>("(J[BI)J"), reinterpret_cast<void *>(native_balances)},
    {const_cast<char *>("nativeGetAccountNonce"), const_cast<char *>("(J[B)J"), reinterpret_cast<void *>(native_nonce)},
    {const_cast<char *>("nativeGetFeeSnapshot"), const_cast<char *>("(J)J"), reinterpret_cast<void *>(native_fee)},
    {const_cast<char *>("nativeGetWalletProfile"), const_cast<char *>("(J)J"), reinterpret_cast<void *>(native_wallet_profile)},
    {const_cast<char *>("nativeOpenPrivateKeyView"), const_cast<char *>("(J[BLorg/citizen/sdk/ui/CitizenSdkPrivateKeyDisplayBuffer;)[J"), reinterpret_cast<void *>(native_open_private_key_view)},
    {const_cast<char *>("nativeRevealPrivateKeyView"), const_cast<char *>("(JJ)V"), reinterpret_cast<void *>(native_reveal_private_key_view)},
    {const_cast<char *>("nativeCancelPrivateKeyView"), const_cast<char *>("(JJ)V"), reinterpret_cast<void *>(native_cancel_private_key_view)},
    {const_cast<char *>("nativeFinishPrivateKeyView"), const_cast<char *>("(JJ)V"), reinterpret_cast<void *>(native_finish_private_key_view)},
    {const_cast<char *>("nativeReleasePrivateKeyViewContext"), const_cast<char *>("(J)V"), reinterpret_cast<void *>(native_release_private_key_view_context)},
    {const_cast<char *>("nativeSetActiveWalletAccount"), const_cast<char *>("(J[B)J"), reinterpret_cast<void *>(native_set_active)},
    {const_cast<char *>("nativeRenameWalletAccount"), const_cast<char *>("(J[B[B)J"), reinterpret_cast<void *>(native_rename)},
    {const_cast<char *>("nativeDeleteWalletAccount"), const_cast<char *>("(J[B)J"), reinterpret_cast<void *>(native_delete_account)},
    {const_cast<char *>("nativeDeleteWallet"), const_cast<char *>("(J)J"), reinterpret_cast<void *>(native_delete_wallet)},
    {const_cast<char *>("nativeReconcileWalletCleanup"), const_cast<char *>("(J)J"), reinterpret_cast<void *>(native_reconcile)},
    {const_cast<char *>("nativeSignWalletPayload"), const_cast<char *>("(J[B[B)J"), reinterpret_cast<void *>(native_sign)},
    {const_cast<char *>("nativeQrParse"), const_cast<char *>("(J[B)[B"), reinterpret_cast<void *>(native_qr_parse)},
    {const_cast<char *>("nativeQrCreateSignRequest"), const_cast<char *>("(JI[B[BJ)[B"), reinterpret_cast<void *>(native_qr_create_request)},
    {const_cast<char *>("nativeReviewQrSignRequest"), const_cast<char *>("(J[B)J"), reinterpret_cast<void *>(native_review_qr_request)},
    {const_cast<char *>("nativeSignQrRequest"), const_cast<char *>("(JJ)J"), reinterpret_cast<void *>(native_sign_qr_request)},
    {const_cast<char *>("nativeReleaseQrReview"), const_cast<char *>("(JJ)V"), reinterpret_cast<void *>(native_release_qr_review)},
    {const_cast<char *>("nativeQrConsumeSignResponse"), const_cast<char *>("(J[B)[B"), reinterpret_cast<void *>(native_qr_consume_response)},
    {const_cast<char *>("nativeQrCancelSignRequest"), const_cast<char *>("(J[B)Z"), reinterpret_cast<void *>(native_qr_cancel_request)},
    {const_cast<char *>("nativeQrEncodeAccountId"), const_cast<char *>("(J[B)[B"), reinterpret_cast<void *>(native_qr_encode_account)},
    {const_cast<char *>("nativeQrEncodeUserTransfer"), const_cast<char *>("(J[BJ[B[B[B[B[B)[B"), reinterpret_cast<void *>(native_qr_encode_transfer)},
    {const_cast<char *>("nativeQrDecodeLuminance"), const_cast<char *>("(J[BIII)[B"), reinterpret_cast<void *>(native_qr_decode_luminance)},
    {const_cast<char *>("nativeQrEncode"), const_cast<char *>("(J[BI)[B"), reinterpret_cast<void *>(native_qr_encode_image)},
    {const_cast<char *>("nativeTransferWithRemark"), const_cast<char *>("(J[B[BJJ[B)J"), reinterpret_cast<void *>(native_transfer)},
    {const_cast<char *>("nativeInitializeFinalizedHistory"), const_cast<char *>("(J[BI)J"), reinterpret_cast<void *>(native_history_initialize)},
    {const_cast<char *>("nativeSyncFinalizedHistory"), const_cast<char *>("(J[BI)J"), reinterpret_cast<void *>(native_history_sync)},
    {const_cast<char *>("nativePrepareWalletCreation"), const_cast<char *>("(JI[B)J"), reinterpret_cast<void *>(native_prepare)},
    {const_cast<char *>("nativeValidateWalletPassword"), const_cast<char *>("([B)V"), reinterpret_cast<void *>(native_validate_password)},
    {const_cast<char *>("nativeValidateWalletMnemonic"), const_cast<char *>("([BI)V"), reinterpret_cast<void *>(native_validate_mnemonic)},
    {const_cast<char *>("nativeWalletWordSuggestions"), const_cast<char *>("([B)[B"), reinterpret_cast<void *>(native_word_suggestions)},
    {const_cast<char *>("nativeImportWallet"), const_cast<char *>("(J[B[B)J"), reinterpret_cast<void *>(native_import)},
    {const_cast<char *>("nativeAddWalletAccounts"), const_cast<char *>("(J[B[B[I)J"), reinterpret_cast<void *>(native_add_accounts)},
    {const_cast<char *>("nativeCopyPreparedMnemonic"), const_cast<char *>("(JJ)[B"), reinterpret_cast<void *>(native_copy_prepared)},
    {const_cast<char *>("nativeCommitPreparedWallet"), const_cast<char *>("(JJ)J"), reinterpret_cast<void *>(native_commit_prepared)},
    {const_cast<char *>("nativeReleasePreparedWallet"), const_cast<char *>("(JJ)V"), reinterpret_cast<void *>(native_release_prepared)},
    {const_cast<char *>("nativeDestroy"), const_cast<char *>("(J)V"), reinterpret_cast<void *>(native_destroy)},
    {const_cast<char *>("completeVaultUnwrap"), const_cast<char *>("(JJI)V"), reinterpret_cast<void *>(native_complete_unwrap)},
};

}  // namespace

void throw_sdk(JNIEnv *env, citizensdk_error_code_t code,
               const char *fallback_message) {
  jclass code_class = env->FindClass("org/citizen/sdk/CitizenSdkErrorCode");
  jmethodID from = code_class == nullptr
                       ? nullptr
                       : env->GetStaticMethodID(
                             code_class, "fromValue",
                             "(I)Lorg/citizen/sdk/CitizenSdkErrorCode;");
  jobject code_value = from == nullptr
                           ? nullptr
                           : env->CallStaticObjectMethod(code_class, from, code);
  jclass exception_class = env->FindClass("org/citizen/sdk/CitizenSdkException");
  jmethodID constructor = exception_class == nullptr
                              ? nullptr
                              : env->GetMethodID(
                                    exception_class, "<init>",
                                    "(Lorg/citizen/sdk/CitizenSdkErrorCode;Ljava/lang/String;Ljava/lang/Throwable;)V");
  jstring message = env->NewStringUTF(fallback_message);
  if (!env->ExceptionCheck() && constructor != nullptr && code_value != nullptr &&
      message != nullptr) {
    jobject exception = env->NewObject(exception_class, constructor, code_value,
                                       message, nullptr);
    if (exception != nullptr) env->Throw(static_cast<jthrowable>(exception));
  }
  if (!env->ExceptionCheck()) {
    jclass fallback = env->FindClass("java/lang/IllegalStateException");
    if (fallback != nullptr) env->ThrowNew(fallback, fallback_message);
  }
}

bool take_bytes(JNIEnv *env, jbyteArray source, std::vector<uint8_t> *out) {
  if (source == nullptr) return false;
  const jsize length = env->GetArrayLength(source);
  out->resize(static_cast<size_t>(length));
  if (length != 0) {
    env->GetByteArrayRegion(source, 0, length,
                            reinterpret_cast<jbyte *>(out->data()));
  }
  return !env->ExceptionCheck();
}

bool take_ints(JNIEnv *env, jintArray source, std::vector<uint32_t> *out) {
  if (source == nullptr) return false;
  const jsize length = env->GetArrayLength(source);
  if (length <= 0 || length > kMaxWalletAccountIndices) {
    throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "Wallet index list must contain 1..1989 items");
    return false;
  }
  std::vector<jint> values(static_cast<size_t>(length));
  env->GetIntArrayRegion(source, 0, length, values.data());
  if (env->ExceptionCheck()) return false;
  out->reserve(values.size());
  std::array<bool, 1990> seen{};
  for (const jint value : values) {
    if (value < 1 || value > 1989 || seen[static_cast<size_t>(value)]) {
      throw_sdk(env, CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "Wallet indices must be unique values in 1..1989");
      return false;
    }
    seen[static_cast<size_t>(value)] = true;
    out->push_back(static_cast<uint32_t>(value));
  }
  return true;
}

jbyteArray to_byte_array(JNIEnv *env, const std::vector<uint8_t> &bytes) {
  if (bytes.size() > static_cast<size_t>(std::numeric_limits<jsize>::max())) return nullptr;
  jbyteArray result = env->NewByteArray(static_cast<jsize>(bytes.size()));
  if (result != nullptr && !bytes.empty()) {
    env->SetByteArrayRegion(result, 0, static_cast<jsize>(bytes.size()),
                            reinterpret_cast<const jbyte *>(bytes.data()));
  }
  return result;
}

void WireWriter::u8(uint8_t value) { data_.push_back(value); }
void WireWriter::u32(uint32_t value) {
  for (uint32_t shift = 0; shift < 32; shift += 8)
    data_.push_back(static_cast<uint8_t>(value >> shift));
}
void WireWriter::i32(int32_t value) { u32(static_cast<uint32_t>(value)); }
void WireWriter::u64(uint64_t value) {
  for (uint32_t shift = 0; shift < 64; shift += 8)
    data_.push_back(static_cast<uint8_t>(value >> shift));
}
void WireWriter::fixed(const uint8_t *bytes, size_t length) {
  if (length == 0) return;
  data_.insert(data_.end(), bytes, bytes + length);
}
void WireWriter::bytes(const uint8_t *value, size_t length) {
  u32(static_cast<uint32_t>(length));
  if (length != 0) fixed(value, length);
}
void WireWriter::text(const std::vector<uint8_t> &value) {
  bytes(value.data(), value.size());
}

void write_block(WireWriter *writer, const citizensdk_block_ref_t &block) {
  writer->fixed(block.hash, 32);
  writer->u64(block.number);
  writer->u32(block.finality);
}

void write_execution(WireWriter *writer,
                     const citizensdk_execution_info_t &execution) {
  writer->u32(execution.status);
  writer->u32(execution.reason_or_dispatch_variant);
  writer->u8(execution.has_block == 0 ? 0 : 1);
  if (execution.has_block != 0) write_block(writer, execution.block);
  writer->u8(execution.has_extrinsic_index == 0 ? 0 : 1);
  if (execution.has_extrinsic_index != 0) writer->u32(execution.extrinsic_index);
  writer->u8(execution.has_module == 0 ? 0 : 1);
  if (execution.has_module != 0) {
    writer->u32(execution.pallet_index);
    writer->u32(execution.error_index);
  }
}

// 单项与批量只共享公开余额结构的编码，不在 JNI 计算或查询链状态。
void write_balance(WireWriter *writer, const citizensdk_account_balance_info_t &value) {
  write_block(writer, value.block);
  writer->fixed(value.account_id.bytes, 32);
  writer->u64(value.free_fen.low); writer->u64(value.free_fen.high);
  writer->u64(value.reserved_fen.low); writer->u64(value.reserved_fen.high);
  writer->u64(value.total_fen.low); writer->u64(value.total_fen.high);
}

bool encode_result(citizensdk_result_handle_t result, uint64_t prepared_token,
                   WireWriter *writer,
                   citizensdk_prepared_wallet_handle_t *prepared, bool *qr_review) {
  *prepared = 0;
  *qr_review = false;
  auto info = info_value<citizensdk_result_info_t>();
  if (citizensdk_result_get_info(result, &info) != kOk) {
    write_internal_decode_failure(writer);
    return true;
  }
  std::vector<uint8_t> message;
  if (!copy_error(result, &message)) {
    write_internal_decode_failure(writer);
    return true;
  }
  if (info.error_code != kOk) {
    write_failure(writer, info.error_code, info.kind, message);
    return true;
  }

  WireWriter payload;
  bool valid = true;
  switch (info.kind) {
    case CITIZENSDK_RESULT_EMPTY:
      break;
    case CITIZENSDK_RESULT_BLOCK_REF: {
      auto block = info_value<citizensdk_block_ref_t>();
      valid = citizensdk_result_get_block_ref(result, &block) == kOk;
      if (valid) write_block(&payload, block);
      break;
    }
    case CITIZENSDK_RESULT_ACCOUNT_BALANCE: {
      auto value = info_value<citizensdk_account_balance_info_t>();
      valid = citizensdk_result_get_account_balance(result, &value) == kOk;
      if (valid) write_balance(&payload, value);
      break;
    }
    case CITIZENSDK_RESULT_ACCOUNT_BALANCES: {
      uint32_t count = 0;
      valid = citizensdk_result_get_account_balance_count(result, &count) == kOk && count <= 1990;
      if (valid) payload.u32(count);
      for (uint32_t index = 0; valid && index < count; ++index) {
        auto value = info_value<citizensdk_account_balance_info_t>();
        valid = citizensdk_result_get_account_balance_at(result, index, &value) == kOk;
        if (valid) write_balance(&payload, value);
      }
      break;
    }
    case CITIZENSDK_RESULT_ACCOUNT_NONCE: {
      auto value = info_value<citizensdk_account_nonce_info_t>();
      valid = citizensdk_result_get_account_nonce(result, &value) == kOk;
      if (valid) {
        write_block(&payload, value.best_block);
        payload.fixed(value.account_id.bytes, 32);
        payload.u64(value.nonce);
      }
      break;
    }
    case CITIZENSDK_RESULT_FEE_SNAPSHOT: {
      auto value = info_value<citizensdk_fee_snapshot_info_t>();
      valid = citizensdk_result_get_fee_snapshot(result, &value) == kOk;
      if (valid) {
        write_block(&payload, value.best_block);
        payload.u32(value.fee_rate_parts);
        payload.u64(value.minimum_fee_fen.low); payload.u64(value.minimum_fee_fen.high);
        payload.u64(value.existential_deposit_fen.low); payload.u64(value.existential_deposit_fen.high);
      }
      break;
    }
    case CITIZENSDK_RESULT_WALLET_PROFILE:
      valid = write_wallet_profile(result, &payload);
      break;
    case CITIZENSDK_RESULT_WALLET_ACCOUNTS:
      valid = write_wallet_accounts(result, &payload);
      break;
    case CITIZENSDK_RESULT_SIGNATURE: {
      uint8_t signature[64]{};
      valid = citizensdk_result_get_signature(result, signature) == kOk;
      if (valid) payload.fixed(signature, sizeof(signature));
      std::memset(signature, 0, sizeof(signature));
      break;
    }
    case CITIZENSDK_RESULT_PREPARED_WALLET: {
      auto value = info_value<citizensdk_prepared_wallet_info_t>();
      const bool copied = citizensdk_result_get_prepared_wallet(result, &value) == kOk;
      if (copied) {
        *prepared = value.prepared_wallet;
      }
      valid = copied && prepared_token != 0;
      if (valid) {
        payload.u64(prepared_token);
      }
      break;
    }
    case CITIZENSDK_RESULT_WALLET_TRANSFER:
      valid = copy_wallet_transfer(result, &payload);
      break;
    case CITIZENSDK_RESULT_TRANSACTION_HISTORY:
      valid = write_history(result, &payload);
      break;
    case CITIZENSDK_RESULT_QR_REVIEW:
    case CITIZENSDK_RESULT_QR_SIGNED: {
      uint64_t required = 0;
      valid = citizensdk_result_copy_qr(result, nullptr, 0, &required) == kOk && required > 0 && required <= 65536;
      std::vector<uint8_t> json(valid ? static_cast<size_t>(required) : 0);
      if (valid) valid = citizensdk_result_copy_qr(result, json.data(), required, &required) == kOk && required == json.size();
      if (valid && info.kind == CITIZENSDK_RESULT_QR_REVIEW) {
        valid = result > 0 && result <= static_cast<uint64_t>(INT64_MAX);
        if (valid) payload.u64(result);
      }
      if (valid) payload.text(json);
      break;
    }
    default:
      valid = false;
      break;
  }
  if (!valid) {
    write_internal_decode_failure(writer);
    return true;
  }
  writer->u32(kWireVersion);
  writer->i32(kOk);
  writer->u32(info.kind);
  writer->text(message);
  writer->fixed(payload.data().data(), payload.data().size());
  *qr_review = info.kind == CITIZENSDK_RESULT_QR_REVIEW;
  return true;
}

bool encode_capabilities(citizensdk_handle_t handle, WireWriter *writer) {
  auto snapshot = info_value<citizensdk_capability_snapshot_t>();
  if (citizensdk_get_capabilities(handle, &snapshot) != kOk ||
      snapshot.count != CITIZENSDK_CAPABILITY_COUNT) return false;
  writer->u32(kWireVersion);
  writer->u64(snapshot.revision);
  writer->u32(snapshot.count);
  for (uint32_t index = 0; index < snapshot.count; ++index) {
    const auto &status = snapshot.statuses[index];
    writer->u32(status.name);
    writer->u32(status.reason);
    writer->u8(status.supported); writer->u8(status.available);
    writer->u8(status.enabled); writer->u8(status.ready);
  }
  return true;
}

bool encode_watch(citizensdk_result_handle_t result, WireWriter *writer) {
  auto info = info_value<citizensdk_watch_event_info_t>();
  if (citizensdk_result_get_watch_event(result, &info) != kOk) return false;
  writer->u32(kWireVersion);
  writer->u32(info.status);
  writer->u32(info.peer_count);
  writer->u8(info.has_block == 0 ? 0 : 1);
  if (info.has_block != 0) write_block(writer, info.block);
  writer->u8(info.has_replacement_hash == 0 ? 0 : 1);
  if (info.has_replacement_hash != 0)
    writer->fixed(info.replacement_hash, 32);
  return true;
}

}  // namespace citizen::sdk::jni

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *) {
  JNIEnv *env = nullptr;
  if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK)
    return JNI_ERR;
  jclass type = env->FindClass("org/citizen/sdk/internal/CitizenSdkNative");
  if (type == nullptr) return JNI_ERR;
  const jint result = env->RegisterNatives(
      type, citizen::sdk::jni::kMethods,
      static_cast<jint>(sizeof(citizen::sdk::jni::kMethods) /
                        sizeof(citizen::sdk::jni::kMethods[0])));
  env->DeleteLocalRef(type);
  return result == JNI_OK ? JNI_VERSION_1_6 : JNI_ERR;
}
