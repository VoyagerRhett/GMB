#include <cassert>
#include <functional>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <variant>
#include <vector>

#include "citizen_sdk/citizen_sdk_error.hpp"
#include "citizen_sdk_flutter_sessions.hpp"
#include "citizen_sdk_flutter_test_support.hpp"

#ifdef NDEBUG
#error "CitizenSDK Flutter session contract assertions must remain enabled"
#endif

namespace csf = citizen_sdk::flutter;

namespace {

using citizen_sdk::flutter::test::items;
using citizen_sdk::flutter::test::text;
using citizen_sdk::flutter::test::FakeTransport;
using citizen_sdk::flutter::test::request;
using citizen_sdk::flutter::test::drain_tasks;

void close_guard_contract() {
  const auto rejects = [](bool attempted, citizensdk_lifecycle_t state,
                          citizensdk_error_code_t status, citizensdk_handle_t core,
                          citizensdk_error_code_t expected) {
    bool rejected = false;
    try { (void)csf::allow_close_without_core(attempted, state, status, core); }
    catch (const citizen_sdk::Error &error) { rejected = error.code() == expected; }
    assert(rejected);
  };
  assert(!csf::allow_close_without_core(false, 0, CITIZENSDK_OK, 1));
  rejects(false, CITIZENSDK_LIFECYCLE_STOPPED, CITIZENSDK_ERROR_NOT_READY, 0,
          CITIZENSDK_ERROR_NOT_READY);
  rejects(true, CITIZENSDK_LIFECYCLE_RUNNING, CITIZENSDK_ERROR_NOT_READY, 0,
          CITIZENSDK_ERROR_NOT_READY);
  rejects(true, CITIZENSDK_LIFECYCLE_STOPPED, CITIZENSDK_ERROR_INVALID_HANDLE, 0,
          CITIZENSDK_ERROR_INVALID_HANDLE);
  rejects(true, CITIZENSDK_LIFECYCLE_STOPPED, CITIZENSDK_OK, 0, CITIZENSDK_ERROR_INTEGRITY);
  for (const auto state : {CITIZENSDK_LIFECYCLE_CREATED,
                           CITIZENSDK_LIFECYCLE_START_FAILED, CITIZENSDK_LIFECYCLE_STOPPED}) {
    assert(csf::allow_close_without_core(true, state, CITIZENSDK_ERROR_NOT_READY, 0));
  }
}
}  // namespace

