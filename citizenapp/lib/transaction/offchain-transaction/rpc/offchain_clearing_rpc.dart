import 'dart:convert';
import 'dart:io';

/// 扫码支付清算体系:**清算行节点** JSON-RPC 客户端。
///
///
/// - 对接 `citizenchain/node/src/transaction/offchain_transaction/rpc.rs::OffchainClearingRpcImpl`,
///   命名空间 `offchain`。
/// - 余额查询与缓存唯一归 wallet；本类只提供通用 RPC 传输及支付协议方法。
/// - Step 2c-i 起补充 `submitPayment`(扫码付款提交)+ `queryUserBank`(付款方
///   绑定的清算行查询)+ `queryFeeRate`(费率查询)。WebSocket 订阅(实时 push
///   settlement 回执)留后续里程碑。
/// - WebSocket(WSS)直连清算行节点;所有方法都会短时连入 → 发送 → 读首帧 → 关闭。
/// - 调用方应根据 L3 当前绑定的清算行把 `wssUrl` 指向对应节点。
class OffchainClearingBankRpc {
  /// [wssUrl] 清算行节点的 WebSocket URL,例如 `wss://l2.example.com:9944`。
  /// 由调用方根据用户绑定的清算行实际地址注入。
  OffchainClearingBankRpc(this.wssUrl);

  final String wssUrl;

  /// 查询 L3 下一个应使用的支付 nonce(Step 2 扫码支付前调用)。
  Future<int> queryNextNonce(String userAccountId) async {
    final result = await call('offchain_queryNextNonce', [userAccountId]);
    return _parseInt(result, fallback: 1);
  }

  /// 查询本清算行待上链笔数(运维查看)。
  Future<int> queryPendingCount() async {
    final result = await call('offchain_queryPendingCount', const []);
    return _parseInt(result, fallback: 0);
  }

  /// 查询 L3 当前绑定的清算行主账户 SS58 地址,未绑定返回 `null`。
  ///
  /// 对应节点侧 `UserBank[user]` storage。返回该用户绑定清算行的 **CID 文本**
  /// (机构唯一永久主键);扫码付款前调用以确定 `payer_bank_cid` / `recipient_bank_cid`。
  Future<String?> queryUserBank(String userAccountId) async {
    final result = await call('offchain_queryUserBank', [userAccountId]);
    if (result == null) return null;
    if (result is String) return result;
    throw Exception('offchain_queryUserBank 返回类型异常:$result');
  }

  /// 查询指定清算行当前费率。
  ///
  /// 返回 `(rateBp, minFeeFen)`:`rateBp` 是万分之一(runtime `L2FeeRateBp` 存储值),
  /// `minFeeFen` 是节点侧常量下限(当前 1 分)。调用方据此本地预计算 `fee_amount`:
  /// `fee = max(round(amount * rateBp / 10000), minFeeFen)`,四舍五入规则与
  /// runtime `fee_config::calc_fee` 对齐(余数 ≥ 5000 进位)。
  Future<({int rateBp, int minFeeFen})> queryFeeRate(String bankCid) async {
    final result = await call('offchain_queryFeeRate', [bankCid]);
    if (result is! Map) {
      throw Exception('offchain_queryFeeRate 返回类型异常:$result');
    }
    final map = result.cast<String, dynamic>();
    final rateBp = _parseInt(map['rate_bp'] ?? map['rateBp'], fallback: 0);
    final minFeeFen = _parseInt(
      map['min_fee_fen'] ?? map['minFeeFen'],
      fallback: 1,
    );
    return (rateBp: rateBp, minFeeFen: minFeeFen);
  }

  /// 扫码付款提交。
  ///
  /// [intentHex] 是 `NodePaymentIntent` 的 SCALE 编码 hex(含 `0x` 前缀);
  /// [payerSigHex] 是 L3 sr25519 对
  /// `signing_message(OP_SIGN_L3_PAY=0x15, SCALE(intent))`
  /// = `blake2_256(GMB || 0x15 || SCALE(intent))` 的 64 字节签名 hex(含 `0x`
  /// 前缀)。
  ///
  /// 返回 `(txId, l2AckSig, acceptedAt)`:
  /// - `txId`:本笔支付 tx_id hex(与 intent 中同)
  /// - `l2AckSig`:清算行 ACK 签名 hex(Step 2b-i 为全零占位,Step 3 启用)
  /// - `acceptedAt`:节点接受本笔的 UNIX 秒时间戳
  Future<({String txId, String l2AckSig, int acceptedAt})> submitPayment({
    required String intentHex,
    required String payerSigHex,
  }) async {
    final result = await call('offchain_submitPayment', [
      intentHex,
      payerSigHex,
    ]);
    if (result is! Map) {
      throw Exception('offchain_submitPayment 返回类型异常:$result');
    }
    final map = result.cast<String, dynamic>();
    final txId = (map['tx_id'] ?? map['txId']) as String? ?? '';
    final l2AckSig = (map['l2_ack_sig'] ?? map['l2AckSig']) as String? ?? '';
    final acceptedAt = _parseInt(
      map['accepted_at'] ?? map['acceptedAt'],
      fallback: 0,
    );
    if (txId.isEmpty) {
      throw Exception('offchain_submitPayment 返回缺 tx_id:$result');
    }
    return (txId: txId, l2AckSig: l2AckSig, acceptedAt: acceptedAt);
  }

  /// 通用 JSON-RPC over WSS 调用,带超时和错误传播。
  /// 通用 WSS 传输；余额方法选择、数据校验和持久化由 wallet 所有者实现。
  Future<dynamic> call(String method, List<dynamic> params) async {
    final ws = await WebSocket.connect(wssUrl)
        .timeout(const Duration(seconds: 10));
    try {
      final request = jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        'params': params,
      });
      ws.add(request);

      final response = await ws.first.timeout(const Duration(seconds: 15));
      final json = jsonDecode(response as String) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        final error = json['error'] as Map<String, dynamic>;
        throw Exception('清算行 RPC 调用失败:${error['message'] ?? '未知错误'}');
      }
      return json['result'];
    } finally {
      await ws.close();
    }
  }

  static int _parseInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    if (value is num) return value.toInt();
    return fallback;
  }
}
