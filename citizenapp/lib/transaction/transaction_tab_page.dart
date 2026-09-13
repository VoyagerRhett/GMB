import 'package:flutter/material.dart';
import 'package:citizenapp/transaction/onchain-transaction/onchain_payment_page.dart';
import 'package:citizenapp/transaction/personal-manage/personal_account_entry.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 交易 Tab 页面。
///
/// 本页只负责交易页入口编排；链上支付主体仍由 onchain 模块渲染。
/// 扫码收在收款地址输入框内（只填地址）；签名请求统一走「聊天 → 扫一扫」。
class TransactionTabPage extends StatelessWidget {
  const TransactionTabPage({
    super.key,
    this.currentWalletLoader,
    this.localRecordsLoader,
    this.balanceLoader,
    this.contactPageBuilder,
  });

  /// 测试夹具可注入公开页面数据；正式 Tab 不传值并直接读取 CitizenSDK。
  final OnchainCurrentWalletLoader? currentWalletLoader;
  final OnchainLocalRecordsLoader? localRecordsLoader;
  final Future<double> Function(String accountId)? balanceLoader;
  final OnchainContactPageBuilder? contactPageBuilder;

  @override
  Widget build(BuildContext context) {
    return OnchainPaymentPanel(
      // 交易 Tab 的页面标题由真实公民链状态取代；独立链上支付页仍保留自己的标题。
      chainStatusInHeader: true,
      currentWalletLoader: currentWalletLoader,
      localRecordsLoader: localRecordsLoader,
      balanceLoader: balanceLoader,
      contactPageBuilder: contactPageBuilder,
      extraEntriesBuilder: (context) => [
        const PersonalAccountEntryCard(),
        SizedBox(height: AppLayout.scaled(context, 12)),
      ],
    );
  }
}
