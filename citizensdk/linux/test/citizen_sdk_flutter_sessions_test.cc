#include <cassert>
#include <algorithm>
#include <future>
#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "citizen_sdk/citizen_sdk_error.hpp"
#include "citizen_sdk_flutter_sessions.hpp"

#ifdef NDEBUG
#error "CitizenSDK Flutter session contract assertions must remain enabled"
#endif

namespace csf = citizen_sdk::flutter;

namespace {

const csf::Value::List &items(const csf::Value &value) {
  return std::get<csf::Value::List>(value.data);
}
const std::string &text(const csf::Value &value) {
  return std::get<std::string>(value.data);
}

class FakeTransport final : public csf::NativeTransport {
 public:
  void observe(Observer value) override { observer = std::move(value); }
  citizensdk_error_code_t accept(csf::Method native_method,
                                 const csf::DecodedRequest &request,
                                 citizensdk_request_id_t *out) override {
    accepted.push_back(native_method);
    public_methods.push_back(request.method);
    if (native_method == csf::Method::get_account_balances) balance_count = request.account_ids.size();
    if (fail_accept) { *out = 0; return CITIZENSDK_ERROR_NETWORK; }
    if (native_method == csf::Method::start) lifecycle = CITIZENSDK_LIFECYCLE_RUNNING;
    if (native_method == csf::Method::stop) lifecycle = CITIZENSDK_LIFECYCLE_STOPPED;
    const auto id = next_id++;
    if ((defer_history && native_method == csf::Method::get_transaction_history) ||
        (defer_profile && native_method == csf::Method::get_wallet_profile)) {
      deferred_id = id; *out = id; return CITIZENSDK_OK;
    }
    citizensdk_event_t event{};
    event.struct_size = sizeof(event); event.abi_version = CITIZENSDK_ABI_VERSION;
    event.event_type = CITIZENSDK_EVENT_REQUEST_COMPLETED;
    event.request_id = id; event.result = id + 1000;
    observer(event);  // early completion before acceptance returns
    ++released_results; // models Host observer wrapper's exact release
    *out = id;
    return CITIZENSDK_OK;
  }
  csf::Value copy_result(csf::Method method, citizensdk_result_handle_t) override {
    ++copied_results;
    if (method == csf::Method::get_account_balances) {
      csf::Value::List balances;
      for (std::size_t index = 0; index < balance_count; ++index) {
        balances.push_back(csf::Value::list({
            csf::Value::string("0x" + std::string(64, '0')),
            csf::Value::list({csf::Value::string("0x" + std::string(64, '0')),
                             csf::Value::string("1"), csf::Value::string("finalized")}),
            csf::Value::string("1"), csf::Value::string("0"), csf::Value::string("1")}));
      }
      return csf::Value::list({csf::Value::list(std::move(balances))});
    }
    if (method == csf::Method::get_transaction_history ||
        method == csf::Method::sync_transaction_history)
      return csf::Value::list({csf::Value::list({csf::Value::string("0"),
          csf::Value::list({}), csf::Value::null()})});
    if (method == csf::Method::start || method == csf::Method::stop ||
        method == csf::Method::delete_wallet_account ||
        method == csf::Method::delete_wallet ||
        method == csf::Method::reconcile_wallet_cleanup)
      return csf::Value::list({}); // canonical Core EMPTY, not a fake profile
    return csf::Value::list({csf::Value::string(csf::method_name(method))});
  }
  citizensdk_lifecycle_t lifecycle_state() override { return lifecycle; }
  csf::Value genesis_hash() override {
    ++genesis_queries;
    return csf::Value::string("0x" + std::string(64, '0'));
  }
  csf::Value capability_snapshot() override {
    return csf::Value::list({csf::Value::integer(10)});
  }
  std::function<void(uint64_t)> credential_cancel;
  std::vector<uint64_t> credential_cancellations;
  void cancel_credential(uint64_t id) override {
    credential_cancellations.push_back(id);
    if (credential_cancel) credential_cancel(id);
  }
  void cancel(citizensdk_request_id_t request) override {
    ++cancelled;
    assert(request == deferred_id);
    complete_deferred();
  }
  void complete_deferred() {
    assert(deferred_id != 0);
    citizensdk_event_t event{};
    event.struct_size = sizeof(event); event.abi_version = CITIZENSDK_ABI_VERSION;
    event.event_type = CITIZENSDK_EVENT_REQUEST_COMPLETED;
    event.request_id = deferred_id; event.result = deferred_id + 1000;
    observer(event); ++released_results;
    deferred_id = 0;
  }
  csf::WalletCancellation present(const csf::DecodedRequest &request,
                                   citizen_sdk::WalletFlowCompletion completion) override {
    ++wallet_presented;
    assert(request.method == csf::Method::view_account_private_key ||
           request.method == csf::Method::create_wallet ||
           request.method == csf::Method::import_wallet ||
           request.method == csf::Method::add_wallet_accounts);
    if (defer_wallet) wallet_completion = std::move(completion);
    else completion({citizen_sdk::WalletFlowStatus::Completed, CITIZENSDK_OK});
    return [this] { ++wallet_cancelled; };
  }
  csf::WalletCancellation present_qr(const csf::DecodedRequest &request, QrCompletion completion) override {
    assert(request.method == csf::Method::qr_scan || request.method == csf::Method::sign_qr_request);
    ++qr_presented; qr_completion = std::move(completion);
    return [this] { ++qr_cancelled; };
  }
  void close() override {
    if (fail_close) throw citizen_sdk::Error(CITIZENSDK_ERROR_STORAGE,
                                             "injected close failure");
    ++closed; lifecycle = CITIZENSDK_LIFECYCLE_DISPOSED;
  }
  void retire() noexcept override { ++retired; }

