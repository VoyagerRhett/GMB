#include "citizen_sdk_flutter_sessions.hpp"

#include <sys/random.h>
#include <array>
#include <cerrno>
#include <exception>
#include <limits>
#include <map>
#include <mutex>
#include <optional>
#include <thread>
#include <utility>
#include <vector>
#include "citizen_sdk/citizen_sdk.hpp"
#include "citizensdk_qr_image.h"

namespace citizen_sdk::flutter {
namespace {

citizensdk_bytes_view_t view(const std::vector<uint8_t> &bytes) noexcept {
  return {bytes.empty() ? nullptr : bytes.data(), static_cast<uint64_t>(bytes.size())};
}

citizensdk_bytes_view_t view(const std::string &text) noexcept {
  return {reinterpret_cast<const uint8_t *>(text.data()),
          static_cast<uint64_t>(text.size())};
}

template <typename Call>
std::vector<uint8_t> qr_core_output(Call call) {
  uint64_t required = 0;
  auto code = call(nullptr, 0, &required);
  if (code != CITIZENSDK_OK) throw Error(code, "CitizenSDK QR output query failed");
  if (required == 0 || required > 65536)
    throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY, "CitizenSDK QR output length is invalid");
  std::vector<uint8_t> output(static_cast<std::size_t>(required));
  code = call(output.data(), required, &required);
  if (code != CITIZENSDK_OK) throw Error(code, "CitizenSDK QR output copy failed");
  if (required != output.size())
    throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY, "CitizenSDK QR output length changed");
  return output;
}

std::string qr_text(std::vector<uint8_t> bytes) {
  return std::string(reinterpret_cast<const char *>(bytes.data()), bytes.size());
}

std::string preparation_id(const uint8_t *bytes) {
  static constexpr char digits[] = "0123456789abcdef";
  std::string result(34, '0'); result[1] = 'x';
  for (std::size_t index = 0; index < 16; ++index) {
    result[2 + index * 2] = digits[bytes[index] >> 4];
    result[3 + index * 2] = digits[bytes[index] & 15];
  }
  return result;
}

citizensdk_error_code_t qr_image_error(citizensdk_qr_image_status_t status) noexcept {
  switch (status) {
    case CITIZENSDK_QR_IMAGE_INVALID_ARGUMENT:
    case CITIZENSDK_QR_IMAGE_CAPACITY_EXCEEDED: return CITIZENSDK_ERROR_INVALID_ARGUMENT;
    case CITIZENSDK_QR_IMAGE_NO_CODE: return CITIZENSDK_ERROR_NOT_FOUND;
    case CITIZENSDK_QR_IMAGE_MULTIPLE_CODES: return CITIZENSDK_ERROR_CONFLICT;
    case CITIZENSDK_QR_IMAGE_INVALID_UTF8: return CITIZENSDK_ERROR_DECODE;
    default: return CITIZENSDK_ERROR_INTERNAL;
  }
}

void check_qr_image(citizensdk_qr_image_status_t status, const char *message) {
  if (status != CITIZENSDK_QR_IMAGE_OK) throw Error(qr_image_error(status), message);
}

