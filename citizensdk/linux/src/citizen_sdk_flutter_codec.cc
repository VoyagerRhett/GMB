#include "citizen_sdk_flutter_codec.hpp"

#include <algorithm>
#include <array>
#include <charconv>
#include <cstring>
#include <limits>
#include <set>
#include <utility>

namespace citizen_sdk::flutter {
namespace {

struct UnicodeInfo {
  std::size_t scalars{};
  std::size_t utf16{};
  uint32_t first{};
  uint32_t last{};
  bool controls{};
};
[[noreturn]] void fail(citizensdk_error_code_t code, const char *message);
void require(bool condition, citizensdk_error_code_t code, const char *message);
bool inspect_utf8(const std::string &text, UnicodeInfo *info) noexcept;
bool trim_space(uint32_t scalar) noexcept;
const std::string &string(const Value &value, std::size_t minimum,
                          std::size_t maximum_utf16);
citizensdk_account_id_t account(const Value &value);

uint64_t u64_text(const Value &value) {
  const auto &text = string(value, 1, 20);
  require(text.size() == 1 || text.front() != '0', CITIZENSDK_ERROR_INTEGRITY,
          "Public u64 is not canonical decimal");
  uint64_t result = 0;
  const auto parsed = std::from_chars(text.data(), text.data() + text.size(), result);
  require(parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size(),
          CITIZENSDK_ERROR_INTEGRITY, "Public u64 is outside its range");
  return result;
}
const Value::List &semantic_tuple(const Value &value, std::size_t expected) {
  const auto *fields = std::get_if<Value::List>(&value.data);
  require(fields != nullptr && fields->size() == expected, CITIZENSDK_ERROR_INTEGRITY,
          "Public result tuple shape is invalid");
  return *fields;
}
bool null_value(const Value &value) { return std::holds_alternative<std::monostate>(value.data); }
int64_t semantic_int(const Value &value, int64_t maximum = INT64_MAX) {
  const auto *result = std::get_if<int64_t>(&value.data);
  require(result != nullptr && *result >= 0 && *result <= maximum,
          CITIZENSDK_ERROR_INTEGRITY, "Public integer is outside its range");
  return *result;
}
std::string semantic_text(const Value &value) {
  const auto *result = std::get_if<std::string>(&value.data);
  require(result != nullptr && valid_utf8(*result), CITIZENSDK_ERROR_INTEGRITY,
          "Public text is not valid UTF-8");
  return *result;
}
struct SemanticBlock { citizensdk_account_id_t hash{}; uint64_t number{}; bool finalized{}; };
SemanticBlock semantic_block(const Value &value) {
  const auto &fields = semantic_tuple(value, 3);
  const std::string finality = semantic_text(fields[2]);
  require(finality == "best" || finality == "finalized", CITIZENSDK_ERROR_INTEGRITY,
          "Public block finality is invalid");
  return {account(fields[0]), u64_text(fields[1]), finality == "finalized"};
}
bool same_id(const citizensdk_account_id_t &a, const citizensdk_account_id_t &b) {
  return std::memcmp(a.bytes, b.bytes, 32) == 0;
}
bool same_block(const SemanticBlock &a, const SemanticBlock &b) {
  return a.number == b.number && same_id(a.hash, b.hash) && a.finalized == b.finalized;
}
struct SemanticExecution { bool success{}; SemanticBlock block; };
SemanticExecution semantic_execution(const Value &value) {
  const auto &fields = semantic_tuple(value, 6);
  const std::string status = semantic_text(fields[0]);
  require(status == "success" || status == "failed", CITIZENSDK_ERROR_INTEGRITY,
          "Public execution status is invalid");
  const auto block_value = semantic_block(fields[1]);
  require(block_value.finalized, CITIZENSDK_ERROR_INTEGRITY,
          "Execution is not finalized");
  (void)semantic_int(fields[2], UINT32_MAX);
  const bool dispatch = !null_value(fields[3]);
  const bool pallet = !null_value(fields[4]), error = !null_value(fields[5]);
  if (dispatch) (void)semantic_int(fields[3], UINT8_MAX);
  if (pallet) (void)semantic_int(fields[4], UINT8_MAX);
  if (error) (void)semantic_int(fields[5], UINT8_MAX);
  require((status == "success" && !dispatch && !pallet && !error) ||
              (status == "failed" && dispatch &&
               ((semantic_int(fields[3], UINT8_MAX) == CITIZENSDK_DISPATCH_ERROR_MODULE && pallet && error) ||
                (semantic_int(fields[3], UINT8_MAX) != CITIZENSDK_DISPATCH_ERROR_MODULE && !pallet && !error))),
          CITIZENSDK_ERROR_INTEGRITY, "Execution dispatch fields disagree");
  return {status == "success", block_value};
}

bool semantic_bool(const Value &value) {
  const auto *result = std::get_if<bool>(&value.data);
  require(result != nullptr, CITIZENSDK_ERROR_INTEGRITY, "Public boolean is invalid");
  return *result;
}
citizensdk_u128_t semantic_u128(const Value &value) {
  try { return parse_u128(semantic_text(value)); }
  catch (...) { fail(CITIZENSDK_ERROR_INTEGRITY, "Public u128 is invalid"); }
}
bool positive(citizensdk_u128_t value) noexcept { return value.low != 0 || value.high != 0; }
bool sum_matches(citizensdk_u128_t a, citizensdk_u128_t b,
                 citizensdk_u128_t total) noexcept {
  const uint64_t low = a.low + b.low;
  const uint64_t carry = low < a.low ? 1 : 0;
  const uint64_t high_sum = a.high + b.high;
  const uint64_t high = high_sum + carry;
  const bool overflow = high_sum < a.high || high < high_sum;
  return !overflow && low == total.low && high == total.high;
}
bool contains_non_whitespace(const std::string &text) {
  for (std::size_t offset = 0; offset < text.size();) {
    const auto first = static_cast<uint8_t>(text[offset++]);
    uint32_t scalar = first; unsigned remaining = 0;
    if (first >= 0xc2 && first <= 0xdf) { scalar = first & 0x1fU; remaining = 1; }
    else if (first >= 0xe0 && first <= 0xef) { scalar = first & 0x0fU; remaining = 2; }
    else if (first >= 0xf0) { scalar = first & 7U; remaining = 3; }
    for (unsigned i = 0; i < remaining; ++i)
      scalar = (scalar << 6) | (static_cast<uint8_t>(text[offset++]) & 0x3fU);
    if (!trim_space(scalar)) return true;
  }
  return false;
}
void validate_profile(const Value &value) {
  if (null_value(value)) return;
  const auto &profile = semantic_tuple(value, 6);
  require(semantic_int(profile[0], UINT32_MAX) == 0,
          CITIZENSDK_ERROR_INTEGRITY, "Wallet index must be zero");
  const auto origin = semantic_text(profile[1]);
  require(origin == "created" || origin == "imported", CITIZENSDK_ERROR_INTEGRITY,
          "Wallet origin is invalid");
  (void)u64_text(profile[2]);
  const auto master = account(profile[3]), active_id = account(profile[4]);
  const auto *accounts = std::get_if<Value::List>(&profile[5].data);
  require(accounts != nullptr && !accounts->empty() && accounts->size() <= 1990,
          CITIZENSDK_ERROR_INTEGRITY, "Wallet account closure is invalid");
  std::set<std::array<uint8_t, 32>> ids;
  std::set<int64_t> indices;
  unsigned active_count = 0; bool master_found = false, active_matches = false;
  for (const auto &item : *accounts) {
    const auto &fields = semantic_tuple(item, 6);
    const auto index = semantic_int(fields[0], 1989);
    const auto id = account(fields[1]); std::array<uint8_t, 32> key{};
    std::copy(std::begin(id.bytes), std::end(id.bytes), key.begin());
    require(ids.insert(key).second && indices.insert(index).second,
            CITIZENSDK_ERROR_INTEGRITY, "Wallet account identity or index is duplicated");
    // 不在薄绑定重写 SS58 算法；精确 AccountId/prefix 校验由既有 Core 与 Dart 共同保持。
    require(!semantic_text(fields[2]).empty(), CITIZENSDK_ERROR_INTEGRITY,
            "Wallet account SS58 must be nonempty UTF-8");
    const auto name = semantic_text(fields[3]); UnicodeInfo info;
    require(inspect_utf8(name, &info) && info.scalars >= 1 && info.scalars <= 30 &&
                !info.controls && !trim_space(info.first) && !trim_space(info.last),
            CITIZENSDK_ERROR_INTEGRITY, "Wallet account name is invalid");
    (void)u64_text(fields[4]);
    if (semantic_bool(fields[5])) {
      ++active_count;
      if (same_id(id, active_id)) active_matches = true;
    }
    if (index == 0 && same_id(id, master)) master_found = true;
  }
  require(active_count == 1 && active_matches && master_found,
          CITIZENSDK_ERROR_INTEGRITY, "Wallet active/master closure is inconsistent");
}

void validate_wallet_state(const Value &value) {
  const auto &state = semantic_tuple(value, 3); (void)u64_text(state[0]);
  validate_profile(state[1]);
  const auto *accounts = std::get_if<Value::List>(&state[2].data);
  require(accounts != nullptr && accounts->size() <= 3980,
          CITIZENSDK_ERROR_INTEGRITY, "Wallet state account collection is invalid");
  std::set<std::array<uint8_t, 32>> ids;
  std::set<int64_t> cold_indices;
  std::set<std::array<uint8_t, 32>> hot_ids;
  for (std::size_t index = 0; index < accounts->size(); ++index) {
    const auto &fields = semantic_tuple((*accounts)[index], 8);
    const auto mode = semantic_text(fields[0]);
    const auto wallet_index = semantic_int(fields[1], UINT32_MAX);
    const bool has_account_index = !null_value(fields[2]);
    if (has_account_index) (void)semantic_int(fields[2], 1989);
    const auto id = account(fields[3]); std::array<uint8_t, 32> key{};
    std::copy(std::begin(id.bytes), std::end(id.bytes), key.begin());
    const auto ss58 = semantic_text(fields[4]);
    const auto name = semantic_text(fields[5]); UnicodeInfo unicode;
    const auto *is_default = std::get_if<bool>(&fields[7].data);
    require(ids.insert(key).second && !ss58.empty() &&
                inspect_utf8(name, &unicode) && unicode.scalars >= 1 && unicode.scalars <= 30 &&
                !unicode.controls && !trim_space(unicode.first) && !trim_space(unicode.last) &&
                is_default != nullptr && *is_default == (index == 0),
            CITIZENSDK_ERROR_INTEGRITY, "Wallet state account facts are inconsistent");
    (void)u64_text(fields[6]);
    if (mode == "hot") {
      require(wallet_index == 0 && has_account_index,
              CITIZENSDK_ERROR_INTEGRITY, "Hot wallet state account indices are invalid");
      hot_ids.insert(key);
    } else {
      require(mode == "cold" && wallet_index > 0 && !has_account_index &&
                  cold_indices.insert(wallet_index).second,
              CITIZENSDK_ERROR_INTEGRITY, "Cold wallet state account indices are invalid");
    }
  }
  if (!null_value(state[1])) {
    const auto &profile = semantic_tuple(state[1], 6);
    const auto *hot = std::get_if<Value::List>(&profile[5].data);
    std::set<std::array<uint8_t, 32>> profile_hot_ids;
    if (hot != nullptr) for (const auto &item : *hot) {
      const auto &fields = semantic_tuple(item, 6); const auto id = account(fields[1]);
      std::array<uint8_t, 32> key{};
      std::copy(std::begin(id.bytes), std::end(id.bytes), key.begin());
      profile_hot_ids.insert(key);
    }
    require(hot != nullptr && profile_hot_ids == hot_ids,
            CITIZENSDK_ERROR_INTEGRITY, "Wallet state hot profile closure is inconsistent");
  } else {
    require(hot_ids.empty(), CITIZENSDK_ERROR_INTEGRITY,
            "Wallet state exposes hot accounts without a profile");
  }
}

void validate_history(const Value &value) {
  const auto &history = semantic_tuple(value, 3); (void)u64_text(history[0]);
  const auto *records = std::get_if<Value::List>(&history[1].data);
  require(records != nullptr && records->size() <= 100,
          CITIZENSDK_ERROR_INTEGRITY, "Transaction history page exceeds its contract");
  auto valid_id = [](const std::string &id) {
    return id.size() == 34 && id.rfind("0x", 0) == 0 &&
        std::all_of(id.begin() + 2, id.end(), [](char value) {
          return (value >= '0' && value <= '9') || (value >= 'a' && value <= 'f');
        });
  };
  std::set<std::string> execution_ids, transaction_hashes;
  std::string last_execution_id;
  for (const auto &item : *records) {
    const auto &fields = semantic_tuple(item, 11);
    const auto id = semantic_text(fields[0]);
    require(valid_id(id) && execution_ids.insert(id).second,
            CITIZENSDK_ERROR_INTEGRITY, "Transaction history execution identity is invalid");
    (void)account(fields[1]); (void)account(fields[2]);
    const auto transaction = semantic_text(fields[3]);
    (void)account(fields[3]);
    require(transaction_hashes.insert(transaction).second,
            CITIZENSDK_ERROR_INTEGRITY, "Transaction history hash is duplicated");
    const auto status = semantic_text(fields[4]);
    const bool has_block = !null_value(fields[5]), has_execution = !null_value(fields[6]);
    std::optional<SemanticBlock> block_value;
    std::optional<SemanticExecution> execution_value;
    if (has_block) block_value = semantic_block(fields[5]);
    if (has_execution) execution_value = semantic_execution(fields[6]);
    if (!null_value(fields[7])) (void)account(fields[7]);
    const uint64_t created = u64_text(fields[8]), updated = u64_text(fields[9]);
    require(updated >= created, CITIZENSDK_ERROR_INTEGRITY,
            "Transaction history timestamps are invalid");
    const bool has_reason = !null_value(fields[10]);
    std::string reason; if (has_reason) reason = semantic_text(fields[10]);
    const bool matching = has_block && has_execution && same_block(*block_value, execution_value->block);
    const bool valid =
        (status == "pending" && !has_block && !has_execution && !has_reason) ||
        (status == "inBlock" && has_block && !has_execution && !has_reason) ||
        (status == "poolRejected" && !has_block && !has_execution && has_reason && contains_non_whitespace(reason)) ||
        (status == "finalizedSuccess" && matching && block_value->finalized && execution_value->success && !has_reason) ||
        (status == "finalizedFailed" && matching && block_value->finalized && !execution_value->success && !has_reason);
    require(valid, CITIZENSDK_ERROR_INTEGRITY,
            "Transaction history record status fields disagree");
    last_execution_id = id;
  }
  if (!null_value(history[2])) {
    const auto next = semantic_text(history[2]);
    require(valid_id(next) && !records->empty() && next == last_execution_id,
            CITIZENSDK_ERROR_INTEGRITY,
            "Transaction history next cursor is not the final record");
  }
}


constexpr std::size_t kMaximumBytes = 16 * 1024 * 1024;
constexpr std::size_t kMaximumRequestCopiedBytes = kMaximumBytes + 4096;
constexpr std::size_t kMaximumStorageKeyBytes = 4 * 1024;
constexpr std::size_t kMaximumStorageBatchKeys = 1024;
constexpr std::size_t kMaximumStorageBatchKeyBytes = 1024 * 1024;
constexpr std::size_t kMaximumHeaderDigestBytes = 1024 * 1024;
constexpr std::size_t kMaximumBlockBodyExtrinsics = 16 * 1024;
constexpr std::size_t kMaximumBlockBodyBytes = 64 * 1024 * 1024;
constexpr std::size_t kMaximumRuntimeMetadataBytes = 64 * 1024 * 1024;
constexpr std::size_t kMaximumTransactionCallDataBytes = 1024 * 1024;
constexpr std::size_t kMaximumExportedStateBytes = 256 * 1024;
constexpr int kLengthPreservingString = 0x43535331;
constexpr const char *kMethods[] = {
    "open", "start", "stop", "close", "getCapabilities", "getFinalizedHead",
    "getSyncStatus", "getBestHead", "getFinalizedBlockAt", "resolveFinalizedBlock",
    "getBlockHeader", "getBlockBody", "getRuntimeContext", "getStorage", "getStorageBatch",
    "getSystemEvents", "exportState", "importState", "getGenesisHash",
    "getAccountBalance", "getAccountBalances", "getAccountNonce", "getFeeSnapshot", "getWalletProfile", "viewAccountPrivateKey",
    "getWalletState", "importColdAccountId", "importColdAccountSs58",
    "reorderWalletAccountsWithoutDefaultChange", "renameAccount", "deleteAccount",
    "createWallet", "importWallet", "addWalletAccounts", "setActiveWalletAccount",
    "renameWalletAccount", "deleteWalletAccount", "deleteWallet",
    "reconcileWalletCleanup", "signWalletPayload", "beginSigning",
    "consumeExternalSignature", "cancelSigning", "beginDefaultAccountChange",
    "consumeDefaultAccountChange", "verifySignature", "prepareTransaction",
    "cancelPreparedTransaction", "executePreparedTransaction",
    "consumePreparedTransactionQrResponse", "cancelPreparedTransactionExecution",
    "getTransactionHistory", "syncTransactionHistory",
    "qrParse", "qrCreateSignRequest",
    "qrConsumeSignResponse", "qrCancelSignRequest", "qrEncodeAccountId",
    "qrDecodeLuminance", "qrEncode", "qrScan", "signQrRequest",
};
static_assert(std::size(kMethods) == 62);

[[noreturn]] void fail(citizensdk_error_code_t code, const char *message) {
  throw ContractFailure(code, message);
}
void require(bool condition, citizensdk_error_code_t code, const char *message) {
  if (!condition) fail(code, message);
}

// Decode Unicode scalars ourselves: GLib's NUL-terminated validation API is
// insufficient for the exact, length-preserving StandardMessageCodec string.
bool inspect_utf8(const std::string &text, UnicodeInfo *info) noexcept {
  UnicodeInfo parsed;
  for (std::size_t offset = 0; offset < text.size();) {
    const auto first = static_cast<uint8_t>(text[offset++]);
    uint32_t scalar = first;
    uint32_t minimum = 0;
    unsigned remaining = 0;
    if (first >= 0xc2 && first <= 0xdf) {
      scalar = static_cast<uint32_t>(first & 0x1fU); remaining = 1; minimum = 0x80;
    } else if (first >= 0xe0 && first <= 0xef) {
      scalar = static_cast<uint32_t>(first & 0x0fU); remaining = 2; minimum = 0x800;
    } else if (first >= 0xf0 && first <= 0xf4) {
      scalar = static_cast<uint32_t>(first & 7U); remaining = 3; minimum = 0x10000;
    } else if (first >= 0x80) {
      return false;
    }
    if (remaining > text.size() - offset) return false;
    for (unsigned index = 0; index < remaining; ++index) {
      const auto next = static_cast<uint8_t>(text[offset++]);
      if ((next & 0xc0) != 0x80) return false;
      scalar = (scalar << 6) | static_cast<uint32_t>(next & 0x3fU);
    }
    if (scalar < minimum || scalar > 0x10ffff ||
        (scalar >= 0xd800 && scalar <= 0xdfff)) return false;
    if (parsed.scalars == 0) parsed.first = scalar;
    parsed.last = scalar;
    ++parsed.scalars;
    parsed.utf16 += scalar > 0xffff ? 2 : 1;
    parsed.controls = parsed.controls || scalar <= 0x1f ||
                      (scalar >= 0x7f && scalar <= 0x9f);
  }
  if (info != nullptr) *info = parsed;
  return true;
}

// Dart String.trim's Unicode whitespace set (including BOM) is relevant only
// at the ends of a wallet label; an internal ordinary space stays valid.
bool trim_space(uint32_t scalar) noexcept {
  return (scalar >= 0x09 && scalar <= 0x0d) || scalar == 0x20 ||
         scalar == 0x85 || scalar == 0xa0 || scalar == 0x1680 ||
         (scalar >= 0x2000 && scalar <= 0x200a) || scalar == 0x2028 ||
         scalar == 0x2029 || scalar == 0x202f || scalar == 0x205f ||
         scalar == 0x3000 || scalar == 0xfeff;
}

std::string fl_string(FlValue *value) {
  require(value != nullptr, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "Expected UTF-8 string");
  std::string text;
  if (fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
    const char *raw = fl_value_get_string(value);
    require(raw != nullptr, CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "String storage is missing");
    text = raw;
  } else if (fl_value_get_type(value) == FL_VALUE_TYPE_CUSTOM &&
             fl_value_get_custom_type(value) == kLengthPreservingString) {
    const auto *raw = static_cast<const std::string *>(
        fl_value_get_custom_value(value));
    require(raw != nullptr, CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "String storage is missing");
    text = *raw;
  } else {
    fail(CITIZENSDK_ERROR_INVALID_ARGUMENT, "Expected UTF-8 string");
  }
  require(inspect_utf8(text, nullptr), CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "String is not valid UTF-8");
  return text;
}

void destroy_string(gpointer value) { delete static_cast<std::string *>(value); }
FlValue *owned_fl_string(const std::string &text) {
  require(valid_utf8(text), CITIZENSDK_ERROR_INTEGRITY,
          "Public result string is not valid UTF-8");
  if (text.find('\0') == std::string::npos) return fl_value_new_string(text.c_str());
  auto storage = std::make_unique<std::string>(text);
  FlValue *value = fl_value_new_custom(kLengthPreservingString, storage.get(),
                                      destroy_string);
  (void)storage.release();
  return value;
}

// This is an internal representation adapter using Flutter's official virtual
// hooks. It never emits a custom wire tag: text remains standard string tag 7.
typedef struct _CitizenSdkStringCodec {
  FlStandardMessageCodec parent_instance;
} CitizenSdkStringCodec;
typedef struct _CitizenSdkStringCodecClass {
  FlStandardMessageCodecClass parent_class;
} CitizenSdkStringCodecClass;
G_DEFINE_TYPE(CitizenSdkStringCodec, citizen_sdk_string_codec,
              fl_standard_message_codec_get_type())

FlValue *read_string_value(FlStandardMessageCodec *codec, GBytes *buffer,
                          size_t *offset, int type, GError **error) {
  try {
    if (type != 7) {
      return FL_STANDARD_MESSAGE_CODEC_CLASS(citizen_sdk_string_codec_parent_class)
          ->read_value_of_type(codec, buffer, offset, type, error);
    }
    uint32_t length = 0;
    if (!fl_standard_message_codec_read_size(codec, buffer, offset, &length,
                                              error)) return nullptr;
    gsize size = 0;
    const auto *raw = static_cast<const char *>(g_bytes_get_data(buffer, &size));
    if (*offset > size || length > size - *offset || length > kMaximumBytes) {
      g_set_error_literal(error, FL_MESSAGE_CODEC_ERROR,
                          FL_MESSAGE_CODEC_ERROR_FAILED,
                          "CitizenSDK string length is invalid");
      return nullptr;
    }
    const std::string text(length == 0 ? "" : raw + *offset, length);
    if (!valid_utf8(text)) {
      g_set_error_literal(error, FL_MESSAGE_CODEC_ERROR,
                          FL_MESSAGE_CODEC_ERROR_FAILED,
                          "CitizenSDK string is not valid UTF-8");
      return nullptr;
    }
    *offset += length;
    return owned_fl_string(text);
  } catch (...) {
    g_set_error_literal(error, FL_MESSAGE_CODEC_ERROR, FL_MESSAGE_CODEC_ERROR_FAILED,
                        "CitizenSDK string decode failed");
    return nullptr;
  }
}

gboolean write_string_value(FlStandardMessageCodec *codec, GByteArray *buffer,
                            FlValue *value, GError **error) {
  try {
    if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_CUSTOM) {
      if (fl_value_get_custom_type(value) != kLengthPreservingString) {
        g_set_error_literal(error, FL_MESSAGE_CODEC_ERROR,
                            FL_MESSAGE_CODEC_ERROR_FAILED,
                            "CitizenSDK rejects unknown custom values");
        return FALSE;
      }
      const auto text = fl_string(value);
      if (text.size() > kMaximumBytes) {
        g_set_error_literal(error, FL_MESSAGE_CODEC_ERROR,
                            FL_MESSAGE_CODEC_ERROR_FAILED,
                            "CitizenSDK string length is invalid");
        return FALSE;
      }
      const uint8_t tag = 7;
      g_byte_array_append(buffer, &tag, 1);
      fl_standard_message_codec_write_size(codec, buffer,
                                            static_cast<uint32_t>(text.size()));
      g_byte_array_append(buffer, reinterpret_cast<const uint8_t *>(text.data()),
                           static_cast<guint>(text.size()));
      return TRUE;
    }
    if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
      (void)fl_string(value);  // Reject malformed native UTF-8, too.
    }
    return FL_STANDARD_MESSAGE_CODEC_CLASS(citizen_sdk_string_codec_parent_class)
        ->write_value(codec, buffer, value, error);
  } catch (...) {
    g_set_error_literal(error, FL_MESSAGE_CODEC_ERROR, FL_MESSAGE_CODEC_ERROR_FAILED,
                        "CitizenSDK string encode failed");
    return FALSE;
  }
}
void citizen_sdk_string_codec_class_init(CitizenSdkStringCodecClass *klass) {
  auto *codec = FL_STANDARD_MESSAGE_CODEC_CLASS(klass);
  codec->read_value_of_type = read_string_value;
  codec->write_value = write_string_value;
}
void citizen_sdk_string_codec_init(CitizenSdkStringCodec *) {}

