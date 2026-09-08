#include "citizen_sdk_flutter_codec.hpp"

#include <algorithm>
#include <array>
#include <charconv>
#include <cstring>
#include <limits>
#include <set>
#include <tuple>
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
std::string lossy_utf8(const Value::Bytes &bytes) {
  // 对齐 Dart utf8.decode(allowMalformed: true)：非法子序列替换、保留 NUL、丢弃开头 BOM。
  // This is only the public remark-display postcondition, not key material.
  std::string result;
  const std::size_t start = bytes.size() >= 3 && bytes[0] == 0xef &&
                                   bytes[1] == 0xbb && bytes[2] == 0xbf ? 3 : 0;
  for (std::size_t offset = start; offset < bytes.size();) {
    const uint8_t first = bytes[offset];
    if (first < 0x80) { result.push_back(static_cast<char>(first)); ++offset; continue; }
    std::size_t expected = 0;
    if (first >= 0xc2 && first <= 0xdf) expected = 2;
    else if (first >= 0xe0 && first <= 0xef) expected = 3;
    else if (first >= 0xf0 && first <= 0xf4) expected = 4;
    if (expected == 0) { result.append("\xef\xbf\xbd", 3); ++offset; continue; }
    std::size_t consumed = 1;
    for (; consumed < expected && offset + consumed < bytes.size(); ++consumed) {
      const uint8_t next = bytes[offset + consumed];
      const bool continuation = next >= 0x80 && next <= 0xbf;
      const bool scalar_range = consumed != 1 ||
          !((first == 0xe0 && next < 0xa0) || (first == 0xed && next > 0x9f) ||
            (first == 0xf0 && next < 0x90) || (first == 0xf4 && next > 0x8f));
      if (!continuation || !scalar_range) break;
    }
    if (consumed == expected)
      result.append(reinterpret_cast<const char *>(bytes.data() + offset), expected);
    else result.append("\xef\xbf\xbd", 3);
    offset += consumed;
  }
  return result;
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

void validate_transfer(const Value &value) {
  const auto &fields = semantic_tuple(value, 4);
  (void)account(fields[0]);
  const auto resolution = semantic_text(fields[1]);
  const bool has_execution = !null_value(fields[2]);
  std::optional<SemanticExecution> execution_value;
  if (has_execution) execution_value = semantic_execution(fields[2]);
  const bool has_reason = !null_value(fields[3]);
  std::string reason;
  if (has_reason) reason = semantic_text(fields[3]);
  const bool valid =
      (resolution == "finalizedSuccess" && has_execution && execution_value->success && !has_reason) ||
      (resolution == "finalizedFailed" && has_execution && !execution_value->success && !has_reason) ||
      (resolution == "poolRejected" && !has_execution && has_reason && contains_non_whitespace(reason));
  require(valid, CITIZENSDK_ERROR_INTEGRITY, "Wallet transfer terminal fields disagree");
}

void validate_history(const Value &value) {
  // 游标单调性、交易终态与三类唯一键同时校验；不能把“包含”当成“执行成功”。
  const auto &history = semantic_tuple(value, 4); (void)u64_text(history[0]);
  const auto *cursor_values = std::get_if<Value::List>(&history[1].data);
  const auto *record_values = std::get_if<Value::List>(&history[2].data);
  const auto *transfer_values = std::get_if<Value::List>(&history[3].data);
  require(cursor_values != nullptr && record_values != nullptr && transfer_values != nullptr,
          CITIZENSDK_ERROR_INTEGRITY, "History collections are not lists");
  const auto &cursors = *cursor_values, &records = *record_values, &transfers = *transfer_values;
  require(cursors.size() <= 1990 && records.size() <= 100000 && transfers.size() <= 100000,
          CITIZENSDK_ERROR_INTEGRITY, "History collection exceeds its contract");
  std::set<std::array<uint8_t, 32>> cursor_keys;
  for (const auto &item : cursors) {
    const auto &fields = semantic_tuple(item, 3); const auto id = account(fields[0]);
    std::array<uint8_t, 32> key{}; std::copy(std::begin(id.bytes), std::end(id.bytes), key.begin());
    const auto start = semantic_block(fields[1]), last = semantic_block(fields[2]);
    require(cursor_keys.insert(key).second && start.finalized && last.finalized &&
                last.number >= start.number && (last.number != start.number || same_block(last, start)),
            CITIZENSDK_ERROR_INTEGRITY, "History cursor is duplicated or regressed");
  }
  std::set<std::array<uint8_t, 64>> record_keys;
  for (const auto &item : records) {
    const auto &fields = semantic_tuple(item, 12);
    const auto owner = account(fields[0]), transaction = account(fields[1]);
    std::array<uint8_t, 64> key{};
    std::copy(std::begin(owner.bytes), std::end(owner.bytes), key.begin());
    std::copy(std::begin(transaction.bytes), std::end(transaction.bytes), key.begin() + 32);
    require(record_keys.insert(key).second, CITIZENSDK_ERROR_INTEGRITY,
            "History account/transaction key is duplicated");
    (void)u64_text(fields[2]); (void)account(fields[3]);
    require(positive(semantic_u128(fields[4])), CITIZENSDK_ERROR_INTEGRITY,
            "History amount must be positive");
    const auto status = semantic_text(fields[5]);
    const bool has_block = !null_value(fields[6]), has_execution = !null_value(fields[7]);
    std::optional<SemanticBlock> block_value;
    std::optional<SemanticExecution> execution_value;
    if (has_block) block_value = semantic_block(fields[6]);
    if (has_execution) execution_value = semantic_execution(fields[7]);
    const uint64_t created = u64_text(fields[8]), updated = u64_text(fields[9]);
    const auto remark = semantic_text(fields[10]);
    require(updated >= created && remark.size() <= 99, CITIZENSDK_ERROR_INTEGRITY,
            "History time or remark is invalid");
    const bool has_reason = !null_value(fields[11]);
    std::string reason; if (has_reason) reason = semantic_text(fields[11]);
    const bool matching = has_block && has_execution && same_block(*block_value, execution_value->block);
    const bool valid =
        (status == "pending" && !has_block && !has_execution && !has_reason) ||
        (status == "inBlock" && has_block && !has_execution && !has_reason) ||
        (status == "poolRejected" && !has_block && !has_execution && has_reason && contains_non_whitespace(reason)) ||
        (status == "finalizedSuccess" && matching && block_value->finalized && execution_value->success && !has_reason) ||
        (status == "finalizedFailed" && matching && block_value->finalized && !execution_value->success && !has_reason);
    require(valid, CITIZENSDK_ERROR_INTEGRITY, "History record status fields disagree");
  }
  struct TransferKey { std::array<uint8_t,32> owner{}, hash{}; uint32_t event{};
    bool operator<(const TransferKey &other) const { return std::tie(owner, hash, event) < std::tie(other.owner, other.hash, other.event); } };
  std::set<TransferKey> transfer_keys;
  for (const auto &item : transfers) {
    const auto &fields = semantic_tuple(item, 11);
    const auto tracked = account(fields[0]), from = account(fields[1]), to = account(fields[2]);
    require(positive(semantic_u128(fields[3])) && !same_id(from, to) &&
                (same_id(tracked, from) || same_id(tracked, to)),
            CITIZENSDK_ERROR_INTEGRITY, "Finalized transfer parties or amount are invalid");
    const auto block_value = semantic_block(fields[4]);
    require(block_value.finalized, CITIZENSDK_ERROR_INTEGRITY,
            "Finalized transfer is not finalized");
    const auto event_index = semantic_int(fields[5], UINT32_MAX);
    const bool has_extrinsic = !null_value(fields[6]);
    if (has_extrinsic) (void)semantic_int(fields[6], UINT32_MAX);
    const auto direction = semantic_text(fields[7]);
    require(direction == (same_id(tracked, to) ? "incoming" : "outgoing"),
            CITIZENSDK_ERROR_INTEGRITY, "Finalized transfer direction is invalid");
    const auto source = semantic_text(fields[8]), display = semantic_text(fields[9]);
    const auto *remark = std::get_if<Value::Bytes>(&fields[10].data);
    require(remark != nullptr && remark->size() <= 99 && display == lossy_utf8(*remark) &&
                ((source == "Balances" && remark->empty() && display.empty()) ||
                 (source == "OnchainTransaction" && has_extrinsic)),
            CITIZENSDK_ERROR_INTEGRITY, "Finalized transfer source or remark is invalid");
    TransferKey key{}; std::copy(std::begin(tracked.bytes), std::end(tracked.bytes), key.owner.begin());
    key.hash = {}; std::copy(std::begin(block_value.hash.bytes), std::end(block_value.hash.bytes), key.hash.begin());
    key.event = static_cast<uint32_t>(event_index);
    require(transfer_keys.insert(key).second, CITIZENSDK_ERROR_INTEGRITY,
            "Finalized event key is duplicated");
  }
}


constexpr std::size_t kMaximumBytes = 16 * 1024 * 1024;
constexpr std::size_t kMaximumRequestCopiedBytes = kMaximumBytes + 4096;
constexpr int kLengthPreservingString = 0x43535331;
constexpr const char *kMethods[] = {
    "open", "start", "stop", "close", "getCapabilities", "getFinalizedHead", "getGenesisHash",
    "getAccountBalance", "getAccountBalances", "getAccountNonce", "getFeeSnapshot", "getWalletProfile", "viewAccountPrivateKey",
    "createWallet", "importWallet", "addWalletAccounts", "setActiveWalletAccount",
    "renameWalletAccount", "deleteWalletAccount", "deleteWallet",
    "reconcileWalletCleanup", "signWalletPayload", "verifySignature", "transferWithRemark",
    "initializeFinalizedHistory", "syncFinalizedHistory",
    "qrParse", "qrCreateSignRequest",
    "qrConsumeSignResponse", "qrCancelSignRequest", "qrEncodeAccountId",
    "qrEncodeUserTransfer", "qrDecodeLuminance", "qrEncode", "qrScan", "signQrRequest",
};
static_assert(std::size(kMethods) == 36);

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
Value hex(const uint8_t *bytes) {
  constexpr char digits[] = "0123456789abcdef";
  std::string text(66, '0'); text[1] = 'x';
  for (std::size_t i = 0; i < 32; ++i) {
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
                                 std::optional<int64_t> request_sequence)
    : std::runtime_error(std::move(message)), code(error_code),
      session(std::move(session_id)), sequence(request_sequence) {}

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
      case Method::get_capabilities: case Method::get_finalized_head: case Method::get_genesis_hash:
      case Method::get_fee_snapshot: case Method::get_wallet_profile:
      case Method::import_wallet: case Method::delete_wallet:
      case Method::reconcile_wallet_cleanup:
        (void)list(root, 3); break;
      case Method::get_account_balance: case Method::get_account_nonce:
      case Method::view_account_private_key:
      case Method::set_active_wallet_account: case Method::delete_wallet_account:
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
      case Method::rename_wallet_account: {
        (void)list(root, 5); result.account_id = account(fields[3]);
        result.name = string(fields[4], 1, 128); UnicodeInfo unicode;
        (void)inspect_utf8(result.name, &unicode);
        require(unicode.scalars <= 30 && !unicode.controls &&
                    !trim_space(unicode.first) && !trim_space(unicode.last),
                CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "name must be trimmed 1...30 Unicode scalars without controls");
        break;
      }
      case Method::sign_wallet_payload: {
        (void)list(root, 5); result.account_id = account(fields[3]);
        const auto *bytes = std::get_if<Value::Bytes>(&fields[4].data);
        require(bytes != nullptr && bytes->size() <= kMaximumBytes,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "Signing payload must be bytes of at most 16 MiB");
        result.payload = *bytes; break;
      }
      case Method::transfer_with_remark: {
        (void)list(root, 7); result.account_id = account(fields[3]);
        result.destination = account(fields[4]);
        result.amount = parse_u128(string(fields[5], 1, 39));
        require(result.amount.low != 0 || result.amount.high != 0,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "amountFen must be positive");
        const auto &remark = string(fields[6], 0, 99);
        require(remark.size() <= 99, CITIZENSDK_ERROR_INVALID_ARGUMENT,
                "remark exceeds 99 UTF-8 bytes");
        result.remark.assign(remark.begin(), remark.end()); break;
      }
      case Method::initialize_finalized_history: case Method::sync_finalized_history: {
        (void)list(root, 4); std::set<std::array<uint8_t, 32>> unique;
        for (const auto &item : bounded_list(fields[3], 1990)) {
          const auto id = account(item); std::array<uint8_t, 32> key{};
          std::copy(std::begin(id.bytes), std::end(id.bytes), key.begin());
          require(unique.insert(key).second, CITIZENSDK_ERROR_INVALID_ARGUMENT,
                  "History accounts must be unique");
          result.account_ids.push_back(id);
        }
        break;
      }
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
      case Method::qr_encode_user_transfer: {
        (void)list(root, 10); result.qr_request_id = string(fields[3], 16, 128);
        result.qr_expires_at = static_cast<uint64_t>(integer(fields[4]));
        require(result.qr_expires_at > 0, CITIZENSDK_ERROR_INVALID_ARGUMENT, "QR expiry must be positive");
        result.account_id = account(fields[5]); result.qr_amount = string(fields[6], 1, 64);
        result.qr_symbol = string(fields[7], 1, 16); result.qr_memo = string(fields[8], 0, 256);
        result.qr_bank_cid = string(fields[9], 1, 32);
        require(result.qr_amount.size() <= 64 && result.qr_symbol.size() <= 16 &&
                    result.qr_memo.size() <= 256 && result.qr_bank_cid.size() <= 32,
                CITIZENSDK_ERROR_INVALID_ARGUMENT, "QR transfer text exceeds UTF-8 limits"); break;
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
                          result.sequence > 0 ? std::optional<int64_t>(result.sequence) : std::nullopt);
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
  require(sequence > 0 && (type == "historyChanged" || type == "lifecycleChanged" || type == "capabilitiesChanged" ||
                          type == "transferProgress"),
          CITIZENSDK_ERROR_INTEGRITY, "Invalid event envelope");
  (void)response(session, sequence, payload);
  return tuple({Value::integer(kProtocolVersion), Value::string(session), Value::integer(sequence),
                Value::string(type), std::move(payload)});
}
Value error_details(citizensdk_error_code_t code, const std::string &message,
                    std::optional<std::string> session, std::optional<int64_t> sequence) {
  require(code >= 1 && code <= 22 && (!sequence || *sequence > 0) && valid_utf8(message),
          CITIZENSDK_ERROR_INTEGRITY, "Invalid error envelope");
  if (session) (void)response(*session, 0, Value::list({}));
  return tuple({Value::integer(kProtocolVersion), session ? Value::string(*session) : Value::null(),
                sequence ? Value::integer(*sequence) : Value::null(), Value::integer(code),
                Value::string(message)});
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
    throw ContractFailure(info.error_code,
                          message.empty() ? "CitizenSDK operation failed" : message);
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

Value copy_transfer(citizensdk_result_handle_t result) {
  auto value = prepared<citizensdk_wallet_transfer_info_t>();
  uint64_t required = 0;
  check_code(citizensdk_result_get_wallet_transfer(result, &value, nullptr, 0, &required));
  check_abi(value); Value::Bytes reason(copy_size(required)); uint64_t confirmed = required;
  check_code(citizensdk_result_get_wallet_transfer(
      result, &value, reason.empty() ? nullptr : reason.data(), required, &confirmed));
  require(confirmed == required && value.resolution >= CITIZENSDK_TRANSFER_FINALIZED_SUCCESS &&
              value.resolution <= CITIZENSDK_TRANSFER_POOL_REJECTED,
          CITIZENSDK_ERROR_INTEGRITY, "Core transfer result is invalid");
  const bool has_execution = flag(value.has_execution);
  constexpr const char *resolutions[] = {"finalizedSuccess", "finalizedFailed", "poolRejected"};
  return tuple({hex(value.transaction_hash), Value::string(resolutions[value.resolution - 1]),
                has_execution ? execution(value.execution) : Value::null(), nullable_text(reason)});
}

Value copy_history(citizensdk_result_handle_t result) {
  auto info = prepared<citizensdk_history_info_t>();
  check_code(citizensdk_result_get_history_info(result, &info)); check_abi(info);
  require(info.cursor_count <= 1990 && info.record_count <= 100000 &&
              info.transfer_count <= 100000,
          CITIZENSDK_ERROR_INTEGRITY, "Core history result exceeds the public contract");
  Value::List cursors; cursors.reserve(info.cursor_count);
  for (uint32_t i = 0; i < info.cursor_count; ++i) {
    auto value = prepared<citizensdk_history_cursor_info_t>();
    check_code(citizensdk_result_get_history_cursor(result, i, &value)); check_abi(value);
    cursors.push_back(tuple({hex(value.account_id.bytes), block(value.tracking_start_block),
                             block(value.last_synced_block)}));
  }
  Value::List records; records.reserve(info.record_count);
  constexpr const char *statuses[] = {"pending", "inBlock", "poolRejected",
                                      "finalizedSuccess", "finalizedFailed"};
  for (uint32_t i = 0; i < info.record_count; ++i) {
    auto value = prepared<citizensdk_history_record_info_t>();
    uint64_t remark_length = 0, reason_length = 0;
    check_code(citizensdk_result_get_history_record(result, i, &value, nullptr, 0,
        &remark_length, nullptr, 0, &reason_length)); check_abi(value);
    // Copy both variable values atomically on the second call so metadata and
    // lengths cannot be observed from different result revisions.
    Value::Bytes remark(copy_size(remark_length)), reason(copy_size(reason_length));
    uint64_t rc = remark_length, xc = reason_length;
    check_code(citizensdk_result_get_history_record(result, i, &value,
        remark.empty() ? nullptr : remark.data(), remark_length, &rc,
        reason.empty() ? nullptr : reason.data(), reason_length, &xc));
    require(rc == remark_length && xc == reason_length && value.status >= 1 && value.status <= 5 &&
                remark.size() <= 99,
            CITIZENSDK_ERROR_INTEGRITY, "Core history record is invalid");
    const bool has_block = flag(value.has_block), has_execution = flag(value.has_execution);
    records.push_back(tuple({hex(value.account_id.bytes), hex(value.transaction_hash),
        Value::string(std::to_string(value.nonce)), hex(value.destination_account_id.bytes),
        Value::string(decimal_u128(value.amount_fen)), Value::string(statuses[value.status - 1]),
        has_block ? block(value.block) : Value::null(),
        has_execution ? execution(value.execution) : Value::null(),
        Value::string(std::to_string(value.created_at_millis)),
        Value::string(std::to_string(value.updated_at_millis)), Value::string(copied_text(remark)),
        nullable_text(reason)}));
  }
  Value::List transfers; transfers.reserve(info.transfer_count);
  for (uint32_t i = 0; i < info.transfer_count; ++i) {
    auto value = prepared<citizensdk_finalized_transfer_info_t>();
    uint64_t source_length = 0, display_length = 0, bytes_length = 0;
    check_code(citizensdk_result_get_finalized_transfer(result, i, &value,
        nullptr, 0, &source_length, nullptr, 0, &display_length,
        nullptr, 0, &bytes_length)); check_abi(value);
    Value::Bytes source(copy_size(source_length)), display(copy_size(display_length)),
                 bytes(copy_size(bytes_length));
    uint64_t sc = source_length, dc = display_length, bc = bytes_length;
    check_code(citizensdk_result_get_finalized_transfer(result, i, &value,
        source.empty() ? nullptr : source.data(), source_length, &sc,
        display.empty() ? nullptr : display.data(), display_length, &dc,
        bytes.empty() ? nullptr : bytes.data(), bytes_length, &bc));
    require(sc == source_length && dc == display_length && bc == bytes_length &&
                value.direction >= CITIZENSDK_TRANSFER_OUTGOING &&
                value.direction <= CITIZENSDK_TRANSFER_INCOMING && bytes.size() <= 99,
            CITIZENSDK_ERROR_INTEGRITY, "Core finalized transfer is invalid");
    transfers.push_back(tuple({hex(value.tracked_account_id.bytes), hex(value.from_account_id.bytes),
        hex(value.to_account_id.bytes), Value::string(decimal_u128(value.amount_fen)), block(value.block),
        Value::integer(value.event_record_index),
        flag(value.has_extrinsic_index) ? Value::integer(value.extrinsic_index) : Value::null(),
        Value::string(value.direction == CITIZENSDK_TRANSFER_OUTGOING ? "outgoing" : "incoming"),
        Value::string(copied_text(source)), Value::string(copied_text(display)), Value::bytes(std::move(bytes))}));
  }
  return tuple({Value::string(std::to_string(info.revision)), Value::list(std::move(cursors)),
                Value::list(std::move(records)), Value::list(std::move(transfers))});
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
    case Method::get_finalized_head:
      (void)inspect_result(result, CITIZENSDK_RESULT_BLOCK_REF);
      { auto value = prepared<citizensdk_block_ref_t>();
        check_code(citizensdk_result_get_block_ref(result, &value));
        return checked(tuple({block(value)})); }
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
    case Method::transfer_with_remark:
      (void)inspect_result(result, CITIZENSDK_RESULT_WALLET_TRANSFER);
      return checked(tuple({copy_transfer(result)}));
    case Method::initialize_finalized_history: case Method::sync_finalized_history:
      (void)inspect_result(result, CITIZENSDK_RESULT_TRANSACTION_HISTORY);
      return checked(tuple({copy_history(result)}));
    case Method::view_account_private_key:
    case Method::verify_signature:
    case Method::open: case Method::close: case Method::get_capabilities: case Method::get_genesis_hash:
    case Method::qr_parse: case Method::qr_create_sign_request:
    case Method::qr_scan: case Method::sign_qr_request:
    case Method::qr_consume_sign_response: case Method::qr_cancel_sign_request:
    case Method::qr_encode_account_id: case Method::qr_encode_user_transfer:
    case Method::qr_decode_luminance: case Method::qr_encode:
      fail(CITIZENSDK_ERROR_INVALID_STATE, "This method has no borrowed Core result");
  }
  fail(CITIZENSDK_ERROR_UNSUPPORTED, "Unsupported result method");
}

Value watch_payload(citizensdk_result_handle_t result, int64_t request_sequence) {
  (void)inspect_result(result, CITIZENSDK_RESULT_WATCH_EVENT);
  auto value = prepared<citizensdk_watch_event_info_t>();
  check_code(citizensdk_result_get_watch_event(result, &value)); check_abi(value);
  require(request_sequence > 0 && value.status >= CITIZENSDK_WATCH_READY &&
              value.status <= CITIZENSDK_WATCH_USURPED,
          CITIZENSDK_ERROR_INTEGRITY, "Core watch progress is invalid");
  constexpr const char *statuses[] = {"ready", "broadcast", "future", "inBlock", "finalized",
      "retracted", "finalityTimeout", "dropped", "invalid", "usurped"};
  const bool has_block = flag(value.has_block), replacement = flag(value.has_replacement_hash);
  auto payload = tuple({Value::integer(request_sequence), Value::string(statuses[value.status - 1]),
                has_block ? block(value.block) : Value::null(),
                replacement ? hex(value.replacement_hash) : Value::null(),
                Value::integer(value.peer_count)});
  validate_watch_value(payload);
  return payload;
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
    const auto &fields = semantic_tuple(value, 1);
    const auto &item = fields[0];
    switch (method) {
      case Method::get_finalized_head:
        require(semantic_block(item).finalized, CITIZENSDK_ERROR_INTEGRITY,
                "Finalized head must reference a finalized block"); return;
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
      case Method::sign_wallet_payload: {
        const auto *bytes = std::get_if<Value::Bytes>(&item.data);
        require(bytes != nullptr && bytes->size() == 64, CITIZENSDK_ERROR_INTEGRITY,
                "sr25519 public signature must be 64 bytes"); return;
      }
      case Method::verify_signature:
        require(std::holds_alternative<bool>(item.data), CITIZENSDK_ERROR_INTEGRITY,
                "Verification result must be bool"); return;
      case Method::transfer_with_remark: validate_transfer(item); return;
      case Method::initialize_finalized_history: case Method::sync_finalized_history:
        validate_history(item); return;
      case Method::view_account_private_key:
      case Method::open: case Method::start: case Method::stop: case Method::close:
      case Method::get_capabilities:
      case Method::qr_parse: case Method::qr_create_sign_request:
      case Method::qr_scan: case Method::sign_qr_request:
      case Method::qr_consume_sign_response: case Method::qr_cancel_sign_request:
      case Method::qr_encode_account_id: case Method::qr_encode_user_transfer:
      case Method::qr_decode_luminance: case Method::qr_encode:
        fail(CITIZENSDK_ERROR_INVALID_STATE, "This method uses its dedicated lifecycle/capability encoder");
    }
  } catch (const ContractFailure &error) {
    if (error.code == CITIZENSDK_ERROR_INVALID_STATE) throw;
    throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY, error.what());
  }
}

