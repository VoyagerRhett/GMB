import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

// ShimmerEffect - 为子组件添加从左到右的光泽扫过动画
/// 通用 shimmer 包装器。
///
/// 在 [child] 上叠加一个 [LinearGradient] 动画遮罩，模拟骨架屏加载效果。
/// 不依赖任何第三方包，仅使用 Flutter 内置动画 API。
class ShimmerEffect extends StatefulWidget {
  const ShimmerEffect({super.key, required this.child});

  final Widget child;

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        // 渐变从 -1.0 滑到 2.0，产生扫过效果
        final begin = Alignment(-1.0 + 3.0 * value, -0.3);
        final end = Alignment(-1.0 + 3.0 * value + 1.0, 0.3);

        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: begin,
              end: end,
              colors: const [
                AppTheme.surfaceMuted,
                AppTheme.surfaceCard,
                AppTheme.surfaceMuted,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ShimmerBox - 圆角矩形占位块
/// 可配置宽高和圆角的灰色占位块，配合 [ShimmerEffect] 使用。
class ShimmerBox extends StatelessWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ProposalCardSkeleton - 模拟提案卡片布局的骨架
/// 提案卡片骨架屏：左侧图标占位 + 两行文本 + 右侧状态徽章。
class ProposalCardSkeleton extends StatelessWidget {
  const ProposalCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 14),
          vertical: AppLayout.scaled(context, 12)),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // 图标占位
          ShimmerBox(
              width: AppLayout.scaled(context, 36),
              height: AppLayout.scaled(context, 36),
              radius: AppLayout.scaled(context, 10)),
          SizedBox(width: AppLayout.scaled(context, 12)),
          // 文本行
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(
                    width: AppLayout.scaled(context, 120),
                    height: AppLayout.scaled(context, 14)),
                SizedBox(height: AppLayout.scaled(context, 6)),
                ShimmerBox(
                    width: AppLayout.scaled(context, 180),
                    height: AppLayout.scaled(context, 12)),
              ],
            ),
          ),
          SizedBox(width: AppLayout.scaled(context, 8)),
          // 状态徽章占位
          ShimmerBox(
              width: AppLayout.scaled(context, 52),
              height: AppLayout.scaled(context, 20),
              radius: AppLayout.scaled(context, 10)),
        ],
      ),
    );
  }
}

// WalletCardSkeleton - 模拟钱包列表卡片的骨架
/// 钱包卡片骨架屏：左侧头像占位 + 名称行 + 地址行。
class WalletCardSkeleton extends StatelessWidget {
  const WalletCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppLayout.scaled(context, 14),
          vertical: AppLayout.scaled(context, 12)),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppLayout.scaledValue(12)),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // 头像占位
          ShimmerBox(
              width: AppLayout.scaled(context, 40),
              height: AppLayout.scaled(context, 40),
              radius: AppLayout.scaled(context, 20)),
          SizedBox(width: AppLayout.scaled(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(
                    width: AppLayout.scaled(context, 100),
                    height: AppLayout.scaled(context, 14)),
                SizedBox(height: AppLayout.scaled(context, 6)),
                ShimmerBox(height: AppLayout.scaled(context, 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ListSkeleton - 批量骨架列表
/// 将 [itemCount] 个骨架项包裹在 [ShimmerEffect] 中。
///
/// [builder] 用于自定义每个骨架项的 widget（默认无需提供）。
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(
            horizontal: AppLayout.scaled(context, 16),
            vertical: AppLayout.scaled(context, 24)),
        itemCount: itemCount,
        separatorBuilder: (_, _) =>
            SizedBox(height: AppLayout.scaled(context, 8)),
        itemBuilder: itemBuilder,
      ),
    );
  }
}
