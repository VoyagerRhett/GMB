#include <cassert>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "citizen_sdk_flutter_wallet_flow.hpp"
#include "citizen_sdk_flutter_test_support.hpp"
#include "citizen_sdk_host_record.hpp"
#include "citizen_sdk_wallet_validation.hpp"

#ifdef NDEBUG
#error "CitizenSDK Flutter wallet-flow contract assertions must remain enabled"
#endif

using citizen_sdk::WalletFlowKind;
using citizen_sdk::WalletFlowResult;
using citizen_sdk::WalletFlowStatus;
using citizen_sdk::flutter::DecodedRequest;
using citizen_sdk::flutter::FlutterWalletFlows;
using citizen_sdk::flutter::Method;

namespace {

// 与公开 C++ 门面的字段投影一致，并实际调用 Host 生产校验器；不再让
// mock presenter 仅比较 kind、却漏掉会在 Host 被拒绝的 word_count。
citizen_sdk::linux::ValidatedWalletRequest validate_contract(
    const citizen_sdk::WalletFlowRequest &request) {
  citizensdk_wallet_flow_request_v1_t native{};
  native.struct_size = sizeof(native);
  native.abi_version = CITIZENSDK_HOST_ABI_VERSION;
  native.kind = static_cast<uint32_t>(request.kind);
  native.word_count = request.word_count;
  native.account_indices = request.account_indices.empty()
                               ? nullptr : request.account_indices.data();
  native.account_index_count = static_cast<uint32_t>(request.account_indices.size());
  return citizen_sdk::linux::validate_wallet_request(native);
}

void expect_host_rejection(const citizen_sdk::WalletFlowRequest &request) {
  bool rejected = false;
  try {
    (void)validate_contract(request);
  } catch (const citizen_sdk::linux::HostError &error) {
    rejected = error.code() == CITIZENSDK_ERROR_INVALID_ARGUMENT;
  }
  assert(rejected);
}

}  // namespace