// This adapter contains no chain/wallet algorithm. Every accepted method goes
// directly to the same installed Host/Core used by the native C/C++ binding.
class HostTransport final : public NativeTransport {
 public:
  explicit HostTransport(const Config &config)
      : host_(std::make_unique<Host>(config)), modules_(config.modules) {
    host_->open();
  }
  ~HostTransport() override = default;
  void observe(Observer observer) override { host_->set_event_observer(std::move(observer)); }
  citizensdk_error_code_t accept(Method native_method, const DecodedRequest &r,
                                citizensdk_request_id_t *out) override {
    if (!host_) return CITIZENSDK_ERROR_INVALID_STATE;
    const auto sdk = host_->native_handle();
    switch (native_method) {
      case Method::start: return citizensdk_start(sdk, out);
      case Method::stop: return citizensdk_stop(sdk, out);
      case Method::get_finalized_head: return citizensdk_get_finalized_head(sdk, out);
      case Method::get_sync_status: return citizensdk_get_sync_status(sdk, out);
      case Method::get_best_head: return citizensdk_get_best_head(sdk, out);
      case Method::get_finalized_block_at:
        return citizensdk_get_finalized_block_at(sdk, r.block_number, out);
      case Method::resolve_finalized_block:
        return citizensdk_resolve_finalized_block(sdk, r.block.hash, r.block_number, out);
      case Method::get_block_header:
        return citizensdk_get_block_header_at(sdk, &r.block, out);
      case Method::get_block_body:
        return citizensdk_get_block_body_at(sdk, &r.block, out);
      case Method::get_runtime_context:
        return citizensdk_get_runtime_context_at(sdk, &r.block, out);
      case Method::get_storage:
        return citizensdk_get_storage_at(sdk, &r.block, view(r.payload), out);
      case Method::get_storage_batch: {
        std::vector<citizensdk_bytes_view_t> keys;
        keys.reserve(r.storage_keys.size());
        for (const auto &key : r.storage_keys) keys.push_back(view(key));
        return citizensdk_get_storage_batch_at(sdk, &r.block, keys.data(),
                                                static_cast<uint32_t>(keys.size()), out);
      }
      case Method::get_system_events:
        return citizensdk_get_system_events_at(sdk, &r.block, out);
      case Method::export_state: return citizensdk_export_state(sdk, out);
      case Method::import_state:
        return citizensdk_import_state(sdk, &r.block, r.state_format_version,
                                       view(r.state_database), out);
      case Method::get_account_balance:
        return citizensdk_get_finalized_account_balance(sdk, &r.account_id, out);
      case Method::get_account_balances:
        return citizensdk_get_finalized_account_balances(sdk,
            r.account_ids.empty() ? nullptr : r.account_ids.data(),
            static_cast<uint32_t>(r.account_ids.size()), out);
      case Method::get_account_nonce: return citizensdk_get_account_nonce(sdk, &r.account_id, out);
      case Method::get_fee_snapshot: return citizensdk_get_best_fee_snapshot(sdk, out);
      case Method::get_wallet_profile: return citizensdk_get_wallet_profile(sdk, out);
      case Method::get_wallet_state: return citizensdk_get_wallet_state(sdk, out);
      case Method::import_cold_account_id:
        return citizensdk_import_cold_account_id(sdk, &r.account_id, bytes_view(r.name), out);
      case Method::import_cold_account_ss58:
        return citizensdk_import_cold_account_ss58(sdk, bytes_view(r.qr_text), bytes_view(r.name), out);
      case Method::reorder_wallet_accounts_without_default_change:
        return citizensdk_reorder_wallet_accounts_without_default_change(
            sdk, r.wallet_revision, r.account_ids.data(),
            static_cast<uint32_t>(r.account_ids.size()), out);
      case Method::rename_account:
        return citizensdk_rename_account(sdk, &r.account_id, bytes_view(r.name), out);
      case Method::delete_account:
        return citizensdk_delete_account(sdk, &r.account_id, out);
      case Method::set_active_wallet_account:
        return citizensdk_set_active_wallet_account(sdk, &r.account_id, out);
      case Method::rename_wallet_account:
        return citizensdk_rename_wallet_account(sdk, &r.account_id, bytes_view(r.name), out);
      case Method::delete_wallet_account:
        return citizensdk_delete_wallet_account(sdk, &r.account_id, out);
      case Method::delete_wallet: return citizensdk_delete_wallet(sdk, out);
      case Method::reconcile_wallet_cleanup: return citizensdk_reconcile_wallet_cleanup(sdk, out);
      case Method::sign_wallet_payload:
        return citizensdk_sign_wallet_payload(sdk, &r.account_id, view(r.payload), out);
      case Method::begin_signing:
        return citizensdk_begin_signing(
            sdk, &r.account_id, view(r.payload), r.signing_transform,
            view(r.signing_domain), r.external_signer_transport,
            r.signing_action, r.signing_ttl, out);
      case Method::consume_external_signature:
        return citizensdk_consume_external_signature(
            sdk, view(r.signing_session_id), view(r.signing_response), out);
      case Method::begin_default_account_change:
        return citizensdk_begin_default_account_change(
            sdk, r.wallet_revision, r.account_ids.data(),
            static_cast<uint32_t>(r.account_ids.size()), r.signing_ttl, out);
      case Method::consume_default_account_change:
        return citizensdk_consume_default_account_change(
            sdk, view(r.signing_session_id), view(r.signing_response), out);
      case Method::prepare_transaction:
        return citizensdk_prepare_transaction(sdk, &r.account_id, view(r.payload), out);
      case Method::execute_prepared_transaction: {
        citizensdk_prepared_transaction_handle_t prepared = 0;
        {
          std::lock_guard<std::mutex> guard(prepared_lock_);
          const auto found = prepared_transactions_.find(r.preparation_id);
          if (found == prepared_transactions_.end()) return CITIZENSDK_ERROR_NOT_FOUND;
          prepared = found->second;
          prepared_transactions_.erase(found);
        }
        const auto code = citizensdk_execute_prepared_transaction(sdk, prepared, out);
        if (code != CITIZENSDK_OK) {
          std::lock_guard<std::mutex> guard(prepared_lock_);
          prepared_transactions_.emplace(r.preparation_id, prepared);
        }
        return code;
      }
      case Method::consume_prepared_transaction_qr_response:
        return citizensdk_transaction_execution_consume_qr_response(
            sdk, &r.execution_id, view(r.signing_response), out);
      case Method::get_transaction_history:
        return citizensdk_get_transaction_history(
            sdk, r.before_execution_id ? &*r.before_execution_id : nullptr,
            r.history_limit, out);
      case Method::sync_transaction_history:
        return citizensdk_sync_transaction_history(sdk, out);
      // open/close/capabilities are synchronous Host operations; the three
      // secret-bearing wallet mutations are admitted only by existing GTK UI.
      case Method::view_account_private_key:
      case Method::cancel_signing:
      case Method::cancel_prepared_transaction:
      case Method::cancel_prepared_transaction_execution:
      case Method::verify_signature:
      case Method::open: case Method::close: case Method::get_capabilities: case Method::get_genesis_hash:
      case Method::create_wallet: case Method::import_wallet: case Method::add_wallet_accounts:
      case Method::qr_parse: case Method::qr_create_sign_request:
      case Method::qr_scan: case Method::sign_qr_request:
      case Method::qr_consume_sign_response: case Method::qr_cancel_sign_request:
      case Method::qr_encode_account_id:
      case Method::qr_decode_luminance: case Method::qr_encode:
        return CITIZENSDK_ERROR_UNSUPPORTED;
    }
    return CITIZENSDK_ERROR_UNSUPPORTED;
  }
  Value copy_result(Method method, citizensdk_result_handle_t result) override {
    Value value = copy_public_result(method, result);
    if (method == Method::prepare_transaction) {
      citizensdk_prepared_transaction_info_t info{};
      info.struct_size = sizeof(info);
      info.abi_version = CITIZENSDK_ABI_VERSION;
      const auto code = citizensdk_result_get_prepared_transaction(result, &info);
      if (code != CITIZENSDK_OK) throw Error(code, "Prepared transaction ownership copy failed");
      const auto id = preparation_id(info.preparation_id);
      std::lock_guard<std::mutex> guard(prepared_lock_);
      if (!prepared_transactions_.emplace(id, info.prepared_transaction).second) {
        (void)citizensdk_prepared_transaction_release(
            host_->native_handle(), info.prepared_transaction);
        throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY,
                              "Core returned a duplicate preparation identity");
      }
    }
    return value;
  }
  citizensdk_lifecycle_t lifecycle_state() override {
    citizensdk_lifecycle_t state{};
    const auto code = citizensdk_get_lifecycle(host_->native_handle(), &state);
    if (code != CITIZENSDK_OK) throw Error(code, "CitizenSDK lifecycle query failed");
    return state;
  }
  Value genesis_hash() override { return copy_genesis_hash(host_->native_handle()); }
  Value cancel_signing(const DecodedRequest &r) override {
    uint8_t cancelled = 0;
    const auto code = citizensdk_cancel_signing_session(
        host_->native_handle(), view(r.signing_session_id), &cancelled);
    if (code != CITIZENSDK_OK) throw Error(code, "CitizenSDK signing cancellation failed");
    if (cancelled > 1)
      throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY,
                            "CitizenSDK signing cancellation result is invalid");
    return Value::list({Value::boolean(cancelled != 0)});
  }
  Value cancel_prepared_transaction(const DecodedRequest &r) override {
    std::lock_guard<std::mutex> guard(prepared_lock_);
    const auto found = prepared_transactions_.find(r.preparation_id);
    if (found == prepared_transactions_.end())
      throw ContractFailure(CITIZENSDK_ERROR_NOT_FOUND,
                            "Transaction preparation was not found");
    const auto code = citizensdk_prepared_transaction_release(
        host_->native_handle(), found->second);
    if (code != CITIZENSDK_OK)
      throw Error(code, "CitizenSDK prepared transaction cancellation failed");
    prepared_transactions_.erase(found);
    return Value::list({Value::null()});
  }
  Value cancel_transaction_execution(const DecodedRequest &r) override {
    const auto code = citizensdk_transaction_execution_cancel(
        host_->native_handle(), &r.execution_id);
    if (code != CITIZENSDK_OK)
      throw Error(code, "CitizenSDK transaction execution cancellation failed");
    return Value::list({Value::null()});
  }
  Value capability_snapshot() override {
    citizensdk_capability_snapshot_t snapshot{};
    snapshot.struct_size = sizeof(snapshot);
    snapshot.abi_version = CITIZENSDK_ABI_VERSION;
    const auto code = citizensdk_get_capabilities(host_->native_handle(), &snapshot);
    if (code != CITIZENSDK_OK) throw Error(code, "CitizenSDK capability query failed");
    return capabilities(snapshot);
  }
  Value qr(const DecodedRequest &r) override {
    if ((modules_ & CITIZENSDK_MODULE_QR) == 0)
      throw Error(CITIZENSDK_ERROR_UNSUPPORTED, "CitizenSDK QR module is not enabled");
    const auto sdk = host_->native_handle();
    switch (r.method) {
      case Method::qr_parse: {
        auto output = qr_core_output([&](uint8_t *target, uint64_t capacity, uint64_t *required) {
          return citizensdk_qr_parse(sdk, view(r.qr_text), target, capacity, required);
        });
        return Value::list({Value::string(qr_text(std::move(output)))});
      }
      case Method::qr_create_sign_request: {
        auto output = qr_core_output([&](uint8_t *target, uint64_t capacity, uint64_t *required) {
          return citizensdk_qr_create_sign_request(sdk, r.qr_action, &r.account_id,
              view(r.payload), r.qr_ttl, target, capacity, required);
        });
        return Value::list({Value::string(qr_text(std::move(output)))});
      }
      case Method::qr_consume_sign_response: {
        std::vector<uint8_t> signature(64);
        const auto code = citizensdk_qr_consume_sign_response(sdk, view(r.qr_text), signature.data());
        if (code != CITIZENSDK_OK) throw Error(code, "CitizenSDK QR response was rejected");
        return Value::list({Value::bytes(std::move(signature))});
      }
      case Method::qr_cancel_sign_request: {
        uint8_t cancelled = 0;
        const auto code = citizensdk_qr_cancel_sign_request(sdk, view(r.qr_request_id), &cancelled);
        if (code != CITIZENSDK_OK) throw Error(code, "CitizenSDK QR request cancellation failed");
        if (cancelled > 1)
          throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY, "CitizenSDK QR cancellation result is invalid");
        return Value::list({Value::boolean(cancelled != 0)});
      }
      case Method::qr_encode_account_id: {
        auto output = qr_core_output([&](uint8_t *target, uint64_t capacity, uint64_t *required) {
          return citizensdk_qr_encode_account_id(sdk, &r.account_id, target, capacity, required);
        });
        return Value::list({Value::string(qr_text(std::move(output)))});
      }
      case Method::qr_decode_luminance: {
        size_t required = 0;
        auto status = citizensdk_qr_image_decode_luminance(r.payload.data(), r.payload.size(),
            r.qr_width, r.qr_height, r.qr_stride, nullptr, 0, &required);
        if (status != CITIZENSDK_QR_IMAGE_BUFFER_TOO_SMALL || required == 0 || required > 2331)
          throw Error(qr_image_error(status), "ZXing-C++ QR decode query failed");
        std::vector<uint8_t> output(required);
        status = citizensdk_qr_image_decode_luminance(r.payload.data(), r.payload.size(),
            r.qr_width, r.qr_height, r.qr_stride, output.data(), output.size(), &required);
        check_qr_image(status, "ZXing-C++ QR decode failed");
        if (required != output.size())
          throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY, "ZXing-C++ QR decode length changed");
        const auto text = qr_text(std::move(output));
        auto document = qr_core_output([&](uint8_t *target, uint64_t capacity, uint64_t *size) {
          return citizensdk_qr_parse(sdk, view(text), target, capacity, size);
        });
        return Value::list({Value::string(qr_text(std::move(document)))});
      }
      case Method::qr_encode: {
        uint32_t width = 0, height = 0;
        size_t required = 0;
        auto status = citizensdk_qr_image_encode_text(
            reinterpret_cast<const uint8_t *>(r.qr_text.data()), r.qr_text.size(), r.qr_scale,
            nullptr, 0, &width, &height, &required);
        if (status != CITIZENSDK_QR_IMAGE_BUFFER_TOO_SMALL || required == 0 || required > 16777216)
          throw Error(qr_image_error(status), "ZXing-C++ QR encode query failed");
        std::vector<uint8_t> output(required);
        status = citizensdk_qr_image_encode_text(
            reinterpret_cast<const uint8_t *>(r.qr_text.data()), r.qr_text.size(), r.qr_scale,
            output.data(), output.size(), &width, &height, &required);
        check_qr_image(status, "ZXing-C++ QR encode failed");
        if (required != output.size())
          throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY, "ZXing-C++ QR image length changed");
        return Value::list({Value::integer(width), Value::integer(height), Value::bytes(std::move(output))});
      }
      default: throw ContractFailure(CITIZENSDK_ERROR_UNSUPPORTED, "Unsupported QR method");
    }
  }
  void cancel(citizensdk_request_id_t request) override {
    const auto code = citizensdk_cancel_request(host_->native_handle(), request);
    if (code != CITIZENSDK_OK && code != CITIZENSDK_ERROR_NOT_FOUND &&
        code != CITIZENSDK_ERROR_INVALID_HANDLE)
      throw Error(code, "CitizenSDK request cancellation failed");
  }
  WalletCancellation present(const DecodedRequest &request,
                              WalletFlowCompletion completion) override {
    auto flow = request.method == Method::view_account_private_key
        ? host_->view_account_private_key(request.account_id, std::move(completion))
        : host_->present_wallet_flow(FlutterWalletFlows::contract(request), std::move(completion));
    return [flow]() mutable { flow.cancel(); };
  }
  WalletCancellation present_qr(const DecodedRequest &request, QrCompletion completion) override {
    auto done = [completion = std::move(completion)](QrFlowResult result) {
      completion(result.error_code, std::move(result.document));
    };
    auto flow = request.method == Method::qr_scan ? host_->scan_qr(std::move(done))
        : host_->sign_qr_request(request.qr_text, std::move(done));
    return [flow]() mutable { flow.cancel(); };
  }
  void close() override { host_->close(); }
  void retire() noexcept override {
    // Host::~Host performs its callback barrier and, if needed, transfers the
    // full Host/Core/store/vault graph to the existing process supervisor.
    host_.reset();
  }
 private:
  std::unique_ptr<Host> host_;
  const uint32_t modules_;
  std::mutex prepared_lock_;
  std::map<std::string, citizensdk_prepared_transaction_handle_t> prepared_transactions_;
};

