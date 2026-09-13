import 'dart:async';
import 'dart:io' show Platform;

import 'package:citizen_sdk/citizen_sdk.dart';
import 'package:flutter/material.dart';
import 'package:citizenapp/log/app_log.dart';
import 'package:provider/provider.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 公民链状态读取与交易顶栏唯一可见状态。
///
/// 所有调用方共用真实轻节点轮询和门禁回调；只有交易 Tab 设置
/// [showInlineStatus] 后可见，其他页面只读取状态，不渲染连接状态 UI。
class ChainProgressBanner extends StatefulWidget {
  const ChainProgressBanner({
    super.key,
    this.margin = EdgeInsets.zero,
    this.busy = false,
    this.showInlineStatus = false,
    this.pollInterval = const Duration(seconds: 6),
    this.onProgressChanged,
    this.onErrorChanged,
    this.progressLoader,
  });

  final EdgeInsetsGeometry margin;
  final bool busy;

  /// 是否在交易 Tab 顶栏显示唯一的全局链状态。
  ///
  /// 默认关闭；不可见调用方仍会读取链状态并回传给业务门禁。
  final bool showInlineStatus;
  final Duration pollInterval;
  final ValueChanged<CitizenChainSyncStatus?>? onProgressChanged;
  final ValueChanged<String?>? onErrorChanged;

  /// 专项测试注入；生产直接读取 [CitizenChain.getSyncStatus]。
  final Future<CitizenChainSyncStatus> Function()? progressLoader;

  @override
  State<ChainProgressBanner> createState() => _ChainProgressBannerState();
}

class _ChainProgressBannerState extends State<ChainProgressBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathingController;
  CitizenChainSyncStatus? _progress;
  String? _error;
  Timer? _pollTimer;
  String? _lastLoggedProgress;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.35,
      upperBound: 1,
    );
    // Widget test 中不启动无限动画，避免 pumpAndSettle 无法稳定；真机保持呼吸效果。
    if (widget.showInlineStatus && !_isTestProcess) {
      _breathingController.repeat(reverse: true);
    }
    if (_isFlutterTest) return;
    unawaited(_loadProgress());
  }

  @override
  void didUpdateWidget(covariant ChainProgressBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showInlineStatus != oldWidget.showInlineStatus &&
        !_isTestProcess) {
      if (widget.showInlineStatus) {
        _breathingController.repeat(reverse: true);
      } else {
        _breathingController.stop();
      }
    }
    if (_isFlutterTest) return;
    if (widget.busy && !oldWidget.busy) {
      unawaited(_loadProgress());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _breathingController.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    if (_isFlutterTest) return;
    _pollTimer?.cancel();

    try {
      final progress = await (widget.progressLoader?.call() ??
          context.read<CitizenSdk>().chain.getSyncStatus());
      if (!mounted) return;
      _logProgressTransition(progress);
      setState(() {
        _progress = progress;
        _error = null;
      });
      widget.onProgressChanged?.call(progress);
      widget.onErrorChanged?.call(null);
      _scheduleNextPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _chainErrorMessage(e);
      });
      widget.onProgressChanged?.call(_progress);
      widget.onErrorChanged?.call(_error);
      _scheduleNextPoll();
    }
  }

  /// 轮询常驻、永不自停:最终区块高度随链持续推进,同步完成(isUsable)后也按
  /// [ChainProgressBanner.pollInterval] 继续轮询,顶部高度才能自动跟上链尖。
  /// fetchChainProgress 只读原生内存状态快照,不发网络请求、不依赖 peer,常驻
  /// 轮询零负担;若同步完成即停(旧行为),高度会冻结在启动时的值、只能靠下拉刷新。
  void _scheduleNextPoll() {
    if (_isFlutterTest) return;
    _pollTimer = Timer(widget.pollInterval, () {
      if (!mounted) return;
      unawaited(_loadProgress());
    });
  }

  void _logProgressTransition(CitizenChainSyncStatus progress) {
    final signature = '${progress.isSyncing}/'
        '${progress.isUsable}/'
        '${progress.peerCount}/'
        '${progress.best.number}/'
        '${progress.finalized.number}';
    if (_lastLoggedProgress == signature) return;
    _lastLoggedProgress = signature;
    AppLog.d(
      '[CitizenSDK] syncing=${progress.isSyncing}, '
      'usable=${progress.isUsable}, '
      'peers=${progress.peerCount}, '
      'best=#${progress.best.number}, '
      'finalized=#${progress.finalized.number}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showInlineStatus) return const SizedBox.shrink();
    return _buildInlineStatus(progress: _progress, error: _error);
  }

  bool get _isFlutterTest =>
      widget.progressLoader == null &&
      Platform.environment.containsKey('FLUTTER_TEST');

  bool get _isTestProcess => Platform.environment.containsKey('FLUTTER_TEST');

  ({Color color, String semanticsStatus}) _resolveState({
    required CitizenChainSyncStatus? progress,
    required String? error,
  }) {
    if (error != null) {
      return (color: AppTheme.danger, semanticsStatus: '连接失败');
    }
    if (progress?.isUsable == true) {
      return (color: AppTheme.success, semanticsStatus: '连接正常');
    }
    return (color: AppTheme.info, semanticsStatus: '正在连接');
  }

  Widget _buildInlineStatus({
    required CitizenChainSyncStatus? progress,
    required String? error,
  }) {
    final state = _resolveState(progress: progress, error: error);
    final finalizedBlockNumber = progress?.finalized.number;
    final detail = '最终区块 ${finalizedBlockNumber ?? '—'}';

    return Semantics(
      key: const ValueKey<String>('transaction-chain-status-inline'),
      excludeSemantics: true,
      label: '公民链${state.semanticsStatus}，$detail',
      child: Padding(
        padding: widget.margin,
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedBuilder(
                      animation: _breathingController,
                      builder: (context, _) {
                        final opacity =
                            _isTestProcess ? 1.0 : _breathingController.value;
                        return SizedBox(
                          width: AppLayout.scaled(context, 18),
                          height: AppLayout.scaled(context, 18),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: opacity * 0.22,
                                child: Container(
                                  width: AppLayout.scaled(context, 16),
                                  height: AppLayout.scaled(context, 16),
                                  decoration: BoxDecoration(
                                    color: state.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Container(
                                width: AppLayout.scaled(context, 8),
                                height: AppLayout.scaled(context, 8),
                                decoration: BoxDecoration(
                                  color: state.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    SizedBox(width: AppLayout.scaledValue(6)),
                    Flexible(
                      child: Text(
                        '公民链',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: state.color,
                          fontSize: AppLayout.scaledValue(13),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 两段之间的固定空隙以顶栏几何中心为中点，确保视觉轴线落在屏幕中央。
            SizedBox(
              key:
                  const ValueKey<String>('transaction-chain-status-center-gap'),
              width: AppLayout.scaledValue(10),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                // 状态栏保持中心轴线不变；极端大字体下截断视觉副本，完整信息仍由
                // 外层 Semantics.label 提供，禁止反向缩小系统文字。
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: state.color,
                    fontSize: AppLayout.scaledValue(12),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _chainErrorMessage(Object error) {
    if (error is CitizenSdkException && error.message.isNotEmpty) {
      return error.message;
    }
    return '公民链状态暂时不可用';
  }
}