void debit_bytes(std::size_t count, std::size_t &remaining) {
  require(count <= remaining, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "Tuple cumulative byte size exceeds the public contract");
  remaining -= count;
}
Value from_fl(FlValue *value, unsigned depth, std::size_t &remaining_nodes,
              std::size_t &remaining_bytes) {
  require(value != nullptr && depth <= 32 && remaining_nodes > 0,
          CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "Invalid or excessively nested tuple");
  --remaining_nodes;
  switch (fl_value_get_type(value)) {
    case FL_VALUE_TYPE_NULL: return Value::null();
    case FL_VALUE_TYPE_BOOL: return Value::boolean(fl_value_get_bool(value));
    case FL_VALUE_TYPE_INT: return Value::integer(fl_value_get_int(value));
    case FL_VALUE_TYPE_STRING: {
      const char *text = fl_value_get_string(value);
      require(text != nullptr && g_utf8_validate(text, -1, nullptr), CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "String is not valid UTF-8");
      const std::size_t length = std::strlen(text);
      debit_bytes(length, remaining_bytes);
      return Value::string(std::string(text, length));
    }
    case FL_VALUE_TYPE_CUSTOM: {
      require(fl_value_get_custom_type(value) == kLengthPreservingString,
              CITIZENSDK_ERROR_INVALID_ARGUMENT, "Unknown custom value");
      const auto *text = static_cast<const std::string *>(fl_value_get_custom_value(value));
      require(text != nullptr && valid_utf8(*text), CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "String is not valid UTF-8");
      debit_bytes(text->size(), remaining_bytes);
      return Value::string(*text);
    }
    case FL_VALUE_TYPE_UINT8_LIST: {
      const auto count = fl_value_get_length(value);
      require(count <= kMaximumBytes, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "Byte value exceeds 16 MiB");
      debit_bytes(count, remaining_bytes);
      const auto *bytes = fl_value_get_uint8_list(value);
      return Value::bytes(count == 0 ? Value::Bytes{} : Value::Bytes(bytes, bytes + count));
    }
    case FL_VALUE_TYPE_LIST: {
      const auto count = fl_value_get_length(value);
      require(count <= 100000, CITIZENSDK_ERROR_INVALID_ARGUMENT,
              "Tuple list exceeds the public contract");
      Value::List list;
      list.reserve(count);
      for (std::size_t i = 0; i < count; ++i) {
        list.push_back(from_fl(fl_value_get_list_value(value, i), depth + 1,
                               remaining_nodes, remaining_bytes));
      }
      return Value::list(std::move(list));
    }
    default:
      fail(CITIZENSDK_ERROR_INVALID_ARGUMENT,
           "Maps, floating-point values and non-byte typed lists are forbidden");
  }
}

