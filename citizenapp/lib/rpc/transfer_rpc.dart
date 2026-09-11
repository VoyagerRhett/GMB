import 'dart:convert';
import 'dart:typed_data';

import 'package:polkadart_keyring/polkadart_keyring.dart' show Keyring;
import 'package:citizenapp/transaction/onchain-transaction/citizenchain_transfer_call_encoder.dart';

import 'chain_rpc.dart';
import 'signed_extrinsic_builder.dart';

/// onchain 模块所有 RPC 功能：extrinsic 构造与普通转账提交。
class TransferRpc {
  TransferRpc({ChainRpc? chainRpc}) : _rpc = chainRpc ?? ChainRpc();

  final ChainRpc _rpc;

  /// 普通转账备注最大 UTF-8 字节数，与 runtime `MaxTransferRemarkLen` 保持一致。
  static const int maxTransferRemarkBytes =
      CitizenChainTransferCallEncoder.maxRemarkBytes;

  // ──── 公开方法 ────

  /// 执行 OnchainTransaction::transfer_with_remark 转账。
  ///
  /// [fromSs58Address] 发送方 SS58 地址
  /// [signerPublicKey] 发送方公钥 32 字节
  /// [toSs58Address] 接收方 SS58 地址
  /// [amountYuan] 转账金额（元），内部转为分
  /// [remark] 转账备注，按 UTF-8 字节编码并随交易事件上链
  /// [sign] 签名回调：接收签名载荷字节，返回 64 字节 sr25519 签名
  ///
  /// 返回交易哈希 hex（含 0x 前缀）和提交时使用的 nonce。
  Future<({String txHash, int usedNonce})> transferWithRemark({
    required String fromSs58Address,
    required Uint8List signerPublicKey,
    required String toSs58Address,
    required double amountYuan,
    required String remark,
    required Future<Uint8List> Function(Uint8List payload) sign,
    TxPoolWatchCallback? onWatchEvent,
  }) async {
    final destAccountId = Keyring().decodeAddress(toSs58Address);
    final amountFen = BigInt.from((amountYuan * 100).round());
    final remarkBytes = Uint8List.fromList(utf8.encode(remark));
    final callData = const CitizenChainTransferCallEncoder().encode(
      destinationAccountId: destAccountId,
      amountFen: amountFen,
      remarkBytes: remarkBytes,
    );
    return SignedExtrinsicBuilder(
      chainRpc: _rpc,
      logLabel: 'TransferRpc',
    ).signAndSubmit(
      callData: callData,
      fromSs58Address: fromSs58Address,
      signerPublicKey: signerPublicKey,
      sign: sign,
      onWatchEvent: onWatchEvent,
    );
  }

  // 钱包交易流水由区块事件监听写入本地记录,不逐块拉 extrinsic 搜索
  // (逐块拉 body 会触发 substrate block-request 反滥用机制
  // MAX_NUMBER_OF_SAME_REQUESTS_PER_PEER=2 把轻节点 peer ban 掉)。

  // ──── 手续费估算 ────

  /// 预估转账手续费（元）。
  ///
  /// 与链上 `onchain_transaction` 计算逻辑一致：
  /// `fee = max(amount_fen * Perbill(1_000_000), 10 fen)`
  ///
  /// - 费率 0.1%（`Perbill::from_parts(1_000_000)`）
  /// - 最低手续费 10 fen（0.10 元）
  /// - half-up 舍入到 fen 精度
  static double estimateTransferFeeYuan(double amountYuan) {
    const int perbillParts = 1000000;
    const int perbillDenom = 1000000000;
    const int minFeeFen = 10;

    final amountFen = BigInt.from((amountYuan * 100).round());
    // half-up rounding: (amount * parts + denom/2) ~/ denom
    final byRate = (amountFen * BigInt.from(perbillParts) +
            BigInt.from(perbillDenom ~/ 2)) ~/
        BigInt.from(perbillDenom);
    final feeFen =
        byRate < BigInt.from(minFeeFen) ? BigInt.from(minFeeFen) : byRate;
    return feeFen.toDouble() / 100.0;
  }

}
