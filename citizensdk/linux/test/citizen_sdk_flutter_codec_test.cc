// 验证 Linux Flutter 边界逐字段复用既有 v1 tuple，且不会截断 UTF-8/NUL。
#include <cassert>
#include <cstdint>
#include <cstring>
#include <set>
#include <string>

#include "citizen_sdk_flutter_test_support.hpp"

namespace {
using citizen_sdk::flutter::ContractFailure;
using citizen_sdk::flutter::DecodedRequest;
using citizen_sdk::flutter::FlValuePtr;
using citizen_sdk::flutter::Method;
using citizen_sdk::flutter::Value;
using citizen_sdk::flutter::test::GBytesPtr;
using citizen_sdk::flutter::test::GObjectPtr;
using citizen_sdk::flutter::test::expect_failure;
using citizen_sdk::flutter::test::fl;
using citizen_sdk::flutter::test::list;

std::string account(char digit) { return "0x" + std::string(64, digit); }

DecodedRequest decode(const char *method, Value request) {
  auto native = fl(request);
  return citizen_sdk::flutter::decode_request(method, native.get());
}

const Value::List &as_list(const Value &value) {
  const auto *result = std::get_if<Value::List>(&value.data);
  assert(result != nullptr);
  return *result;
}
const std::string &as_string(const Value &value) {
  const auto *result = std::get_if<std::string>(&value.data);
  assert(result != nullptr);
  return *result;
}

GBytesPtr encode_call(FlMethodCodec *codec, const char *method, FlValue *args) {
  GError *raw_error = nullptr;
  GBytes *bytes = FL_METHOD_CODEC_GET_CLASS(codec)->encode_method_call(
      codec, method, args, &raw_error);
  assert(raw_error == nullptr && bytes != nullptr);
  return GBytesPtr(bytes);
}
FlValuePtr decode_call(FlMethodCodec *codec, GBytes *bytes, std::string *method) {
  gchar *raw_method = nullptr;
  FlValue *arguments = nullptr;
  GError *raw_error = nullptr;
  const gboolean ok = FL_METHOD_CODEC_GET_CLASS(codec)->decode_method_call(
      codec, bytes, &raw_method, &arguments, &raw_error);
  assert(ok && raw_error == nullptr && raw_method != nullptr && arguments != nullptr);
  *method = raw_method;
  g_free(raw_method);
  return FlValuePtr(arguments);
}

void test_method_closure_and_requests() {
  constexpr Method all[] = {
      Method::open, Method::start, Method::stop, Method::close,
      Method::get_capabilities, Method::get_finalized_head, Method::get_sync_status,
      Method::get_best_head, Method::get_finalized_block_at,
      Method::resolve_finalized_block, Method::get_block_header, Method::get_block_body,
      Method::get_runtime_context, Method::get_storage, Method::get_storage_batch,
      Method::get_storage_keys_paged, Method::call_runtime_api,
      Method::get_system_events, Method::export_state, Method::import_state,
      Method::get_genesis_hash,
      Method::get_account_balance, Method::get_account_balances, Method::get_account_nonce,
      Method::get_fee_snapshot, Method::get_wallet_profile, Method::get_wallet_state,
      Method::import_cold_account_id, Method::import_cold_account_ss58,
      Method::reorder_wallet_accounts_without_default_change, Method::rename_account,
      Method::delete_account, Method::view_account_private_key,
      Method::create_wallet, Method::import_wallet, Method::add_wallet_accounts,
      Method::set_active_wallet_account, Method::rename_wallet_account,
      Method::delete_wallet_account, Method::delete_wallet,
      Method::reconcile_wallet_cleanup, Method::sign_wallet_payload,
      Method::derive_application_key, Method::begin_signing,
      Method::consume_external_signature, Method::cancel_signing,
      Method::begin_default_account_change, Method::consume_default_account_change,
      Method::verify_signature, Method::prepare_transaction,
      Method::cancel_prepared_transaction, Method::execute_prepared_transaction,
      Method::consume_prepared_transaction_qr_response,
      Method::cancel_prepared_transaction_execution,
      Method::get_transaction_history, Method::sync_transaction_history,
      Method::qr_parse, Method::qr_create_sign_request,
      Method::qr_consume_sign_response, Method::qr_cancel_sign_request,
      Method::qr_encode_account_id,
      Method::qr_decode_luminance, Method::qr_encode, Method::qr_scan, Method::sign_qr_request,
  };
  std::set<std::string> names;
  for (Method method : all) names.insert(citizen_sdk::flutter::method_name(method));
  assert(names.size() == 65 && names.count("open") == 1 &&
         names.count("getTransactionHistory") == 1);

  assert(decode("open", list({Value::integer(1), Value::integer(63)})).modules == 63);
  assert(decode("open", list({Value::integer(1), Value::integer(2)})).modules == 2);
  expect_failure([&] { (void)decode("open", list({Value::integer(1)})); },
                 CITIZENSDK_ERROR_INVALID_ARGUMENT);
  for (const auto invalid : {int64_t{0}, int64_t{-1}, int64_t{UINT32_MAX} + 1}) {
    expect_failure([&] { (void)decode("open", list({Value::integer(1), Value::integer(invalid)})); },
                   CITIZENSDK_ERROR_INVALID_ARGUMENT);
  }
  for (const char *method : {"start", "stop", "close", "getCapabilities",
       "getFinalizedHead", "getSyncStatus", "getBestHead", "exportState",
       "getGenesisHash", "getFeeSnapshot", "getWalletProfile", "getWalletState", "importWallet",
       "deleteWallet", "reconcileWalletCleanup"}) {
    auto value = decode(method, list({Value::integer(1), Value::string("s"),
                                      Value::integer(1)}));
    assert(value.session == "s" && value.sequence == 1);
  }
  const auto finalized = list({Value::string(account('1')), Value::string("1"),
                               Value::string("finalized")});
  assert(decode("getFinalizedBlockAt", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("1")})).block_number == 1);
  assert(decode("resolveFinalizedBlock", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string(account('1')), Value::string("1")})).block_number == 1);
  for (const char *method : {"getBlockHeader", "getBlockBody", "getRuntimeContext",
                             "getSystemEvents"})
    assert(decode(method, list({Value::integer(1), Value::string("s"),
        Value::integer(1), finalized})).block.finality == CITIZENSDK_FINALITY_FINALIZED);
  assert(decode("getStorage", list({Value::integer(1), Value::string("s"), Value::integer(1),
      finalized, Value::bytes({1})})).payload.size() == 1);
  assert(decode("getStorageBatch", list({Value::integer(1), Value::string("s"), Value::integer(1),
      finalized, list({Value::bytes({1}), Value::bytes({2})})})).storage_keys.size() == 2);
  const auto keys_page = decode("getStorageKeysPaged", list({Value::integer(1),
      Value::string("s"), Value::integer(1), finalized, Value::bytes({1}),
      Value::null(), Value::integer(1000)}));
  assert(keys_page.storage_keys_limit == 1000 && !keys_page.storage_start_key);
  const auto runtime = decode("callRuntimeApi", list({Value::integer(1), Value::string("s"),
      Value::integer(1), finalized, Value::string("CitizenApi_items"), Value::bytes({})}));
  assert(runtime.runtime_api_method == "CitizenApi_items" && runtime.payload.empty());
  assert(decode("importState", list({Value::integer(1), Value::string("s"), Value::integer(1),
      Value::integer(1), finalized, Value::bytes({1})})).state_database.size() == 1);
  for (const char *method : {"getAccountBalance", "getAccountNonce",
       "setActiveWalletAccount", "deleteWalletAccount", "deleteAccount", "viewAccountPrivateKey"}) {
    assert(decode(method, list({Value::integer(1), Value::string("s"),
        Value::integer(1), Value::string(account('0'))})).account_id.bytes[0] == 0);
  }
  citizen_sdk::flutter::validate_public_value(Method::view_account_private_key, list({}));
  expect_failure([&] { citizen_sdk::flutter::validate_public_value(
      Method::view_account_private_key, list({Value::bytes(Value::Bytes(32))})); },
      CITIZENSDK_ERROR_INTEGRITY);
  expect_failure([&] { (void)decode("viewAccountPrivateKey", list({Value::integer(1),
      Value::string("s"), Value::integer(1), Value::string(account('0')), Value::integer(1)})); },
      CITIZENSDK_ERROR_INVALID_ARGUMENT);
  assert(decode("createWallet", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::integer(24)})).word_count == 24);
  assert(decode("createWallet", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::integer(18)})).word_count == 18);
  assert((decode("addWalletAccounts", list({Value::integer(1), Value::string("s"),
      Value::integer(1), list({Value::integer(1), Value::integer(1989)})})).indices ==
      std::vector<uint32_t>{1, 1989}));
  assert(decode("renameWalletAccount", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string(account('1')), Value::string("账户") })).name == "账户");
  assert(decode("renameAccount", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string(account('1')), Value::string("冷账户") })).name == "冷账户");
  assert(decode("importColdAccountId", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string(account('1')), Value::string("冷账户") })).name == "冷账户");
  assert(decode("importColdAccountSs58", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("w5CZACAABUbK4jspzPB5be9trhtSgRCRZFafGe7kvFPvxq8M2"),
      Value::string("冷账户") })).name == "冷账户");
  const auto reordered = decode("reorderWalletAccountsWithoutDefaultChange", list({
      Value::integer(1), Value::string("s"), Value::integer(1), Value::string("7"),
      list({Value::string(account('1')), Value::string(account('2'))})}));
  assert(reordered.wallet_revision == 7 && reordered.account_ids.size() == 2);
  assert(decode("signWalletPayload", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string(account('2')), Value::bytes({1, 2})})).payload.size() == 2);
  const auto application_key = decode("deriveApplicationKey", list({Value::integer(1),
      Value::string("s"), Value::integer(1), Value::string(account('2')),
      Value::bytes(Value::Bytes(32, 7)), Value::bytes({1})}));
  assert(application_key.application_key_salt.size() == 32 &&
         application_key.application_key_info.size() == 1);
  const auto signing = decode("beginSigning", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string(account('2')), Value::bytes({1, 2}), Value::string("raw"),
      Value::bytes({}), Value::string("none"), Value::integer(0), Value::integer(120)}));
  assert(signing.signing_transform == CITIZENSDK_SIGNING_TRANSFORM_RAW &&
         signing.external_signer_transport == CITIZENSDK_EXTERNAL_SIGNER_NONE);
  assert(decode("consumeExternalSignature", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("signing-session"), Value::string("{}")})).signing_response == "{}");
  assert(decode("cancelSigning", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("signing-session")})).signing_session_id == "signing-session");
  const auto default_change = decode("beginDefaultAccountChange", list({Value::integer(1),
      Value::string("s"), Value::integer(1), Value::string("7"),
      list({Value::string(account('2')), Value::string(account('1'))}), Value::integer(120)}));
  assert(default_change.wallet_revision == 7 && default_change.account_ids.size() == 2);
  assert(decode("consumeDefaultAccountChange", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("signing-session"), Value::string("{}")})).signing_response == "{}");
  const auto verification = decode("verifySignature", list({Value::integer(1),
      Value::string(account('2')), Value::bytes(Value::Bytes(64)), Value::bytes({})}));
  assert(verification.signature.size() == 64 && verification.session.empty() &&
         verification.sequence == 0);
  const auto prepared = decode("prepareTransaction", list({Value::integer(1),
      Value::string("s"), Value::integer(1), Value::string(account('2')),
      Value::bytes({1, 2})}));
  assert(prepared.account_id.bytes[0] == 0x22 && prepared.payload.size() == 2);
  assert(decode("cancelPreparedTransaction", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("0x00112233445566778899aabbccddeeff")})).preparation_id ==
      "0x00112233445566778899aabbccddeeff");
  assert(decode("executePreparedTransaction", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("0x00112233445566778899aabbccddeeff")})).preparation_id ==
      "0x00112233445566778899aabbccddeeff");
  assert(decode("consumePreparedTransactionQrResponse", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("0x112233445566778899aabbccddeeff00"),
      Value::string("QR_V1")})).signing_response == "QR_V1");
  assert(decode("cancelPreparedTransactionExecution", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("0x112233445566778899aabbccddeeff00")})).execution_id.bytes[0] == 0x11);

  assert(decode("qrScan", list({Value::integer(1), Value::string("s"),
      Value::integer(1)})).method == Method::qr_scan);
  assert(decode("signQrRequest", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::string("{}")})).qr_text == "{}");
  expect_failure([&] { (void)decode("qrParse", list({Value::integer(1),
      Value::string("s"), Value::integer(1), Value::string("{}"), Value::integer(10)})); },
      CITIZENSDK_ERROR_INVALID_ARGUMENT);
  for (const char *removed : {"qrSigningInput", "qrCreateSignResponse", "qrEncodeImage"})
    expect_failure([&] { (void)decode(removed, list({Value::integer(1),
        Value::string("s"), Value::integer(1)})); }, CITIZENSDK_ERROR_UNSUPPORTED);
  citizen_sdk::flutter::validate_public_value(Method::qr_consume_sign_response,
      list({Value::bytes(Value::Bytes(64))}));
  expect_failure([&] { citizen_sdk::flutter::validate_public_value(Method::qr_consume_sign_response,
      list({})); }, CITIZENSDK_ERROR_INTEGRITY);
  expect_failure([&] { citizen_sdk::flutter::validate_public_value(Method::qr_consume_sign_response,
      list({Value::bytes(Value::Bytes(63))})); }, CITIZENSDK_ERROR_INTEGRITY);
  citizen_sdk::flutter::validate_public_value(Method::qr_scan, list({Value::string("{}")}));
  assert(decode("qrParse", list({Value::integer(1), Value::string("s"), Value::integer(2),
      Value::string("{}")})).qr_text == "{}");
  assert(decode("qrCreateSignRequest", list({Value::integer(1), Value::string("s"),
      Value::integer(3), Value::integer(0x0400), Value::string(account('2')),
      Value::bytes({4, 0}), Value::integer(120)})).qr_action == 0x0400);
  assert(decode("qrEncode", list({Value::integer(1), Value::string("s"),
      Value::integer(4), Value::string("{}"), Value::integer(4)})).qr_scale == 4);
  expect_failure([&] { (void)decode("verifySignature", list({Value::integer(1),
      Value::string(account('2')), Value::bytes(Value::Bytes(63)), Value::bytes({})}));
  }, CITIZENSDK_ERROR_INVALID_ARGUMENT);
  expect_failure([&] { (void)decode("verifySignature", list({Value::integer(1),
      Value::string("s"), Value::integer(1), Value::string(account('2')),
      Value::bytes(Value::Bytes(64)), Value::bytes({})}));
  }, CITIZENSDK_ERROR_INVALID_ARGUMENT);
  citizen_sdk::flutter::validate_public_value(Method::verify_signature, list({Value::boolean(false)}));
  expect_failure([&] { citizen_sdk::flutter::validate_public_value(
      Method::verify_signature, list({Value::integer(0)})); }, CITIZENSDK_ERROR_INTEGRITY);
  for (const std::size_t count : {std::size_t{0}, std::size_t{2}, std::size_t{1990}}) {
    const auto batch = decode("getAccountBalances", list({Value::integer(1), Value::string("s"),
        Value::integer(1), Value::list(Value::List(count, Value::string(account('2'))))}));
    assert(batch.account_ids.size() == count);
  }
  expect_failure([&] { (void)decode("getAccountBalances", list({Value::integer(1), Value::string("s"),
      Value::integer(1), Value::list(Value::List(1991, Value::string(account('2'))))}));
  }, CITIZENSDK_ERROR_INVALID_ARGUMENT);
  expect_failure([&] { (void)decode("getAccountBalances", list({Value::integer(1), Value::string("s"),
      Value::integer(1), list({Value::string("invalid")})}));
  }, CITIZENSDK_ERROR_INVALID_ARGUMENT);
  const auto anchor = list({Value::string(account('3')), Value::string("9"), Value::string("finalized")});
  const auto balance = list({Value::string(account('2')), anchor, Value::string("1"),
                            Value::string("0"), Value::string("1")});
  citizen_sdk::flutter::validate_public_value(Method::get_genesis_hash, list({Value::string(account('3'))}));
  expect_failure([&] { citizen_sdk::flutter::validate_public_value(
      Method::get_genesis_hash, list({Value::string("invalid")})); }, CITIZENSDK_ERROR_INTEGRITY);
  auto request = decode("getAccountBalances", list({Value::integer(1), Value::string("s"),
      Value::integer(1), list({Value::string(account('2')), Value::string(account('2'))})}));
  citizen_sdk::flutter::validate_account_balances(request, list({list({balance, balance})}));
  expect_failure([&] { citizen_sdk::flutter::validate_account_balances(
      request, list({list({balance})})); }, CITIZENSDK_ERROR_INTEGRITY);
  auto wrong_account = balance;
  std::get<Value::List>(wrong_account.data)[0] = Value::string(account('1'));
  expect_failure([&] { citizen_sdk::flutter::validate_account_balances(
      request, list({list({balance, wrong_account})})); }, CITIZENSDK_ERROR_INTEGRITY);
  auto wrong_block = balance;
  std::get<Value::List>(wrong_block.data)[1] =
      list({Value::string(account('3')), Value::string("10"), Value::string("finalized")});
  expect_failure([&] { citizen_sdk::flutter::validate_account_balances(
      request, list({list({balance, wrong_block})})); }, CITIZENSDK_ERROR_INTEGRITY);
  const auto history = decode("getTransactionHistory", list({Value::integer(1),
      Value::string("s"), Value::integer(1), Value::null(), Value::integer(100)}));
  assert(!history.before_execution_id.has_value() && history.history_limit == 100);
  const auto paged = decode("getTransactionHistory", list({Value::integer(1),
      Value::string("s"), Value::integer(2),
      Value::string("0x00112233445566778899aabbccddeeff"), Value::integer(25)}));
  assert(paged.before_execution_id.has_value() && paged.history_limit == 25);
  assert(decode("syncTransactionHistory", list({Value::integer(1), Value::string("s"),
      Value::integer(3)})).method == Method::sync_transaction_history);
}