const Value::List &list(const Value &value, std::size_t length) {
  const auto *items = std::get_if<Value::List>(&value.data);
  require(items != nullptr && items->size() == length,
          CITIZENSDK_ERROR_INVALID_ARGUMENT, "Invalid fixed-position tuple length");
  return *items;
}
const Value::List &bounded_list(const Value &value, std::size_t maximum, std::size_t minimum = 1) {
  const auto *items = std::get_if<Value::List>(&value.data);
  require(items != nullptr && items->size() >= minimum && items->size() <= maximum,
          CITIZENSDK_ERROR_INVALID_ARGUMENT, "List count is outside the contract");
  return *items;
}
int64_t integer(const Value &value) {
  const auto *number = std::get_if<int64_t>(&value.data);
  require(number != nullptr && *number >= 0, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "Expected a nonnegative integer, not a boolean or float");
  return *number;
}
const std::string &string(const Value &value, std::size_t minimum,
                          std::size_t maximum_utf16) {
  const auto *text = std::get_if<std::string>(&value.data);
  UnicodeInfo info;
  require(text != nullptr && inspect_utf8(*text, &info) &&
              info.utf16 >= minimum && info.utf16 <= maximum_utf16,
          CITIZENSDK_ERROR_INVALID_ARGUMENT, "Invalid string length or UTF-8");
  return *text;
}
citizensdk_account_id_t account(const Value &value) {
  const std::string &text = string(value, 66, 66);
  require(text.size() == 66 && text.compare(0, 2, "0x") == 0,
          CITIZENSDK_ERROR_INVALID_ARGUMENT, "Expected canonical 32-byte hex");
  citizensdk_account_id_t result{};
  auto nibble = [](char c) -> uint8_t {
    if (c >= '0' && c <= '9') return static_cast<uint8_t>(c - '0');
    if (c >= 'a' && c <= 'f') return static_cast<uint8_t>(c - 'a' + 10);
    fail(CITIZENSDK_ERROR_INVALID_ARGUMENT, "Hex must use lowercase digits");
  };
  for (std::size_t i = 0; i < 32; ++i) {
    result.bytes[i] = static_cast<uint8_t>((nibble(text[2 + 2 * i]) << 4) |
                                          nibble(text[3 + 2 * i]));
  }
  return result;
}
citizensdk_transaction_execution_id_t execution_id(const std::string &text) {
  require(text.size() == 34 && text.rfind("0x", 0) == 0,
          CITIZENSDK_ERROR_INVALID_ARGUMENT, "Expected canonical 16-byte hex");
  auto nibble = [](char c) -> uint8_t {
    if (c >= '0' && c <= '9') return static_cast<uint8_t>(c - '0');
    if (c >= 'a' && c <= 'f') return static_cast<uint8_t>(c - 'a' + 10);
    fail(CITIZENSDK_ERROR_INVALID_ARGUMENT, "Hex must use lowercase digits");
  };
  citizensdk_transaction_execution_id_t result{};
  for (std::size_t i = 0; i < 16; ++i)
    result.bytes[i] = static_cast<uint8_t>((nibble(text[2 + 2 * i]) << 4) |
                                           nibble(text[3 + 2 * i]));
  return result;
}
uint64_t request_u64(const Value &value, const char *message) {
  const auto &text = string(value, 1, 20);
  require(text.size() == 1 || text.front() != '0',
          CITIZENSDK_ERROR_INVALID_ARGUMENT, message);
  uint64_t result = 0;
  const auto parsed = std::from_chars(text.data(), text.data() + text.size(), result);
  require(parsed.ec == std::errc{} && parsed.ptr == text.data() + text.size(),
          CITIZENSDK_ERROR_INVALID_ARGUMENT, message);
  return result;
}
citizensdk_block_ref_t request_block(const Value &value) {
  const auto &fields = list(value, 3);
  const auto hash = account(fields[0]);
  const auto number = request_u64(fields[1], "Block number must be canonical uint64 decimal");
  const auto &finality = string(fields[2], 4, 9);
  require(finality == "best" || finality == "finalized",
          CITIZENSDK_ERROR_INVALID_ARGUMENT, "Block finality is invalid");
  citizensdk_block_ref_t result{};
  result.struct_size = sizeof(result);
  result.abi_version = CITIZENSDK_ABI_VERSION;
  std::copy(std::begin(hash.bytes), std::end(hash.bytes), std::begin(result.hash));
  result.number = number;
  result.finality = finality == "best" ? CITIZENSDK_FINALITY_BEST
                                        : CITIZENSDK_FINALITY_FINALIZED;
  return result;
}
Value hex(const uint8_t *bytes) {
  constexpr char digits[] = "0123456789abcdef";
  std::string text(66, '0'); text[1] = 'x';
  for (std::size_t i = 0; i < 32; ++i) {
    text[2 + 2 * i] = digits[bytes[i] >> 4];
    text[3 + 2 * i] = digits[bytes[i] & 15];
  }
  return Value::string(std::move(text));
}
Value hex16(const uint8_t *bytes) {
  constexpr char digits[] = "0123456789abcdef";
  std::string text(34, '0'); text[1] = 'x';
  for (std::size_t i = 0; i < 16; ++i) {
    text[2 + 2 * i] = digits[bytes[i] >> 4];
    text[3 + 2 * i] = digits[bytes[i] & 15];
  }
  return Value::string(std::move(text));
}
Value tuple(std::initializer_list<Value> fields) {
  return Value::list(Value::List(fields));
}
template <typename T> T prepared() {
  T value{}; value.struct_size = sizeof(value); value.abi_version = CITIZENSDK_ABI_VERSION;
  return value;
}
template <typename T> void check_abi(const T &value) {
  require(value.struct_size >= sizeof(value) && value.abi_version == CITIZENSDK_ABI_VERSION,
          CITIZENSDK_ERROR_INTEGRITY, "Core returned an incompatible ABI value");
}
void check_code(citizensdk_error_code_t code) {
  if (code != CITIZENSDK_OK) fail(code, "CitizenSDK result copy failed");
}
std::size_t copy_size(uint64_t count) {
  require(count <= kMaximumBytes, CITIZENSDK_ERROR_INTEGRITY,
          "Core public result exceeds the bounded copy contract");
  return static_cast<std::size_t>(count);
}
std::string copied_text(const Value::Bytes &bytes) {
  const std::string text(bytes.begin(), bytes.end());
  require(valid_utf8(text), CITIZENSDK_ERROR_INTEGRITY,
          "Core public result contains malformed UTF-8");
  return text;
}
Value nullable_text(const Value::Bytes &bytes) {
  return bytes.empty() ? Value::null() : Value::string(copied_text(bytes));
}
bool flag(uint32_t value) {
  require(value <= 1, CITIZENSDK_ERROR_INTEGRITY, "Core boolean is not 0 or 1");
  return value == 1;
}

}  // namespace

ContractFailure::ContractFailure(citizensdk_error_code_t error_code,
                                 std::string message,
                                 std::optional<std::string> session_id,
                                 std::optional<int64_t> request_sequence,
                                 citizensdk_failure_stage_t failure_stage)
    : std::runtime_error(std::move(message)), code(error_code),
      session(std::move(session_id)), sequence(request_sequence),
      stage(failure_stage == 0 ? flutter_default_failure_stage(error_code) : failure_stage) {}

const char *method_name(Method method) noexcept {
  const auto index = static_cast<std::size_t>(method);
  return index < std::size(kMethods) ? kMethods[index] : "unsupported";
}
bool valid_utf8(const std::string &text) noexcept { return inspect_utf8(text, nullptr); }

FlStandardMethodCodec *new_method_codec() {
  auto *message_codec = FL_STANDARD_MESSAGE_CODEC(
      g_object_new(citizen_sdk_string_codec_get_type(), nullptr));
  auto *codec = fl_standard_method_codec_new_with_message_codec(message_codec);
  g_object_unref(message_codec);
  return codec;
}
Value from_fl_value(FlValue *value) {
  // 总节点/总字节共享递归预算，先扣减再复制；保留 16 MiB payload 的固定 tuple 余量。
  // The largest valid request has 1,995 nodes. A 4,096-node budget rejects
  // exponentially nested or irrelevant input before copying it. The byte
  // budget preserves a maximum 16 MiB signing payload plus its small fixed
  // tuple fields, while rejecting aggregate bulk values above that contract.
  std::size_t remaining_nodes = 4096;
  std::size_t remaining_bytes = kMaximumRequestCopiedBytes;
  return from_fl(value, 0, remaining_nodes, remaining_bytes);
}
FlValuePtr to_fl_value(const Value &value) {
  if (std::holds_alternative<std::monostate>(value.data)) return FlValuePtr(fl_value_new_null());
  if (const auto *v = std::get_if<bool>(&value.data)) return FlValuePtr(fl_value_new_bool(*v));
  if (const auto *v = std::get_if<int64_t>(&value.data)) return FlValuePtr(fl_value_new_int(*v));
  if (const auto *v = std::get_if<std::string>(&value.data)) return FlValuePtr(owned_fl_string(*v));
  if (const auto *v = std::get_if<Value::Bytes>(&value.data)) {
    return FlValuePtr(fl_value_new_uint8_list(v->data(), v->size()));
  }
  FlValuePtr result(fl_value_new_list());
  for (const auto &item : std::get<Value::List>(value.data)) {
    auto child = to_fl_value(item);
    fl_value_append_take(result.get(), child.release());
  }
  return result;
}

citizensdk_u128_t parse_u128(const std::string &text) {
  require(!text.empty() && text.size() <= 39 &&
              (text.size() == 1 || text.front() != '0'),
          CITIZENSDK_ERROR_INVALID_ARGUMENT, "Expected canonical u128 decimal");
  // Four base-2^32 limbs avoid nonstandard compiler integer extensions.
  std::array<uint32_t, 4> limbs{};
  for (char digit : text) {
    require(digit >= '0' && digit <= '9', CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "Expected canonical u128 decimal");
    uint64_t carry = static_cast<uint64_t>(digit - '0');
    for (auto &limb : limbs) {
      const uint64_t product = static_cast<uint64_t>(limb) * 10 + carry;
      limb = static_cast<uint32_t>(product); carry = product >> 32;
    }
    require(carry == 0, CITIZENSDK_ERROR_INVALID_ARGUMENT, "u128 decimal overflow");
  }
  return {static_cast<uint64_t>(limbs[0]) | (static_cast<uint64_t>(limbs[1]) << 32),
          static_cast<uint64_t>(limbs[2]) | (static_cast<uint64_t>(limbs[3]) << 32)};
}
std::string decimal_u128(citizensdk_u128_t value) {
  std::array<uint32_t, 4> limbs{static_cast<uint32_t>(value.low),
      static_cast<uint32_t>(value.low >> 32), static_cast<uint32_t>(value.high),
      static_cast<uint32_t>(value.high >> 32)};
  std::string result;
  do {
    uint64_t remainder = 0;
    for (std::size_t i = limbs.size(); i-- > 0;) {
      const uint64_t current = (remainder << 32) | limbs[i];
      limbs[i] = static_cast<uint32_t>(current / 10); remainder = current % 10;
    }
    result.push_back(static_cast<char>('0' + remainder));
  } while (std::any_of(limbs.begin(), limbs.end(), [](uint32_t x) { return x != 0; }));
  std::reverse(result.begin(), result.end());
  return result;
}

