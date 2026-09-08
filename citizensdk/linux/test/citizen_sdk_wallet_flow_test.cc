// 验证 Linux SDK-owned 钱包流程严格复用 Core 的 prepare/commit 和输入门禁。
#include <cassert>
#include <array>
#include <thread>
#include <memory>
#include "citizen_sdk_wallet_flow.hpp"
#include <fstream>
#include <iterator>
#include <string>

#include "citizen_sdk/citizen_sdk_wallet_flow.hpp"
#include "citizen_sdk_host_record.hpp"
#include "citizen_sdk_wallet_validation.hpp"

#ifndef CITIZENSDK_LINUX_TEST_SOURCE_DIR
#error "CITIZENSDK_LINUX_TEST_SOURCE_DIR must point at the Linux source root"
#endif
#ifdef NDEBUG
#error "CitizenSDK Linux contract assertions must remain enabled"
#endif

namespace citizen_sdk::linux {
struct WalletFlowTestPeer final {
  static void private_view_buffer_contract() {
    ValidatedWalletRequest request;
    request.account_id = citizensdk_account_id_t{};
    auto make_flow = [&] {
      return std::make_shared<WalletFlow>(1, nullptr, 0, request, nullptr, nullptr,
                                          [](citizensdk_wallet_flow_handle_t) {});
    };
    auto flow = make_flow();
    assert(WalletFlow::private_key_authorizing(nullptr, 9, 71) == CITIZENSDK_ERROR_INTEGRITY);
    assert(WalletFlow::private_key_authorizing(flow.get(), 0, 71) == CITIZENSDK_ERROR_INTEGRITY);
    assert(WalletFlow::private_key_authorizing(flow.get(), 9, 0) == CITIZENSDK_ERROR_INTEGRITY);
    flow->private_view_id_ = 9;
    assert(WalletFlow::private_key_authorizing(flow.get(), 10, 71) == CITIZENSDK_ERROR_INTEGRITY);
    std::array<uint8_t, 32> synthetic{};
    synthetic[0] = 7;
    assert(WalletFlow::display_private_key(flow.get(), 9, {synthetic.data(), 31}) ==
           CITIZENSDK_ERROR_INTEGRITY);
    assert(WalletFlow::display_private_key(flow.get(), 9, {nullptr, 32}) ==
           CITIZENSDK_ERROR_INTEGRITY);
    assert(WalletFlow::display_private_key(flow.get(), 9, {synthetic.data(), 32}) == CITIZENSDK_OK);
    synthetic[0] = 0;
    assert(flow->private_key_.data()[0] == 7);  // 已同步复制，不保存借用指针。
    assert(WalletFlow::display_private_key(flow.get(), 10, {synthetic.data(), 32}) ==
           CITIZENSDK_ERROR_INVALID_HANDLE);
    assert(WalletFlow::display_private_key(flow.get(), 9, {synthetic.data(), 32}) ==
           CITIZENSDK_ERROR_INVALID_STATE);
    assert(flow->revoke_private_key_display() == 9);
    assert(flow->private_key_.empty());
    assert(WalletFlow::private_key_authorizing(flow.get(), 9, 71) == CITIZENSDK_ERROR_CANCELLED);
    assert(WalletFlow::display_private_key(flow.get(), 9, {synthetic.data(), 32}) ==
           CITIZENSDK_ERROR_CANCELLED);
    // 锁屏/关闭使用相同撤销门：并发认证晚回调与清屏的顺序不影响最终空缓冲。
    for (unsigned attempt = 0; attempt < 32; ++attempt) {
      auto racing = make_flow();
      std::thread late([&] {
        const auto code = WalletFlow::display_private_key(racing.get(), 11, {synthetic.data(), 32});
        assert(code == CITIZENSDK_OK || code == CITIZENSDK_ERROR_CANCELLED);
      });
      (void)racing->revoke_private_key_display();
      late.join();
      assert(racing->private_key_.empty());
      assert(WalletFlow::display_private_key(racing.get(), 11, {synthetic.data(), 32}) ==
             CITIZENSDK_ERROR_CANCELLED);
    }
  }
};
}  // namespace citizen_sdk::linux

namespace {

bool rejected(const citizensdk_wallet_flow_request_v1_t &request) {
  try {
    (void)citizen_sdk::linux::validate_wallet_request(request);
    return false;
  } catch (const citizen_sdk::linux::HostError &error) {
    return error.code() == CITIZENSDK_ERROR_INVALID_ARGUMENT;
  }
}

citizensdk_wallet_flow_request_v1_t request(
    citizensdk_wallet_flow_kind_t kind) {
  citizensdk_wallet_flow_request_v1_t value{};
  value.struct_size = sizeof(value);
  value.abi_version = CITIZENSDK_HOST_ABI_VERSION;
  value.kind = kind;
  return value;
}

}  // namespace