std::string random_session_id() {
  std::array<uint8_t, 16> bytes{};
  std::size_t done = 0;
  while (done < bytes.size()) {
    const auto count = getrandom(bytes.data() + done, bytes.size() - done, 0);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) throw ContractFailure(CITIZENSDK_ERROR_UNAVAILABLE,
                                         "CitizenSDK session entropy is unavailable");
    done += static_cast<std::size_t>(count);
  }
  static constexpr char hex[] = "0123456789abcdef";
  std::string value; value.reserve(32);
  for (const auto byte : bytes) {
    value.push_back(hex[static_cast<std::size_t>(byte >> 4)]);
    value.push_back(hex[static_cast<std::size_t>(byte & 15)]);
  }
  return value;
}

Reply failure(citizensdk_error_code_t code, const std::string &message,
              const DecodedRequest &request, citizensdk_failure_stage_t stage = 0) {
  const bool open = request.method == Method::open || request.method == Method::verify_signature;
  return {false, error_details(code, message,
          open ? std::optional<std::string>{} : request.session,
          open ? std::optional<int64_t>{} : request.sequence,
          method_name(request.method), stage), code, message};
}

Reply success(const DecodedRequest &request, Value payload) {
  if (request.method == Method::get_account_balances)
    validate_account_balances(request, payload);
  if (request.method == Method::get_genesis_hash ||
      request.method == Method::cancel_signing ||
      request.method == Method::cancel_prepared_transaction ||
      request.method == Method::cancel_prepared_transaction_execution ||
      (request.method >= Method::qr_parse && request.method <= Method::sign_qr_request))
    validate_public_value(request.method, payload);
  return {true, response(request.session, request.sequence, std::move(payload)),
          CITIZENSDK_OK, {}};
}