DecodedRequest decode_request(const std::string &name, FlValue *arguments) {
  const auto found = std::find(std::begin(kMethods), std::end(kMethods), name);
  require(found != std::end(kMethods), CITIZENSDK_ERROR_UNSUPPORTED, "Unsupported method");
  DecodedRequest result;
  result.method = static_cast<Method>(found - std::begin(kMethods));
  // Root length is checked before recursively copying fields. The protocol
  // never accepts Map; expected nested fields also have closed list types.
  require(arguments != nullptr && fl_value_get_type(arguments) == FL_VALUE_TYPE_LIST,
          CITIZENSDK_ERROR_INVALID_ARGUMENT, "Arguments must be a tuple");
  const auto count = fl_value_get_length(arguments);
  require(count >= 1 && count <= 10, CITIZENSDK_ERROR_INVALID_ARGUMENT,
          "Invalid request tuple length");
  const Value root = from_fl_value(arguments);
  const auto &fields = std::get<Value::List>(root.data);
  require(integer(fields[0]) == kProtocolVersion, CITIZENSDK_ERROR_UNSUPPORTED,
          "Unsupported protocol version");
  if (result.method == Method::open) {
    (void)list(root, 2);
    const auto modules = integer(fields[1]);
    require(modules > 0 && modules <= UINT32_MAX, CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "modules must be a nonzero uint32");
    result.modules = static_cast<uint32_t>(modules);
    return result;
  }
  // 纯验签在解析 session 前单独解码，只接受 [版本, 账户, 签名, 消息]。
  if (result.method == Method::verify_signature) {
    (void)list(root, 4); result.account_id = account(fields[1]);
    const auto *signature = std::get_if<Value::Bytes>(&fields[2].data);
    const auto *payload = std::get_if<Value::Bytes>(&fields[3].data);
    require(signature != nullptr && signature->size() == 64 &&
                payload != nullptr && payload->size() <= kMaximumBytes,
            CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "Verification requires 64 signature bytes and at most 16 MiB");
    result.signature = *signature; result.payload = *payload;
    return result;
  }
  require(count >= 3, CITIZENSDK_ERROR_INVALID_ARGUMENT, "Truncated session request");
  result.session = string(fields[1], 1, 128);
  result.sequence = integer(fields[2]);
  try {
    require(result.sequence > 0, CITIZENSDK_ERROR_INVALID_ARGUMENT,
            "requestSequence must be positive");
    switch (result.method) {
      case Method::start: case Method::stop: case Method::close:
      case Method::get_capabilities: case Method::get_finalized_head:
      case Method::get_sync_status: case Method::get_best_head:
      case Method::export_state: case Method::get_genesis_hash:
      case Method::get_fee_snapshot: case Method::get_wallet_profile:
      case Method::get_wallet_state:
      case Method::import_wallet: case Method::delete_wallet:
      case Method::reconcile_wallet_cleanup:
        (void)list(root, 3); break;
      case Method::get_finalized_block_at: {
        (void)list(root, 4);
        result.block_number = request_u64(
            fields[3], "Finalized block number must be canonical uint64 decimal");
        break;
      }
      case Method::resolve_finalized_block: {
        (void)list(root, 5);
        const auto hash = account(fields[3]);
        result.block = {};
        result.block.struct_size = sizeof(result.block);
        result.block.abi_version = CITIZENSDK_ABI_VERSION;
        std::copy(std::begin(hash.bytes), std::end(hash.bytes), std::begin(result.block.hash));
        result.block_number = request_u64(
            fields[4], "Resolved block number must be canonical uint64 decimal");
        break;
      }
      case Method::get_block_header: case Method::get_block_body:
      case Method::get_runtime_context: case Method::get_system_events:
        (void)list(root, 4); result.block = request_block(fields[3]);
        require(result.method != Method::get_system_events ||
                    result.block.finality == CITIZENSDK_FINALITY_FINALIZED,
                CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "System.Events requires a finalized block");
        break;
      case Method::get_storage: {
        (void)list(root, 5); result.block = request_block(fields[3]);
        const auto *key = std::get_if<Value::Bytes>(&fields[4].data);
        require(key != nullptr && !key->empty() && key->size() <= kMaximumStorageKeyBytes,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "Storage key must contain 1..4096 bytes");
        result.payload = *key; break;
      }
      case Method::get_storage_batch: {
        (void)list(root, 5); result.block = request_block(fields[3]);
        std::size_t total = 0;
        for (const auto &item : bounded_list(fields[4], kMaximumStorageBatchKeys)) {
          const auto *key = std::get_if<Value::Bytes>(&item.data);
          require(key != nullptr && !key->empty() && key->size() <= kMaximumStorageKeyBytes &&
                      key->size() <= kMaximumStorageBatchKeyBytes - total,
                  CITIZENSDK_ERROR_INVALID_ARGUMENT, "Storage batch keys are invalid");
          total += key->size(); result.storage_keys.push_back(*key);
        }
        break;
      }
      case Method::import_state: {
        (void)list(root, 6);
        const auto version = integer(fields[3]);
        require(version >= 1 && static_cast<uint64_t>(version) <= UINT32_MAX,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "State format version must be nonzero uint32");
        result.state_format_version = static_cast<uint32_t>(version);
        result.block = request_block(fields[4]);
        const auto *database = std::get_if<Value::Bytes>(&fields[5].data);
        require(result.block.finality == CITIZENSDK_FINALITY_FINALIZED &&
                    database != nullptr && !database->empty() &&
                    database->size() <= kMaximumExportedStateBytes,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "Imported state is invalid");
        result.state_database = *database; break;
      }
      case Method::get_account_balance: case Method::get_account_nonce:
      case Method::view_account_private_key:
      case Method::set_active_wallet_account: case Method::delete_wallet_account:
      case Method::delete_account:
        (void)list(root, 4); result.account_id = account(fields[3]); break;
      case Method::get_account_balances: {
        (void)list(root, 4);
        // 只验证边界，不去重、不提前返回空列表；Core 统一决定生命周期与查询。
        for (const auto &item : bounded_list(fields[3], 1990, 0))
          result.account_ids.push_back(account(item));
        break;
      }
      case Method::create_wallet: {
        (void)list(root, 4); const auto words = integer(fields[3]);
        require(words == 12 || words == 18 || words == 24,
                CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "wordCount must be 12, 18, or 24");
        result.word_count = static_cast<uint32_t>(words); break;
      }
      case Method::add_wallet_accounts: {
        (void)list(root, 4); std::set<uint32_t> unique;
        for (const auto &item : bounded_list(fields[3], 1989)) {
          const auto index = integer(item);
          require(index >= 1 && index <= 1989 &&
                      unique.insert(static_cast<uint32_t>(index)).second,
                  CITIZENSDK_ERROR_INVALID_ARGUMENT, "indices must be unique values in 1...1989");
          result.indices.push_back(static_cast<uint32_t>(index));
        }
        break;
      }
      case Method::rename_wallet_account: case Method::rename_account:
      case Method::import_cold_account_id: {
        (void)list(root, 5); result.account_id = account(fields[3]);
        result.name = string(fields[4], 1, 128); UnicodeInfo unicode;
        (void)inspect_utf8(result.name, &unicode);
        require(unicode.scalars <= 30 && !unicode.controls &&
                    !trim_space(unicode.first) && !trim_space(unicode.last),
                CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "name must be trimmed 1...30 Unicode scalars without controls");
        break;
      }
      case Method::import_cold_account_ss58: {
        (void)list(root, 5);
        result.qr_text = string(fields[3], 1, 64);
        result.name = string(fields[4], 1, 128); UnicodeInfo unicode;
        require(inspect_utf8(result.name, &unicode) && unicode.scalars <= 30 &&
                    !unicode.controls && !trim_space(unicode.first) && !trim_space(unicode.last),
                CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "name must be trimmed 1...30 Unicode scalars without controls");
        break;
      }
      case Method::reorder_wallet_accounts_without_default_change: {
        (void)list(root, 5);
        const auto &revision = string(fields[3], 1, 20);
        require(revision.size() == 1 || revision.front() != '0',
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "expectedRevision is not canonical");
        const auto parsed = std::from_chars(revision.data(), revision.data() + revision.size(),
                                            result.wallet_revision);
        require(parsed.ec == std::errc{} && parsed.ptr == revision.data() + revision.size(),
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "expectedRevision is outside uint64");
        for (const auto &item : bounded_list(fields[4], 3980))
          result.account_ids.push_back(account(item));
        break;
      }
      case Method::sign_wallet_payload: {
        (void)list(root, 5); result.account_id = account(fields[3]);
        const auto *bytes = std::get_if<Value::Bytes>(&fields[4].data);
        require(bytes != nullptr && bytes->size() <= kMaximumBytes,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "Signing payload must be bytes of at most 16 MiB");
        result.payload = *bytes; break;
      }
      case Method::begin_signing: {
        (void)list(root, 10); result.account_id = account(fields[3]);
        const auto *payload = std::get_if<Value::Bytes>(&fields[4].data);
        const auto &transform = string(fields[5], 3, 32);
        const auto *domain = std::get_if<Value::Bytes>(&fields[6].data);
        const auto &transport = string(fields[7], 4, 8);
        const auto action = integer(fields[8]), ttl = integer(fields[9]);
        require(payload != nullptr && !payload->empty() && payload->size() <= kMaximumBytes &&
                    domain != nullptr && domain->size() <= 32 && action <= UINT16_MAX &&
                    ttl >= 1 && ttl <= 300,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "Invalid generic signing fields");
        if (transform == "raw") result.signing_transform = CITIZENSDK_SIGNING_TRANSFORM_RAW;
        else if (transform == "substrateSigningPayload")
          result.signing_transform = CITIZENSDK_SIGNING_TRANSFORM_SUBSTRATE_PAYLOAD;
        else if (transform == "blake2Domain")
          result.signing_transform = CITIZENSDK_SIGNING_TRANSFORM_BLAKE2_DOMAIN;
        else fail(CITIZENSDK_ERROR_INVALID_ARGUMENT, "Unknown signing transform");
        require((result.signing_transform == CITIZENSDK_SIGNING_TRANSFORM_BLAKE2_DOMAIN &&
                 !domain->empty()) ||
                    (result.signing_transform != CITIZENSDK_SIGNING_TRANSFORM_BLAKE2_DOMAIN &&
                     domain->empty()),
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "Invalid signing transform/domain");
        if (transport == "none") result.external_signer_transport = CITIZENSDK_EXTERNAL_SIGNER_NONE;
        else if (transport == "qrV1") result.external_signer_transport = CITIZENSDK_EXTERNAL_SIGNER_QR_V1;
        else fail(CITIZENSDK_ERROR_INVALID_ARGUMENT, "Unknown external signer transport");
        result.payload = *payload; result.signing_domain = *domain;
        result.signing_action = static_cast<uint16_t>(action);
        result.signing_ttl = static_cast<uint64_t>(ttl); break;
      }
      case Method::consume_external_signature:
      case Method::consume_default_account_change: {
        (void)list(root, 5);
        result.signing_session_id = string(fields[3], 1, 128);
        result.signing_response = string(fields[4], 1, 2331);
        require(result.signing_response.size() <= 2331,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "External signing response is too large");
        break;
      }
      case Method::cancel_signing: {
        (void)list(root, 4);
        result.signing_session_id = string(fields[3], 1, 128); break;
      }
      case Method::begin_default_account_change: {
        (void)list(root, 6);
        const auto &revision = string(fields[3], 1, 20);
        require(revision.size() == 1 || revision.front() != '0',
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "expectedRevision is not canonical");
        const auto parsed = std::from_chars(revision.data(), revision.data() + revision.size(),
                                            result.wallet_revision);
        require(parsed.ec == std::errc{} && parsed.ptr == revision.data() + revision.size(),
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "expectedRevision is outside uint64");
        for (const auto &item : bounded_list(fields[4], 256))
          result.account_ids.push_back(account(item));
        const auto ttl = integer(fields[5]);
        require(ttl >= 1 && ttl <= 300, CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "Default-account TTL is invalid");
        result.signing_ttl = static_cast<uint64_t>(ttl); break;
      }
      case Method::prepare_transaction: {
        (void)list(root, 5); result.account_id = account(fields[3]);
        const auto *call_data = std::get_if<Value::Bytes>(&fields[4].data);
        require(call_data != nullptr && !call_data->empty() &&
                    call_data->size() <= kMaximumTransactionCallDataBytes,
                CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "callData must contain 1..1 MiB bytes");
        result.payload = *call_data; break;
      }
      case Method::cancel_prepared_transaction: {
        (void)list(root, 4);
        result.preparation_id = string(fields[3], 34, 34);
        require(result.preparation_id.rfind("0x", 0) == 0 &&
                    std::all_of(result.preparation_id.begin() + 2,
                                result.preparation_id.end(), [](char value) {
                      return (value >= '0' && value <= '9') ||
                             (value >= 'a' && value <= 'f');
                    }),
                CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "preparationId must be 16-byte lowercase hex");
        break;
      }
      case Method::execute_prepared_transaction: {
        (void)list(root, 4);
        result.preparation_id = string(fields[3], 34, 34);
        require(result.preparation_id.rfind("0x", 0) == 0 &&
                    std::all_of(result.preparation_id.begin() + 2,
                                result.preparation_id.end(), [](char value) {
                      return (value >= '0' && value <= '9') ||
                             (value >= 'a' && value <= 'f');
                    }),
                CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "preparationId must be 16-byte lowercase hex");
        break;
      }
      case Method::cancel_prepared_transaction_execution: {
        (void)list(root, 4);
        result.execution_id = execution_id(string(fields[3], 34, 34));
        break;
      }
      case Method::consume_prepared_transaction_qr_response: {
        (void)list(root, 5);
        result.preparation_id = string(fields[3], 34, 34);
        result.execution_id = execution_id(result.preparation_id);
        result.signing_response = string(fields[4], 1, 2331);
        break;
      }
      case Method::get_transaction_history: {
        (void)list(root, 5);
        if (!null_value(fields[3]))
          result.before_execution_id = execution_id(string(fields[3], 34, 34));
        const auto limit = integer(fields[4]);
        require(limit >= 1 && limit <= 100, CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "History limit must be in 1..100");
        result.history_limit = static_cast<uint32_t>(limit);
        break;
      }
      case Method::sync_transaction_history:
        (void)list(root, 3); break;
      case Method::qr_scan: (void)list(root, 3); break;
      case Method::qr_parse: case Method::sign_qr_request:
      case Method::qr_consume_sign_response: {
        (void)list(root, 4); result.qr_text = string(fields[3], 1, 2331);
        require(result.qr_text.size() <= 2331, CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "QR text exceeds 2331 UTF-8 bytes"); break;
      }
      case Method::qr_create_sign_request: {
        (void)list(root, 7); const auto action = integer(fields[3]);
        const auto ttl = integer(fields[6]);
        const auto *payload = std::get_if<Value::Bytes>(&fields[5].data);
        require(action >= 1 && action <= UINT16_MAX && ttl >= 1 && ttl <= 300 &&
                    payload != nullptr && !payload->empty() && payload->size() <= 1920,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "Invalid QR signing request fields");
        result.qr_action = static_cast<uint16_t>(action); result.account_id = account(fields[4]);
        result.payload = *payload; result.qr_ttl = static_cast<uint64_t>(ttl); break;
      }
      case Method::qr_cancel_sign_request: {
        (void)list(root, 4); result.qr_request_id = string(fields[3], 16, 128); break;
      }
      case Method::qr_encode_account_id: {
        (void)list(root, 4); result.account_id = account(fields[3]); break;
      }
      case Method::qr_decode_luminance: {
        (void)list(root, 7); const auto *pixels = std::get_if<Value::Bytes>(&fields[3].data);
        const auto width = integer(fields[4]), height = integer(fields[5]), stride = integer(fields[6]);
        require(pixels != nullptr && !pixels->empty() && pixels->size() <= 16U * 1024U * 1024U &&
                    width >= 1 && width <= 4096 && height >= 1 && height <= 4096 &&
                    stride >= width && stride <= 4096 &&
                    pixels->size() >= static_cast<size_t>((height - 1) * stride + width),
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "Invalid QR luminance frame");
        result.payload = *pixels; result.qr_width = static_cast<uint32_t>(width);
        result.qr_height = static_cast<uint32_t>(height); result.qr_stride = static_cast<uint32_t>(stride); break;
      }
      case Method::qr_encode: {
        (void)list(root, 5); result.qr_text = string(fields[3], 1, 2331);
        const auto scale = integer(fields[4]);
        require(result.qr_text.size() <= 2331 && scale >= 1 && scale <= 16,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "Invalid QR image fields");
        result.qr_scale = static_cast<uint32_t>(scale); break;
      }
      case Method::open: case Method::verify_signature:
        fail(CITIZENSDK_ERROR_INVALID_STATE, "Stateless method cannot be a session request");
    }
  } catch (const ContractFailure &error) {
    throw ContractFailure(error.code, error.what(), result.session,
                          result.sequence > 0 ? std::optional<int64_t>(result.sequence) : std::nullopt,
                          error.stage);
  }
  return result;
}
bool decode_subscription(FlValue *arguments) {
  const auto root = from_fl_value(arguments);
  require(integer(list(root, 1)[0]) == kProtocolVersion,
          CITIZENSDK_ERROR_INVALID_ARGUMENT, "Invalid event subscription tuple");
  return true;
}