void test_strict_failures() {
  expect_failure([&] { (void)decode("open", list({Value::boolean(true)})); },
                 CITIZENSDK_ERROR_INVALID_ARGUMENT);
  expect_failure([&] { (void)decode("unknown", list({Value::integer(1)})); },
                 CITIZENSDK_ERROR_UNSUPPORTED);
  for (const int64_t words : {int64_t{15}, int64_t{21}}) {
    expect_failure([&] { (void)decode("createWallet", list({Value::integer(1), Value::string("s"),
        Value::integer(1), Value::integer(words)})); }, CITIZENSDK_ERROR_INVALID_ARGUMENT);
  }
  expect_failure([&] { (void)decode("addWalletAccounts", list({Value::integer(1), Value::string("s"),
      Value::integer(1), list({Value::integer(1), Value::integer(1)})})); },
      CITIZENSDK_ERROR_INVALID_ARGUMENT);
  expect_failure([&] { (void)decode("getTransactionHistory", list({Value::integer(1),
      Value::string("s"), Value::integer(1), Value::null(), Value::integer(101)})); },
      CITIZENSDK_ERROR_INVALID_ARGUMENT);

  Value nested = Value::integer(1);
  for (int i = 0; i < 34; ++i) nested = list({std::move(nested)});
  auto native = fl(nested);
  expect_failure([&] { (void)citizen_sdk::flutter::from_fl_value(native.get()); },
                 CITIZENSDK_ERROR_INVALID_ARGUMENT);

  Value::List too_many;
  too_many.reserve(4097);
  for (int i = 0; i < 4097; ++i) too_many.push_back(Value::null());
  native = fl(Value::list(std::move(too_many)));
  expect_failure([&] { (void)citizen_sdk::flutter::from_fl_value(native.get()); },
                 CITIZENSDK_ERROR_INVALID_ARGUMENT);

  Value::Bytes bulk(9 * 1024 * 1024, 7);
  native = fl(list({Value::bytes(bulk), Value::bytes(std::move(bulk))}));
  expect_failure([&] { (void)citizen_sdk::flutter::from_fl_value(native.get()); },
                 CITIZENSDK_ERROR_INVALID_ARGUMENT);

  FlValuePtr custom(fl_value_new_custom(999, nullptr, nullptr));
  expect_failure([&] { (void)citizen_sdk::flutter::from_fl_value(custom.get()); },
                 CITIZENSDK_ERROR_INVALID_ARGUMENT);
}

