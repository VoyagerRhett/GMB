#ifndef CITIZENSDK_LINUX_WALLET_VALIDATION_HPP
#define CITIZENSDK_LINUX_WALLET_VALIDATION_HPP

#include <cstdint>
#include <optional>
#include <vector>
#include "citizen_sdk/citizensdk_host.h"

namespace citizen_sdk::linux {

struct ValidatedWalletRequest final {
  // SDK 内部查看模式；不改变公开 WalletFlowKind 或 C 请求结构。
  std::optional<citizensdk_account_id_t> account_id;
  citizensdk_wallet_flow_kind_t kind{};
  citizensdk_wallet_word_count_t word_count{};
  std::vector<uint32_t> account_indices;
};

ValidatedWalletRequest validate_wallet_request(
    const citizensdk_wallet_flow_request_v1_t &request);

}  // namespace citizen_sdk::linux

#endif