const char *error_name(citizensdk_error_code_t code) noexcept {
  constexpr const char *names[] = {"ok", "invalidArgument", "invalidHandle", "invalidState",
      "unsupported", "unavailable", "notReady", "notFound", "conflict", "integrity",
      "authenticationCancelled", "authenticationRequired", "keyInvalidated", "permissionDenied",
      "storage", "network", "decode", "timeout", "busy", "queueFull", "internal", "panic", "cancelled"};
  return code >= 0 && static_cast<std::size_t>(code) < std::size(names)
             ? names[static_cast<std::size_t>(code)] : "integrity";
}
Value response(const std::string &session, int64_t sequence, Value value) {
  UnicodeInfo info;
  require(inspect_utf8(session, &info) && info.utf16 >= 1 && info.utf16 <= 128 && sequence >= 0 &&
              std::holds_alternative<Value::List>(value.data),
          CITIZENSDK_ERROR_INTEGRITY, "Invalid response envelope");
  return tuple({Value::integer(kProtocolVersion), Value::string(session),
                Value::integer(sequence), std::move(value)});
}
Value event(const std::string &session, int64_t sequence,
            const std::string &type, Value payload) {
  if (type == "historyChanged") (void)list(payload, 0);
  require(sequence > 0 && (type == "historyChanged" || type == "lifecycleChanged" ||
                          type == "capabilitiesChanged"),
          CITIZENSDK_ERROR_INTEGRITY, "Invalid event envelope");
  (void)response(session, sequence, payload);
  return tuple({Value::integer(kProtocolVersion), Value::string(session), Value::integer(sequence),
                Value::string(type), std::move(payload)});
}
Value error_details(citizensdk_error_code_t code, const std::string &message,
                    std::optional<std::string> session, std::optional<int64_t> sequence,
                    const std::string &method, citizensdk_failure_stage_t stage) {
  if (stage == 0) stage = flutter_default_failure_stage(code);
  bool known_method = false;
  for (std::size_t index = 0; index <= static_cast<std::size_t>(Method::sign_qr_request); ++index)
    known_method = known_method || method == method_name(static_cast<Method>(index));
  require(code >= 1 && code <= 22 && stage >= 1 && stage <= 8 && known_method &&
              (!sequence || *sequence > 0) && valid_utf8(message),
          CITIZENSDK_ERROR_INTEGRITY, "Invalid error envelope");
  if (session) (void)response(*session, 0, Value::list({}));
  return tuple({Value::integer(kProtocolVersion), session ? Value::string(*session) : Value::null(),
                sequence ? Value::integer(*sequence) : Value::null(), Value::integer(code),
                Value::integer(stage), Value::string(method), Value::string(message)});
}

Value lifecycle(citizensdk_lifecycle_t value) {
  constexpr const char *names[] = {"created", "importingState", "starting", "running",
                                  "startFailed", "stopped", "disposed"};
  require(value >= 1 && value <= std::size(names), CITIZENSDK_ERROR_INTEGRITY,
          "Unknown Core lifecycle");
  return Value::string(names[value - 1]);
}
Value block(const citizensdk_block_ref_t &value) {
  check_abi(value);
  require(value.finality == CITIZENSDK_FINALITY_BEST || value.finality == CITIZENSDK_FINALITY_FINALIZED,
          CITIZENSDK_ERROR_INTEGRITY, "Unknown block finality");
  return tuple({hex(value.hash), Value::string(std::to_string(value.number)),
                Value::string(value.finality == CITIZENSDK_FINALITY_BEST ? "best" : "finalized")});
}
Value capabilities(const citizensdk_capability_snapshot_t &value) {
  check_abi(value);
  require(value.count == CITIZENSDK_CAPABILITY_COUNT, CITIZENSDK_ERROR_INTEGRITY,
          "Capability snapshot count is invalid");
  constexpr const char *names[] = {"chainRead", "transactionBuild", "transactionSubmit", "transactionVerify",
      "walletProfile", "localSigning", "hardwareVault", "userAuthentication", "history", "backgroundSync"};
  constexpr const char *reasons[] = {"none", "buildUnsupported", "deviceUnavailable", "hostDisabled",
      "engineNotRunning", "dependencyNotReady", "userAuthenticationRequired", "vaultLocked",
      "chainStarting", "chainUnsynced", "storageUnavailable"};
  std::set<uint32_t> unique; Value::List statuses;
  for (uint32_t i = 0; i < value.count; ++i) {
    const auto &status = value.statuses[i];
    require(status.name >= 1 && status.name <= std::size(names) &&
                status.reason < std::size(reasons) && unique.insert(status.name).second,
            CITIZENSDK_ERROR_INTEGRITY, "Unknown or duplicated capability");
    const bool supported = flag(status.supported), available = flag(status.available),
               enabled = flag(status.enabled), ready = flag(status.ready);
    require((ready && supported && available && enabled &&
             status.reason == CITIZENSDK_CAPABILITY_REASON_NONE) ||
                (!ready && status.reason != CITIZENSDK_CAPABILITY_REASON_NONE),
            CITIZENSDK_ERROR_INTEGRITY,
            "Capability readiness and reason disagree");
    statuses.push_back(tuple({Value::string(names[status.name - 1]), Value::boolean(supported),
        Value::boolean(available), Value::boolean(enabled), Value::boolean(ready),
        Value::string(reasons[status.reason])}));
  }
  return tuple({Value::string(std::to_string(value.revision)), Value::list(std::move(statuses))});
}

}  // namespace citizen_sdk::flutter

