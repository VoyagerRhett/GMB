#ifndef CITIZENSDK_CPP_WALLET_FLOW_HPP
#define CITIZENSDK_CPP_WALLET_FLOW_HPP

#include <cstdint>
#include <functional>
#include <string>
#include <vector>
#include "citizen_sdk/citizensdk_host.h"
#include "citizen_sdk/citizen_sdk_error.hpp"

namespace citizen_sdk {

enum class WalletFlowKind : uint32_t { Create = 1, Import = 2, AddAccounts = 3 };
enum class WalletFlowStatus : uint32_t { Completed = 1, Cancelled = 2, Failed = 3 };

struct WalletFlowRequest {
  WalletFlowKind kind{WalletFlowKind::Create};
  uint32_t word_count{12};
  std::vector<uint32_t> account_indices;
};

struct WalletFlowResult {
  WalletFlowStatus status;
  citizensdk_error_code_t error_code;
};

using WalletFlowCompletion = std::function<void(WalletFlowResult)>;

struct QrImage {
  uint32_t width{}, height{};
  std::vector<uint8_t> luminance;
};
struct QrFlowResult {
  citizensdk_error_code_t error_code{CITIZENSDK_OK};
  std::string document;
  std::string canonical_text;
  std::string request_id;
  std::string signer_account_id;
  std::string sign_request;
  std::vector<uint8_t> signature;
  QrImage qr_image;
};
using QrFlowCompletion = std::function<void(QrFlowResult)>;

class WalletFlow final {
 public:
  WalletFlow() = default;
  WalletFlow(citizensdk_host_handle_t host, citizensdk_wallet_flow_handle_t flow)
      : host_(host), flow_(flow) {}
  citizensdk_wallet_flow_handle_t native_handle() const noexcept { return flow_; }
  void cancel() {
    if (flow_ == 0) return;
    const auto code = citizensdk_host_cancel_wallet_flow(host_, flow_);
    if (code != CITIZENSDK_OK && code != CITIZENSDK_ERROR_INVALID_HANDLE) {
      throw Error(code, "CitizenSDK wallet-flow cancellation failed");
    }
  }

 private:
  citizensdk_host_handle_t host_{};
  citizensdk_wallet_flow_handle_t flow_{};
};

}  // namespace citizen_sdk

#endif
