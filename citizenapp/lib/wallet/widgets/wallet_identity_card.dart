import 'package:citizen_sdk/citizen_sdk.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/wallet/widgets/wallet_qr_dialog.dart';

/// 钱包详情页主视觉中的身份区。
///
/// - 与 [WalletOnchainBalanceCard] 共用外层纯色主视觉面板，本组件只负责身份内容。
/// - 钱包名可点击进入编辑态;提交(回车 / onTapOutside)时通过 [onNameChanged]
///   回调让外层落盘。空字符串或与现值相同则回滚不报错,由编辑态自行处理。
/// - 地址完整展示，空间不足时从第二行左对齐换行；复制按钮独立位于分隔线左侧。
/// - 右侧 QR 入口打开账户二维码弹窗，内容为 QR_V1 `k=5` 账户码（只声明账户）。
///   身份码(`k=3` 用户码)只在用户主页出示,本卡不做「该出哪种码」的运行时判断。
class WalletIdentityCard extends StatefulWidget {
  const WalletIdentityCard({
    super.key,
    required this.wallet,
    required this.onNameChanged,
  });

  final CitizenWalletStateAccount wallet;

  /// 钱包名提交回调。外层负责持久化,Widget 内部已做 trim 和空值回滚。
  final Future<void> Function(String) onNameChanged;

  @override
  State<WalletIdentityCard> createState() => _WalletIdentityCardState();
}

class _WalletIdentityCardState extends State<WalletIdentityCard> {
  /// 当前展示态的钱包名(与 widget.wallet.name 同步,编辑提交后更新)。
  late String _walletName;

  /// 是否处于编辑态。
  bool _isEditingName = false;

  /// 编辑态 TextField 的 controller。
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _walletName = widget.wallet.name;
    _nameController = TextEditingController(text: _walletName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 提交钱包名。trim 后空或与当前相同则回滚编辑态,不调用回调。
  Future<void> _submitName(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == _walletName) {
      setState(() {
        _isEditingName = false;
        _nameController.text = _walletName;
      });
      return;
    }
    try {
      await widget.onNameChanged(trimmed);
      if (!mounted) return;
      setState(() {
        _walletName = trimmed;
        _isEditingName = false;
      });
    } catch (_) {
      // 落盘失败由外层回调自行 SnackBar,这里仅负责回滚编辑态。
      if (!mounted) return;
      setState(() {
        _isEditingName = false;
        _nameController.text = _walletName;
      });
    }
  }