namespace citizen_sdk::flutter {
namespace {

citizensdk_result_info_t inspect_result(citizensdk_result_handle_t result,
                                        citizensdk_result_kind_t kind) {
  auto info = prepared<citizensdk_result_info_t>();
  check_code(citizensdk_result_get_info(result, &info));
  check_abi(info);
  if (info.error_code != CITIZENSDK_OK) {
    require(info.error_code >= CITIZENSDK_ERROR_INVALID_ARGUMENT &&
                info.error_code <= CITIZENSDK_ERROR_CANCELLED,
            CITIZENSDK_ERROR_INTEGRITY, "Core returned an unknown error code");
    uint64_t required = 0;
    check_code(citizensdk_result_copy_error_message(result, nullptr, 0, &required));
    Value::Bytes bytes(copy_size(required));
    uint64_t confirmed = required;
    check_code(citizensdk_result_copy_error_message(
        result, bytes.empty() ? nullptr : bytes.data(), required, &confirmed));
    require(confirmed == required, CITIZENSDK_ERROR_INTEGRITY,
            "Core error text length changed during copy");
    const std::string message = copied_text(bytes);
    citizensdk_failure_stage_t stage = 0;
    check_code(citizensdk_result_get_failure_stage(result, &stage));
    require(stage >= 1 && stage <= 8, CITIZENSDK_ERROR_INTEGRITY,
            "Core returned an unknown failure stage");
    throw ContractFailure(info.error_code,
                          message.empty() ? "CitizenSDK operation failed" : message,
                          {}, {}, stage);
  }
  require(info.kind == kind, CITIZENSDK_ERROR_INTEGRITY,
          "Core returned an unexpected result kind");
  return info;
}

Value execution(const citizensdk_execution_info_t &value) {
  check_abi(value);
  require((value.status == CITIZENSDK_EXECUTION_SUCCESS ||
           value.status == CITIZENSDK_EXECUTION_FAILED) &&
              flag(value.has_block) && flag(value.has_extrinsic_index) &&
              value.block.finality == CITIZENSDK_FINALITY_FINALIZED,
          CITIZENSDK_ERROR_INTEGRITY,
          "Flutter requires a verified finalized execution");
  const bool module = flag(value.has_module);
  if (value.status == CITIZENSDK_EXECUTION_SUCCESS) {
    require(value.reason_or_dispatch_variant == 0 && !module,
            CITIZENSDK_ERROR_INTEGRITY,
            "Successful execution contains dispatch failure fields");
  } else {
    require((value.reason_or_dispatch_variant == CITIZENSDK_DISPATCH_ERROR_MODULE) == module,
            CITIZENSDK_ERROR_INTEGRITY,
            "Failed execution module fields disagree with its variant");
  }
  return tuple({Value::string(value.status == CITIZENSDK_EXECUTION_SUCCESS ? "success" : "failed"),
                block(value.block), Value::integer(value.extrinsic_index),
                value.status == CITIZENSDK_EXECUTION_FAILED
                    ? Value::integer(value.reason_or_dispatch_variant) : Value::null(),
                module ? Value::integer(value.pallet_index) : Value::null(),
                module ? Value::integer(value.error_index) : Value::null()});
}

Value profile(citizensdk_result_handle_t result) {
  auto info = prepared<citizensdk_wallet_profile_info_t>();
  check_code(citizensdk_result_get_wallet_profile(result, &info)); check_abi(info);
  require(info.present <= 1, CITIZENSDK_ERROR_INTEGRITY,
          "Core wallet profile presence is invalid");
  if (info.present == 0) return Value::null();
  require(info.account_count <= 1990 && info.wallet_index == 0 &&
              (info.origin == CITIZENSDK_WALLET_ORIGIN_CREATED ||
               info.origin == CITIZENSDK_WALLET_ORIGIN_IMPORTED),
          CITIZENSDK_ERROR_INTEGRITY, "Core wallet profile descriptor is invalid");
  uint32_t count = 0;
  check_code(citizensdk_result_get_wallet_account_count(result, &count));
  require(count == info.account_count && count <= 1990,
          CITIZENSDK_ERROR_INTEGRITY, "Core wallet account count drifted");
  Value::List accounts; accounts.reserve(count);
  for (uint32_t index = 0; index < count; ++index) {
    auto account_info = prepared<citizensdk_wallet_account_info_t>();
    uint64_t ss58_required = 0, name_required = 0;
    check_code(citizensdk_result_get_wallet_account(
        result, index, &account_info, nullptr, 0, &ss58_required,
        nullptr, 0, &name_required));
    check_abi(account_info);
    Value::Bytes ss58(copy_size(ss58_required)), name(copy_size(name_required));
    uint64_t ss58_confirmed = ss58_required, name_confirmed = name_required;
    check_code(citizensdk_result_get_wallet_account(
        result, index, &account_info, ss58.empty() ? nullptr : ss58.data(),
        ss58_required, &ss58_confirmed, name.empty() ? nullptr : name.data(),
        name_required, &name_confirmed));
    require(ss58_confirmed == ss58_required && name_confirmed == name_required &&
                account_info.index <= 1989,
            CITIZENSDK_ERROR_INTEGRITY, "Core wallet account changed during copy");
    const bool active = flag(account_info.is_active);
    accounts.push_back(tuple({Value::integer(account_info.index), hex(account_info.account_id.bytes),
        Value::string(copied_text(ss58)),
        Value::string(name.empty() ? "" : copied_text(name)),
        Value::string(std::to_string(account_info.created_at_millis)), Value::boolean(active)}));
  }
  return tuple({Value::integer(info.wallet_index),
      Value::string(info.origin == CITIZENSDK_WALLET_ORIGIN_CREATED ? "created" : "imported"),
      Value::string(std::to_string(info.created_at_millis)), hex(info.master_account_id.bytes),
      hex(info.active_account_id.bytes), Value::list(std::move(accounts))});
}

Value wallet_state(citizensdk_result_handle_t result) {
  auto state = prepared<citizensdk_wallet_state_info_t>();
  auto profile_info = prepared<citizensdk_wallet_profile_info_t>();
  check_code(citizensdk_result_get_wallet_state(result, &state)); check_abi(state);
  check_code(citizensdk_result_get_wallet_profile(result, &profile_info)); check_abi(profile_info);
  require(state.account_count <= 3980 && profile_info.account_count <= 1990 &&
              state.has_default_account <= 1 &&
              ((state.account_count == 0) == (state.has_default_account == 0)),
          CITIZENSDK_ERROR_INTEGRITY, "Core wallet state descriptor is invalid");
  Value::List accounts; accounts.reserve(state.account_count);
  Value::List hot_accounts; hot_accounts.reserve(profile_info.account_count);
  for (uint32_t index = 0; index < state.account_count; ++index) {
    auto info = prepared<citizensdk_wallet_state_account_info_t>();
    uint64_t ss58_required = 0, name_required = 0;
    check_code(citizensdk_result_get_wallet_state_account(
        result, index, &info, nullptr, 0, &ss58_required, nullptr, 0, &name_required));
    check_abi(info);
    Value::Bytes ss58(copy_size(ss58_required)), name(copy_size(name_required));
    uint64_t ss58_confirmed = ss58_required, name_confirmed = name_required;
    check_code(citizensdk_result_get_wallet_state_account(
        result, index, &info, ss58.empty() ? nullptr : ss58.data(), ss58_required,
        &ss58_confirmed, name.empty() ? nullptr : name.data(), name_required, &name_confirmed));
    require(ss58_confirmed == ss58_required && name_confirmed == name_required &&
                info.has_account_index <= 1 && info.is_default == (index == 0 ? 1U : 0U),
            CITIZENSDK_ERROR_INTEGRITY, "Core wallet state account changed during copy");
    require(index != 0 || state.has_default_account == 0 ||
                std::equal(std::begin(info.account_id.bytes), std::end(info.account_id.bytes),
                           std::begin(state.default_account_id.bytes)),
            CITIZENSDK_ERROR_INTEGRITY, "Core wallet state default account drifted");
    const auto ss58_text = copied_text(ss58), name_text = copied_text(name);
    const bool hot = info.sign_mode == CITIZENSDK_WALLET_SIGN_HOT;
    require((hot && info.wallet_index == 0 && info.has_account_index == 1) ||
                (info.sign_mode == CITIZENSDK_WALLET_SIGN_COLD && info.wallet_index > 0 &&
                 info.has_account_index == 0),
            CITIZENSDK_ERROR_INTEGRITY, "Core wallet state signing mode is invalid");
    if (hot) {
      bool active = false;
      if (profile_info.present != 0)
        active = std::equal(std::begin(info.account_id.bytes), std::end(info.account_id.bytes),
                            std::begin(profile_info.active_account_id.bytes));
      hot_accounts.push_back(tuple({Value::integer(info.account_index), hex(info.account_id.bytes),
          Value::string(ss58_text), Value::string(name_text),
          Value::string(std::to_string(info.created_at_millis)), Value::boolean(active)}));
    }
    accounts.push_back(tuple({Value::string(hot ? "hot" : "cold"),
        Value::integer(info.wallet_index),
        hot ? Value::integer(info.account_index) : Value::null(), hex(info.account_id.bytes),
        Value::string(ss58_text), Value::string(name_text),
        Value::string(std::to_string(info.created_at_millis)), Value::boolean(index == 0)}));
  }
  Value profile_value = Value::null();
  if (profile_info.present != 0) {
    require(profile_info.present == 1 && profile_info.wallet_index == 0 &&
                (profile_info.origin == CITIZENSDK_WALLET_ORIGIN_CREATED ||
                 profile_info.origin == CITIZENSDK_WALLET_ORIGIN_IMPORTED) &&
                hot_accounts.size() == profile_info.account_count,
            CITIZENSDK_ERROR_INTEGRITY, "Core wallet state hot profile is invalid");
    profile_value = tuple({Value::integer(profile_info.wallet_index),
        Value::string(profile_info.origin == CITIZENSDK_WALLET_ORIGIN_CREATED ? "created" : "imported"),
        Value::string(std::to_string(profile_info.created_at_millis)), hex(profile_info.master_account_id.bytes),
        hex(profile_info.active_account_id.bytes), Value::list(std::move(hot_accounts))});
  }
  return tuple({Value::string(std::to_string(state.revision)), std::move(profile_value),
                Value::list(std::move(accounts))});
}

Value balance(const citizensdk_account_balance_info_t &value) {
  check_abi(value);
  return tuple({hex(value.account_id.bytes), block(value.block),
                Value::string(decimal_u128(value.free_fen)),
                Value::string(decimal_u128(value.reserved_fen)),
                Value::string(decimal_u128(value.total_fen))});
}
Value copy_balance(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_account_balance_info_t>();
  check_code(citizensdk_result_get_account_balance(result, &value));
  return balance(value);
}
Value copy_nonce(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_account_nonce_info_t>();
  check_code(citizensdk_result_get_account_nonce(result, &value)); check_abi(value);
  return tuple({hex(value.account_id.bytes), block(value.best_block),
                Value::string(std::to_string(value.nonce))});
}
Value copy_fee(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_fee_snapshot_info_t>();
  check_code(citizensdk_result_get_fee_snapshot(result, &value)); check_abi(value);
  return tuple({block(value.best_block), Value::integer(value.fee_rate_parts),
                Value::string(decimal_u128(value.minimum_fee_fen)),
                Value::string(decimal_u128(value.existential_deposit_fen))});
}

std::size_t bounded_copy_size(uint64_t count, std::size_t maximum,
                              const char *message) {
  require(count <= maximum, CITIZENSDK_ERROR_INTEGRITY, message);
  return static_cast<std::size_t>(count);
}

Value copy_sync_status(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_chain_sync_status_info_t>();
  check_code(citizensdk_result_get_sync_status(result, &value)); check_abi(value);
  return tuple({Value::string(std::to_string(value.peer_count)),
                Value::boolean(flag(value.is_syncing)),
                Value::boolean(flag(value.is_usable)), block(value.best),
                block(value.finalized)});
}

Value copy_header(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_block_header_info_t>();
  uint64_t required = 0;
  check_code(citizensdk_result_get_block_header(result, &value, nullptr, 0, &required));
  check_abi(value);
  Value::Bytes digest(bounded_copy_size(required, kMaximumHeaderDigestBytes,
                                        "Core header digest exceeds 1 MiB"));
  uint64_t confirmed = required;
  check_code(citizensdk_result_get_block_header(
      result, &value, digest.empty() ? nullptr : digest.data(), digest.size(), &confirmed));
  require(confirmed == required && value.digest_len == required,
          CITIZENSDK_ERROR_INTEGRITY, "Core header changed during copy");
  return tuple({block(value.block), hex(value.parent_hash), hex(value.state_root),
                hex(value.extrinsics_root), Value::bytes(std::move(digest))});
}

Value copy_body(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_block_body_info_t>();
  check_code(citizensdk_result_get_block_body_info(result, &value)); check_abi(value);
  require(value.extrinsic_count <= kMaximumBlockBodyExtrinsics &&
              value.total_bytes <= kMaximumBlockBodyBytes,
          CITIZENSDK_ERROR_INTEGRITY, "Core block body exceeds its public limits");
  Value::List extrinsics; extrinsics.reserve(value.extrinsic_count);
  uint64_t total = 0;
  for (uint32_t index = 0; index < value.extrinsic_count; ++index) {
    uint64_t required = 0;
    check_code(citizensdk_result_copy_block_body_extrinsic(
        result, index, nullptr, 0, &required));
    require(required > 0 && required <= kMaximumBlockBodyBytes - total,
            CITIZENSDK_ERROR_INTEGRITY, "Core block body item exceeds its public limits");
    Value::Bytes bytes(static_cast<std::size_t>(required)); uint64_t confirmed = required;
    check_code(citizensdk_result_copy_block_body_extrinsic(
        result, index, bytes.data(), bytes.size(), &confirmed));
    require(confirmed == required, CITIZENSDK_ERROR_INTEGRITY,
            "Core block body changed during copy");
    total += required; extrinsics.push_back(Value::bytes(std::move(bytes)));
  }
  require(total == value.total_bytes, CITIZENSDK_ERROR_INTEGRITY,
          "Core block body byte total is inconsistent");
  return tuple({block(value.block), Value::list(std::move(extrinsics))});
}

template <typename Copy>
Value copy_optional_bytes(Copy copy, const char *message,
                          std::size_t maximum = kMaximumBlockBodyBytes) {
  uint8_t present = 0; uint64_t required = 0;
  check_code(copy(&present, nullptr, 0, &required));
  require(present <= 1 && required <= maximum,
          CITIZENSDK_ERROR_INTEGRITY, message);
  if (present == 0) {
    require(required == 0, CITIZENSDK_ERROR_INTEGRITY, message);
    return Value::null();
  }
  Value::Bytes bytes(static_cast<std::size_t>(required));
  uint8_t confirmed_present = 0; uint64_t confirmed = required;
  check_code(copy(&confirmed_present, bytes.empty() ? nullptr : bytes.data(),
                  bytes.size(), &confirmed));
  require(confirmed_present == 1 && confirmed == required,
          CITIZENSDK_ERROR_INTEGRITY, message);
  return Value::bytes(std::move(bytes));
}

Value copy_storage(citizensdk_result_handle_t result) {
  return copy_optional_bytes(
      [result](uint8_t *present, uint8_t *buffer, uint64_t capacity, uint64_t *required) {
        return citizensdk_result_copy_storage(result, present, buffer, capacity, required);
      }, "Core storage value is invalid");
}

Value copy_storage_batch(citizensdk_result_handle_t result) {
  uint32_t count = 0;
  check_code(citizensdk_result_get_storage_batch_count(result, &count));
  require(count <= kMaximumStorageBatchKeys, CITIZENSDK_ERROR_INTEGRITY,
          "Core storage batch exceeds 1024 items");
  Value::List values; values.reserve(count);
  std::size_t total = 0;
  for (uint32_t index = 0; index < count; ++index) {
    auto item = copy_optional_bytes(
        [result, index](uint8_t *present, uint8_t *buffer, uint64_t capacity,
                        uint64_t *required) {
          return citizensdk_result_copy_storage_batch_item(
              result, index, present, buffer, capacity, required);
        }, "Core storage batch item is invalid", kMaximumBlockBodyBytes - total);
    if (const auto *bytes = std::get_if<Value::Bytes>(&item.data)) total += bytes->size();
    values.push_back(std::move(item));
  }
  return Value::list(std::move(values));
}

Value copy_runtime_context(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_runtime_context_info_t>(); uint64_t required = 0;
  check_code(citizensdk_result_get_runtime_context(result, &value, nullptr, 0, &required));
  check_abi(value);
  require(required > 0 && required <= kMaximumRuntimeMetadataBytes,
          CITIZENSDK_ERROR_INTEGRITY, "Core runtime metadata exceeds its public limits");
  Value::Bytes metadata(static_cast<std::size_t>(required)); uint64_t confirmed = required;
  check_code(citizensdk_result_get_runtime_context(
      result, &value, metadata.data(), metadata.size(), &confirmed));
  require(confirmed == required && value.metadata_len == required,
          CITIZENSDK_ERROR_INTEGRITY, "Core runtime context changed during copy");
  return tuple({block(value.block), Value::integer(value.spec_version),
                Value::integer(value.transaction_version), Value::bytes(std::move(metadata))});
}

Value copy_exported_state(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_exported_state_info_t>(); uint64_t required = 0;
  check_code(citizensdk_result_get_exported_state(result, &value, nullptr, 0, &required));
  check_abi(value);
  require(value.format_version > 0 && required > 0 &&
              required <= kMaximumExportedStateBytes,
          CITIZENSDK_ERROR_INTEGRITY, "Core exported state exceeds its public limits");
  Value::Bytes database(static_cast<std::size_t>(required)); uint64_t confirmed = required;
  check_code(citizensdk_result_get_exported_state(
      result, &value, database.data(), database.size(), &confirmed));
  require(confirmed == required && value.database_len == required,
          CITIZENSDK_ERROR_INTEGRITY, "Core exported state changed during copy");
  return tuple({Value::integer(value.format_version), block(value.finalized),
                Value::bytes(std::move(database))});
}

Value copy_signing_outcome(citizensdk_result_handle_t result) {
  auto info = prepared<citizensdk_signing_outcome_info_t>();
  uint64_t signature_required = 0, session_required = 0, request_required = 0;
  check_code(citizensdk_result_get_signing_outcome(
      result, &info, nullptr, 0, &signature_required, nullptr, 0,
      &session_required, nullptr, 0, &request_required));
  check_abi(info);
  require(signature_required <= 64 && session_required <= 128 && request_required <= 2331,
          CITIZENSDK_ERROR_INTEGRITY, "Core signing outcome exceeds its limits");
  Value::Bytes signature(copy_size(signature_required)), session(copy_size(session_required)),
               request(copy_size(request_required));
  uint64_t signature_confirmed = signature_required, session_confirmed = session_required,
           request_confirmed = request_required;
  check_code(citizensdk_result_get_signing_outcome(
      result, &info, signature.empty() ? nullptr : signature.data(), signature.size(),
      &signature_confirmed, session.empty() ? nullptr : session.data(), session.size(),
      &session_confirmed, request.empty() ? nullptr : request.data(), request.size(),
      &request_confirmed));
  require(signature_confirmed == signature_required && session_confirmed == session_required &&
              request_confirmed == request_required,
          CITIZENSDK_ERROR_INTEGRITY, "Core signing outcome changed during copy");
  if (info.status == CITIZENSDK_SIGNING_COMPLETED) {
    require(signature.size() == 64 && session.empty() && request.empty(),
            CITIZENSDK_ERROR_INTEGRITY, "Core completed signing outcome is inconsistent");
    return tuple({Value::string("completed"), hex(info.account_id.bytes), hex(info.payload_hash),
                  Value::bytes(std::move(signature)), Value::null(), Value::null(), Value::null()});
  }
  require(info.status == CITIZENSDK_SIGNING_EXTERNAL_PENDING && signature.empty() &&
              session.size() >= 16 && !request.empty() &&
              info.transport == CITIZENSDK_EXTERNAL_SIGNER_QR_V1,
          CITIZENSDK_ERROR_INTEGRITY, "Core pending signing outcome is inconsistent");
  return tuple({Value::string("externalPending"), hex(info.account_id.bytes), hex(info.payload_hash),
                Value::null(), Value::string(std::to_string(info.expires_at)),
                Value::string(copied_text(session)), Value::string(copied_text(request))});
}

Value copy_default_account_change(citizensdk_result_handle_t result) {
  auto info = prepared<citizensdk_default_account_change_info_t>();
  uint64_t session_required = 0, request_required = 0;
  check_code(citizensdk_result_get_default_account_change(
      result, &info, nullptr, 0, &session_required, nullptr, 0, &request_required));
  check_abi(info);
  require(session_required <= 128 && request_required <= 2331,
          CITIZENSDK_ERROR_INTEGRITY, "Core default-account change exceeds its limits");
  Value::Bytes session(copy_size(session_required)), request(copy_size(request_required));
  uint64_t session_confirmed = session_required, request_confirmed = request_required;
  check_code(citizensdk_result_get_default_account_change(
      result, &info, session.empty() ? nullptr : session.data(), session.size(),
      &session_confirmed, request.empty() ? nullptr : request.data(), request.size(),
      &request_confirmed));
  require(session_confirmed == session_required && request_confirmed == request_required,
          CITIZENSDK_ERROR_INTEGRITY, "Core default-account change changed during copy");
  if (info.status == CITIZENSDK_SIGNING_COMPLETED) {
    require(session.empty() && request.empty(), CITIZENSDK_ERROR_INTEGRITY,
            "Core completed default-account change is inconsistent");
    return tuple({Value::string("completed"), hex(info.current_default_account_id.bytes),
                  hex(info.payload_hash), Value::string(std::to_string(info.committed_revision)),
                  Value::null(), Value::null(), Value::null()});
  }
  require(info.status == CITIZENSDK_SIGNING_EXTERNAL_PENDING && session.size() >= 16 &&
              !request.empty() && info.transport == CITIZENSDK_EXTERNAL_SIGNER_QR_V1,
          CITIZENSDK_ERROR_INTEGRITY, "Core pending default-account change is inconsistent");
  return tuple({Value::string("externalPending"), hex(info.current_default_account_id.bytes),
                hex(info.payload_hash), Value::null(), Value::string(std::to_string(info.expires_at)),
                Value::string(copied_text(session)), Value::string(copied_text(request))});
}

Value copy_prepared_transaction(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_prepared_transaction_info_t>();
  check_code(citizensdk_result_get_prepared_transaction(result, &value));
  check_abi(value);
  require(value.prepared_transaction != 0 &&
              value.best_block.finality == CITIZENSDK_FINALITY_BEST,
          CITIZENSDK_ERROR_INTEGRITY,
          "Core prepared transaction result is invalid");
  return tuple({hex16(value.preparation_id), hex(value.source_account_id.bytes),
                hex(value.call_data_hash), block(value.best_block),
                Value::integer(value.runtime_spec_number),
                Value::integer(value.transaction_format_number),
                Value::string(std::to_string(value.nonce))});
}

Value copy_transaction_execution(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_transaction_execution_info_t>();
  uint64_t session_required = 0, request_required = 0, reason_required = 0;
  check_code(citizensdk_result_get_transaction_execution(
      result, &value, nullptr, 0, &session_required, nullptr, 0,
      &request_required, nullptr, 0, &reason_required));
  check_abi(value);
  require(session_required == value.session_id_len &&
              request_required == value.transport_request_len &&
              reason_required == value.pool_rejection_reason_len &&
              session_required <= 128 && request_required <= 2331 &&
              reason_required <= 4096,
          CITIZENSDK_ERROR_INTEGRITY,
          "Core transaction execution text lengths are invalid");
  Value::Bytes session(copy_size(session_required)), request(copy_size(request_required)),
               reason(copy_size(reason_required));
  uint64_t session_confirmed = session_required, request_confirmed = request_required,
           reason_confirmed = reason_required;
  check_code(citizensdk_result_get_transaction_execution(
      result, &value, session.empty() ? nullptr : session.data(), session.size(),
      &session_confirmed, request.empty() ? nullptr : request.data(), request.size(),
      &request_confirmed, reason.empty() ? nullptr : reason.data(), reason.size(),
      &reason_confirmed));
  require(session_confirmed == session_required && request_confirmed == request_required &&
              reason_confirmed == reason_required,
          CITIZENSDK_ERROR_INTEGRITY,
          "Core transaction execution changed during copy");

  const auto identity = [&]() {
    return Value::List{hex16(value.execution_id), hex(value.source_account_id.bytes),
                       hex(value.call_data_hash)};
  }();
  if (value.status == CITIZENSDK_TRANSACTION_EXECUTION_EXTERNAL_PENDING) {
    require(value.transport == CITIZENSDK_EXTERNAL_SIGNER_QR_V1 && !session.empty() &&
                !request.empty() && value.expires_at > 0 && !flag(value.has_block) &&
                !flag(value.has_extrinsic_index) && !flag(value.has_dispatch_failure) &&
                !flag(value.has_module_failure) && !flag(value.has_replacement_hash) &&
                reason.empty(),
            CITIZENSDK_ERROR_INTEGRITY,
            "Core pending transaction execution is inconsistent");
    return tuple({Value::integer(1), identity[0], identity[1], identity[2], Value::null(),
                  Value::string(std::to_string(value.expires_at)),
                  Value::string(copied_text(request)), Value::null(), Value::null(),
                  Value::null()});
  }

  require(value.transport == CITIZENSDK_EXTERNAL_SIGNER_NONE && session.empty() &&
              request.empty() && value.expires_at == 0,
          CITIZENSDK_ERROR_INTEGRITY,
          "Core terminal transaction execution contains QR_V1 fields");
  if (value.status == CITIZENSDK_TRANSACTION_EXECUTION_POOL_REJECTED) {
    require(!flag(value.has_block) && !flag(value.has_extrinsic_index) &&
                !flag(value.has_dispatch_failure) && !flag(value.has_module_failure) &&
                !reason.empty(),
            CITIZENSDK_ERROR_INTEGRITY,
            "Core pool rejection is inconsistent");
    return tuple({Value::integer(4), identity[0], identity[1], identity[2],
                  hex(value.transaction_hash), Value::null(), Value::null(), Value::null(),
                  Value::string(copied_text(reason)),
                  flag(value.has_replacement_hash) ? hex(value.replacement_hash)
                                                   : Value::null()});
  }

  require((value.status == CITIZENSDK_TRANSACTION_EXECUTION_FINALIZED_SUCCESS ||
           value.status == CITIZENSDK_TRANSACTION_EXECUTION_FINALIZED_FAILED) &&
              flag(value.has_block) && flag(value.has_extrinsic_index) && reason.empty() &&
              !flag(value.has_replacement_hash),
          CITIZENSDK_ERROR_INTEGRITY,
          "Core finalized transaction execution is inconsistent");
  auto verified = prepared<citizensdk_execution_info_t>();
  verified.status = value.status == CITIZENSDK_TRANSACTION_EXECUTION_FINALIZED_SUCCESS
      ? CITIZENSDK_EXECUTION_SUCCESS : CITIZENSDK_EXECUTION_FAILED;
  verified.has_block = value.has_block;
  verified.has_extrinsic_index = value.has_extrinsic_index;
  verified.reason_or_dispatch_variant = value.dispatch_variant;
  verified.has_module = value.has_module_failure;
  verified.pallet_index = value.pallet_index;
  verified.error_index = value.error_index;
  verified.block = value.block;
  verified.extrinsic_index = value.extrinsic_index;
  require((verified.status == CITIZENSDK_EXECUTION_FAILED) ==
              flag(value.has_dispatch_failure),
          CITIZENSDK_ERROR_INTEGRITY,
          "Core finalized execution dispatch fields are inconsistent");
  return tuple({Value::integer(value.status), identity[0], identity[1], identity[2],
                hex(value.transaction_hash), Value::null(), Value::null(),
                execution(verified), Value::null(), Value::null()});
}

Value copy_history(citizensdk_result_handle_t result) {
  auto info = prepared<citizensdk_transaction_history_page_info_t>();
  check_code(citizensdk_result_get_transaction_history_page(result, &info));
  check_abi(info);
  require(info.record_count <= 100,
          CITIZENSDK_ERROR_INTEGRITY,
          "Core transaction history page exceeds the public contract");
  const bool has_next = flag(info.has_next_before_execution_id);
  Value::List records; records.reserve(info.record_count);
  constexpr const char *statuses[] = {"pending", "inBlock", "poolRejected",
                                      "finalizedSuccess", "finalizedFailed"};
  for (uint32_t i = 0; i < info.record_count; ++i) {
    auto value = prepared<citizensdk_transaction_history_record_info_t>();
    uint64_t reason_length = 0;
    check_code(citizensdk_result_get_transaction_history_record(
        result, i, &value, nullptr, 0, &reason_length));
    check_abi(value);
    require(reason_length <= 4096 && reason_length == value.pool_rejection_reason_len,
            CITIZENSDK_ERROR_INTEGRITY,
            "Core transaction history reason exceeds the public contract");
    Value::Bytes reason(copy_size(reason_length));
    uint64_t confirmed = reason_length;
    check_code(citizensdk_result_get_transaction_history_record(
        result, i, &value, reason.empty() ? nullptr : reason.data(),
        reason.size(), &confirmed));
    require(confirmed == reason_length && value.status >= 1 && value.status <= 5,
            CITIZENSDK_ERROR_INTEGRITY, "Core transaction history record is invalid");
    const bool has_block = flag(value.has_block);
    const bool has_execution = flag(value.has_execution);
    const bool has_replacement = flag(value.has_replacement_hash);
    records.push_back(tuple({hex16(value.execution_id.bytes),
        hex(value.source_account_id.bytes), hex(value.call_data_hash),
        hex(value.transaction_hash), Value::string(statuses[value.status - 1]),
        has_block ? block(value.block) : Value::null(),
        has_execution ? execution(value.execution) : Value::null(),
        has_replacement ? hex(value.replacement_hash) : Value::null(),
        Value::string(std::to_string(value.created_at_millis)),
        Value::string(std::to_string(value.updated_at_millis)), nullable_text(reason)}));
  }
  return tuple({Value::string(std::to_string(info.revision)),
                Value::list(std::move(records)),
                has_next ? hex16(info.next_before_execution_id.bytes) : Value::null()});
}

}  // namespace

Value copy_genesis_hash(citizensdk_handle_t sdk) {
  uint8_t value[32]{};
  check_code(citizensdk_get_genesis_hash(sdk, value));
  return hex(value);
}

Value copy_public_result(Method method, citizensdk_result_handle_t result) {
  auto checked = [method](Value value) {
    // ABI 正确并不代表业务字段一致；在离开原生借用窗口前执行与 Dart 相同的后置校验。
    validate_public_value(method, value);
    return value;
  };
  switch (method) {
    case Method::start: case Method::stop:
      (void)inspect_result(result, CITIZENSDK_RESULT_EMPTY); return Value::list({});
    case Method::import_state: {
      (void)inspect_result(result, CITIZENSDK_RESULT_BLOCK_REF);
      auto value = prepared<citizensdk_block_ref_t>();
      check_code(citizensdk_result_get_block_ref(result, &value));
      require(value.finality == CITIZENSDK_FINALITY_FINALIZED,
              CITIZENSDK_ERROR_INTEGRITY, "Imported state receipt is not finalized");
      return Value::list({});
    }
    case Method::get_finalized_head: case Method::get_best_head:
    case Method::get_finalized_block_at: case Method::resolve_finalized_block:
      (void)inspect_result(result, CITIZENSDK_RESULT_BLOCK_REF);
      { auto value = prepared<citizensdk_block_ref_t>();
        check_code(citizensdk_result_get_block_ref(result, &value));
        return checked(tuple({block(value)})); }
    case Method::get_sync_status:
      (void)inspect_result(result, CITIZENSDK_RESULT_CHAIN_SYNC_STATUS);
      return checked(tuple({copy_sync_status(result)}));
    case Method::get_block_header:
      (void)inspect_result(result, CITIZENSDK_RESULT_BLOCK_HEADER);
      return checked(tuple({copy_header(result)}));
    case Method::get_block_body:
      (void)inspect_result(result, CITIZENSDK_RESULT_BLOCK_BODY);
      return checked(tuple({copy_body(result)}));
    case Method::get_runtime_context:
      (void)inspect_result(result, CITIZENSDK_RESULT_RUNTIME_CONTEXT);
      return checked(tuple({copy_runtime_context(result)}));
    case Method::get_storage: case Method::get_system_events:
      (void)inspect_result(result, CITIZENSDK_RESULT_STORAGE_VALUE);
      return checked(tuple({copy_storage(result)}));
    case Method::get_storage_batch:
      (void)inspect_result(result, CITIZENSDK_RESULT_STORAGE_BATCH);
      return checked(tuple({copy_storage_batch(result)}));
    case Method::export_state:
      (void)inspect_result(result, CITIZENSDK_RESULT_EXPORTED_STATE);
      return checked(tuple({copy_exported_state(result)}));
    case Method::get_account_balance:
      (void)inspect_result(result, CITIZENSDK_RESULT_ACCOUNT_BALANCE);
      return checked(tuple({copy_balance(result)}));
    case Method::get_account_balances: {
      (void)inspect_result(result, CITIZENSDK_RESULT_ACCOUNT_BALANCES);
      uint32_t count = 0;
      check_code(citizensdk_result_get_account_balance_count(result, &count));
      require(count <= 1990, CITIZENSDK_ERROR_INTEGRITY, "Core balance count exceeds the contract");
      Value::List balances; balances.reserve(count);
      for (uint32_t index = 0; index < count; ++index) {
        auto value = prepared<citizensdk_account_balance_info_t>();
        check_code(citizensdk_result_get_account_balance_at(result, index, &value));
        balances.push_back(balance(value));
      }
      return checked(tuple({Value::list(std::move(balances))}));
    }
    case Method::get_account_nonce:
      (void)inspect_result(result, CITIZENSDK_RESULT_ACCOUNT_NONCE);
      return checked(tuple({copy_nonce(result)}));
    case Method::get_fee_snapshot:
      (void)inspect_result(result, CITIZENSDK_RESULT_FEE_SNAPSHOT);
      return checked(tuple({copy_fee(result)}));
    case Method::get_wallet_profile: case Method::create_wallet: case Method::import_wallet:
    case Method::add_wallet_accounts: case Method::set_active_wallet_account:
    case Method::rename_wallet_account:
      (void)inspect_result(result, CITIZENSDK_RESULT_WALLET_PROFILE);
      return checked(tuple({profile(result)}));
    case Method::get_wallet_state: case Method::import_cold_account_id:
    case Method::import_cold_account_ss58:
    case Method::reorder_wallet_accounts_without_default_change:
    case Method::rename_account: case Method::delete_account:
      (void)inspect_result(result, CITIZENSDK_RESULT_WALLET_STATE);
      return checked(tuple({wallet_state(result)}));
    // The public session gate chains these Core UNIT mutations to one
    // get_wallet_profile request before replying to Dart.
    case Method::delete_wallet_account: case Method::delete_wallet:
    case Method::reconcile_wallet_cleanup:
      (void)inspect_result(result, CITIZENSDK_RESULT_EMPTY);
      return Value::list({});
    case Method::sign_wallet_payload: {
      (void)inspect_result(result, CITIZENSDK_RESULT_SIGNATURE);
      Value::Bytes bytes(64); check_code(citizensdk_result_get_signature(result, bytes.data()));
      return checked(tuple({Value::bytes(std::move(bytes))}));
    }
    case Method::begin_signing: case Method::consume_external_signature:
      (void)inspect_result(result, CITIZENSDK_RESULT_SIGNING_OUTCOME);
      return checked(tuple({copy_signing_outcome(result)}));
    case Method::begin_default_account_change: case Method::consume_default_account_change:
      (void)inspect_result(result, CITIZENSDK_RESULT_DEFAULT_ACCOUNT_CHANGE);
      return checked(tuple({copy_default_account_change(result)}));
    case Method::prepare_transaction:
      (void)inspect_result(result, CITIZENSDK_RESULT_PREPARED_TRANSACTION);
      return checked(tuple({copy_prepared_transaction(result)}));
    case Method::execute_prepared_transaction:
    case Method::consume_prepared_transaction_qr_response:
      (void)inspect_result(result, CITIZENSDK_RESULT_TRANSACTION_EXECUTION);
      return checked(tuple({copy_transaction_execution(result)}));
    case Method::get_transaction_history: case Method::sync_transaction_history:
      (void)inspect_result(result, CITIZENSDK_RESULT_TRANSACTION_HISTORY_PAGE);
      return checked(tuple({copy_history(result)}));
    case Method::view_account_private_key:
    case Method::cancel_prepared_transaction:
    case Method::cancel_prepared_transaction_execution:
    case Method::cancel_signing:
    case Method::verify_signature:
    case Method::open: case Method::close: case Method::get_capabilities: case Method::get_genesis_hash:
    case Method::qr_parse: case Method::qr_create_sign_request:
    case Method::qr_scan: case Method::sign_qr_request:
    case Method::qr_consume_sign_response: case Method::qr_cancel_sign_request:
    case Method::qr_encode_account_id:
    case Method::qr_decode_luminance: case Method::qr_encode:
      fail(CITIZENSDK_ERROR_INVALID_STATE, "This method has no borrowed Core result");
  }
  fail(CITIZENSDK_ERROR_UNSUPPORTED, "Unsupported result method");
}

void validate_account_balances(const DecodedRequest &request, const Value &value) {
  validate_public_value(Method::get_account_balances, value);
  const auto &balances = bounded_list(semantic_tuple(value, 1)[0], 1990, 0);
  require(balances.size() == request.account_ids.size(), CITIZENSDK_ERROR_INTEGRITY,
          "Balance response count differs from the request");
  for (std::size_t index = 0; index < balances.size(); ++index) {
    require(same_id(account(semantic_tuple(balances[index], 5)[0]), request.account_ids[index]),
            CITIZENSDK_ERROR_INTEGRITY, "Balance accounts differ from request order");
  }
}

void validate_public_value(Method method, const Value &value) {
  if (method >= Method::qr_parse && method <= Method::sign_qr_request) {
    const auto &fields = semantic_tuple(value, method == Method::qr_encode ? 3 : 1);
    if (method == Method::qr_consume_sign_response) {
      const auto *bytes = std::get_if<Value::Bytes>(&fields[0].data);
      require(bytes != nullptr && bytes->size() == 64, CITIZENSDK_ERROR_INTEGRITY,
              "QR consume must return the verified 64-byte signature");
    } else if (method == Method::qr_cancel_sign_request) {
      require(std::holds_alternative<bool>(fields[0].data), CITIZENSDK_ERROR_INTEGRITY,
              "QR cancellation must be bool");
    } else if (method == Method::qr_encode) {
      const auto width = semantic_int(fields[0], 4096), height = semantic_int(fields[1], 4096);
      const auto *bytes = std::get_if<Value::Bytes>(&fields[2].data);
      require(width > 0 && height > 0 && bytes != nullptr &&
                  bytes->size() == static_cast<std::size_t>(width * height),
              CITIZENSDK_ERROR_INTEGRITY, "QR image dimensions do not match luminance");
    } else {
      const auto &text = string(fields[0], 1, 65536);
      const bool document = method == Method::qr_parse || method == Method::qr_scan ||
          method == Method::qr_decode_luminance || method == Method::sign_qr_request;
      require(text.size() <= (document ? 65536U : 2331U), CITIZENSDK_ERROR_INTEGRITY,
              "QR public text exceeds its UTF-8 limit");
    }
    return;
  }

  try {
    if (method == Method::view_account_private_key) {
      (void)semantic_tuple(value, 0);
      return;
    }
    if (method == Method::import_state) {
      (void)semantic_tuple(value, 0);
      return;
    }
    const auto &fields = semantic_tuple(value, 1);
    const auto &item = fields[0];
    switch (method) {
      case Method::get_finalized_head:
        require(semantic_block(item).finalized, CITIZENSDK_ERROR_INTEGRITY,
                "Finalized head must reference a finalized block"); return;
      case Method::get_best_head:
        require(!semantic_block(item).finalized, CITIZENSDK_ERROR_INTEGRITY,
                "Best head must reference a best block"); return;
      case Method::get_finalized_block_at: case Method::resolve_finalized_block:
        require(semantic_block(item).finalized, CITIZENSDK_ERROR_INTEGRITY,
                "Finalized block lookup must return a finalized block"); return;
      case Method::get_sync_status: {
        const auto &status = semantic_tuple(item, 5);
        (void)u64_text(status[0]); (void)semantic_bool(status[1]);
        (void)semantic_bool(status[2]);
        const auto best = semantic_block(status[3]);
        const auto finalized = semantic_block(status[4]);
        require(!best.finalized && finalized.finalized && finalized.number <= best.number,
                CITIZENSDK_ERROR_INTEGRITY, "Sync status block closure is invalid"); return;
      }
      case Method::get_block_header: {
        const auto &header = semantic_tuple(item, 5); (void)semantic_block(header[0]);
        (void)account(header[1]); (void)account(header[2]); (void)account(header[3]);
        const auto *digest = std::get_if<Value::Bytes>(&header[4].data);
        require(digest != nullptr && digest->size() <= kMaximumHeaderDigestBytes,
                CITIZENSDK_ERROR_INTEGRITY, "Block header digest exceeds 1 MiB"); return;
      }
      case Method::get_block_body: {
        const auto &body = semantic_tuple(item, 2); (void)semantic_block(body[0]);
        const auto *extrinsics = std::get_if<Value::List>(&body[1].data);
        require(extrinsics != nullptr && extrinsics->size() <= kMaximumBlockBodyExtrinsics,
                CITIZENSDK_ERROR_INTEGRITY, "Block body count exceeds its public limit");
        std::size_t total = 0;
        for (const auto &extrinsic : *extrinsics) {
          const auto *bytes = std::get_if<Value::Bytes>(&extrinsic.data);
          require(bytes != nullptr && !bytes->empty() &&
                      bytes->size() <= kMaximumBlockBodyBytes - total,
                  CITIZENSDK_ERROR_INTEGRITY, "Block body bytes exceed 64 MiB");
          total += bytes->size();
        }
        return;
      }
      case Method::get_runtime_context: {
        const auto &runtime = semantic_tuple(item, 4); (void)semantic_block(runtime[0]);
        (void)semantic_int(runtime[1], UINT32_MAX);
        (void)semantic_int(runtime[2], UINT32_MAX);
        const auto *metadata = std::get_if<Value::Bytes>(&runtime[3].data);
        require(metadata != nullptr && !metadata->empty() &&
                    metadata->size() <= kMaximumRuntimeMetadataBytes,
                CITIZENSDK_ERROR_INTEGRITY, "Runtime metadata exceeds its public limit"); return;
      }
      case Method::get_storage: case Method::get_system_events: {
        if (null_value(item)) return;
        const auto *bytes = std::get_if<Value::Bytes>(&item.data);
        require(bytes != nullptr && bytes->size() <= kMaximumBlockBodyBytes,
                CITIZENSDK_ERROR_INTEGRITY, "Storage value exceeds its public limit"); return;
      }
      case Method::get_storage_batch: {
        const auto *items = std::get_if<Value::List>(&item.data);
        require(items != nullptr && items->size() <= kMaximumStorageBatchKeys,
                CITIZENSDK_ERROR_INTEGRITY, "Storage batch exceeds its public limit");
        std::size_t total = 0;
        for (const auto &entry : *items) {
          if (null_value(entry)) continue;
          const auto *bytes = std::get_if<Value::Bytes>(&entry.data);
          require(bytes != nullptr && bytes->size() <= kMaximumBlockBodyBytes - total,
                  CITIZENSDK_ERROR_INTEGRITY, "Storage batch item exceeds its public limit");
          total += bytes->size();
        }
        return;
      }
      case Method::export_state: {
        const auto &state = semantic_tuple(item, 3);
        require(semantic_int(state[0], UINT32_MAX) > 0 &&
                    semantic_block(state[1]).finalized,
                CITIZENSDK_ERROR_INTEGRITY, "Exported state descriptor is invalid");
        const auto *database = std::get_if<Value::Bytes>(&state[2].data);
        require(database != nullptr && !database->empty() &&
                    database->size() <= kMaximumExportedStateBytes,
                CITIZENSDK_ERROR_INTEGRITY, "Exported state database is invalid"); return;
      }
      case Method::get_account_balance: {
        const auto &balance = semantic_tuple(item, 5); (void)account(balance[0]);
        require(semantic_block(balance[1]).finalized &&
                    sum_matches(semantic_u128(balance[2]), semantic_u128(balance[3]), semantic_u128(balance[4])),
                CITIZENSDK_ERROR_INTEGRITY, "Balance finality or total is inconsistent"); return;
      }
      case Method::get_genesis_hash:
        (void)account(item); return;
      case Method::get_account_balances: {
        const auto &balances = bounded_list(item, 1990, 0);
        std::optional<SemanticBlock> anchor;
        for (const auto &value : balances) {
          validate_public_value(Method::get_account_balance, tuple({value}));
          const auto current = semantic_block(semantic_tuple(value, 5)[1]);
          require(!anchor || same_block(*anchor, current), CITIZENSDK_ERROR_INTEGRITY,
                  "Balances must reference the same finalized block");
          anchor = current;
        }
        return;
      }
      case Method::get_account_nonce: {
        const auto &nonce = semantic_tuple(item, 3); (void)account(nonce[0]);
        require(!semantic_block(nonce[1]).finalized, CITIZENSDK_ERROR_INTEGRITY,
                "Account nonce must reference the best block");
        (void)u64_text(nonce[2]); return;
      }
      case Method::get_fee_snapshot: {
        const auto &fee = semantic_tuple(item, 4);
        require(!semantic_block(fee[0]).finalized && semantic_int(fee[1], 1000000000) > 0 &&
                    positive(semantic_u128(fee[2])),
                CITIZENSDK_ERROR_INTEGRITY, "Fee snapshot finality, Perbill or minimum is invalid");
        (void)semantic_u128(fee[3]); return;
      }
      case Method::get_wallet_profile: case Method::create_wallet: case Method::import_wallet:
      case Method::add_wallet_accounts: case Method::set_active_wallet_account:
      case Method::rename_wallet_account: case Method::delete_wallet_account:
      case Method::delete_wallet: case Method::reconcile_wallet_cleanup:
        validate_profile(item); return;
      case Method::get_wallet_state: case Method::import_cold_account_id:
      case Method::import_cold_account_ss58:
      case Method::reorder_wallet_accounts_without_default_change:
      case Method::rename_account: case Method::delete_account:
        validate_wallet_state(item); return;
      case Method::sign_wallet_payload: {
        const auto *bytes = std::get_if<Value::Bytes>(&item.data);
        require(bytes != nullptr && bytes->size() == 64, CITIZENSDK_ERROR_INTEGRITY,
                "sr25519 public signature must be 64 bytes"); return;
      }
      case Method::begin_signing: case Method::consume_external_signature: {
        const auto &outcome = semantic_tuple(item, 7);
        const auto status = semantic_text(outcome[0]);
        (void)account(outcome[1]); (void)account(outcome[2]);
        if (status == "completed") {
          const auto *signature = std::get_if<Value::Bytes>(&outcome[3].data);
          require(signature != nullptr && signature->size() == 64 &&
                      null_value(outcome[4]) && null_value(outcome[5]) && null_value(outcome[6]),
                  CITIZENSDK_ERROR_INTEGRITY, "Completed signing outcome is invalid");
        } else {
          require(status == "externalPending" && null_value(outcome[3]) &&
                      u64_text(outcome[4]) > 0 &&
                      semantic_text(outcome[5]).size() >= 16 &&
                      semantic_text(outcome[5]).size() <= 128 &&
                      !semantic_text(outcome[6]).empty() && semantic_text(outcome[6]).size() <= 2331,
                  CITIZENSDK_ERROR_INTEGRITY, "Pending signing outcome is invalid");
        }
        return;
      }
      case Method::begin_default_account_change:
      case Method::consume_default_account_change: {
        const auto &outcome = semantic_tuple(item, 7);
        const auto status = semantic_text(outcome[0]);
        (void)account(outcome[1]); (void)account(outcome[2]);
        if (status == "completed") {
          (void)u64_text(outcome[3]);
          require(null_value(outcome[4]) && null_value(outcome[5]) && null_value(outcome[6]),
                  CITIZENSDK_ERROR_INTEGRITY, "Completed default-account change is invalid");
        } else {
          require(status == "externalPending" && null_value(outcome[3]) &&
                      u64_text(outcome[4]) > 0 &&
                      semantic_text(outcome[5]).size() >= 16 &&
                      semantic_text(outcome[5]).size() <= 128 &&
                      !semantic_text(outcome[6]).empty() && semantic_text(outcome[6]).size() <= 2331,
                  CITIZENSDK_ERROR_INTEGRITY, "Pending default-account change is invalid");
        }
        return;
      }
      case Method::cancel_signing:
        require(std::holds_alternative<bool>(item.data), CITIZENSDK_ERROR_INTEGRITY,
                "Signing cancellation result must be bool"); return;
      case Method::verify_signature:
        require(std::holds_alternative<bool>(item.data), CITIZENSDK_ERROR_INTEGRITY,
                "Verification result must be bool"); return;
      case Method::prepare_transaction: {
        const auto &prepared_value = semantic_tuple(item, 7);
        const auto preparation = semantic_text(prepared_value[0]);
        require(preparation.size() == 34 && preparation.rfind("0x", 0) == 0 &&
                    std::all_of(preparation.begin() + 2, preparation.end(), [](char value) {
                      return (value >= '0' && value <= '9') ||
                             (value >= 'a' && value <= 'f');
                    }),
                CITIZENSDK_ERROR_INTEGRITY, "Preparation identity is invalid");
        (void)account(prepared_value[1]);
        (void)account(prepared_value[2]);
        const auto anchor = semantic_block(prepared_value[3]);
        require(!anchor.finalized && semantic_int(prepared_value[4], UINT32_MAX) >= 0 &&
                    semantic_int(prepared_value[5], UINT32_MAX) >= 0,
                CITIZENSDK_ERROR_INTEGRITY, "Prepared transaction anchor is invalid");
        (void)u64_text(prepared_value[6]);
        return;
      }
      case Method::cancel_prepared_transaction:
        require(null_value(item), CITIZENSDK_ERROR_INTEGRITY,
                "Prepared transaction cancellation result must be null");
        return;
      case Method::execute_prepared_transaction:
      case Method::consume_prepared_transaction_qr_response: {
        const auto &outcome = semantic_tuple(item, 10);
        const auto status = semantic_int(outcome[0], 4);
        const auto id = semantic_text(outcome[1]);
        require(status >= 1 && id.size() == 34 && id.rfind("0x", 0) == 0 &&
                    std::all_of(id.begin() + 2, id.end(), [](char value) {
                      return (value >= '0' && value <= '9') ||
                             (value >= 'a' && value <= 'f');
                    }),
                CITIZENSDK_ERROR_INTEGRITY,
                "Transaction execution identity/status is invalid");
        (void)account(outcome[2]);
        (void)account(outcome[3]);
        if (status == 1) {
          require(null_value(outcome[4]) && u64_text(outcome[5]) > 0 &&
                      !semantic_text(outcome[6]).empty() &&
                      null_value(outcome[7]) && null_value(outcome[8]) &&
                      null_value(outcome[9]),
                  CITIZENSDK_ERROR_INTEGRITY,
                  "Pending transaction execution fields are invalid");
          return;
        }
        (void)account(outcome[4]);
        require(null_value(outcome[5]) && null_value(outcome[6]),
                CITIZENSDK_ERROR_INTEGRITY,
                "Terminal transaction execution contains QR_V1 fields");
        if (status == 4) {
          require(null_value(outcome[7]) && !semantic_text(outcome[8]).empty(),
                  CITIZENSDK_ERROR_INTEGRITY,
                  "Pool-rejected transaction execution fields are invalid");
          if (!null_value(outcome[9])) (void)account(outcome[9]);
          return;
        }
        const auto verified = semantic_execution(outcome[7]);
        require(null_value(outcome[8]) && null_value(outcome[9]) &&
                    ((status == 2 && verified.status == "success") ||
                     (status == 3 && verified.status == "failed")),
                CITIZENSDK_ERROR_INTEGRITY,
                "Finalized transaction execution fields are invalid");
        return;
      }
      case Method::cancel_prepared_transaction_execution:
        require(null_value(item), CITIZENSDK_ERROR_INTEGRITY,
                "Transaction execution cancellation result must be null");
        return;
      case Method::get_transaction_history: case Method::sync_transaction_history:
        validate_history(item); return;
      case Method::view_account_private_key:
      case Method::open: case Method::start: case Method::stop: case Method::close:
      case Method::get_capabilities:
      case Method::import_state:
      case Method::qr_parse: case Method::qr_create_sign_request:
      case Method::qr_scan: case Method::sign_qr_request:
      case Method::qr_consume_sign_response: case Method::qr_cancel_sign_request:
      case Method::qr_encode_account_id:
      case Method::qr_decode_luminance: case Method::qr_encode:
        fail(CITIZENSDK_ERROR_INVALID_STATE, "This method uses its dedicated lifecycle/capability encoder");
    }
  } catch (const ContractFailure &error) {
    if (error.code == CITIZENSDK_ERROR_INVALID_STATE) throw;
    throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY, error.what());
  }
}

}  // namespace citizen_sdk::flutter
