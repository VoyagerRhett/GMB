use std::collections::BTreeSet;

use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use citizen_sdk_contracts::{
    apply_signing_transform, AccountId32, SigningTransform, Sr25519PublicKey, Sr25519Signature,
};
use serde::de::{self, Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use serde_json::{Map, Value};

use crate::{QrClock, SystemQrClock};

pub const QR_V1: &str = "QR_V1";
/// QR Code Model 2、纠错等级 M 的最大字节容量。
pub const MAX_QR_TEXT_BYTES: usize = 2_331;
pub const MAX_QR_JSON_BYTES: usize = 65_536;
const MAX_REVIEW_PAYLOAD_BYTES: usize = 1_920;
const MAX_REQUEST_ID_BYTES: usize = 128;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QrErrorCode {
    InvalidFormat,
    InvalidField,
    UnsupportedKind,
    Expired,
    MismatchedRequest,
    MismatchedAccount,
    AlreadyConsumed,
    InvalidSignature,
    CapacityExceeded,
    EntropyUnavailable,
    ClockUnavailable,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct QrError {
    code: QrErrorCode,
    message: &'static str,
}

impl QrError {
    pub const fn new(code: QrErrorCode, message: &'static str) -> Self {
        Self { code, message }
    }

    pub const fn code(&self) -> QrErrorCode {
        self.code
    }

    pub const fn message(&self) -> &'static str {
        self.message
    }
}

impl std::fmt::Display for QrError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.message)
    }
}

impl std::error::Error for QrError {}