void test_standard_wire_preserves_nul_and_unicode() {
  GObjectPtr<FlStandardMethodCodec> codec(citizen_sdk::flutter::new_method_codec());
  assert(codec != nullptr);
  const std::string exact("途\0遇", 7);
  auto arguments = fl(list({Value::integer(1), Value::string("session"), Value::integer(8),
      Value::string(exact)}));
  auto wire = encode_call(FL_METHOD_CODEC(codec.get()), "qrParse", arguments.get());
  std::string method;
  auto decoded = decode_call(FL_METHOD_CODEC(codec.get()), wire.get(), &method);
  const auto request = citizen_sdk::flutter::decode_request(method, decoded.get());
  assert(request.qr_text.size() == exact.size() &&
         std::memcmp(request.qr_text.data(), exact.data(), exact.size()) == 0);

  // The same codec must write its internal custom representation back to the
  // ordinary StandardMessageCodec string tag rather than a protocol extension.
  auto second_wire = encode_call(FL_METHOD_CODEC(codec.get()), method.c_str(), decoded.get());
  gsize first_size = 0, second_size = 0;
  const auto *first = g_bytes_get_data(wire.get(), &first_size);
  const auto *second = g_bytes_get_data(second_wire.get(), &second_size);
  assert(first_size == second_size && std::memcmp(first, second, first_size) == 0);

  const uint8_t malformed[] = {7, 4, 'o', 'p', 'e', 'n', 7, 2, 0xc3, 0x28};
  GBytesPtr bad(g_bytes_new(malformed, sizeof(malformed)));
  gchar *bad_method = nullptr; FlValue *bad_args = nullptr; GError *error = nullptr;
  const gboolean accepted = FL_METHOD_CODEC_GET_CLASS(codec.get())->decode_method_call(
      FL_METHOD_CODEC(codec.get()), bad.get(), &bad_method, &bad_args, &error);
  assert(!accepted && error != nullptr && bad_method == nullptr && bad_args == nullptr);
  g_clear_error(&error);
}

