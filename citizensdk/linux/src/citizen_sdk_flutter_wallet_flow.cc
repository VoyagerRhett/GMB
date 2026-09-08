#include "citizen_sdk_flutter_wallet_flow.hpp"

#include <exception>
#include <map>
#include <mutex>
#include <optional>
#include <utility>
#include <vector>

namespace citizen_sdk::flutter {

struct FlutterWalletFlows::State final : std::enable_shared_from_this<State> {
  using Key = std::pair<std::string, int64_t>;
  struct Entry final {
    WalletCancellation cancel;
    WalletFlowCompletion completion;
    std::optional<WalletFlowResult> result;
    bool cancel_requested{};
    bool admitted{};
  };
  explicit State(Scheduler value) : schedule(std::move(value)) {}
  Scheduler schedule;
  mutable std::mutex lock;
  std::map<Key, std::shared_ptr<Entry>> active;

  void finish(const Key &key, const std::shared_ptr<Entry> &entry,
              WalletFlowResult result) noexcept {
    {
      std::lock_guard<std::mutex> guard(lock);
      const auto found = active.find(key);
      if (found == active.end() || found->second != entry || entry->result) return;
      entry->result = result;
    }
    // A scheduler allocation failure does not lose accepted completion. The
    // result remains in Entry and the next main-thread dispatch/drain retries.
    try {
      std::weak_ptr<State> weak = shared_from_this();
      schedule([weak] { if (const auto state = weak.lock()) state->drain(); });
    } catch (...) {}
  }

  void drain() {
    for (;;) {
      WalletFlowCompletion completion;
      std::optional<WalletFlowResult> result;
      {
        std::lock_guard<std::mutex> guard(lock);
        auto found = active.begin();
        while (found != active.end() &&
               (!found->second->admitted || !found->second->result)) ++found;
        if (found == active.end()) return;
        completion = std::move(found->second->completion);
        result = found->second->result;
        active.erase(found);
      }
      // Retire ownership before invoking a reentrant consumer. Duplicate/late
      // native callbacks cannot settle the same request a second time.
      if (completion) completion(*result);
    }
  }
};

FlutterWalletFlows::FlutterWalletFlows(Scheduler scheduler)
    : state_(std::make_shared<State>(std::move(scheduler))) {
  if (!state_->schedule) throw ContractFailure(CITIZENSDK_ERROR_INVALID_ARGUMENT,
                                               "wallet scheduler is required");
}
FlutterWalletFlows::~FlutterWalletFlows() = default;

WalletFlowRequest FlutterWalletFlows::contract(const DecodedRequest &request) {
  WalletFlowRequest value;
  switch (request.method) {
    case Method::create_wallet:
      if (request.word_count != 12 && request.word_count != 18 &&
          request.word_count != 24)
        throw ContractFailure(CITIZENSDK_ERROR_INVALID_ARGUMENT,
                              "wallet word count must be 12, 18, or 24");
      value.kind = WalletFlowKind::Create;
      value.word_count = request.word_count;
      break;
    case Method::import_wallet:
      value.kind = WalletFlowKind::Import;
      // word_count 仅属于创建；导入必须按 Host 合同清空默认创建参数。
      value.word_count = 0;
      break;
    case Method::add_wallet_accounts:
      value.kind = WalletFlowKind::AddAccounts;
      value.word_count = 0;
      value.account_indices = request.indices;
      break;
    default:
      throw ContractFailure(CITIZENSDK_ERROR_INVALID_ARGUMENT,
                            "method is not an SDK-owned wallet flow");
  }
  return value;
}

void FlutterWalletFlows::launch(const DecodedRequest &request,
                               WalletPresenter presenter,
                               WalletFlowCompletion completion) {
  if (!presenter || !completion || request.session.empty() || request.sequence <= 0)
    throw ContractFailure(CITIZENSDK_ERROR_INVALID_ARGUMENT,
                          "wallet flow requires a presenter and session request");
  if (request.method != Method::view_account_private_key) (void)contract(request);
  const State::Key key{request.session, request.sequence};
  auto entry = std::make_shared<State::Entry>();
  entry->completion = std::move(completion);
  {
    std::lock_guard<std::mutex> guard(state_->lock);
    if (!state_->active.emplace(key, entry).second)
      throw ContractFailure(CITIZENSDK_ERROR_CONFLICT, "wallet flow already exists");
  }
  WalletCancellation cancel;
  try {
    // Preallocation precedes the Host accepting call. Completion is allowed
    // before present() returns; admitted prevents early UI-thread settlement.
    const auto state = state_;
    cancel = presenter(request, [state, key, entry](WalletFlowResult result) {
      state->finish(key, entry, result);
    });
  } catch (...) {
    std::lock_guard<std::mutex> guard(state_->lock);
    state_->active.erase(key);
    throw;
  }
  bool cancel_now = false;
  {
    std::lock_guard<std::mutex> guard(state_->lock);
    entry->cancel = std::move(cancel);
    entry->admitted = true;
    cancel_now = entry->cancel_requested && !entry->result;
  }
  // Do not treat cancellation failure as launch rejection: the native flow
  // has already been accepted and must retain its completion ownership.
  if (cancel_now && entry->cancel) {
    try { entry->cancel(); } catch (...) {}
  }
  state_->drain();
}

void FlutterWalletFlows::cancel_session(const std::string &session) {
  // 取消只是请求：仍保留 entry，直到既有 GTK 流程报告真实终态，不能假装回滚。
  std::vector<WalletCancellation> cancellations;
  {
    std::lock_guard<std::mutex> guard(state_->lock);
    for (auto &pair : state_->active) {
      if (pair.first.first != session || pair.second->result) continue;
      pair.second->cancel_requested = true;
      if (pair.second->cancel) cancellations.push_back(pair.second->cancel);
    }
  }
  // Try every flow even if one native cancel reports a transient BUSY error.
  std::exception_ptr first_failure;
  for (const auto &cancel : cancellations) {
    try { cancel(); } catch (...) { if (!first_failure) first_failure = std::current_exception(); }
  }
  if (first_failure) std::rethrow_exception(first_failure);
}

void FlutterWalletFlows::drain() { state_->drain(); }
std::size_t FlutterWalletFlows::active_count() const {
  std::lock_guard<std::mutex> guard(state_->lock);
  return state_->active.size();
}

}  // namespace citizen_sdk::flutter