pub type QrResult<T> = Result<T, QrError>;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SignRequest {
    pub request_id: String,
    pub expires_at: u64,
    pub action: u16,
    pub signer_public_key: Sr25519PublicKey,
    pub review_payload: Vec<u8>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SignResponse {
    pub request_id: String,
    pub expires_at: u64,
    pub signer_public_key: Sr25519PublicKey,
    pub signature: Sr25519Signature,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AccountIdCode {
    pub account_id: AccountId32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum QrCode {
    SignRequest(SignRequest),
    SignResponse(SignResponse),
    AccountId(AccountIdCode),
}

/// 生产解析只使用 SDK 时钟；测试钟不会进入 FFI 或平台调用合同。
pub fn parse(raw: &str) -> QrResult<QrCode> {
    let now = SystemQrClock.now_epoch_seconds();
    if now == 0 {
        return Err(QrError::new(
            QrErrorCode::ClockUnavailable,
            "系统时钟不可用",
        ));
    }
    parse_at(raw, now)
}

pub(crate) fn parse_at(raw: &str, now_epoch_seconds: u64) -> QrResult<QrCode> {
    if raw.is_empty() || raw.len() > MAX_QR_TEXT_BYTES {
        return Err(QrError::new(
            QrErrorCode::CapacityExceeded,
            "二维码文本为空或超过单码容量",
        ));
    }
    let value = serde_json::from_str::<StrictValue>(raw)
        .map_err(|_| QrError::new(QrErrorCode::InvalidFormat, "二维码不是规范 JSON"))?
        .0;
    let envelope = object(&value, "二维码 envelope 必须是对象")?;
    if string(envelope, "p")? != QR_V1 {
        return Err(QrError::new(
            QrErrorCode::InvalidField,
            "二维码协议必须是 QR_V1",
        ));
    }
    let kind = unsigned(envelope, "k")?;
    // QR_V1 只保留通用签名请求、签名响应和账户公钥。已删除的业务 kind 数值永久留空，不得复用。
    match kind {
        1 => parse_sign_request(envelope, now_epoch_seconds),
        2 => parse_sign_response(envelope, now_epoch_seconds),
        5 => parse_account_id(envelope),
        _ => Err(QrError::new(
            QrErrorCode::UnsupportedKind,
            "CitizenSDK 不处理该二维码类型",
        )),
    }
}

impl QrCode {
    /// 五端唯一公开投影。协议短键、base64 和签名账户转换只在此处处理。
    pub fn normalized(&self) -> QrResult<Value> {
        let mut value = match self {
            Self::SignRequest(v) => serde_json::json!({
                "kind": 1, "canonical_text": v.encode()?, "request_id": v.request_id,
                "expires_at": v.expires_at, "action": v.action,
                "signer_account_id": hex(v.signer_public_key.as_bytes()),
                "review_payload": hex(&v.review_payload),
            }),
            Self::SignResponse(v) => serde_json::json!({
                "kind": 2, "canonical_text": v.encode()?, "request_id": v.request_id,
                "expires_at": v.expires_at,
                "signer_account_id": hex(v.signer_public_key.as_bytes()),
                "signature": hex(v.signature.as_bytes()),
            }),
            Self::AccountId(v) => serde_json::json!({
                "kind": 5, "canonical_text": v.encode()?, "account_id": hex(v.account_id.as_bytes()),
            }),
        };
        // 显式对象保证平台不必处理多种返回形状。
        if !value.is_object() {
            return Err(invalid_field("二维码公开投影不是对象"));
        }
        Ok(std::mem::take(&mut value))
    }
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    let mut text = String::with_capacity(2 + bytes.len() * 2);
    text.push_str("0x");
    for byte in bytes {
        let _ = write!(text, "{byte:02x}");
    }
    text
}

impl SignRequest {
    /// 仅供 SDK Rust 审阅/验签管线使用，不是公开语言绑定的拆分签名入口。
    #[doc(hidden)]
    pub fn signing_message(&self) -> QrResult<Vec<u8>> {
        signing_bytes(&self.review_payload)
    }

    pub fn encode(&self) -> QrResult<String> {
        validate_request_id(&self.request_id)?;
        validate_expiry_value(self.expires_at)?;
        if self.review_payload.is_empty() {
            return Err(invalid_field("签名请求的期限和审阅载荷不能为空"));
        }
        if self.review_payload.len() > MAX_REVIEW_PAYLOAD_BYTES {
            return Err(QrError::new(
                QrErrorCode::CapacityExceeded,
                "审阅载荷超过单码安全上限",
            ));
        }
        checked_json(serde_json::json!({
            "p": QR_V1,
            "k": 1,
            "i": self.request_id,
            "e": self.expires_at,
            "b": {
                "a": self.action,
                "g": 1,
                "u": URL_SAFE_NO_PAD.encode(self.signer_public_key.as_bytes()),
                "d": URL_SAFE_NO_PAD.encode(&self.review_payload),
            }
        }))
    }
}

impl SignResponse {
    pub fn encode(&self) -> QrResult<String> {
        validate_request_id(&self.request_id)?;
        validate_expiry_value(self.expires_at)?;
        checked_json(serde_json::json!({
            "p": QR_V1,
            "k": 2,
            "i": self.request_id,
            "e": self.expires_at,
            "b": {
                "u": URL_SAFE_NO_PAD.encode(self.signer_public_key.as_bytes()),
                "s": URL_SAFE_NO_PAD.encode(self.signature.as_bytes()),
            }
        }))
    }
}

impl AccountIdCode {
    pub fn encode(&self) -> QrResult<String> {
        checked_json(serde_json::json!({
            "p": QR_V1,
            "k": 5,
            "b": {"n": account_id_text(self.account_id)}
        }))
    }
}

/// Substrate `SignedPayload::using_encoded` 的唯一签名字节规则。
pub(crate) fn signing_bytes(review_payload: &[u8]) -> QrResult<Vec<u8>> {
    if review_payload.len() > MAX_REVIEW_PAYLOAD_BYTES {
        return Err(invalid_field("review_payload 长度无效"));
    }
    apply_signing_transform(review_payload, &SigningTransform::SubstrateSigningPayload)
        .map_err(|_| invalid_field("review_payload 长度无效"))
}

fn parse_sign_request(envelope: &Map<String, Value>, now: u64) -> QrResult<QrCode> {
    exact_keys(envelope, &["p", "k", "i", "e", "b"])?;
    let request_id = string(envelope, "i")?.to_owned();
    validate_request_id(&request_id)?;
    let expires_at = unsigned(envelope, "e")?;
    validate_expiry(expires_at, now)?;
    let body = object(field(envelope, "b")?, "签名请求 body 必须是对象")?;
    exact_keys(body, &["a", "g", "u", "d"])?;
    let action =
        u16::try_from(unsigned(body, "a")?).map_err(|_| invalid_field("签名动作超出 u16"))?;
    if unsigned(body, "g")? != 1 {
        return Err(invalid_field("签名算法只允许 sr25519"));
    }
    let signer_public_key = Sr25519PublicKey::from_bytes(decode_fixed::<32>(
        string(body, "u")?,
        "signer_public_key 长度或编码无效",
    )?);
    let review_payload = decode(string(body, "d")?, MAX_REVIEW_PAYLOAD_BYTES)?;
    if review_payload.is_empty() {
        return Err(invalid_field("review_payload 不能为空"));
    }
    Ok(QrCode::SignRequest(SignRequest {
        request_id,
        expires_at,
        action,
        signer_public_key,
        review_payload,
    }))
}

fn parse_sign_response(envelope: &Map<String, Value>, now: u64) -> QrResult<QrCode> {
    exact_keys(envelope, &["p", "k", "i", "e", "b"])?;
    let request_id = string(envelope, "i")?.to_owned();
    validate_request_id(&request_id)?;
    let expires_at = unsigned(envelope, "e")?;
    validate_expiry(expires_at, now)?;
    let body = object(field(envelope, "b")?, "签名响应 body 必须是对象")?;
    exact_keys(body, &["u", "s"])?;
    Ok(QrCode::SignResponse(SignResponse {
        request_id,
        expires_at,
        signer_public_key: Sr25519PublicKey::from_bytes(decode_fixed::<32>(
            string(body, "u")?,
            "signer_public_key 长度或编码无效",
        )?),
        signature: Sr25519Signature::from_bytes(decode_fixed::<64>(
            string(body, "s")?,
            "signature 长度或编码无效",
        )?),
    }))
}

fn parse_account_id(envelope: &Map<String, Value>) -> QrResult<QrCode> {
    exact_keys(envelope, &["p", "k", "b"])?;
    let body = object(field(envelope, "b")?, "账户码 body 必须是对象")?;
    exact_keys(body, &["n"])?;
    Ok(QrCode::AccountId(AccountIdCode {
        account_id: AccountId32::from_bytes(decode_account_id(string(body, "n")?)?),
    }))
}

/// serde_json 的默认 Value 会覆盖重复对象键；QR_V1 在覆盖发生前失败关闭。
struct StrictValue(Value);

impl<'de> Deserialize<'de> for StrictValue {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_any(StrictValueVisitor)
    }
}

struct StrictValueVisitor;

impl<'de> Visitor<'de> for StrictValueVisitor {
    type Value = StrictValue;

    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("无重复对象键的 JSON 值")
    }

    fn visit_bool<E: de::Error>(self, value: bool) -> Result<Self::Value, E> {
        Ok(StrictValue(Value::Bool(value)))
    }

    fn visit_i64<E: de::Error>(self, value: i64) -> Result<Self::Value, E> {
        Ok(StrictValue(Value::Number(value.into())))
    }

    fn visit_u64<E: de::Error>(self, value: u64) -> Result<Self::Value, E> {
        Ok(StrictValue(Value::Number(value.into())))
    }

    fn visit_f64<E: de::Error>(self, value: f64) -> Result<Self::Value, E> {
        serde_json::Number::from_f64(value)
            .map(Value::Number)
            .map(StrictValue)
            .ok_or_else(|| E::custom("JSON 浮点数无效"))
    }

    fn visit_str<E: de::Error>(self, value: &str) -> Result<Self::Value, E> {
        Ok(StrictValue(Value::String(value.to_owned())))
    }

    fn visit_string<E: de::Error>(self, value: String) -> Result<Self::Value, E> {
        Ok(StrictValue(Value::String(value)))
    }

    fn visit_none<E: de::Error>(self) -> Result<Self::Value, E> {
        Ok(StrictValue(Value::Null))
    }

    fn visit_unit<E: de::Error>(self) -> Result<Self::Value, E> {
        Ok(StrictValue(Value::Null))
    }

    fn visit_seq<A>(self, mut sequence: A) -> Result<Self::Value, A::Error>
    where
        A: SeqAccess<'de>,
    {
        let mut values = Vec::new();
        while let Some(value) = sequence.next_element::<StrictValue>()? {
            values.push(value.0);
        }
        Ok(StrictValue(Value::Array(values)))
    }

    fn visit_map<A>(self, mut entries: A) -> Result<Self::Value, A::Error>
    where
        A: MapAccess<'de>,
    {
        let mut values = Map::new();
        while let Some(key) = entries.next_key::<String>()? {
            if values.contains_key(&key) {
                return Err(de::Error::custom("JSON 对象含重复键"));
            }
            values.insert(key, entries.next_value::<StrictValue>()?.0);
        }
        Ok(StrictValue(Value::Object(values)))
    }
}

fn account_id_text(account_id: AccountId32) -> String {
    let mut output = String::with_capacity(66);
    output.push_str("0x");
    for byte in account_id.as_bytes() {
        use std::fmt::Write as _;
        let _ = write!(output, "{byte:02x}");
    }
    output
}

fn validate_request_id(request_id: &str) -> QrResult<()> {
    if request_id.len() < 16
        || request_id.len() > MAX_REQUEST_ID_BYTES
        || !request_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'-')
    {
        return Err(invalid_field("request_id 格式无效"));
    }
    Ok(())
}

