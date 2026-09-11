import Foundation

/// 安全签名的完整结果；响应文档与二维码由同一次 Core 结果生成。
public struct CitizenQRSigned: Sendable, Equatable {
    public let document: CitizenQRDocument
    public let qrImage: CitizenQRImage
}

/// 字段只来自 Rust 展开结果，不解析 QR_V1 短键，也不在平台复算签名载荷。
public struct CitizenQRDocument: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case signRequest(requestID: String, expiresAt: UInt64, action: UInt16,
                         signerAccountID: String, reviewPayload: String)
        case signResponse(requestID: String, expiresAt: UInt64, signerAccountID: String, signature: String)
        case accountID(String)
    }
    public let kind: UInt32
    public let canonicalText: String
    public let content: Content
    /// 仅签名成功结果携带原规范请求；普通解析结果不伪造关联信息。
    public let signRequest: String?
    @_spi(CitizenSDKFlutter) public let coreJSON: String
    internal var signedImage: CitizenQRImage?

    internal init(coreJSON: String) throws {
        let value = try CitizenSDKQrProjection.decode(coreJSON)
        self.coreJSON = coreJSON; kind = value.kind; canonicalText = value.canonical_text
        signRequest = value.sign_request
        if let expiration = value.expires_at {
            guard expiration > 0, expiration <= UInt64(Int64.max) else {
                throw CitizenSDKError(.integrity, "Core QR 时间不在统一正 i64 域内")
            }
        }
        switch kind {
        case 1:
            content = .signRequest(requestID: try value.required(value.request_id),
                expiresAt: try value.required(value.expires_at), action: try value.required(value.action),
                signerAccountID: try value.hex(value.signer_account_id, count: 32),
                reviewPayload: try value.hex(value.review_payload))
        case 2:
            content = .signResponse(requestID: try value.required(value.request_id),
                expiresAt: try value.required(value.expires_at),
                signerAccountID: try value.hex(value.signer_account_id, count: 32),
                signature: try value.hex(value.signature, count: 64))
        case 5: content = .accountID(try value.hex(value.account_id, count: 32))
        default: throw CitizenSDKError(.integrity, "Core QR kind is invalid")
        }
    }
}

/// 此模型只解码 Core 的可信输出结构，不是第二个二维码协议解析器。
internal struct CitizenSDKQrProjection: Decodable {
    let kind: UInt32
    let canonical_text: String
    let request_id: String?
    let expires_at: UInt64?
    let action: UInt16?
    let signer_account_id: String?
    let review_payload: String?
    let signature: String?
    let account_id: String?
    let sign_request: String?
    let pallet_name: String?
    let call_name: String?
    let call_arguments: String?
    let genesis_hash: String?
    let spec_version: UInt32?
    let transaction_version: UInt32?
    let era: String?
    let nonce: String?
    let tip: String?
    let block_hash: String?

    static func decode(_ json: String) throws -> Self {
        let data = Data(json.utf8)
        guard !data.isEmpty, data.count <= 65_536 else { throw CitizenSDKError(.integrity, "Core QR JSON length is invalid") }
        do {
            let value = try JSONDecoder().decode(Self.self, from: data)
            guard !value.canonical_text.isEmpty, value.canonical_text.utf8.count <= 2_331 else {
                throw CitizenSDKError(.integrity, "Core QR canonical text is invalid")
            }
            return value
        } catch { throw CitizenSDKError(.integrity, "Core QR JSON is invalid") }
    }

    func required<T>(_ value: T?) throws -> T {
        guard let value else { throw CitizenSDKError(.integrity, "Core QR field is missing") }
        return value
    }

    func hex(_ value: String?, count: Int? = nil) throws -> String {
        let value = try required(value)
        let bytes = Array(value.utf8)
        guard bytes.count >= 2, bytes[0] == 48, bytes[1] == 120, bytes.count % 2 == 0,
              count.map({ bytes.count == 2 + $0 * 2 }) ?? true,
              bytes.dropFirst(2).allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw CitizenSDKError(.integrity, "Core QR byte field is invalid")
        }
        return value
    }

    func reviewText() throws -> String {
        guard kind == 1 else { throw CitizenSDKError(.integrity, "Core QR review kind is invalid") }
        // 不截断、不省略参数；Core 已为控制字符提供无损转义，原生只作纯文本显示。
        return """
        请求：\(try required(request_id))
        签名账户：\(try hex(signer_account_id, count: 32))
        到期时间：\(try required(expires_at))
        操作：\(try required(action))
        调用：\(try required(pallet_name)).\(try required(call_name))
        参数：\(try required(call_arguments))
        创世哈希：\(try hex(genesis_hash, count: 32))
        Runtime：\(try required(spec_version)) / 交易版本：\(try required(transaction_version))
        Era：\(try required(era))
        Nonce：\(try required(nonce))
        Tip：\(try required(tip))
        区块哈希：\(try hex(block_hash, count: 32))
        完整审阅载荷：\(try hex(review_payload))
        """
    }
}

/// Review 句柄的唯一内部所有者；确认后按同一结果签名，取消或释放时归还 Core。
internal final class CitizenSDKQrReview: @unchecked Sendable {
    let text: String
    let document: CitizenQRDocument
    private let lock = NSLock()
    private var result: UInt64
    init(result: UInt64, json: String) throws {
        let projection = try CitizenSDKQrProjection.decode(json)
        text = try projection.reviewText(); document = try CitizenQRDocument(coreJSON: json)
        self.result = result
    }
    func withResult<T>(_ body: (UInt64) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard result != 0 else { throw CitizenSDKError(.invalidState, "QR review was already released") }
        return try body(result)
    }
    func release() {
        lock.lock(); let owned = result; result = 0; lock.unlock()
        if owned != 0 { _ = citizensdk_result_release(owned) }
    }
    deinit { release() }
}

public struct CitizenQRImage: Sendable, Equatable {
    public let width: UInt32
    public let height: UInt32
    public let luminance: Data
}