void test_envelopes_and_decimal() {
  using namespace citizen_sdk::flutter;
  assert(decimal_u128(parse_u128("0")) == "0");
  assert(decimal_u128(parse_u128("340282366920938463463374607431768211455")) ==
         "340282366920938463463374607431768211455");
  const auto envelope = response("s", 7, list({Value::string("running")}));
  assert(as_list(envelope).size() == 4 && as_string(as_list(envelope)[1]) == "s");
  const auto failure = error_details(CITIZENSDK_ERROR_BUSY, "busy", "s", 7, "getStorage");
  assert(as_list(failure).size() == 7 && as_integer(as_list(failure)[4]) ==
         CITIZENSDK_FAILURE_STAGE_ADMISSION &&
         as_string(as_list(failure)[5]) == "getStorage" &&
         as_string(as_list(failure)[6]) == "busy");
  assert(std::string(error_name(CITIZENSDK_ERROR_BUSY)) == "busy");
}

Value::List &mutable_list(Value &value) { return std::get<Value::List>(value.data); }
Value block_fixture(char hash = '1', const char *number = "7", bool finalized = true) {
  return list({Value::string(account(hash)), Value::string(number),
               Value::string(finalized ? "finalized" : "best")});
}
Value execution_fixture(bool success = true) {
  return list({Value::string(success ? "success" : "failed"), block_fixture(),
      Value::integer(0), success ? Value::null() : Value::integer(0), Value::null(), Value::null()});
}
Value profile_fixture() {
  // Public AccountId/SS58 golden pair from citizenchain-wallet-derivation-v1;
  // no mnemonic, child seed or password is copied into this fixture.
  constexpr const char *id = "0x2afba9278e30ccf6a6ceb3a8b6e336b70068f045c666f2e7f4f9cc5f47db8972";
  constexpr const char *address = "w5CZACAABUbK4jspzPB5be9trhtSgRCRZFafGe7kvFPvxq8M2";
  auto item = list({Value::integer(0), Value::string(id), Value::string(address),
      Value::string("主账户"), Value::string("0"), Value::boolean(true)});
  return list({Value::integer(0), Value::string("created"), Value::string("0"),
      Value::string(id), Value::string(id), list({std::move(item)})});
}
Value history_fixture() {
  const auto id = Value::string("0x00112233445566778899aabbccddeeff");
  auto record = list({id, Value::string(account('1')), Value::string(account('2')),
      Value::string(account('3')), Value::string("pending"), Value::null(),
      Value::null(), Value::null(), Value::string("1"), Value::string("1"), Value::null()});
  return list({Value::string("1"), list({std::move(record)}), id});
}

