#ifndef CITIZENSDK_LINUX_FLUTTER_SESSIONS_HPP
#define CITIZENSDK_LINUX_FLUTTER_SESSIONS_HPP

#include <functional>
#include <memory>
#include <string>
#include "citizen_sdk/citizen_sdk_config.hpp"
#include "citizen_sdk_flutter_codec.hpp"
#include "citizen_sdk_flutter_environment.hpp"
#include "citizen_sdk_flutter_wallet_flow.hpp"

namespace citizen_sdk::flutter {

struct Reply final {
  bool success{};
  Value value;
  citizensdk_error_code_t error_code{CITIZENSDK_OK};
  std::string message;
};
using ReplyCallback = std::function<void(Reply)>;
using EventSink = std::function<void(Value)>;
using EnvironmentFactory = std::function<OpenEnvironment(uint32_t modules)>;

// Internal native seam, not an exported SDK API. Production delegates only to
// the installed Host and its borrowed Core. Tests inject finite callbacks into
// the same routing/state machine without running a chain, GTK or TPM.
class NativeTransport {
 public:
  using Observer = std::function<void(const citizensdk_event_t &)>;
  virtual ~NativeTransport() = default;
  virtual void observe(Observer observer) = 0;
  virtual citizensdk_error_code_t accept(Method native_method,
                                        const DecodedRequest &public_request,
                                        citizensdk_request_id_t *out_id) = 0;
  // Result is borrowed for Observer's dynamic extent. Transport owns and
  // releases it exactly once, including decoder exceptions/unknown routes.
  virtual Value copy_result(Method method, citizensdk_result_handle_t result) = 0;
  virtual citizensdk_lifecycle_t lifecycle_state() = 0;
  virtual Value capability_snapshot() = 0;
  virtual Value genesis_hash() = 0;
  virtual Value cancel_signing(const DecodedRequest &) {
    throw ContractFailure(CITIZENSDK_ERROR_UNSUPPORTED, "Signing cancellation is unavailable");
  }
  virtual Value cancel_prepared_transaction(const DecodedRequest &) {
    throw ContractFailure(CITIZENSDK_ERROR_UNSUPPORTED,
                          "Prepared transaction cancellation is unavailable");
  }
  virtual Value cancel_transaction_execution(const DecodedRequest &) {
    throw ContractFailure(CITIZENSDK_ERROR_UNSUPPORTED,
                          "Transaction execution cancellation is unavailable");
  }
  virtual Value qr(const DecodedRequest &) {
    throw ContractFailure(CITIZENSDK_ERROR_UNSUPPORTED, "QR transport is unavailable");
  }
  using QrCompletion = std::function<void(citizensdk_error_code_t, std::string)>;
  virtual WalletCancellation present_qr(const DecodedRequest &, QrCompletion) {
    throw ContractFailure(CITIZENSDK_ERROR_UNSUPPORTED, "QR native UI is unavailable");
  }
  virtual void cancel(citizensdk_request_id_t request) = 0;
  virtual WalletCancellation present(const DecodedRequest &request,
                                      WalletFlowCompletion completion) = 0;
  virtual void close() = 0;
  // No-throw ownership transfer to the existing Host supervisor. Caller must
  // cease use afterwards. A live transport is never silently dropped.
  virtual void retire() noexcept = 0;
};
using TransportFactory = std::function<std::shared_ptr<NativeTransport>(const Config &)>;

class Sessions final : public std::enable_shared_from_this<Sessions> {
 public:
  static std::shared_ptr<Sessions> create(EnvironmentFactory environment,
                                           Scheduler scheduler,
                                           TransportFactory transport = {});
  ~Sessions();
  Sessions(const Sessions &) = delete;
  Sessions &operator=(const Sessions &) = delete;

  // All entry points belong to the registrar's UI thread. Scheduler must queue
  // onto that thread and must never execute inline on a native callback thread.
  void dispatch(DecodedRequest request, ReplyCallback reply);
  void listen(EventSink sink);
  void cancel_events();
  void detach() noexcept;
  std::size_t session_count() const;

 private:
  struct State;
  explicit Sessions(std::shared_ptr<State> state);
  std::shared_ptr<State> state_;
};

}  // namespace citizen_sdk::flutter
#endif
