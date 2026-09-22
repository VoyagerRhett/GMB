import 'package:flutter/material.dart';

import 'package:citizenapp/citizen/shared/account_derivation.dart';
import 'package:citizenapp/qr/widgets/qr_display_scaffold.dart';

/// 用户码展示页(`QR_V1 k=3 user_contact`,固定码)。
///
/// 用户码表达「人」——永久 CID 与其当前绑定账户(码内不含昵称)。本人可从
/// “我的”背景图或用户主页进入，他人从其用户主页进入；所有入口复用本页。
/// 只有链上 CID↔AccountId 闭环命中的身份账户才能出这张码。账户维度的展示走账户码
/// (`lib/wallet/widgets/wallet_qr_dialog.dart`),一笔收款请求走收款码;三者按入口分类,
/// 本页不做任何「该出哪种码」的运行时判断。
///
/// 用户码是唯一能写入通讯录的码:通讯录关系必须锚永久 CID,不能锚会换绑的账户。
class UserQrPage extends StatelessWidget {
  const UserQrPage({
    super.key,
    required this.cidNumber,
    required this.displayName,
    required this.accountId,
    required this.qrData,
    this.isSelf = false,
  });

  /// SDK已编码的用户码；页面只展示，不解析或构造QR_V1。
  final String qrData;

  /// 永久公民身份号,身份主键。
  final String cidNumber;

  /// 公开昵称,只作展示。
  final String displayName;

  /// CID 当前绑定的钱包账户(0x + 64hex)。
  final String accountId;

  /// 本人用户码显式标记“我的”；他人页面不得冒充本人。
  final bool isSelf;

  /// 展示态 SS58 地址(accountId 为授权真源,ss58 仅用于展示与二维码载荷)。
  String get _ss58Address => ss58FromAccountIdText(accountId);

  @override
  Widget build(BuildContext context) {
    return QrDisplayScaffold(
      title: isSelf ? '我的用户码' : '用户码',
      headline: displayName,
      qrData: qrData,
      ss58Address: _ss58Address,
      footerText: '扫描此二维码可加为联系人，或向其转账',
    );
  }
}