void test_profile_semantics() {
  using citizen_sdk::flutter::validate_public_value;
  const auto good = profile_fixture();
  validate_public_value(Method::get_wallet_profile, list({good}));
  for (unsigned kind = 0; kind < 7; ++kind) {
    auto bad = good; auto &profile = mutable_list(bad);
    auto &accounts = mutable_list(profile[5]); auto &first = mutable_list(accounts[0]);
    switch (kind) {
      case 0: first[2] = Value::string(""); break;
      case 1: accounts.push_back(accounts[0]); break;
      case 2: first[0] = Value::integer(1); break;
      case 3: profile[4] = Value::string(account('1')); break;
      case 4: first[3] = Value::string("\xc2\xa0"); break;
      case 5: profile[0] = Value::integer(1); break;
      case 6: profile[1] = Value::string("unknown"); break;
    }
    expect_failure([&] { validate_public_value(Method::get_wallet_profile, list({bad})); },
                   CITIZENSDK_ERROR_INTEGRITY);
  }
}

void test_history_semantics() {
  using citizen_sdk::flutter::validate_public_value;
  const auto good = history_fixture();
  validate_public_value(Method::sync_transaction_history, list({good}));
  for (unsigned kind = 0; kind < 6; ++kind) {
    auto bad = good; auto &history = mutable_list(bad);
    auto &records = mutable_list(history[1]);
    switch (kind) {
      case 0: records.push_back(records[0]); break;
      case 1: mutable_list(records[0])[4] = Value::string("finalizedSuccess"); break;
      case 2: mutable_list(records[0])[9] = Value::string("0"); break;
      case 3: history[2] = Value::string("0xffffffffffffffffffffffffffffffff"); break;
      case 4: mutable_list(records[0])[3] = Value::string("invalid"); break;
      case 5: mutable_list(records[0])[0] = Value::string("invalid"); break;
    }
    expect_failure([&] { validate_public_value(Method::sync_transaction_history, list({bad})); },
                   CITIZENSDK_ERROR_INTEGRITY);
  }
}