std::mutex &process_mutation_lock() { static std::mutex value; return value; }
std::weak_ptr<void> &process_mutation_owner() {
  static std::weak_ptr<void> value;
  return value;
}
bool acquire_process_mutation(const std::shared_ptr<void> &owner) {
  // 全进程共享，不按 session 或 Flutter engine 分裂；并发变更直接 BUSY。
  std::lock_guard<std::mutex> guard(process_mutation_lock());
  if (!process_mutation_owner().expired()) return false;
  process_mutation_owner() = owner;
  return true;
}
void release_process_mutation(const std::shared_ptr<void> &owner) noexcept {
  std::lock_guard<std::mutex> guard(process_mutation_lock());
  const auto current = process_mutation_owner().lock();
  if (current == owner) process_mutation_owner().reset();
}

}  // namespace

struct Sessions::State final : std::enable_shared_from_this<State> {
  struct Route final {
    DecodedRequest request;
    // Public method/arguments never change. native_method alone advances an
    // approved compound operation to its private profile-read stage.
    Method native_method{Method::open};
    ReplyCallback reply;
    citizensdk_request_id_t native_id{};
    std::optional<Reply> ready;
    bool accepting{};
    bool terminal_seen{};
    bool completed{};
    bool close_stop{};
    bool wallet{};
    WalletCancellation qr_cancel;
    bool qr_revoked{};
    bool mutation{};
    bool fetch_profile_after_mutation{};
    std::shared_ptr<void> mutation_owner;
  };
  struct Session final {
    std::string id;
    std::shared_ptr<NativeTransport> transport;
    int64_t next_request{1};
    int64_t next_event{1};
    std::mutex lock;
    std::map<int64_t, std::shared_ptr<Route>> routes;
    std::shared_ptr<Route> admitting;
    bool closing{};
    bool retired{};
    std::optional<DecodedRequest> close_request;
    ReplyCallback close_reply;
  };

  State(EnvironmentFactory source, Scheduler queue, TransportFactory make)
      : environment(std::move(source)), schedule(std::move(queue)),
        factory(std::move(make)), wallets(schedule), owner(std::this_thread::get_id()) {}
  EnvironmentFactory environment;
  Scheduler schedule;
  TransportFactory factory;
  FlutterWalletFlows wallets;
  std::thread::id owner;
  std::map<std::string, std::shared_ptr<Session>> sessions;
  EventSink sink;
  // One process-local gate matches Android/Apple: every profile mutation,
  // including SDK-owned UI and a required post-mutation profile read, is
  // serialized across all sessions and plugin/Flutter-engine instances.
  std::shared_ptr<Route> active_mutation;
  // The callback thread snapshots epoch under this lock; all Flutter objects
  // remain UI-owned and are never accessed from that thread.
  std::mutex epoch_lock;
  uint64_t epoch{};
  bool detached{};
  std::shared_ptr<State> detached_owner;
  void retain_detached_state() {
    // detach 只撤销 Flutter 回调，不等于原生操作完成。自保活无需新增线程或
    // 分配全局队列；待已接受请求排空后解除，再交既有 Host supervisor。
    if (!detached_owner) detached_owner = shared_from_this();
  }
  void release_detached_state_if_empty() {
    if (sessions.empty()) detached_owner.reset();
  }

  void require_owner() const {
    if (std::this_thread::get_id() != owner)
      throw ContractFailure(CITIZENSDK_ERROR_INVALID_STATE,
                            "CitizenSDK Flutter entry point requires the UI thread");
  }