fn validate_expiry(expires_at: u64, now: u64) -> QrResult<()> {
    validate_expiry_value(expires_at)?;
    if expires_at <= now {
        return Err(QrError::new(QrErrorCode::Expired, "二维码已经过期"));
    }
    Ok(())
}

fn validate_expiry_value(expires_at: u64) -> QrResult<()> {
    // 五端 JSON 整数共同的精确正 Unix 秒域，不能让平台分别截断或转 Double。
    if expires_at == 0 || expires_at > i64::MAX as u64 {
        return Err(invalid_field("二维码过期时间必须位于 1..i64::MAX"));
    }
    Ok(())
}

fn checked_json(value: Value) -> QrResult<String> {
    let encoded = serde_json::to_string(&value)
        .map_err(|_| QrError::new(QrErrorCode::InvalidFormat, "二维码编码失败"))?;
    if encoded.len() > MAX_QR_TEXT_BYTES {
        return Err(QrError::new(
            QrErrorCode::CapacityExceeded,
            "二维码文本超过单码容量",
        ));
    }
    Ok(encoded)
}

fn exact_keys(object: &Map<String, Value>, expected: &[&str]) -> QrResult<()> {
    let actual = object.keys().map(String::as_str).collect::<BTreeSet<_>>();
    let expected = expected.iter().copied().collect::<BTreeSet<_>>();
    if actual != expected {
        return Err(invalid_field("二维码字段集合不符合 QR_V1"));
    }
    Ok(())
}

