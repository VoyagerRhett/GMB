import 'dart:async';

import 'package:flutter/widgets.dart';

import 'scanner_controller.dart';
import 'scanner_failure.dart';

/// 统一摄像头预览组件，只向调用方交付一次二维码原始字符串。
class ScannerView extends StatefulWidget {
  const ScannerView({
    super.key,
    required this.controller,
    required this.onRawValue,
    this.onFailure,
  });

  final ScannerController controller;
  final ValueChanged<String> onRawValue;
  final ValueChanged<ScannerFailure>? onFailure;

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_start());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(_stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.controller.buildPreview(
      onCandidates: (values) {
        try {
          final raw = widget.controller.claimFirst(values);
          if (raw != null) widget.onRawValue(raw);
        } on ScannerFailure catch (failure) {
          widget.onFailure?.call(failure);
        }
      },
    );
  }

  Future<void> _start() async {
    try {
      await widget.controller.start();
    } on ScannerFailure catch (failure) {
      widget.onFailure?.call(failure);
    }
  }

  Future<void> _stop() async {
    try {
      await widget.controller.stop();
    } on ScannerFailure catch (failure) {
      widget.onFailure?.call(failure);
    }
  }
}