void validate_watch_value(const Value &value) {
  try {
    const auto &fields = semantic_tuple(value, 5);
    require(semantic_int(fields[0]) > 0, CITIZENSDK_ERROR_INTEGRITY,
            "Transfer progress request sequence must be positive");
    const auto status = semantic_text(fields[1]);
    const bool has_block = !null_value(fields[2]), replacement = !null_value(fields[3]);
    std::optional<SemanticBlock> block_value;
    if (has_block) block_value = semantic_block(fields[2]);
    if (replacement) (void)account(fields[3]);
    const auto peers = semantic_int(fields[4], UINT32_MAX);
    const bool valid =
        ((status == "ready" || status == "future" || status == "dropped" || status == "invalid") &&
         !has_block && !replacement && peers == 0) ||
        (status == "broadcast" && !has_block && !replacement) ||
        ((status == "inBlock" || status == "retracted") && has_block && !replacement && peers == 0) ||
        (status == "finalized" && has_block && block_value->finalized && !replacement && peers == 0) ||
        (status == "finalityTimeout" && !replacement && peers == 0) ||
        (status == "usurped" && !has_block && replacement && peers == 0);
    require(valid, CITIZENSDK_ERROR_INTEGRITY, "Transfer progress status fields disagree");
  } catch (const ContractFailure &error) {
    throw ContractFailure(CITIZENSDK_ERROR_INTEGRITY, error.what());
  }
}

}  // namespace citizen_sdk::flutter