int main() {

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
  close_guard_contract();
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
  // state machine. Synchronous capabilities and the three Win32 flows are the
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
      csf::Method::initialize_finalized_history, csf::Method::sync_finalized_history,
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

  // Close cancels an accepted transfer, waits for its terminal result, then
  // checkpoints a running Core and destroys Host. It does not claim rollback
  // of durable history.
  native->defer_transfer = true;
  native->lifecycle = CITIZENSDK_LIFECYCLE_RUNNING;
  auto transfer = request(csf::Method::transfer_with_remark, session, sequence++);
  csf::Reply transfer_reply;
  sessions->dispatch(transfer, [&](csf::Reply value) { transfer_reply = std::move(value); });
  bool close_replied = false;
  sessions->dispatch(request(csf::Method::close, session, sequence++),
                     [&](csf::Reply value) { close_replied = value.success; });
  assert(transfer_reply.success && native->cancelled == 1);
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

  // checkpoint 请求被拒时不能擦除 session，也不能虚构 Host 已关闭。
  auto checkpoint_native = std::make_shared<FakeTransport>();
  auto checkpoint = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [checkpoint_native](const citizen_sdk::Config &) { return checkpoint_native; });
  csf::Reply checkpoint_open;
  checkpoint->dispatch(open, [&](csf::Reply value) { checkpoint_open = std::move(value); });
  const auto checkpoint_id = text(items(checkpoint_open.value)[1]);
  checkpoint_native->lifecycle = CITIZENSDK_LIFECYCLE_RUNNING;
  checkpoint_native->fail_accept = true;
  csf::Reply checkpoint_close;
  checkpoint->dispatch(request(csf::Method::close, checkpoint_id, 1),
                       [&](csf::Reply value) { checkpoint_close = std::move(value); });
  assert(!checkpoint_close.success && checkpoint_close.error_code == CITIZENSDK_ERROR_NETWORK &&
         checkpoint->session_count() == 1 && checkpoint_native->closed == 0);
  checkpoint_native->fail_accept = false;
  checkpoint->dispatch(request(csf::Method::close, checkpoint_id, 2),
                       [&](csf::Reply value) { checkpoint_close = std::move(value); });
  assert(checkpoint_close.success && checkpoint->session_count() == 0);

  auto cancel_native = std::make_shared<FakeTransport>();
  cancel_native->defer_transfer = true;
  cancel_native->fail_cancel = true;
  auto cancelling = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [cancel_native](const citizen_sdk::Config &) { return cancel_native; });
  csf::Reply cancel_open;
  cancelling->dispatch(open, [&](csf::Reply value) { cancel_open = std::move(value); });
  const auto cancel_id = text(items(cancel_open.value)[1]);
  bool cancelled_transfer_replied = false;
  cancelling->dispatch(request(csf::Method::transfer_with_remark, cancel_id, 1),
                        [&](csf::Reply value) { cancelled_transfer_replied = value.success; });
  csf::Reply cancel_close;
  cancelling->dispatch(request(csf::Method::close, cancel_id, 2),
                        [&](csf::Reply value) { cancel_close = std::move(value); });
  assert(!cancel_close.success && cancel_close.error_code == CITIZENSDK_ERROR_BUSY &&
         !cancelled_transfer_replied && cancelling->session_count() == 1);
  cancel_native->fail_cancel = false;
  cancelling->dispatch(request(csf::Method::close, cancel_id, 3),
                        [&](csf::Reply value) { cancel_close = std::move(value); });
  assert(cancel_close.success && cancelled_transfer_replied && cancelling->session_count() == 0);

  // Engine detach revokes a pending response and transfers the still-live
  // Host graph exactly once; it never invents a successful native completion.
  auto orphan_native = std::make_shared<FakeTransport>();
  orphan_native->defer_transfer = true;
  auto orphan = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [orphan_native](const citizen_sdk::Config &) { return orphan_native; });
  csf::Reply orphan_open;
  orphan->dispatch(open, [&](csf::Reply value) { orphan_open = std::move(value); });
  const std::string orphan_id = text(items(orphan_open.value)[1]);
  bool orphan_replied = false;
  orphan->dispatch(request(csf::Method::transfer_with_remark, orphan_id, 1),
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

  // Windows 特有两阶段退休：有限替身只注入 Host 状态，重试许可执行上方生产守门。
  // Core 已消失但 UI 两次 BUSY 时保留 session；不得提前返回 disposed 或恢复新操作。
  auto partial_native = std::make_shared<FakeTransport>();
  partial_native->busy_closes = 2;
  auto partial = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [partial_native](const citizen_sdk::Config &) { return partial_native; });
  csf::Reply partial_open;
  partial->dispatch(open, [&](csf::Reply value) { partial_open = std::move(value); });
  const auto partial_id = text(items(partial_open.value)[1]);
  csf::Reply partial_close;
  partial->dispatch(request(csf::Method::close, partial_id, 1),
                    [&](csf::Reply value) { partial_close = std::move(value); });
  assert(!partial_close.success && partial_close.error_code == CITIZENSDK_ERROR_BUSY &&
         !partial_native->core_present && partial->session_count() == 1);
  int64_t partial_sequence = 2;
  for (const auto method : {csf::Method::get_capabilities, csf::Method::start,
                             csf::Method::create_wallet}) {
    csf::Reply denied;
    partial->dispatch(request(method, partial_id, partial_sequence++),
                      [&](csf::Reply value) { denied = std::move(value); });
    assert(!denied.success && denied.error_code == CITIZENSDK_ERROR_INVALID_STATE);
  }
  partial->dispatch(request(csf::Method::close, partial_id, partial_sequence++),
                    [&](csf::Reply value) { partial_close = std::move(value); });
  assert(!partial_close.success && partial_close.error_code == CITIZENSDK_ERROR_BUSY &&
         partial->session_count() == 1 && partial_native->closed == 0);
  partial->dispatch(request(csf::Method::close, partial_id, partial_sequence++),
                    [&](csf::Reply value) { partial_close = std::move(value); });
  assert(partial_close.success && partial->session_count() == 0 && partial_native->closed == 1 &&
         text(items(items(partial_close.value)[3])[0]) == "disposed");

  auto absent_native = std::make_shared<FakeTransport>();
  absent_native->core_present = false;
  auto absent = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [absent_native](const citizen_sdk::Config &) { return absent_native; });
  csf::Reply absent_open;
  absent->dispatch(open, [&](csf::Reply value) { absent_open = std::move(value); });
  assert(!absent_open.success && absent_open.error_code == CITIZENSDK_ERROR_NOT_READY &&
         absent->session_count() == 0 && absent_native->retired == 1);

  // 重复 completion 仍由 transport 各自释放，但同一请求只复制一次、回复一次。
  auto duplicate_native = std::make_shared<FakeTransport>();
  duplicate_native->duplicate_completion = true;
  auto duplicate = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; },
      [&](std::function<void()> work) { queue.push_back(std::move(work)); },
      [duplicate_native](const citizen_sdk::Config &) { return duplicate_native; });
  csf::Reply duplicate_open;
  duplicate->dispatch(open, [&](csf::Reply value) { duplicate_open = std::move(value); });
  const auto duplicate_id = text(items(duplicate_open.value)[1]);
  int duplicate_replies = 0;
  duplicate->dispatch(request(csf::Method::get_finalized_head, duplicate_id, 1),
                      [&](csf::Reply value) { assert(value.success); ++duplicate_replies; });
  assert(duplicate_replies == 1 && duplicate_native->copied_results == 1 &&
         duplicate_native->released_results == 2);
  duplicate_native->fail_copy = true;
  csf::Reply copy_failure;
  duplicate->dispatch(request(csf::Method::rename_wallet_account, duplicate_id, 2),
                      [&](csf::Reply value) { copy_failure = std::move(value); });
  assert(!copy_failure.success && copy_failure.error_code == CITIZENSDK_ERROR_INTEGRITY);
  duplicate_native->fail_copy = false;
  duplicate->dispatch(request(csf::Method::rename_wallet_account, duplicate_id, 3),
                      [&](csf::Reply value) { assert(value.success); ++duplicate_replies; });
  assert(duplicate_replies == 2); // 失败复制已释放进程级变更门，不留下 BUSY。
  int throwing_replies = 0;
  bool reply_threw = false;
  try {
    duplicate->dispatch(request(csf::Method::get_capabilities, duplicate_id, 4),
                        [&](csf::Reply) { ++throwing_replies; throw std::runtime_error("synthetic reply"); });
  } catch (const std::runtime_error &) { reply_threw = true; }
  assert(reply_threw && throwing_replies == 1);
  csf::Reply repeated_sequence;
  duplicate->dispatch(request(csf::Method::get_capabilities, duplicate_id, 4),
                      [&](csf::Reply value) { repeated_sequence = std::move(value); });
  assert(!repeated_sequence.success && repeated_sequence.error_code == CITIZENSDK_ERROR_CONFLICT);
  duplicate->dispatch(request(csf::Method::get_capabilities, duplicate_id, 5),
                      [](csf::Reply value) { assert(value.success); });
  duplicate->detach();

  // 原生线程仅复制公开值并排队；关闭回复、事件和 session map 始终在创建线程处理。
  citizen_sdk::flutter::test::FiniteScheduler main_queue;
  auto worker_native = std::make_shared<FakeTransport>();
  worker_native->defer_profile = true;
  auto worker_sessions = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; }, main_queue.scheduler(),
      [worker_native](const citizen_sdk::Config &) { return worker_native; });
  csf::Reply worker_open;
  worker_sessions->dispatch(open, [&](csf::Reply value) { worker_open = std::move(value); });
  const auto worker_id = text(items(worker_open.value)[1]);
  const auto main_thread = std::this_thread::get_id();
  int worker_replies = 0;
  worker_sessions->dispatch(request(csf::Method::get_wallet_profile, worker_id, 1),
      [&](csf::Reply value) {
        assert(std::this_thread::get_id() == main_thread && value.success);
        ++worker_replies;
      });
  main_queue.fail_next();
  std::thread completion_thread([&] { worker_native->complete_deferred(); });
  completion_thread.join();
  assert(worker_replies == 0 && worker_native->released_results == 1);
  // 模拟一次 UI 入队分配失败；下次 dispatch 从 route 中保留的 owning copy 恢复。
  worker_sessions->dispatch(request(csf::Method::get_capabilities, worker_id, 2),
                            [](csf::Reply value) { assert(value.success); });
  assert(worker_replies == 1);
  main_queue.drain();
  worker_sessions->detach();

  // detach 不能把 Win32 用户取消当终态，也不能提前放开全进程钱包变更门。
  auto pending_wallet_native = std::make_shared<FakeTransport>();
  pending_wallet_native->defer_wallet = true;
  auto pending_wallet = csf::Sessions::create(
      [](uint32_t) { return csf::OpenEnvironment{}; }, main_queue.scheduler(),
      [pending_wallet_native](const citizen_sdk::Config &) { return pending_wallet_native; });
  csf::Reply pending_open;
  pending_wallet->dispatch(open, [&](csf::Reply value) { pending_open = std::move(value); });
  const auto pending_id = text(items(pending_open.value)[1]);
  bool wallet_replied = false;
  pending_wallet->dispatch(request(csf::Method::create_wallet, pending_id, 1),
                           [&](csf::Reply) { wallet_replied = true; });
  pending_wallet->detach();
  assert(!wallet_replied && pending_wallet_native->wallet_cancelled == 1 &&
         pending_wallet_native->retired == 0 && pending_wallet->session_count() == 1);
  pending_wallet_native->wallet_completion({citizen_sdk::WalletFlowStatus::Cancelled,
                                          CITIZENSDK_ERROR_AUTHENTICATION_CANCELLED});
  main_queue.drain();
  assert(!wallet_replied && pending_wallet_native->retired == 1 && pending_wallet->session_count() == 0);
  return 0;
}