fn decode(value: &str, max: usize) -> QrResult<Vec<u8>> {
    if value.contains('=') {
        return Err(invalid_field("base64url 不允许填充"));
    }
    let bytes = URL_SAFE_NO_PAD
        .decode(value)
        .map_err(|_| invalid_field("base64url 编码无效"))?;
    if bytes.len() > max || URL_SAFE_NO_PAD.encode(&bytes) != value {
        return Err(invalid_field("base64url 不是规范编码或超过长度"));
    }
    Ok(bytes)
}

fn decode_fixed<const N: usize>(value: &str, message: &'static str) -> QrResult<[u8; N]> {
    let bytes = decode(value, N)?;
    bytes
        .try_into()
        .map_err(|_| QrError::new(QrErrorCode::InvalidField, message))
}

fn decode_account_id(value: &str) -> QrResult<[u8; 32]> {
    let text = value
        .strip_prefix("0x")
        .ok_or_else(|| invalid_field("account_id 必须使用小写 0x 十六进制"))?;
    if text.len() != 64 || !text.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(invalid_field("account_id 长度或字符无效"));
    }
    if text.bytes().any(|byte| byte.is_ascii_uppercase()) {
        return Err(invalid_field("account_id 必须使用小写十六进制"));
    }
    let mut output = [0_u8; 32];
    for (index, chunk) in text.as_bytes().chunks_exact(2).enumerate() {
        let pair = std::str::from_utf8(chunk).map_err(|_| invalid_field("account_id 无效"))?;
        output[index] =
            u8::from_str_radix(pair, 16).map_err(|_| invalid_field("account_id 无效"))?;
    }
    Ok(output)
}

fn object<'a>(value: &'a Value, message: &'static str) -> QrResult<&'a Map<String, Value>> {
    value
        .as_object()
        .ok_or_else(|| QrError::new(QrErrorCode::InvalidField, message))
}

fn field<'a>(object: &'a Map<String, Value>, key: &str) -> QrResult<&'a Value> {
    object
        .get(key)
        .ok_or_else(|| invalid_field("二维码缺少必填字段"))
}

fn string<'a>(object: &'a Map<String, Value>, key: &str) -> QrResult<&'a str> {
    field(object, key)?
        .as_str()
        .ok_or_else(|| invalid_field("二维码字段必须是字符串"))
}