  std::size_t balance_count{};
  int genesis_queries{};
  Observer observer;
  citizensdk_lifecycle_t lifecycle{CITIZENSDK_LIFECYCLE_CREATED};
  citizensdk_request_id_t next_id{1};
  citizensdk_request_id_t deferred_id{};
  std::vector<csf::Method> accepted;
  std::vector<csf::Method> public_methods;
  int copied_results{};
  int released_results{};
  int cancelled{};
  QrCompletion qr_completion;
  int qr_presented{};
  int qr_cancelled{};
  int wallet_presented{};
  int wallet_cancelled{};
  int closed{};
  int retired{};
  bool defer_history{};
  bool fail_close{};
  bool fail_accept{};
  bool defer_profile{};
  bool defer_wallet{};
  citizen_sdk::WalletFlowCompletion wallet_completion;
};

csf::DecodedRequest request(csf::Method method, const std::string &session,
                            int64_t sequence) {
  csf::DecodedRequest value;
  value.method = method; value.session = session; value.sequence = sequence;
  value.word_count = 12; value.indices = {1}; value.account_ids = {value.account_id};
  value.amount.low = 1;
  return value;
}

void drain_tasks(std::vector<std::function<void()>> &queue) {
  while (!queue.empty()) {
    auto current = std::move(queue);
    queue.clear();
    for (auto &work : current) work();
  }
}

}  // namespace