  /// 复制钱包地址并弹 SnackBar。
  void _copyAddress() {
    Clipboard.setData(ClipboardData(text: widget.wallet.ss58Address));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('钱包地址已复制')));
  }

  /// 按最终设计稿把完整地址拆成两行：
  /// 第一行预留复制按钮槽位，第二行使用全部可用宽度并保持左对齐。
  ({String firstLine, String secondLine}) _splitAddressForTwoLines(
    double availableWidth,
    TextStyle style,
  ) {
    final address = widget.wallet.ss58Address;
    const copySlotWidth = 36.0;

    bool fits(String text, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return painter.width <= width;
    }

    if (fits(address, availableWidth - copySlotWidth)) {
      return (firstLine: address, secondLine: '');
    }

    var splitAt = 1;
    for (var split = 1; split < address.length; split += 1) {
      if (fits(address.substring(0, split), availableWidth - copySlotWidth)) {
        // 第一行必须尽量排满，第二行只承接第一行确实放不下的剩余地址。
        splitAt = split;
      } else {
        break;
      }
    }

    return (
      firstLine: address.substring(0, splitAt),
      secondLine: address.substring(splitAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('wallet-identity-section'),
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 20),
          vertical: AppLayout.scaled(context, 12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左侧不放钱包装饰图标，账户信息直接与主视觉的左边距对齐。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: AppLayout.scaled(context, 44),
                  child: _isEditingName
                      ? TextField(
                          controller: _nameController,
                          autofocus: true,
                          style: TextStyle(
                            fontSize: AppLayout.scaled(context, 18),
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: AppLayout.compactLineHeight,
                          ),
                          cursorColor: Colors.white,
                          decoration: InputDecoration(
                            isDense: true,
                            // 身份区名称槽固定为 44px，覆盖普通输入框 52px 基线；
                            // 否则全局输入框约束会把钱包身份卡单独撑高。
                            constraints: BoxConstraints.tightFor(
                              height: AppLayout.scaled(context, 44),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              vertical: AppLayout.scaled(context, 8),
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(
                                color: Colors.white.withAlpha(150),
                              ),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: _submitName,
                          onTapOutside: (_) {
                            _submitName(_nameController.text);
                          },
                        )
                      : Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                            onTap: () {
                              setState(() {
                                _isEditingName = true;
                                _nameController.text = _walletName;
                              });
                            },
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _walletName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppLayout.scaled(context, 18),
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      height: AppLayout.compactLineHeight,
                                    ),
                                  ),
                                ),
                                SizedBox(width: AppLayout.scaled(context, 8)),
                                Icon(
                                  Icons.edit_outlined,
                                  size: AppLayout.scaled(context, 19),
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    height: AppLayout.scaled(context, 44),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final addressStyle = TextStyle(
                          fontSize: AppLayout.scaled(context, 12),
                          height: 1.35,
                          color: Colors.white.withAlpha(190),
                          fontFamily: 'monospace',
                        );
                        final lines = _splitAddressForTwoLines(
                          constraints.maxWidth,
                          addressStyle,
                        );
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSm,
                                ),
                                onTap: _copyAddress,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: AppLayout.scaled(context, 36),
                              top: 0,
                              height: AppLayout.scaled(context, 28),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  lines.firstLine,
                                  key: const ValueKey(
                                    'wallet-identity-address-line-1',
                                  ),
                                  maxLines: 1,
                                  textAlign: TextAlign.left,
                                  style: addressStyle,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: AppLayout.scaled(context, 22),
                              height: AppLayout.scaled(context, 22),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  lines.secondLine,
                                  key: const ValueKey(
                                    'wallet-identity-address-line-2',
                                  ),
                                  maxLines: 1,
                                  textAlign: TextAlign.left,
                                  style: addressStyle,
                                ),
                              ),
                            ),
                            Positioned(
                              // 向左校准 1.25 逻辑像素，使原子图形的可见右缘与
                              // 二维码原子图形的可见左缘到分隔线完全等距。
                              right: AppLayout.scaled(context, 1.25),
                              top: 0,
                              child: Semantics(
                                key: const ValueKey(
                                  'wallet-identity-copy-button',
                                ),
                                button: true,
                                label: '复制钱包地址',
                                child: Tooltip(
                                  message: '复制钱包地址',
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(
                                        AppTheme.radiusSm,
                                      ),
                                      onTap: _copyAddress,
                                      child: SizedBox(
                                        width: AppLayout.scaled(context, 28),
                                        height: AppLayout.scaled(context, 28),
                                        child: Transform.translate(
                                          // 最终确认稿只下移可见图标，不改变原子形状、
                                          // 点击热区、横向位置或与竖线的视觉等距。
                                          offset: Offset(
                                              0, AppLayout.scaled(context, 4)),
                                          child: Icon(
                                            Icons.copy_outlined,
                                            key: const ValueKey(
                                              'wallet-identity-copy-icon',
                                            ),
                                            size: AppLayout.scaled(context, 12),
                                            color: Colors.white.withAlpha(210),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 按真机可见图形边缘校准：复制图标到竖线与竖线到二维码图标等距。
          SizedBox(width: AppLayout.scaled(context, 20)),
          // 方案 2 明确使用竖线分开账户信息和二维码入口。
          Container(
            key: const ValueKey('wallet-identity-qr-divider'),
            width: 1,
            height: AppLayout.scaled(context, 48),
            color: Colors.white.withAlpha(55),
          ),
          SizedBox(width: AppLayout.scaled(context, 16)),
          // 右：冷热钱包共用二维码弹窗，48×48 满足点击目标。
          Material(
            key: const ValueKey('wallet-identity-qr-button'),
            // 最终确认稿删除二维码白色底，只保留透明点击热区和白色原子图标。
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              onTap: () => showWalletQrDialog(
                context,
                accountId: widget.wallet.accountId,
                accountName: _walletName,
              ),
              child: SizedBox(
                width: AppLayout.scaled(context, 48),
                height: AppLayout.scaled(context, 48),
                child: Icon(
                  Icons.qr_code_rounded,
                  key: const ValueKey('wallet-identity-qr-icon'),
                  color: Colors.white,
                  size: AppLayout.scaled(context, 24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