fn unsigned(object: &Map<String, Value>, key: &str) -> QrResult<u64> {
    field(object, key)?
        .as_u64()
        .ok_or_else(|| invalid_field("二维码字段必须是非负整数"))
}

const fn invalid_field(message: &'static str) -> QrError {
    QrError::new(QrErrorCode::InvalidField, message)
}

#[cfg(test)]
mod tests {
    use super::*;
    // 只有纯协议测试可注入时间；生产入口始终读取 SDK 时钟。
    use super::parse_at as parse;

    fn request() -> SignRequest {
        SignRequest {
            request_id: "0123456789abcdef".to_owned(),
            expires_at: 100,
            action: 0x0400,
            signer_public_key: Sr25519PublicKey::from_bytes([7; 32]),
            review_payload: vec![0x04, 0x00, 3],
        }
    }

    #[test]
    fn sign_request_round_trip_is_strict() {
        let encoded = request().encode().unwrap();
        assert_eq!(parse(&encoded, 99), Ok(QrCode::SignRequest(request())));
    }

    #[test]
    fn rejects_unknown_fields_but_accepts_any_opaque_u16_action() {
        let encoded = request().encode().unwrap();
        let injected = encoded.replacen("{\"a\"", "{\"extra\":true,\"a\"", 1);
        assert_eq!(
            parse(&injected, 99).unwrap_err().code(),
            QrErrorCode::InvalidField
        );
        let mut request = request();
        request.action = 2;
        request.review_payload = b"third-party opaque payload".to_vec();
        let encoded = request.encode().unwrap();
        assert_eq!(parse(&encoded, 99), Ok(QrCode::SignRequest(request)));
    }

    #[test]
    fn retired_business_kind_is_not_a_transport_document() {
        let text = r#"{"p":"QR_V1","k":4,"i":"0123456789abcdef","e":100,"b":{}}"#;
        assert_eq!(
            parse(text, 99).unwrap_err().code(),
            QrErrorCode::UnsupportedKind
        );
    }

    #[test]
    fn rejects_duplicate_keys_without_imposing_payload_action_semantics() {
        let encoded = request().encode().unwrap();
        // serde_json 的对象键序不是协议合同的一部分；直接在根对象首位插入
        // 第二个 `p`，保证无论规范编码的键顺序如何都确实形成重复键。
        let duplicate = format!("{{\"p\":\"QR_V1\",{}", &encoded[1..]);
        assert_eq!(
            parse(&duplicate, 99).unwrap_err().code(),
            QrErrorCode::InvalidFormat
        );
        let mut mismatched = request();
        mismatched.review_payload[1] = 1;
        let encoded = mismatched.encode().unwrap();
        assert_eq!(parse(&encoded, 99), Ok(QrCode::SignRequest(mismatched)));
    }

    #[test]
    fn rejects_expired_and_oversized_values() {
        assert_eq!(
            parse(&request().encode().unwrap(), 100).unwrap_err().code(),
            QrErrorCode::Expired
        );
        assert_eq!(
            parse(&"x".repeat(MAX_QR_TEXT_BYTES + 1), 0)
                .unwrap_err()
                .code(),
            QrErrorCode::CapacityExceeded
        );
    }

    #[test]
    fn expiry_uses_the_same_exact_positive_i64_domain_in_every_wire_kind() {
        let mut request = request();
        request.expires_at = i64::MAX as u64;
        let response = SignResponse {
            request_id: request.request_id.clone(),
            expires_at: request.expires_at,
            signer_public_key: request.signer_public_key,
            signature: Sr25519Signature::from_bytes([0; 64]),
        };
        for text in [request.encode().unwrap(), response.encode().unwrap()] {
            assert!(parse(&text, 99).is_ok());
            let invalid = text.replace(&i64::MAX.to_string(), &(i64::MAX as u64 + 1).to_string());
            assert_eq!(
                parse(&invalid, 99).unwrap_err().code(),
                QrErrorCode::InvalidField
            );
        }
        request.expires_at += 1;
        assert_eq!(
            request.encode().unwrap_err().code(),
            QrErrorCode::InvalidField
        );
        let mut response = response;
        response.expires_at += 1;
        assert_eq!(
            response.encode().unwrap_err().code(),
            QrErrorCode::InvalidField
        );
    }
}
