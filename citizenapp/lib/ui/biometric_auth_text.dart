import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart' show visibleForTesting;
// AuthMessages 基类由 local_auth_android 一并导出,无需再单独引 platform_interface。
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

/// 生物识别系统对话框的文案单源。
///
/// **口径(全端统一)**:默认中文;只有手机系统语言是英文时才显示英文,其余语言
/// (日、法、德…)一律回落中文。与 iOS `zh-Hans.lproj`/`en.lproj`、Android
/// `values/`(中文默认)+ `values-en/` 的回落规则完全一致。
///
/// **为什么需要它**:`localizedReason` 只是对话框中间那句解释,而标题、提示、
/// 取消按钮等**框架文字由 local_auth 插件提供,默认是英文硬编码串** —— 不传
/// [messages] 就会出现"中文解释 + 英文标题/按钮"的混排。
///
/// 语言判定用 [PlatformDispatcher.instance.locale](设备当前语言),不依赖
/// `BuildContext`：部分非 Widget 业务层也要复用平台认证文案。
class BiometricAuthText {
  const BiometricAuthText._();

  /// 语言判定的唯一规则:**只有英文为真**,其余语言(日、法、德…)一律按中文处理。
  /// 抽成纯函数,便于逐语言钉死回落行为。
  static bool isEnglishLocale(Locale locale) => locale.languageCode == 'en';

  /// 设备语言来源。生产恒为 [PlatformDispatcher.instance] 的当前语言;
  /// 测试注入用(与仓库 `debugXxx` 惯例一致),`tearDown` 里置 null 复位。
  ///
  /// 之所以需要这个接缝:生产直读 `PlatformDispatcher.instance` 时,
  /// `TestPlatformDispatcher.localeTestValue` 覆写的是测试包装器而非真单例,
  /// 覆盖不到本类 —— 不留接缝这段逻辑就完全不可测。
  @visibleForTesting
  static Locale Function()? debugLocale;

  static Locale get _locale =>
      debugLocale?.call() ?? PlatformDispatcher.instance.locale;

  /// 仅英文手机为真;其余语言一律按中文处理(默认语言)。
  static bool get isEnglish => isEnglishLocale(_locale);

  /// 按当前语言二选一。调用方用它给 `localizedReason` 取值。
  static String pick({required String zh, required String en}) =>
      isEnglish ? en : zh;

  /// 传给 `LocalAuthentication.authenticate(authMessages: ...)`。
  ///
  /// local_auth 3.x 的 Android 文案字段已收敛为标题、提示和取消按钮；iOS
  /// 继续显式提供设备密码回退标题，保持 CitizenApp 既有 `biometricOnly: false`
  /// 行为，不把依赖升级误改成冷钱包的纯生物识别策略。
  static List<AuthMessages> messages() => <AuthMessages>[
        AndroidAuthMessages(
          signInTitle: pick(zh: '身份验证', en: 'Authentication required'),
          signInHint: pick(zh: '验证您的身份', en: 'Verify your identity'),
          cancelButton: pick(zh: '取消', en: 'Cancel'),
        ),
        IOSAuthMessages(
          cancelButton: pick(zh: '取消', en: 'Cancel'),
          localizedFallbackTitle: pick(zh: '使用设备密码', en: 'Use passcode'),
        ),
      ];
}