void test_balance_nonce_fee_semantics() {
  using citizen_sdk::flutter::validate_public_value;
  auto balance = list({Value::string(account('1')), block_fixture(),
      Value::string("3"), Value::string("2"), Value::string("5")});
  validate_public_value(Method::get_account_balance, list({balance}));
  mutable_list(balance)[4] = Value::string("4");
  expect_failure([&] { validate_public_value(Method::get_account_balance, list({balance})); },
                 CITIZENSDK_ERROR_INTEGRITY);
  const auto nonce = list({Value::string(account('1')), block_fixture(), Value::string("0")});
  expect_failure([&] { validate_public_value(Method::get_account_nonce, list({nonce})); },
                 CITIZENSDK_ERROR_INTEGRITY);
  const auto fee = list({block_fixture('1', "7", false), Value::integer(0), Value::string("1"), Value::string("0")});
  expect_failure([&] { validate_public_value(Method::get_fee_snapshot, list({fee})); },
                 CITIZENSDK_ERROR_INTEGRITY);

  citizensdk_capability_snapshot_t snapshot{};
  snapshot.struct_size = sizeof(snapshot); snapshot.abi_version = CITIZENSDK_ABI_VERSION;
  snapshot.count = CITIZENSDK_CAPABILITY_COUNT;
  for (uint32_t i = 0; i < snapshot.count; ++i) {
    snapshot.statuses[i].name = i + 1;
    snapshot.statuses[i].reason = CITIZENSDK_CAPABILITY_REASON_BUILD_UNSUPPORTED;
  }
  (void)citizen_sdk::flutter::capabilities(snapshot);
  snapshot.statuses[0].ready = 1;
  expect_failure([&] { (void)citizen_sdk::flutter::capabilities(snapshot); },
                 CITIZENSDK_ERROR_INTEGRITY);
  snapshot.statuses[0].ready = 0;
  snapshot.statuses[1].name = snapshot.statuses[0].name;
  expect_failure([&] { (void)citizen_sdk::flutter::capabilities(snapshot); },
                 CITIZENSDK_ERROR_INTEGRITY);
}
}  // namespace

int main() {
  (void)citizen_sdk::flutter::event("s", 1, "historyChanged", Value::list({}));
  (void)citizen_sdk::flutter::event(
      "s", 2, "finalizedBlockChanged", Value::list({block_fixture('3', "7", true)}));
  expect_failure([] {
    (void)citizen_sdk::flutter::event(
        "s", 2, "finalizedBlockChanged", Value::list({block_fixture('3', "7", false)}));
  }, CITIZENSDK_ERROR_INTEGRITY);
  expect_failure([] {
    (void)citizen_sdk::flutter::event("s", 1, "historyChanged", Value::list({Value::integer(1)}));
  }, CITIZENSDK_ERROR_INTEGRITY);
  test_method_closure_and_requests();
  test_strict_failures();
  test_standard_wire_preserves_nul_and_unicode();
  test_envelopes_and_decimal();
  test_profile_semantics();
  test_history_semantics();
  test_balance_nonce_fee_semantics();
  return 0;
}
