#ifndef CITIZENSDK_CPP_MODELS_HPP
#define CITIZENSDK_CPP_MODELS_HPP

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>
#include "citizensdk_types.h"

namespace citizen_sdk {

struct CapabilityStatus {
  citizensdk_capability_name_t name{};
  citizensdk_capability_reason_t reason{};
  bool supported{};
  bool available{};
  bool enabled{};
  bool ready{};
};

struct Capabilities {
  uint64_t revision{};
  std::vector<CapabilityStatus> statuses;
};

struct BlockRef {
  std::array<uint8_t, 32> hash{};
  uint64_t number{};
  citizensdk_finality_t finality{CITIZENSDK_FINALITY_FINALIZED};
};

struct AccountId { std::array<uint8_t, 32> bytes{}; };

struct WalletStateAccount {
  citizensdk_wallet_sign_mode_t sign_mode{};
  uint32_t wallet_index{};
  std::optional<uint32_t> account_index;
  AccountId account_id;
  std::string ss58_address;
  std::string name;
  uint64_t created_at_millis{};
  bool is_default{};
};

struct WalletState {
  uint64_t revision{};
  std::vector<WalletStateAccount> accounts;
  const WalletStateAccount *default_account() const noexcept {
    return accounts.empty() ? nullptr : &accounts.front();
  }
};

}  // namespace citizen_sdk

#endif