int main() {
  std::vector<std::function<void()>> queue;
  FlutterWalletFlows flows([&](std::function<void()> work) {
    queue.push_back(std::move(work));
  });

  DecodedRequest create;
  create.method = Method::create_wallet;
  create.session = "session-a";
  create.sequence = 1;
  create.word_count = 24;
  auto contract = FlutterWalletFlows::contract(create);
  assert(contract.kind == WalletFlowKind::Create && contract.word_count == 24);
  assert(validate_contract(contract).word_count == CITIZENSDK_WALLET_WORDS_24);
  auto twelve = create;
  twelve.word_count = 12;
  assert(validate_contract(FlutterWalletFlows::contract(twelve)).word_count ==
         CITIZENSDK_WALLET_WORDS_12);
  auto eighteen = create;
  eighteen.word_count = 18;
  assert(validate_contract(FlutterWalletFlows::contract(eighteen)).word_count ==
         CITIZENSDK_WALLET_WORDS_18);
  assert(citizen_sdk::WalletFlowRequest{}.word_count == 12);

  int completions = 0;
  // Deliberately complete before the presenter returns. The production bridge
  // must have preallocated the route and must settle it exactly once.
  flows.launch(create,
    [](const auto &decoded, auto completion) {
      const auto request = FlutterWalletFlows::contract(decoded);
      assert(request.kind == WalletFlowKind::Create);
      assert(validate_contract(request).word_count == CITIZENSDK_WALLET_WORDS_24);
      completion({WalletFlowStatus::Completed, CITIZENSDK_OK});
      completion({WalletFlowStatus::Failed, CITIZENSDK_ERROR_INTERNAL});
      return [] {};
    },
    [&](WalletFlowResult result) {
      ++completions;
      assert(result.status == WalletFlowStatus::Completed);
    });
  assert(completions == 1);
  assert(flows.active_count() == 0);
  for (auto &work : queue) work();
  assert(completions == 1);

  DecodedRequest imported;
  imported.method = Method::import_wallet;
  imported.session = "session-b";
  imported.sequence = 9;
  bool cancelled = false;
  citizen_sdk::WalletFlowCompletion late;
  flows.launch(imported,
    [&](const auto &decoded, auto completion) {
      const auto request = FlutterWalletFlows::contract(decoded);
      assert(request.kind == WalletFlowKind::Import);
      assert(request.word_count == 0 && request.account_indices.empty());
      assert(validate_contract(request).kind == CITIZENSDK_WALLET_FLOW_IMPORT);
      late = std::move(completion);
      return [&] { cancelled = true; };
    },
    [&](WalletFlowResult result) {
      ++completions;
      assert(result.status == WalletFlowStatus::Cancelled);
    });
  flows.cancel_session("session-b");
  assert(cancelled);
  assert(flows.active_count() == 1);  // cancel is not a terminal promise
  late({WalletFlowStatus::Cancelled, CITIZENSDK_OK});
  assert(completions == 1);
  assert(!queue.empty());
  queue.back()();
  assert(completions == 2 && flows.active_count() == 0);

  DecodedRequest add;
  add.method = Method::add_wallet_accounts;
  add.indices = {1, 1989};
  contract = FlutterWalletFlows::contract(add);
  assert(contract.kind == WalletFlowKind::AddAccounts);
  assert(contract.account_indices == add.indices);
  assert(contract.word_count == 0);
  const auto validated_add = validate_contract(contract);
  assert(validated_add.kind == CITIZENSDK_WALLET_FLOW_ADD_ACCOUNTS);
  assert(validated_add.word_count == 0 && validated_add.account_indices == add.indices);

  // 保持 Host 的严格拒绝合同，不能通过放宽校验掩盖适配层污染。
  auto contaminated = FlutterWalletFlows::contract(imported);
  contaminated.word_count = 12;
  expect_host_rejection(contaminated);
  contaminated = contract;
  contaminated.word_count = 24;
  expect_host_rejection(contaminated);
  contaminated = contract;
  contaminated.account_indices = {1, 1};
  expect_host_rejection(contaminated);
  contaminated.account_indices = {};
  expect_host_rejection(contaminated);
  contaminated = FlutterWalletFlows::contract(create);
  contaminated.account_indices = {1};
  expect_host_rejection(contaminated);

  for (const uint32_t words : {15U, 21U}) {
    auto invalid = create;
    invalid.word_count = words;
    citizen_sdk::flutter::test::expect_failure(
        [&] { (void)FlutterWalletFlows::contract(invalid); },
        CITIZENSDK_ERROR_INVALID_ARGUMENT);
  }

  // 查看只传公开账户并复用同一排空路由；取消先于晚回调不算已结束。
  DecodedRequest viewing;
  viewing.method = Method::view_account_private_key;
  viewing.session = "private-view"; viewing.sequence = 1;
  viewing.account_id.bytes[0] = 7;
  citizen_sdk::WalletFlowCompletion view_done;
  int view_cancelled = 0, view_completed = 0;
  flows.launch(viewing, [&](const auto &request, auto completion) {
    assert(request.method == Method::view_account_private_key && request.account_id.bytes[0] == 7);
    assert(request.payload.empty() && request.indices.empty());
    view_done = std::move(completion);
    return [&] { ++view_cancelled; };
  }, [&](WalletFlowResult result) {
    assert(result.status == WalletFlowStatus::Cancelled);
    ++view_completed;
  });
  flows.cancel_session(viewing.session);
  assert(view_cancelled == 1 && view_completed == 0 && flows.active_count() == 1);
  view_done({WalletFlowStatus::Cancelled, CITIZENSDK_ERROR_CANCELLED});
  flows.drain();
  view_done({WalletFlowStatus::Completed, CITIZENSDK_OK});
  flows.drain();
  assert(view_completed == 1 && flows.active_count() == 0);

  // No secret-bearing field exists in either the decoded public request or
  // wallet contract; import receives all secrets only inside Host-owned GTK.
  static_assert(sizeof(citizen_sdk::WalletFlowRequest) < 128);
  return 0;
}