int main() {

  {
    // 只替代OS/Core执行器；凭据关联、事件、回包、关闭均运行生产Sessions状态机。
    std::vector<std::function<void()>> credential_queue;
    std::vector<decltype(citizen_sdk::Config::credentialProvider)> providers;
    std::vector<std::shared_ptr<FakeTransport>> natives;
    std::vector<csf::Value> events;
    auto credential_sessions = csf::Sessions::create(
        [](uint32_t) { return csf::OpenEnvironment{}; },
        [&](std::function<void()> work) { credential_queue.push_back(std::move(work)); },
        [&](const citizen_sdk::Config &config) {
          providers.push_back(config.credentialProvider);
          auto native = std::make_shared<FakeTransport>();
          natives.push_back(native);
          return native;
        });
    credential_sessions->listen([&](csf::Value value) { events.push_back(std::move(value)); });
    auto open = request(csf::Method::open, {}, 0);
    open.has_credential_provider = true;
    csf::Reply first_open, second_open;
    credential_sessions->dispatch(open, [&](csf::Reply value) { first_open = std::move(value); });
    credential_sessions->dispatch(open, [&](csf::Reply value) { second_open = std::move(value); });
    assert(first_open.success && second_open.success && providers.size() == 2);
    assert(providers[0] && providers[1]);
    const auto first = text(items(first_open.value)[1]);
    const auto second = text(items(second_open.value)[1]);
    std::promise<void> cancel_first;
    citizen_sdk::CredentialChallenge challenge{71, "unlock", std::nullopt,
                                               cancel_first.get_future().share()};
    auto future = providers[0](challenge);
    drain_tasks(credential_queue);
    bool seen = false;
    for (const auto &event : events) {
      const auto &fields = items(event);
      if (text(fields[3]) == "credentialRequest") {
        assert(text(fields[1]) == first);
        const auto &payload = items(fields[4]);
        assert(payload.size() == 3 && text(payload[0]) == "71" && text(payload[1]) == "unlock");
        seen = true;
      }
    }
    assert(seen);
    auto response = request(csf::Method::respond_credential, second, 1);
    response.host_operation_id = 71;
    response.credential.emplace(std::vector<uint8_t>(12, 'a'));
    csf::Reply wrong_host;
    credential_sessions->dispatch(response, [&](csf::Reply value) { wrong_host = std::move(value); });
    assert(!wrong_host.success && wrong_host.error_code == CITIZENSDK_ERROR_INVALID_STATE);
    response.session = first;
    csf::Reply delivered;
    credential_sessions->dispatch(response, [&](csf::Reply value) { delivered = std::move(value); });
    assert(delivered.success && items(items(delivered.value)[3]).empty());
    auto bytes = future.get();
    assert(bytes && *bytes == std::vector<uint8_t>(12, 'a'));
    std::fill(bytes->begin(), bytes->end(), 0);
    response.sequence = 2;
    csf::Reply duplicate;
    credential_sessions->dispatch(response, [&](csf::Reply value) { duplicate = std::move(value); });
    assert(!duplicate.success && duplicate.error_code == CITIZENSDK_ERROR_INVALID_STATE);

    std::promise<void> cancel_second;
    challenge.host_operation_id = 72;
    challenge.cancelled = cancel_second.get_future().share();
    auto pending = providers[0](challenge);
    drain_tasks(credential_queue);
    natives[0]->credential_cancel = [&](uint64_t id) {
      assert(id == 72); cancel_second.set_value();
    };
    auto cancel = request(csf::Method::cancel_credential, first, 3);
    cancel.host_operation_id = 72;
    csf::Reply cancelled;
    credential_sessions->dispatch(cancel, [&](csf::Reply value) { cancelled = std::move(value); });
    assert(cancelled.success && !pending.get());
    drain_tasks(credential_queue);
    assert(natives[0]->credential_cancellations == std::vector<uint64_t>{72});
    response.host_operation_id = 72; response.sequence = 4;
    credential_sessions->dispatch(response, [&](csf::Reply value) {
      assert(!value.success && value.error_code == CITIZENSDK_ERROR_INVALID_STATE);
    });

    // 关闭失败保留同一session；取消已撤销的挑战不能被下一次关闭复活。
    std::promise<void> cancel_close;
    challenge.host_operation_id = 73;
    challenge.cancelled = cancel_close.get_future().share();
    auto during_close = providers[0](challenge);
    drain_tasks(credential_queue);
    natives[0]->credential_cancel = [&](uint64_t id) {
      assert(id == 73); cancel_close.set_value();
    };
    natives[0]->fail_close = true;
    credential_sessions->dispatch(request(csf::Method::close, first, 5), [&](csf::Reply value) {
      assert(!value.success && value.error_code == CITIZENSDK_ERROR_STORAGE);
    });
    assert(!during_close.get());
    drain_tasks(credential_queue);
    assert(credential_sessions->session_count() == 2);
    natives[0]->fail_close = false;
    credential_sessions->dispatch(request(csf::Method::close, first, 6), [&](csf::Reply value) {
      assert(value.success);
    });

    // 没有事件通道就没有可交付的输入交互，实际提供者结果必须取消。
    credential_sessions->cancel_events();
    std::promise<void> never_cancelled;
    challenge.host_operation_id = 74;
    challenge.cancelled = never_cancelled.get_future().share();
    auto without_sink = providers[1](challenge);
    drain_tasks(credential_queue);
    assert(!without_sink.get());
    credential_sessions->dispatch(request(csf::Method::close, second, 2), [&](csf::Reply value) {
      assert(value.success);
    });
    assert(credential_sessions->session_count() == 0);
  }


  {
    // 正式 Sessions 状态机：QR-only 不进入钱包或 Core 异步请求工厂；
    // 关闭只发取消，真正原生终态前不释放 Host，不把晚到成功变成有效响应。
    std::vector<std::function<void()>> qr_queue;
    auto native = std::make_shared<FakeTransport>();
    auto qr = csf::Sessions::create(
        [](uint32_t modules) { assert(modules == CITIZENSDK_MODULE_QR); return csf::OpenEnvironment{}; },
        [&](std::function<void()> work) { qr_queue.push_back(std::move(work)); },
        [native](const citizen_sdk::Config &config) {
          assert(config.modules == CITIZENSDK_MODULE_QR); return native;
        });
    auto open_qr = request(csf::Method::open, {}, 0); open_qr.modules = CITIZENSDK_MODULE_QR;
    csf::Reply opened;
    qr->dispatch(open_qr, [&](csf::Reply value) { opened = std::move(value); });
    const auto id = text(items(opened.value)[1]);
    int completions = 0; bool closed = false;
    qr->dispatch(request(csf::Method::qr_scan, id, 1), [&](csf::Reply value) {
      ++completions; assert(!value.success && value.error_code == CITIZENSDK_ERROR_CANCELLED);
    });
    assert(native->qr_presented == 1 && native->wallet_presented == 0 && native->accepted.empty());
    qr->dispatch(request(csf::Method::close, id, 2), [&](csf::Reply value) { closed = value.success; });
    assert(native->qr_cancelled == 1 && native->closed == 0 && completions == 0 && !closed);
    auto late = native->qr_completion;
    late(CITIZENSDK_OK, "{}");
    drain_tasks(qr_queue);
    assert(completions == 1 && closed && native->closed == 1 && qr->session_count() == 0);
    late(CITIZENSDK_OK, "{}");
    drain_tasks(qr_queue);
    assert(completions == 1);
  }
  {
    // 原生安全签名在认证等待中 detach：只撤销公开回调，继续保活直到真实终态。
    std::vector<std::function<void()>> qr_queue;
    auto native = std::make_shared<FakeTransport>();
    auto qr = csf::Sessions::create(
        [](uint32_t) { return csf::OpenEnvironment{}; },
        [&](std::function<void()> work) { qr_queue.push_back(std::move(work)); },
        [native](const citizen_sdk::Config &) { return native; });
    csf::Reply opened;
    qr->dispatch(request(csf::Method::open, {}, 0), [&](csf::Reply value) { opened = std::move(value); });
    const auto id = text(items(opened.value)[1]);
    bool replied = false;
    qr->dispatch(request(csf::Method::sign_qr_request, id, 1), [&](csf::Reply) { replied = true; });
    qr->detach();
    assert(native->qr_cancelled == 1 && native->retired == 0 && !replied);
    native->qr_completion(CITIZENSDK_ERROR_CANCELLED, {});
    drain_tasks(qr_queue);
    assert(native->retired == 1 && !replied && qr->session_count() == 0);
  }

  {
    // 安全查看真实协调器：无额外 profile query，完成只允许空 tuple；
    // detach/关闭请求取消后仍等原生最终回调，绝不提前释放 transport。
    std::vector<std::function<void()>> view_queue;
    auto native_view = std::make_shared<FakeTransport>();
    native_view->defer_wallet = true;
    auto view_sessions = csf::Sessions::create(
        [](uint32_t modules) {
          assert(modules == CITIZENSDK_MODULE_WALLET);
          return csf::OpenEnvironment{};
        },
        [&](std::function<void()> work) { view_queue.push_back(std::move(work)); },
        [native_view](const citizen_sdk::Config &) { return native_view; });
    csf::DecodedRequest opening;
    opening.method = csf::Method::open; opening.modules = CITIZENSDK_MODULE_WALLET;
    csf::Reply opened_view;
    view_sessions->dispatch(opening, [&](csf::Reply value) { opened_view = std::move(value); });
    assert(opened_view.success);
    const auto view_session = text(items(opened_view.value)[1]);
    auto viewing = request(csf::Method::view_account_private_key, view_session, 1);
    viewing.indices.clear(); viewing.account_ids.clear(); viewing.word_count = 0;
    int completions = 0;
    csf::Reply viewed;
    view_sessions->dispatch(viewing, [&](csf::Reply value) {
      ++completions; viewed = std::move(value);
    });
    drain_tasks(view_queue);
    assert(completions == 0 && native_view->wallet_presented == 1);
    native_view->wallet_completion({citizen_sdk::WalletFlowStatus::Completed, CITIZENSDK_OK});
    drain_tasks(view_queue);
    assert(completions == 1 && viewed.success && items(items(viewed.value)[3]).empty());
    assert(native_view->accepted.empty() && native_view->copied_results == 0);
    viewing.sequence = 2;
    view_sessions->dispatch(viewing, [&](csf::Reply value) {
      ++completions; viewed = std::move(value);
    });
    view_sessions->detach();
    assert(native_view->wallet_cancelled == 1 && native_view->retired == 0 && completions == 1);
    native_view->wallet_completion({citizen_sdk::WalletFlowStatus::Cancelled, CITIZENSDK_ERROR_CANCELLED});
    drain_tasks(view_queue);
    assert(native_view->retired == 1 && view_sessions->session_count() == 0);
  }
  {
    // 未 open、未 listen：验签直接访问纯 Core，环境及原生资源工厂必须均为零次。
    int environments = 0;
    int transports = 0;
    auto isolated = csf::Sessions::create(
        [&](uint32_t) { ++environments; return csf::OpenEnvironment{}; },
        [](std::function<void()> work) { work(); },
        [&](const citizen_sdk::Config &) {
          ++transports; return std::make_shared<FakeTransport>();
        });
    auto verification = request(csf::Method::verify_signature, "", 0);
    constexpr uint8_t public_key[] = {
        0x2a,0xfb,0xa9,0x27,0x8e,0x30,0xcc,0xf6,0xa6,0xce,0xb3,0xa8,0xb6,0xe3,0x36,0xb7,
        0x00,0x68,0xf0,0x45,0xc6,0x66,0xf2,0xe7,0xf4,0xf9,0xcc,0x5f,0x47,0xdb,0x89,0x72};
    for (std::size_t i = 0; i < sizeof(public_key); ++i)
      verification.account_id.bytes[i] = public_key[i];
    verification.signature.resize(64);
    verification.signature.back() = 0x80;  // 编码有效但不匹配该账户的签名。
    csf::Reply verified;
    isolated->dispatch(verification, [&](csf::Reply value) { verified = std::move(value); });
    assert(verified.success && items(verified.value).size() == 2);
    assert(std::get<int64_t>(items(verified.value)[0].data) == 1);
    assert(!std::get<bool>(items(verified.value)[1].data));
    verification.signature.resize(63);
    isolated->dispatch(verification, [&](csf::Reply value) { verified = std::move(value); });
    assert(!verified.success && verified.error_code == CITIZENSDK_ERROR_INVALID_ARGUMENT);
    assert(std::holds_alternative<std::monostate>(items(verified.value)[1].data));
    assert(std::holds_alternative<std::monostate>(items(verified.value)[2].data));
    assert(environments == 0 && transports == 0 && isolated->session_count() == 0);
  }
  std::vector<std::function<void()>> queue;
  auto native = std::make_shared<FakeTransport>();
  uint32_t received_modules = 0;
  auto sessions = csf::Sessions::create(
      [&](uint32_t modules) { received_modules = modules; return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [&](const citizen_sdk::Config &config) { assert(config.modules == received_modules); return native; });

  csf::Reply opened;
  csf::DecodedRequest open;
  open.method = csf::Method::open;
  open.modules = CITIZENSDK_MODULE_SIGNING;
  sessions->dispatch(open, [&](csf::Reply value) { opened = std::move(value); });
  assert(opened.success && sessions->session_count() == 1);
  assert(received_modules == CITIZENSDK_MODULE_SIGNING);
  const auto &wire = items(opened.value);
  assert(wire.size() == 4 && text(wire[1]).size() == 32);
  assert(text(items(wire[3])[0]) == "created");
  assert(std::get<int64_t>(items(wire[3])[1].data) == 1);
  const std::string session = text(wire[1]);

  // A valid but non-CREATED lifecycle is not a valid open response. Reject it
  // natively and retire once, before Dart can lose an unknown session ID.
  auto invalid_initial_native = std::make_shared<FakeTransport>();
  invalid_initial_native->lifecycle = CITIZENSDK_LIFECYCLE_RUNNING;
  auto invalid_initial = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [invalid_initial_native](const citizen_sdk::Config &) { return invalid_initial_native; });
  csf::Reply invalid_initial_reply;
  int invalid_initial_replies = 0;
  invalid_initial->dispatch(open, [&](csf::Reply value) {
    invalid_initial_reply = std::move(value); ++invalid_initial_replies;
  });
  assert(!invalid_initial_reply.success &&
         invalid_initial_reply.error_code == CITIZENSDK_ERROR_INTEGRITY);
  assert(invalid_initial_replies == 1 && invalid_initial->session_count() == 0);
  assert(invalid_initial_native->retired == 1);
  invalid_initial->detach();
  assert(invalid_initial_native->retired == 1);

  int event_count = 0;
  sessions->listen([&](csf::Value event) {
    assert(items(event).size() == 5);
    ++event_count;
  });
  assert(event_count == 2); // initial lifecycle + capabilities snapshots

  // Exercise every non-open/close method against the production routing
  // state machine. Synchronous capabilities and the three GTK flows are the
  // only methods which intentionally do not directly enter Core here.
  const std::vector<csf::Method> methods = {
      csf::Method::start, csf::Method::stop, csf::Method::get_capabilities,
      csf::Method::get_finalized_head, csf::Method::get_genesis_hash,
      csf::Method::get_account_balance, csf::Method::get_account_balances,
      csf::Method::get_account_nonce, csf::Method::get_fee_snapshot,
      csf::Method::get_wallet_profile, csf::Method::create_wallet,
      csf::Method::import_wallet, csf::Method::add_wallet_accounts,
      csf::Method::set_active_wallet_account, csf::Method::rename_wallet_account,
      csf::Method::delete_wallet_account, csf::Method::delete_wallet,
      csf::Method::reconcile_wallet_cleanup, csf::Method::sign_wallet_payload,
      csf::Method::get_transaction_history, csf::Method::sync_transaction_history,
  };
  int64_t sequence = 1;
  int replies = 0;
  for (const auto method : methods) {
    auto call = request(method, session, sequence++);
    sessions->dispatch(std::move(call), [&](csf::Reply value) {
      assert(value.success); ++replies;
    });
  }
  assert(replies == static_cast<int>(methods.size()));
  assert(native->wallet_presented == 3);
  assert(native->genesis_queries == 1);
  assert(native->copied_results == native->released_results);

  // Event cancellation changes epoch without closing sessions. A queued old
  // generation notification therefore cannot reach the replacement sink.
  citizensdk_event_t lifecycle{};
  lifecycle.struct_size = sizeof(lifecycle); lifecycle.abi_version = CITIZENSDK_ABI_VERSION;
  lifecycle.event_type = CITIZENSDK_EVENT_LIFECYCLE_CHANGED;
  native->observer(lifecycle);
  sessions->cancel_events();
  sessions->listen([&](csf::Value) { ++event_count; });
  const auto after_relisten = event_count;
  drain_tasks(queue);
  assert(event_count == after_relisten);

  // Close cancels an accepted history request, waits for its terminal result, then
  // checkpoints a running Core and destroys Host. It does not claim rollback
  // of durable history.
  native->defer_history = true;
  native->lifecycle = CITIZENSDK_LIFECYCLE_RUNNING;
  auto history = request(csf::Method::get_transaction_history, session, sequence++);
  csf::Reply history_reply;
  sessions->dispatch(history, [&](csf::Reply value) { history_reply = std::move(value); });
  bool close_replied = false;
  sessions->dispatch(request(csf::Method::close, session, sequence++),
                     [&](csf::Reply value) { close_replied = value.success; });
  assert(history_reply.success && native->cancelled == 1);
  assert(close_replied && native->closed == 1 && sessions->session_count() == 0);
  assert(native->accepted.back() == csf::Method::stop);

  sessions->detach();
  sessions->detach(); // idempotent; a closed Host is not retired again
  assert(native->retired == 0);

  // A close failure is reported but leaves the exact same native session
  // usable for a monotonic retry; it must not be silently retired or erased.
  auto failing_native = std::make_shared<FakeTransport>();
  failing_native->fail_close = true;
  auto retryable = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [failing_native](const citizen_sdk::Config &) { return failing_native; });
  csf::Reply retry_open;
  retryable->dispatch(open, [&](csf::Reply value) { retry_open = std::move(value); });
  const std::string retry_id = text(items(retry_open.value)[1]);
  failing_native->fail_accept = true;
  csf::Reply rejected_request;
  retryable->dispatch(request(csf::Method::get_finalized_head, retry_id, 1),
                      [&](csf::Reply value) { rejected_request = std::move(value); });
  assert(!rejected_request.success &&
         rejected_request.error_code == CITIZENSDK_ERROR_NETWORK);
  assert(retryable->session_count() == 1);
  failing_native->fail_accept = false;
  csf::Reply failed_close;
  retryable->dispatch(request(csf::Method::close, retry_id, 2),
                      [&](csf::Reply value) { failed_close = std::move(value); });
  assert(!failed_close.success && failed_close.error_code == CITIZENSDK_ERROR_STORAGE);
  assert(retryable->session_count() == 1 && failing_native->retired == 0);
  failing_native->fail_close = false;
  bool retried = false;
  retryable->dispatch(request(csf::Method::close, retry_id, 3),
                      [&](csf::Reply value) { retried = value.success; });
  assert(retried && retryable->session_count() == 0 && failing_native->closed == 1);

  // Engine detach revokes a pending response and transfers the still-live
  // Host graph exactly once; it never invents a successful native completion.
  auto orphan_native = std::make_shared<FakeTransport>();
  orphan_native->defer_history = true;
  auto orphan = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [orphan_native](const citizen_sdk::Config &) { return orphan_native; });
  csf::Reply orphan_open;
  orphan->dispatch(open, [&](csf::Reply value) { orphan_open = std::move(value); });
  const std::string orphan_id = text(items(orphan_open.value)[1]);
  bool orphan_replied = false;
  orphan->dispatch(request(csf::Method::get_transaction_history, orphan_id, 1),
                   [&](csf::Reply) { orphan_replied = true; });
  orphan->detach();
  orphan->detach();
  assert(!orphan_replied && orphan_native->cancelled == 1 &&
         orphan_native->retired == 0 && orphan->session_count() == 1);
  drain_tasks(queue);
  assert(!orphan_replied && orphan_native->retired == 1 &&
         orphan->session_count() == 0);

  // The mutation gate is process-wide, not a per-session or per-plugin lock.
  // Keep the first delete in its mandatory EMPTY -> public-profile window and
  // prove another Flutter engine receives BUSY rather than interleaving.
  auto gate_native_a = std::make_shared<FakeTransport>();
  auto gate_native_b = std::make_shared<FakeTransport>();
  gate_native_a->defer_profile = true;
  auto gate_a = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [gate_native_a](const citizen_sdk::Config &) { return gate_native_a; });
  auto gate_b = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [gate_native_b](const citizen_sdk::Config &) { return gate_native_b; });
  csf::Reply gate_open_a, gate_open_b;
  gate_a->dispatch(open, [&](csf::Reply value) { gate_open_a = std::move(value); });
  gate_b->dispatch(open, [&](csf::Reply value) { gate_open_b = std::move(value); });
  const auto gate_id_a = text(items(gate_open_a.value)[1]);
  const auto gate_id_b = text(items(gate_open_b.value)[1]);
  bool delete_finished = false;
  gate_a->dispatch(request(csf::Method::delete_wallet, gate_id_a, 1),
                   [&](csf::Reply value) { delete_finished = value.success; });
  assert(!delete_finished && gate_native_a->deferred_id != 0);
  assert(gate_native_a->accepted.back() == csf::Method::get_wallet_profile);
  assert(gate_native_a->public_methods.back() == csf::Method::delete_wallet);
  csf::Reply competing;
  gate_b->dispatch(request(csf::Method::rename_wallet_account, gate_id_b, 1),
                   [&](csf::Reply value) { competing = std::move(value); });
  assert(!competing.success && competing.error_code == CITIZENSDK_ERROR_BUSY);
  assert(gate_native_b->accepted.empty());
  gate_a->detach();
  assert(gate_native_a->retired == 0 && gate_a->session_count() == 1);
  csf::Reply still_competing;
  gate_b->dispatch(request(csf::Method::rename_wallet_account, gate_id_b, 2),
                   [&](csf::Reply value) { still_competing = std::move(value); });
  assert(!still_competing.success && still_competing.error_code == CITIZENSDK_ERROR_BUSY);
  gate_native_a->complete_deferred();
  // The callback queued only owning data; drain it on the captured UI thread.
  drain_tasks(queue);
  assert(!delete_finished && gate_native_a->retired == 1 && gate_a->session_count() == 0);
  csf::Reply gate_released;
  gate_b->dispatch(request(csf::Method::rename_wallet_account, gate_id_b, 3),
                   [&](csf::Reply value) { gate_released = std::move(value); });
  assert(gate_released.success && gate_native_b->accepted.size() == 1);
  gate_b->detach();
  return 0;
}