  uint64_t snapshot_epoch() {
    std::lock_guard<std::mutex> guard(epoch_lock);
    return epoch;
  }
  void advance_epoch(bool detach_now = false) {
    std::lock_guard<std::mutex> guard(epoch_lock);
    if (epoch == std::numeric_limits<uint64_t>::max()) {
      detached = true;
      throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY,
                            "CitizenSDK subscription generation is exhausted");
    }
    ++epoch;
    if (detach_now) detached = true;
  }
  bool is_detached() {
    std::lock_guard<std::mutex> guard(epoch_lock);
    return detached;
  }

  bool current(const std::shared_ptr<Session> &session) const {
    const auto found = sessions.find(session->id);
    return found != sessions.end() && found->second == session && !session->retired;
  }
  void emit(const std::shared_ptr<Session> &session, const std::string &type,
            Value payload, uint64_t expected) {
    if (is_detached() || expected != snapshot_epoch() || !sink || !current(session)) return;
    if (session->next_event == std::numeric_limits<int64_t>::max()) {
      // Fail closed instead of wrapping/reusing an event sequence.
      cancel_events();
      throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY,
                            "CitizenSDK event sequence is exhausted");
    }
    const auto sequence = session->next_event++;
    auto callback = sink;
    callback(event(session->id, sequence, type, std::move(payload)));
  }
  void snapshots(const std::shared_ptr<Session> &session, uint64_t expected,
                 citizensdk_event_type_t kind = 0) {
    if (!current(session) || is_detached() || expected != snapshot_epoch()) return;
    if (kind == CITIZENSDK_EVENT_HISTORY_CHANGED)
      emit(session, "historyChanged", Value::list({}), expected);
    // Core callbacks carry only a notification, not an owned snapshot. Query
    // on the UI thread after the callback returns, never re-enter Core while
    // its dispatch thread may hold lifecycle/provider locks.
    if (kind == 0 || kind == CITIZENSDK_EVENT_LIFECYCLE_CHANGED)
      emit(session, "lifecycleChanged",
           Value::list({lifecycle(session->transport->lifecycle_state())}), expected);
    if (kind == 0 || kind == CITIZENSDK_EVENT_CAPABILITIES_CHANGED)
      emit(session, "capabilitiesChanged",
           Value::list({session->transport->capability_snapshot()}), expected);
  }

  void post_drain(const std::shared_ptr<Session> &session) noexcept {
    try {
      std::weak_ptr<State> weak = shared_from_this();
      std::weak_ptr<Session> target = session;
      schedule([weak, target] {
        if (const auto state = weak.lock()) if (const auto value = target.lock()) {
          try { state->drain(value); } catch (...) {}
        }
      });
    } catch (...) {
      // Route::ready remains authoritative until the next UI dispatch/drain.
      // No borrowed result or callback pointer is stored in this recovery path.
    }
  }

  void receive(const std::shared_ptr<Session> &session,
               const citizensdk_event_t &event_value) noexcept {
    const auto expected = snapshot_epoch();
    if (event_value.struct_size < sizeof(event_value) ||
        event_value.abi_version != CITIZENSDK_ABI_VERSION) return;
    if (event_value.event_type == CITIZENSDK_EVENT_LIFECYCLE_CHANGED ||
        event_value.event_type == CITIZENSDK_EVENT_CAPABILITIES_CHANGED ||
        event_value.event_type == CITIZENSDK_EVENT_HISTORY_CHANGED) {
      if (event_value.event_type == CITIZENSDK_EVENT_HISTORY_CHANGED &&
          (event_value.request_id != 0 || event_value.result != 0 ||
           event_value.capability_revision != 0 || event_value.reserved != 0)) return;
      try {
        std::weak_ptr<State> weak = shared_from_this();
        std::weak_ptr<Session> target = session;
        const auto kind = event_value.event_type;
        schedule([weak, target, expected, kind] {
          if (const auto state = weak.lock()) if (const auto value = target.lock()) {
            try { state->snapshots(value, expected, kind); } catch (...) {}
          }
        });
      } catch (...) {}
      return;
    }
    if (event_value.request_id == 0 || event_value.result == 0) return;
    std::shared_ptr<Route> route;
    {
      std::lock_guard<std::mutex> guard(session->lock);
      for (const auto &pair : session->routes) {
        if (pair.second->native_id == event_value.request_id) { route = pair.second; break; }
      }
      // Only one accepting call exists on the owner thread. Its route and
      // projection method were allocated before entering Core. A callback may
      // bind the integer ID first, but the returning call must confirm it.
      if (!route && session->admitting && session->admitting->native_id == 0) {
        route = session->admitting;
        route->native_id = event_value.request_id;
      }
      if (!route || route->terminal_seen) return;
      if (event_value.event_type != CITIZENSDK_EVENT_REQUEST_COMPLETED) return;
      route->terminal_seen = true;
    }
    std::optional<Reply> copied;
    try { copied = success(route->request,
                           session->transport->copy_result(route->native_method, event_value.result)); }
    catch (const ContractFailure &error) { copied = failure(error.code, error.what(), route->request, error.stage); }
    catch (const Error &error) { copied = failure(error.code(), error.what(), route->request, error.stage()); }
    catch (...) {
      try { copied = failure(CITIZENSDK_ERROR_INTERNAL,
                             "CitizenSDK public result copying failed", route->request); }
      catch (...) {
        // Allocation failure cannot release the accepted route's owner. The
        // route remains completed and drain turns the absent copy into error.
      }
    }
    {
      std::lock_guard<std::mutex> guard(session->lock);
      route->ready = std::move(copied);
      // Completion becomes drainable only after public data copying has ended.
      // accept() may return concurrently while its callback is still copying;
      // exposing terminal_seen alone would remove the route too early.
      // 已收到终态与复制完成是两件事；只有 completed 才允许 UI 移除 route。
      route->completed = true;
    }
    // Host's observer wrapper releases the borrowed native result exactly once
    // after this function returns, including every rejected/failed decode.
    post_drain(session);
  }

  void open(DecodedRequest request, ReplyCallback reply) {
    std::shared_ptr<Session> session;
    std::optional<Reply> outcome;
    try {
      const auto module_code = citizensdk_validate_modules(request.modules);
      if (module_code != CITIZENSDK_OK)
        throw ContractFailure(module_code, "CitizenSDK module selection is invalid");
      auto source = environment(request.modules); // keeps upgraded parent alive through Host creation
      session = std::make_shared<Session>();
      session->id = random_session_id();
      source.config.modules = request.modules;
      session->transport = factory(source.config);
      if (!session->transport) throw ContractFailure(CITIZENSDK_ERROR_UNAVAILABLE,
                                                     "CitizenSDK native Host is unavailable");
      std::weak_ptr<State> weak = shared_from_this();
      std::weak_ptr<Session> target = session;
      session->transport->observe([weak, target](const citizensdk_event_t &value) {
        if (const auto state = weak.lock()) if (const auto session = target.lock()) state->receive(session, value);
      });
      const auto initial_state = session->transport->lifecycle_state();
      // open 的固定合同是 created / eventSequence 1；其它合法生命周期也
      // 不能冒充新 session，否则 Dart 会拒绝响应并失去该原生实例的身份。
      if (initial_state != CITIZENSDK_LIFECYCLE_CREATED)
        throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY,
                              "CitizenSDK open requires a newly created native instance");
      if (!sessions.emplace(session->id, session).second)
        throw ContractFailure(CITIZENSDK_ERROR_CONFLICT, "CitizenSDK session identity collision");
      request.session = session->id;
      const auto state = lifecycle(initial_state);
      outcome = success(request, Value::list({state, Value::integer(1)}));
    } catch (const ContractFailure &error) {
      if (session && session->transport) { sessions.erase(session->id); session->transport->retire(); }
      outcome = failure(error.code, error.what(), request, error.stage);
    } catch (const Error &error) {
      if (session && session->transport) { sessions.erase(session->id); session->transport->retire(); }
      outcome = failure(error.code(), error.what(), request, error.stage());
    } catch (...) {
      if (session && session->transport) { sessions.erase(session->id); session->transport->retire(); }
      outcome = failure(CITIZENSDK_ERROR_INTERNAL, "CitizenSDK open failed", request);
    }
    // User/messenger code is outside native resource rollback. Once a session
    // was inserted, a throwing test callback must not make us reply twice.
    reply(std::move(*outcome));
    // Match the other official bindings: publish the open response before the
    // first session events, so Dart learns the random session ID first. A
    // reentrant close removes the session and makes snapshots a no-op.
    if (session && current(session)) {
      try { snapshots(session, snapshot_epoch()); } catch (...) {}
    }
  }

  void submit(const std::shared_ptr<Session> &session, const std::shared_ptr<Route> &route) {
    {
      std::lock_guard<std::mutex> guard(session->lock);
      if (session->admitting) throw ContractFailure(CITIZENSDK_ERROR_BUSY,
                                                   "CitizenSDK request admission is busy");
      route->accepting = true;
      session->admitting = route;
    }
    citizensdk_request_id_t native_id = 0;
    citizensdk_error_code_t code = CITIZENSDK_ERROR_INTERNAL;
    try { code = session->transport->accept(route->native_method, route->request, &native_id); }
    catch (...) {
      // Production C ABI is noexcept; finite test transports may throw before
      // acceptance. An observed ID means completion owns the route already.
      code = CITIZENSDK_ERROR_INTERNAL;
    }
    {
      std::lock_guard<std::mutex> guard(session->lock);
      route->accepting = false;
      session->admitting.reset();
      if (code == CITIZENSDK_OK && native_id != 0 &&
          (route->native_id == 0 || route->native_id == native_id)) {
        route->native_id = native_id;
      } else {
        // A contract-violating adapter must not overwrite the early route.
        // Keep any accepted ID for cancellation/retirement, but fail publicly.
        route->completed = true;
        route->ready = failure(code == CITIZENSDK_OK ? CITIZENSDK_ERROR_INTEGRITY : code,
                              "CitizenSDK native request was not accepted", route->request);
      }
    }
    drain(session);
  }

  static bool is_mutation(Method method) noexcept {
    switch (method) {
      // 查看持有钱包代际租约，沿用同一 UI 排他/关闭排空门。
      case Method::qr_scan: case Method::sign_qr_request:
      case Method::view_account_private_key:
      case Method::create_wallet: case Method::import_wallet:
      case Method::add_wallet_accounts: case Method::set_active_wallet_account:
      case Method::rename_wallet_account: case Method::delete_wallet_account:
      case Method::import_cold_account_id: case Method::import_cold_account_ss58:
      case Method::reorder_wallet_accounts_without_default_change:
      case Method::begin_default_account_change:
      case Method::consume_default_account_change:
      case Method::rename_account: case Method::delete_account:
      case Method::delete_wallet: case Method::reconcile_wallet_cleanup:
        return true;
      default: return false;
    }
  }

  static bool needs_profile_read(Method method) noexcept {
    return method == Method::delete_wallet_account ||
           method == Method::delete_wallet ||
           method == Method::reconcile_wallet_cleanup;
  }

  void settle_launch_failure(const std::shared_ptr<Session> &session,
                             const std::shared_ptr<Route> &route,
                             citizensdk_error_code_t code,
                             const std::string &message,
                             citizensdk_failure_stage_t stage = 0) {
    {
      std::lock_guard<std::mutex> guard(session->lock);
      route->completed = true;
      route->ready = failure(code, message, route->request, stage);
    }
    drain(session);
  }

  void launch_mutation(const std::shared_ptr<Session> &session,
                       const std::shared_ptr<Route> &route) {
    try {
      switch (route->request.method) {
        case Method::qr_scan: case Method::sign_qr_request: qr_flow(session, route); break;
        case Method::view_account_private_key:
        case Method::create_wallet: case Method::import_wallet:
        case Method::add_wallet_accounts: wallet(session, route); break;
        default: submit(session, route); break;
      }
    } catch (const ContractFailure &error) {
      settle_launch_failure(session, route, error.code, error.what(), error.stage);
    } catch (const Error &error) {
      settle_launch_failure(session, route, error.code(), error.what(), error.stage());
    } catch (...) {
      settle_launch_failure(session, route, CITIZENSDK_ERROR_INTERNAL,
                            "CitizenSDK wallet mutation dispatch failed");
    }
  }

  void begin_mutation(const std::shared_ptr<Session> &session,
                      const std::shared_ptr<Route> &route) {
    route->mutation = true;
    route->mutation_owner = std::make_shared<uint8_t>(0);
    if (!acquire_process_mutation(route->mutation_owner)) {
      settle_launch_failure(session, route, CITIZENSDK_ERROR_BUSY,
                            "CitizenSDK wallet mutation is already active");
      return;
    }
    active_mutation = route;
    launch_mutation(session, route);
  }

  void finish_mutation(const std::shared_ptr<Route> &route) {
    if (active_mutation == route) active_mutation.reset();
    release_process_mutation(route->mutation_owner);
    route->mutation_owner.reset();
  }

  void retire_detached_session_if_idle(const std::shared_ptr<Session> &session) {
    if (!is_detached() || !current(session)) return;
    {
      std::lock_guard<std::mutex> guard(session->lock);
      if (!session->routes.empty() || session->admitting) return;
    }
    session->transport->retire();
    session->retired = true;
    sessions.erase(session->id);
    release_detached_state_if_empty();
  }


  void qr_flow(const std::shared_ptr<Session> &session, const std::shared_ptr<Route> &route) {
    route->wallet = true;
    std::weak_ptr<State> weak = shared_from_this();
    std::weak_ptr<Session> target = session;
    auto cancel = session->transport->present_qr(route->request,
      [weak, target, route](citizensdk_error_code_t code, std::string document) noexcept {
        const auto state = weak.lock(); const auto current_session = target.lock();
        if (!state || !current_session) return;
        std::optional<Reply> reply;
        try {
          reply = code == CITIZENSDK_OK
              ? success(route->request, tuple({Value::string(std::move(document))}))
              : failure(code, "CitizenSDK QR flow did not complete", route->request);
        } catch (...) {
          reply = failure(CITIZENSDK_ERROR_INTEGRITY, "CitizenSDK QR result is invalid", route->request);
        }
        {
          std::lock_guard<std::mutex> guard(current_session->lock);
          if (route->completed) return;
          if (route->qr_revoked)
            reply = failure(CITIZENSDK_ERROR_CANCELLED, "CitizenSDK QR flow was cancelled", route->request);
          route->ready = std::move(reply); route->completed = true; route->wallet = false;
          route->qr_cancel = {};
        }
        state->post_drain(current_session);
      });
    {
      std::lock_guard<std::mutex> guard(session->lock);
      if (!route->completed) route->qr_cancel = std::move(cancel);
    }
  }

  void cancel_qr_routes(const std::shared_ptr<Session> &session) {
    std::vector<WalletCancellation> cancellation;
    {
      std::lock_guard<std::mutex> guard(session->lock);
      for (const auto &entry : session->routes) {
        if (!entry.second->completed &&
            (entry.second->request.method == Method::qr_scan ||
             entry.second->request.method == Method::sign_qr_request)) {
          entry.second->qr_revoked = true;
          if (entry.second->qr_cancel) cancellation.push_back(entry.second->qr_cancel);
        }
      }
    }
    // 不能在 session 锁内进入 Host：有限回调可能同步返回。
    for (auto &cancel : cancellation) cancel();
  }

  void wallet(const std::shared_ptr<Session> &session, const std::shared_ptr<Route> &route) {
    route->wallet = true;
    std::weak_ptr<State> weak = shared_from_this();
    std::weak_ptr<Session> target = session;
    wallets.launch(route->request,
      [transport = session->transport](const DecodedRequest &request, WalletFlowCompletion done) {
        return transport->present(request, std::move(done));
      },
      [weak, target, route](WalletFlowResult result) {
        const auto state = weak.lock(); const auto session = target.lock();
        if (!state || !session || !state->current(session)) return;
        route->wallet = false;
        try {
          if (result.status == WalletFlowStatus::Completed && result.error_code == CITIZENSDK_OK) {
            if (route->request.method == Method::view_account_private_key) {
              // 私钥查看只能返回空完成，不投影秘密，也不额外读取钱包资料。
              {
                std::lock_guard<std::mutex> guard(session->lock);
                route->completed = true;
                route->ready = success(route->request, tuple({}));
              }
              state->drain(session);
              return;
            }
            // The GTK flow contains private prepared/import/add operations. Only
            // a new public-profile query is projected onto the original tuple.
            route->native_method = Method::get_wallet_profile;
            state->submit(session, route);
            return;
          }
          throw ContractFailure(
              result.status == WalletFlowStatus::Cancelled
                  ? CITIZENSDK_ERROR_CANCELLED
                  : (result.error_code == CITIZENSDK_OK
                         ? CITIZENSDK_ERROR_INTEGRITY : result.error_code),
              "CitizenSDK wallet flow did not complete");
        } catch (const ContractFailure &error) {
          {
            std::lock_guard<std::mutex> guard(session->lock);
            route->completed = true;
            route->ready = failure(error.code, error.what(), route->request, error.stage);
          }
          state->drain(session);
        } catch (const Error &error) {
          {
            std::lock_guard<std::mutex> guard(session->lock);
            route->completed = true;
            route->ready = failure(error.code(), error.what(), route->request, error.stage());
          }
          state->drain(session);
        } catch (...) {
          {
            std::lock_guard<std::mutex> guard(session->lock);
            route->completed = true;
            route->ready = failure(CITIZENSDK_ERROR_INTERNAL,
                                   "CitizenSDK wallet profile query failed", route->request);
          }
          state->drain(session);
        }
      });
  }

  void drain(const std::shared_ptr<Session> &session) {
    require_owner();
    if (!current(session)) return;
    for (;;) {
      std::shared_ptr<Route> route;
      {
        std::lock_guard<std::mutex> guard(session->lock);
        for (auto found = session->routes.begin(); found != session->routes.end(); ++found) {
          if (!found->second->completed || found->second->accepting) continue;
          route = found->second;
          session->routes.erase(found);
          break;
        }
      }
      if (!route) break;
      auto result = route->ready ? std::move(*route->ready)
          : failure(CITIZENSDK_ERROR_INTERNAL, "CitizenSDK result copying failed", route->request);
      if (result.success && (route->native_method == Method::start ||
                             route->native_method == Method::stop)) {
        try { result = success(route->request, Value::list({lifecycle(session->transport->lifecycle_state())})); }
        catch (const ContractFailure &error) { result = failure(error.code, error.what(), route->request, error.stage); }
        catch (const Error &error) { result = failure(error.code(), error.what(), route->request, error.stage()); }
        catch (...) { result = failure(CITIZENSDK_ERROR_INTERNAL, "CitizenSDK lifecycle query failed", route->request); }
      }
      if (result.success && route->fetch_profile_after_mutation &&
          route->native_method != Method::get_wallet_profile) {
        // delete/deleteAccount/reconcile return EMPTY in the canonical Core.
        // Keep the process mutation gate and original Flutter sequence until
        // a second native request has copied the resulting public profile.
        // EMPTY 不是钱包 profile；保持同一变更锁和公开请求，内部再读一次。
        route->native_method = Method::get_wallet_profile;
        route->native_id = 0;
        route->terminal_seen = false;
        route->completed = false;
        route->ready.reset();
        {
          std::lock_guard<std::mutex> guard(session->lock);
          session->routes.emplace(route->request.sequence, route);
        }
        try { submit(session, route); }
        catch (const ContractFailure &error) {
          settle_launch_failure(session, route, error.code, error.what(), error.stage);
        } catch (const Error &error) {
          settle_launch_failure(session, route, error.code(), error.what(), error.stage());
        } catch (...) {
          settle_launch_failure(session, route, CITIZENSDK_ERROR_INTERNAL,
                                "CitizenSDK wallet profile query failed");
        }
        continue;
      }
      const bool mutation_finished = route->mutation;
      // Release the process gate before exposing terminal completion. A
      // reentrant Flutter reply may immediately begin the next mutation, but
      // never during the canonical Core/GTK/profile chain above.
      if (mutation_finished) finish_mutation(route);
      if (route->close_stop) {
        if (!result.success) close_failed(session, result.error_code, result.message);
      } else if (!is_detached() && route->reply) {
        auto reply = std::move(route->reply);
        // Removal above is the linearization point; a reply may reenter close.
        reply(std::move(result));
      }
    }
    if (is_detached()) {
      retire_detached_session_if_idle(session);
      return;
    }
    if (session->closing) progress_close(session);
  }

  void close_failed(const std::shared_ptr<Session> &session,
                    citizensdk_error_code_t code, const std::string &message) {
    if (!session->close_request) return;
    auto request = std::move(*session->close_request);
    auto reply = std::move(session->close_reply);
    session->close_request.reset();
    session->closing = false;
    if (!is_detached() && reply) reply(failure(code, message, request));
  }

  void progress_close(const std::shared_ptr<Session> &session) {
    if (!current(session) || !session->closing || !session->close_request) return;
    {
      std::lock_guard<std::mutex> guard(session->lock);
      if (!session->routes.empty()) return;
    }
    try {
      const auto state = session->transport->lifecycle_state();
      if (state == CITIZENSDK_LIFECYCLE_RUNNING || state == CITIZENSDK_LIFECYCLE_STARTING ||
          state == CITIZENSDK_LIFECYCLE_IMPORTING_STATE) {
        auto route = std::make_shared<Route>();
        route->request = *session->close_request;
        route->native_method = Method::stop;
        route->close_stop = true;
        {
          std::lock_guard<std::mutex> guard(session->lock);
          session->routes.emplace(route->request.sequence, route);
        }
        submit(session, route);
        return;
      }
      // Host::close rejects still-live result/callback frames as BUSY. This is
      // retryable and retains all ownership; never report disposed beforehand.
      session->transport->close();
      session->retired = true;
      sessions.erase(session->id);
      auto request = std::move(*session->close_request);
      auto reply = std::move(session->close_reply);
      session->close_request.reset();
      if (!is_detached() && reply) reply(success(request, Value::list({Value::string("disposed")})));
    } catch (const ContractFailure &error) { close_failed(session, error.code, error.what()); }
    catch (const Error &error) { close_failed(session, error.code(), error.what()); }
    catch (...) { close_failed(session, CITIZENSDK_ERROR_INTERNAL, "CitizenSDK close failed"); }
  }

  void begin_close(const std::shared_ptr<Session> &session,
                   const DecodedRequest &request, ReplyCallback reply) {
    session->closing = true;
    session->close_request = request;
    session->close_reply = std::move(reply);
    std::exception_ptr first;
    try { wallets.cancel_session(session->id); } catch (...) { first = std::current_exception(); }
    try { cancel_qr_routes(session); } catch (...) { if (!first) first = std::current_exception(); }
    if (first) {
      try { std::rethrow_exception(first); }
      catch (const Error &error) { close_failed(session, error.code(), error.what()); }
      catch (...) { close_failed(session, CITIZENSDK_ERROR_INTERNAL, "CitizenSDK cancellation failed"); }
      return;
    }
    drain(session);
  }

  void dispatch(DecodedRequest request, ReplyCallback reply) {
    require_owner();
    if (!reply) throw ContractFailure(CITIZENSDK_ERROR_INVALID_ARGUMENT, "CitizenSDK reply is required");
    if (is_detached()) { reply(failure(CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK Flutter engine is detached", request)); return; }
    // 不创建或查找 session，不调用环境/Host 工厂，不打开钱包、金库或链。
    if (request.method == Method::verify_signature) {
      uint8_t valid = 0;
      const auto code = citizensdk_verify_signature(
          &request.account_id, view(request.signature), view(request.payload), &valid);
      if (code != CITIZENSDK_OK) {
        reply(failure(code, "CitizenSDK signature verification failed", request));
      } else {
        reply({true, Value::list({Value::integer(kProtocolVersion),
                                 Value::boolean(valid != 0)}), CITIZENSDK_OK, {}});
      }
      return;
    }
    wallets.drain();
    // A previous failed main-loop allocation may have left a copied completion
    // ready. Retry ownership settlement before admitting another request.
    std::vector<std::shared_ptr<Session>> existing;
    for (const auto &pair : sessions) existing.push_back(pair.second);
    for (const auto &session : existing) drain(session);
    if (request.method == Method::open) { open(std::move(request), std::move(reply)); return; }
    const auto found = sessions.find(request.session);
    if (found == sessions.end()) { reply(failure(CITIZENSDK_ERROR_NOT_FOUND, "CitizenSDK session was not found", request)); return; }
    const auto session = found->second;
    if (session->closing || request.sequence != session->next_request) {
      reply(failure(CITIZENSDK_ERROR_CONFLICT, "CitizenSDK request sequence is not the next session sequence", request)); return;
    }
    if (session->next_request == std::numeric_limits<int64_t>::max()) {
      reply(failure(CITIZENSDK_ERROR_INTEGRITY, "CitizenSDK request sequence is exhausted", request)); return;
    }
    ++session->next_request;
    if (request.method == Method::close) { begin_close(session, request, std::move(reply)); return; }
    if (request.method >= Method::qr_parse && request.method <= Method::qr_encode) {
      std::optional<Reply> result;
      try { result = success(request, session->transport->qr(request)); }
      catch (const ContractFailure &error) { result = failure(error.code, error.what(), request, error.stage); }
      catch (const Error &error) { result = failure(error.code(), error.what(), request, error.stage()); }
      catch (...) { result = failure(CITIZENSDK_ERROR_INTERNAL, "CitizenSDK QR operation failed", request); }
      reply(std::move(*result));
      return;
    }
    if (request.method == Method::get_genesis_hash) {
      std::optional<Reply> result;
      try { result = success(request, Value::list({session->transport->genesis_hash()})); }
      catch (const ContractFailure &error) { result = failure(error.code, error.what(), request, error.stage); }
      catch (const Error &error) { result = failure(error.code(), error.what(), request, error.stage()); }
      catch (...) { result = failure(CITIZENSDK_ERROR_INTERNAL, "CitizenSDK genesis query failed", request); }
      reply(std::move(*result));
      return;
    }
    if (request.method == Method::cancel_signing) {
      std::optional<Reply> result;
      try { result = success(request, session->transport->cancel_signing(request)); }
      catch (const ContractFailure &error) { result = failure(error.code, error.what(), request, error.stage); }
      catch (const Error &error) { result = failure(error.code(), error.what(), request, error.stage()); }
      catch (...) { result = failure(CITIZENSDK_ERROR_INTERNAL, "CitizenSDK signing cancellation failed", request); }
      reply(std::move(*result));
      return;
    }
    if (request.method == Method::cancel_prepared_transaction) {
      std::optional<Reply> result;
      try { result = success(request, session->transport->cancel_prepared_transaction(request)); }
      catch (const ContractFailure &error) { result = failure(error.code, error.what(), request, error.stage); }
      catch (const Error &error) { result = failure(error.code(), error.what(), request, error.stage()); }
      catch (...) { result = failure(CITIZENSDK_ERROR_INTERNAL,
                                     "CitizenSDK transaction cancellation failed", request); }
      reply(std::move(*result));
      return;
    }
    if (request.method == Method::cancel_prepared_transaction_execution) {
      std::optional<Reply> result;
      try { result = success(request, session->transport->cancel_transaction_execution(request)); }
      catch (const ContractFailure &error) { result = failure(error.code, error.what(), request, error.stage); }
      catch (const Error &error) { result = failure(error.code(), error.what(), request, error.stage()); }
      catch (...) { result = failure(CITIZENSDK_ERROR_INTERNAL,
                                     "CitizenSDK transaction execution cancellation failed",
                                     request); }
      reply(std::move(*result));
      return;
    }
    if (request.method == Method::get_capabilities) {
      try { reply(success(request, Value::list({session->transport->capability_snapshot()}))); }
      catch (const ContractFailure &error) { reply(failure(error.code, error.what(), request, error.stage)); }
      catch (const Error &error) { reply(failure(error.code(), error.what(), request, error.stage())); }
      catch (...) { reply(failure(CITIZENSDK_ERROR_INTERNAL, "CitizenSDK capability query failed", request)); }
      return;
    }
    auto route = std::make_shared<Route>();
    route->request = std::move(request);
    route->native_method = route->request.method;
    route->reply = std::move(reply);
    route->fetch_profile_after_mutation = needs_profile_read(route->request.method);
    {
      std::lock_guard<std::mutex> guard(session->lock);
      session->routes.emplace(route->request.sequence, route);
    }
    try {
      if (is_mutation(route->request.method)) begin_mutation(session, route);
      else submit(session, route);
    } catch (const ContractFailure &error) {
      {
        std::lock_guard<std::mutex> guard(session->lock);
        route->completed = true; route->ready = failure(error.code, error.what(), route->request, error.stage);
      }
      drain(session);
    } catch (const Error &error) {
      {
        std::lock_guard<std::mutex> guard(session->lock);
        route->completed = true; route->ready = failure(error.code(), error.what(), route->request, error.stage());
      }
      drain(session);
    } catch (...) {
      {
        std::lock_guard<std::mutex> guard(session->lock);
        route->completed = true;
        route->ready = failure(CITIZENSDK_ERROR_INTERNAL, "CitizenSDK request dispatch failed", route->request);
      }
      drain(session);
    }
  }

  void listen(EventSink value) {
    require_owner();
    if (is_detached()) throw ContractFailure(CITIZENSDK_ERROR_UNAVAILABLE, "CitizenSDK Flutter engine is detached");
    if (!value) throw ContractFailure(CITIZENSDK_ERROR_INVALID_ARGUMENT, "CitizenSDK event sink is required");
    if (sink) throw ContractFailure(CITIZENSDK_ERROR_BUSY, "CitizenSDK event subscription is already active");
    advance_epoch(); sink = std::move(value);
    std::vector<std::shared_ptr<Session>> current_sessions;
    for (const auto &pair : sessions) current_sessions.push_back(pair.second);
    const auto expected = snapshot_epoch();
    for (const auto &session : current_sessions) {
      try { snapshots(session, expected); } catch (...) {}
    }
  }
  void cancel_events() {
    require_owner();
    if (is_detached()) { sink = {}; return; }
    advance_epoch(); sink = {};
  }

  void detach() noexcept {
    // This method is called synchronously by plugin dispose on its owner
    // thread, before messenger handles are retired. Host callbacks never wait
    // for this UI thread, so Host's callback barrier cannot deadlock it.
    try { advance_epoch(true); } catch (...) {}
    sink = {};
    if (!sessions.empty()) retain_detached_state();
    for (auto found = sessions.begin(); found != sessions.end();) {
      const auto session = (found++)->second;
      session->closing = true;
      session->close_reply = {};
      try { wallets.cancel_session(session->id); } catch (...) {}
      try { cancel_qr_routes(session); } catch (...) {}
      {
        std::lock_guard<std::mutex> guard(session->lock);
        for (auto &route_pair : session->routes) route_pair.second->reply = {};
      }
      retire_detached_session_if_idle(session);
    }
    release_detached_state_if_empty();
  }
};

Sessions::Sessions(std::shared_ptr<State> state) : state_(std::move(state)) {}
std::shared_ptr<Sessions> Sessions::create(EnvironmentFactory environment,
                                          Scheduler scheduler, TransportFactory factory) {
  if (!environment || !scheduler)
    throw ContractFailure(CITIZENSDK_ERROR_INVALID_ARGUMENT, "CitizenSDK environment and scheduler are required");
  if (!factory) factory = [](const Config &config) { return std::make_shared<HostTransport>(config); };
  return std::shared_ptr<Sessions>(new Sessions(
      std::make_shared<State>(std::move(environment), std::move(scheduler), std::move(factory))));
}
Sessions::~Sessions() { state_->detach(); }
void Sessions::dispatch(DecodedRequest request, ReplyCallback reply) { state_->dispatch(std::move(request), std::move(reply)); }
void Sessions::listen(EventSink sink) { state_->listen(std::move(sink)); }
void Sessions::cancel_events() { state_->cancel_events(); }
void Sessions::detach() noexcept { state_->detach(); }
std::size_t Sessions::session_count() const { state_->require_owner(); return state_->sessions.size(); }

}  // namespace citizen_sdk::flutter
