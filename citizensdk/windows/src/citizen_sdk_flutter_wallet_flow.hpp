#ifndef CITIZENSDK_WINDOWS_FLUTTER_WALLET_FLOW_HPP
#define CITIZENSDK_WINDOWS_FLUTTER_WALLET_FLOW_HPP

#include <cstddef>
#include <functional>
#include <memory>
#include <string>
#include "citizen_sdk/citizen_sdk_wallet_flow.hpp"
#include "citizen_sdk_flutter_codec.hpp"

namespace citizen_sdk::flutter {

using Scheduler = std::function<void(std::function<void()>)>;
using WalletCancellation = std::function<void()>;
using WalletPresenter = std::function<WalletCancellation(
    const DecodedRequest &, WalletFlowCompletion)>;

// Owns only public flow identity and a native cancellation capability. The
// presenter is the existing Host Win32 wallet flow; no mnemonic/password/private
// key or prepared-wallet token is admitted by this bridge.
class FlutterWalletFlows final {
 public:
  explicit FlutterWalletFlows(Scheduler scheduler);
  ~FlutterWalletFlows();
  FlutterWalletFlows(const FlutterWalletFlows &) = delete;
  FlutterWalletFlows &operator=(const FlutterWalletFlows &) = delete;

  static WalletFlowRequest contract(const DecodedRequest &request);
  void launch(const DecodedRequest &request, WalletPresenter presenter,
              WalletFlowCompletion completion);
  // Cancellation is a request, never a terminal result. Accepted completion
  // still owns the entry until the existing Win32 flow reports its outcome.
  void cancel_session(const std::string &session);
  void drain();
  std::size_t active_count() const;

 private:
  struct State;
  std::shared_ptr<State> state_;
};

}  // namespace citizen_sdk::flutter
#endif