int main() {
  citizen_sdk::linux::WalletFlowTestPeer::private_view_buffer_contract();
  assert(citizensdk_validate_wallet_password({nullptr, 0}) == CITIZENSDK_OK);
  const uint8_t prefix[] = {'a', 'b', 'a', 'n'};
  uint64_t required = 0;
  assert(citizensdk_wallet_word_suggestions(
             {prefix, sizeof(prefix)}, nullptr, 0, &required) == CITIZENSDK_OK);
  assert(required == 7);
  uint8_t candidate[7]{};
  assert(citizensdk_wallet_word_suggestions(
             {prefix, sizeof(prefix)}, candidate, sizeof(candidate), &required) ==
         CITIZENSDK_OK);
  assert(std::string(reinterpret_cast<char *>(candidate), sizeof(candidate)) ==
         "abandon");

  const citizen_sdk::WalletFlowRequest public_default{};
  assert(public_default.kind == citizen_sdk::WalletFlowKind::Create);
  assert(public_default.word_count == 12);

  auto create12 = request(CITIZENSDK_WALLET_FLOW_CREATE);
  create12.word_count = CITIZENSDK_WALLET_WORDS_12;
  assert(citizen_sdk::linux::validate_wallet_request(create12).word_count ==
         CITIZENSDK_WALLET_WORDS_12);
  auto create24 = create12;
  create24.word_count = CITIZENSDK_WALLET_WORDS_24;
  assert(!rejected(create24));
  auto create18 = create12;
  create18.word_count = CITIZENSDK_WALLET_WORDS_18;
  assert(citizen_sdk::linux::validate_wallet_request(create18).word_count ==
         CITIZENSDK_WALLET_WORDS_18);
  auto create15 = create12;
  create15.word_count = 15;
  assert(rejected(create15));
  auto create21 = create12;
  create21.word_count = 21;
  assert(rejected(create21));

  uint32_t indices[] = {1, 1989};
  auto create_with_indices = create12;
  create_with_indices.account_indices = indices;
  create_with_indices.account_index_count = 2;
  assert(rejected(create_with_indices));

  auto import = request(CITIZENSDK_WALLET_FLOW_IMPORT);
  assert(!rejected(import));
  import.word_count = CITIZENSDK_WALLET_WORDS_12;
  assert(rejected(import));
  import.word_count = 0;
  import.account_indices = indices;
  import.account_index_count = 2;
  assert(rejected(import));

  auto add = request(CITIZENSDK_WALLET_FLOW_ADD_ACCOUNTS);
  assert(rejected(add));
  add.account_indices = indices;
  add.account_index_count = 2;
  add.word_count = CITIZENSDK_WALLET_WORDS_12;
  assert(rejected(add));
  add.word_count = 0;
  const auto validated = citizen_sdk::linux::validate_wallet_request(add);
  assert(validated.account_indices.size() == 2);
  assert(validated.account_indices[0] == 1);
  assert(validated.account_indices[1] == 1989);
  uint32_t duplicate[] = {1, 1};
  add.account_indices = duplicate;
  assert(rejected(add));
  uint32_t anchor[] = {0};
  add.account_indices = anchor;
  add.account_index_count = 1;
  assert(rejected(add));
  uint32_t out_of_range[] = {1990};
  add.account_indices = out_of_range;
  assert(rejected(add));

  auto wrong_version = create12;
  wrong_version.abi_version = CITIZENSDK_HOST_ABI_VERSION + 1;
  assert(rejected(wrong_version));
  auto short_struct = create12;
  short_struct.struct_size = sizeof(short_struct) - 1;
  assert(rejected(short_struct));

  const std::string source_path =
      std::string(CITIZENSDK_LINUX_TEST_SOURCE_DIR) +
      "/src/citizen_sdk_wallet_flow.cc";
  std::ifstream stream(source_path, std::ios::binary);
  assert(stream.good());
  const std::string source((std::istreambuf_iterator<char>(stream)),
                           std::istreambuf_iterator<char>());
  for (const char *required : {
           "citizensdk_prepare_wallet_creation",
           "citizensdk_validate_wallet_mnemonic",
           "citizensdk_get_wallet_profile",
           "receive_next_account",
           "citizensdk_prepared_wallet_copy_mnemonic",
           "citizensdk_commit_wallet_creation",
           "citizensdk_prepared_wallet_release",
           "class ResultLease final",
           "void WalletFlow::receive_prepare(citizensdk_result_handle_t result) noexcept",
           "void WalletFlow::receive_terminal(citizensdk_result_handle_t result) noexcept",
           "const citizensdk_error_code_t release_code = result_owner.release()",
           "if (result_owner.release() != CITIZENSDK_OK)",
           "if (!scheduled)",
           "if (request != 0)",
           "finish(CITIZENSDK_WALLET_FLOW_FAILED, code)",
           "if (finished_.exchange(true)) return",
           "host_->finish_wallet_flow(lifecycle_token_)",
           "if (host->public_sdk() == 0) return CITIZENSDK_ERROR_NOT_READY",
           "if (vault == CITIZENSDK_HOST_VAULT_UNSUPPORTED)",
           "return CITIZENSDK_ERROR_UNSUPPORTED",
           "if (vault != CITIZENSDK_HOST_VAULT_AVAILABLE)",
           "return CITIZENSDK_ERROR_UNAVAILABLE",
           "for (unsigned attempt = 0; attempt < 8; ++attempt)",
           "std::terminate()",
           "irreversible_.store(true)",
           "window_->clear_secrets()",
           "WalletFlow::release_prepared_or_supervise",
           "WalletFlow::supervise_prepared_release",
           "if (prepared_ != 0) std::terminate()",
           "cleanup_supervised_.exchange(true)",
       }) {
    assert(source.find(required) != std::string::npos);
  }
  assert(source.find("getAccountPrivateKey") == std::string::npos);
  assert(source.find("take_password(true)") == std::string::npos);
  assert(source.find("request_.account_indices.data()") == std::string::npos);
  assert(source.find("window_->use_next_account()") != std::string::npos);
  assert(source.find("window_->account_indices()") != std::string::npos);
  const auto import_begin = source.find("void WalletFlow::begin_import_or_add()");
  const auto mnemonic_validation = source.find("validate_mnemonic(mnemonic", import_begin);
  const auto password_take = source.find("window_->take_password()", import_begin);
  assert(import_begin != std::string::npos &&
         mnemonic_validation != std::string::npos &&
         password_take != std::string::npos &&
         mnemonic_validation < password_take);

  // prepared handle 的 release 失败不能抹掉唯一所有者或提前释放钱包
  // lifecycle token；supervisor 只有在 Core 确认 release 后才收口 flow。
  const auto release_supervisor =
      source.find("void WalletFlow::supervise_prepared_release(");
  const auto retry_loop = source.find("for (;;) {", release_supervisor);
  const auto retry_release = source.find(
      "citizensdk_prepared_wallet_release(sdk, prepared)", retry_loop);
  const auto clear_prepared =
      source.find("self->prepared_ = 0", retry_release);
  const auto finish_lifecycle = source.find(
      "self->host_->finish_wallet_flow(self->lifecycle_token_)",
      clear_prepared);
  const auto erase_flow =
      source.find("self->terminal_(self->handle_)", finish_lifecycle);
  assert(release_supervisor != std::string::npos &&
         retry_loop != std::string::npos &&
         retry_release != std::string::npos &&
         clear_prepared != std::string::npos &&
         finish_lifecycle != std::string::npos &&
         erase_flow != std::string::npos && release_supervisor < retry_loop &&
         retry_loop < retry_release && retry_release < clear_prepared &&
         clear_prepared < finish_lifecycle && finish_lifecycle < erase_flow);

  const std::string window_path =
      std::string(CITIZENSDK_LINUX_TEST_SOURCE_DIR) +
      "/src/citizen_sdk_wallet_window.cc";
  std::ifstream window_stream(window_path, std::ios::binary);
  assert(window_stream.good());
  const std::string window_source(
      (std::istreambuf_iterator<char>(window_stream)),
      std::istreambuf_iterator<char>());
  for (const char *required : {"g_main_current_source()",
                               "g_source_set_ready_time(",
                               "return G_SOURCE_CONTINUE",
                               "gtk_text_iter_equal(&cursor, &end)",
                               "gtk_text_buffer_get_selection_bounds(",
                               "gtk_text_buffer_insert_at_cursor",
                               "citizensdk_wallet_word_suggestions",
                               "citizensdk_validate_wallet_password",
                               "if (!on_ui_thread()) std::terminate()"}) {
    assert(window_source.find(required) != std::string::npos);
  }
  assert(window_source.find("CitizenSDK 钱包") != std::string::npos);
  assert(window_source.find("钱包密码（选填）") != std::string::npos);
  assert(window_source.find("使用所选离线词表候选") != std::string::npos);
  assert(window_source.find("再次输入派生密码") == std::string::npos);
  assert(window_source.find("公民钱包") == std::string::npos);
  assert(window_source.find("当前钱包密码为空") != std::string::npos);
  assert(window_source.find("校验和有效") != std::string::npos);
  assert(window_source.find("校验和尚未通过") != std::string::npos);
  const auto password_begin = window_source.find("SensitiveBuffer WalletWindow::take_password()");
  const auto password_validation = window_source.find(
      "citizensdk_validate_wallet_password", password_begin);
  const auto risk_dialog = window_source.find("gtk_message_dialog_new", password_begin);
  assert(password_begin != std::string::npos &&
         password_validation != std::string::npos &&
         risk_dialog != std::string::npos && password_validation < risk_dialog);
  return 0;
}
