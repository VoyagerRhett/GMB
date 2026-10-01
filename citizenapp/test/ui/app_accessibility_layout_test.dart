import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:citizenapp/ui/app_layout.dart';
import 'package:citizenapp/ui/app_theme.dart';

Widget _wrap({required double textScale, required Widget child}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, builtChild) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Theme(data: AppTheme.lightThemeFor(context), child: builtChild!),
    ),
    home: Scaffold(body: child),
  );
}

Widget _platformGeometryApp(TargetPlatform platform) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => Theme(
      data: AppTheme.lightThemeFor(context).copyWith(platform: platform),
      child: child!,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('页面标题')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined),
            const SizedBox(height: 8),
            const SizedBox(width: 240, child: TextField()),
            const SizedBox(height: 8),
            FilledButton(onPressed: () {}, child: const Text('继续操作')),
          ],
        ),
      ),
    ),
  );
}

void _setViewport(WidgetTester tester, Size logicalSize) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = logicalSize;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('移动端产品名称中文为公民、英文为 CitizenApp', () {
    final catalog = jsonDecode(
      File('ios/Runner/InfoPlist.xcstrings').readAsStringSync(),
    ) as Map<String, dynamic>;
    final strings = catalog['strings'] as Map<String, dynamic>;
    Map<String, String> language(String name) => strings.map((key, value) =>
      MapEntry(key, value['localizations'][name]['stringUnit']['value'] as String));
    final iosChinese = language('zh-Hans');
    final iosEnglish = language('en');
    final androidChinese = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();
    final androidEnglish = File(
      'android/app/src/main/res/values-en_strings.xml',
    ).readAsStringSync();

    expect(iosChinese['CFBundleDisplayName'], '公民');
    expect(iosChinese['CFBundleName'], '公民');
    expect(iosEnglish['CFBundleDisplayName'], 'CitizenApp');
    expect(iosEnglish['CFBundleName'], 'CitizenApp');
    expect(androidChinese, contains('<string name="app_name">公民</string>'));
    expect(
      androidEnglish,
      contains('<string name="app_name">CitizenApp</string>'),
    );
    expect(iosEnglish.values, isNot(contains('Citizen')));
    expect(androidEnglish, isNot(contains('>Citizen<')));
  });

  test('iOS 系统弹窗本地化完整进入 Runner 资源配置', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final catalog = jsonDecode(
      File('ios/Runner/InfoPlist.xcstrings').readAsStringSync(),
    ) as Map<String, dynamic>;
    final strings = catalog['strings'] as Map<String, dynamic>;
    Map<String, String> language(String name) => strings.map((key, value) =>
      MapEntry(key, value['localizations'][name]['stringUnit']['value'] as String));
    final iosChinese = language('zh-Hans');
    final iosEnglish = language('en');

    expect(project, contains('developmentRegion = "zh-Hans";'));
    expect(catalog['sourceLanguage'], 'zh-Hans');
    expect(project, contains('InfoPlist.xcstrings in Resources'));
    expect(project, contains('lastKnownFileType = text.json.xcstrings;'));
    expect(infoPlist, contains('<string>zh-Hans</string>'));
    expect(infoPlist, contains('<string>en</string>'));

    String keys(Map<String, String> source) => (source.keys.toList()..sort()).join(',');

    expect(keys(iosChinese), keys(iosEnglish));
    expect(keys(iosChinese), contains('CFBundleDisplayName'));
    expect(keys(iosChinese), contains('CFBundleName'));
  });

  test('Android 系统权限弹窗应用名保留默认中文与英文限定资源', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final androidChinese = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();
    final androidEnglish = File(
      'android/app/src/main/res/values-en_strings.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:label="@string/app_name"'));
    expect(androidChinese, contains('<string name="app_name">公民</string>'));
    expect(
      androidEnglish,
      contains('<string name="app_name">CitizenApp</string>'),
    );
    expect(
      RegExp(
        r'<string name="([^"]+)"',
      ).allMatches(androidChinese).map((match) => match.group(1)).toSet(),
      RegExp(
        r'<string name="([^"]+)"',
      ).allMatches(androidEnglish).map((match) => match.group(1)).toSet(),
    );
  });

  test('Android MainActivity 固定竖屏，不跟随系统自动旋转', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final androidBuild = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final androidEntry = File(
      'android/app/src/main/MainActivity.kt',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".MainActivity"'));
    expect(manifest, contains('android:screenOrientation="portrait"'));
    expect(androidBuild, contains('applicationId = "com.crcfrcn.citizenapp"'));
    expect(androidBuild, contains('namespace = "com.crcfrcn.citizenapp"'));
    expect(androidEntry, contains('package com.crcfrcn.citizenapp'));
  });

  test('视觉倍率以 411×914 为基准并限制极端缩放', () {
    expect(AppLayout.visualScaleForSize(const Size(411, 914)), 1);
    expect(
      AppLayout.visualScaleForSize(const Size(402, 874)),
      closeTo(874 / 914, 0.000001),
    );
    expect(AppLayout.visualScaleForSize(const Size(320, 568)), 0.90);
    expect(AppLayout.visualScaleForSize(const Size(600, 1200)), 1.10);
  });

  testWidgets('Android 与 iOS 的基础组件按同一视口占比显示', (tester) async {
    final sizes = <TargetPlatform, Map<String, Size>>{};

    final viewports = <TargetPlatform, Size>{
      TargetPlatform.android: const Size(411, 914),
      TargetPlatform.iOS: const Size(402, 874),
    };

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      tester.view.physicalSize = viewports[platform]!;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_platformGeometryApp(platform));
      await tester.pump();
      sizes[platform] = {
        'appBar': tester.getSize(find.byType(AppBar)),
        'icon': tester.getSize(
          find.byIcon(Icons.account_balance_wallet_outlined),
        ),
        'input': tester.getSize(find.byType(TextField)),
        'button': tester.getSize(find.byType(FilledButton)),
      };
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    expect(sizes[TargetPlatform.android]!['appBar']!.height, 56);
    expect(sizes[TargetPlatform.android]!['icon'], const Size(24, 24));
    expect(sizes[TargetPlatform.android]!['input']!.height, 52);
    expect(sizes[TargetPlatform.android]!['button']!.height, 52);

    const iosScale = 874 / 914;
    expect(
      sizes[TargetPlatform.iOS]!['appBar']!.height,
      closeTo(56 * iosScale, 0.001),
    );
    expect(
      sizes[TargetPlatform.iOS]!['icon']!.height,
      closeTo(24 * iosScale, 0.001),
    );
    expect(
      sizes[TargetPlatform.iOS]!['input']!.height,
      closeTo(52 * iosScale, 0.001),
    );
    expect(
      sizes[TargetPlatform.iOS]!['button']!.height,
      greaterThanOrEqualTo(AppLayout.minimumTapTarget),
    );

    expect(
      sizes[TargetPlatform.iOS]!['appBar']!.height / 874,
      closeTo(sizes[TargetPlatform.android]!['appBar']!.height / 914, 0.0001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的页入口在标准倍率下使用统一高度', (tester) async {
    _setViewport(tester, const Size(411, 914));
    double? primaryHeight;
    double? serviceHeight;
    await tester.pumpWidget(
      _wrap(
        textScale: 1,
        child: Builder(
          builder: (context) {
            primaryHeight = AppLayout.primaryEntryCardHeight(context);
            serviceHeight = AppLayout.serviceEntryHeight(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(primaryHeight, AppLayout.primaryEntryHeight);
    expect(serviceHeight, AppLayout.serviceRowHeight);
  });

  testWidgets('系统文字倍率原样进入页面，不被全局主题覆盖', (tester) async {
    _setViewport(tester, const Size(411, 914));
    double? scaled16;
    await tester.pumpWidget(
      _wrap(
        textScale: 19 / 17,
        child: Builder(
          builder: (context) {
            scaled16 = MediaQuery.textScalerOf(context).scale(16);
            return const Text('系统文字倍率');
          },
        ),
      ),
    );

    expect(scaled16, closeTo(16 * 19 / 17, 0.001));
  });

  for (final scale in [1.0, 19 / 17, 23 / 17, 28 / 17, 53 / 17]) {
    testWidgets('主导航在文字倍率 $scale 下只增加必要文字高度', (tester) async {
      _setViewport(tester, const Size(411, 914));
      double? navigationHeight;
      await tester.pumpWidget(
        _wrap(
          textScale: scale,
          child: Builder(
            builder: (context) {
              navigationHeight = AppLayout.navigationBarHeight(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final expectedTextGrowth = (12 * 1.2 * scale) - (12 * 1.2);
      expect(
        navigationHeight,
        closeTo(
          AppLayout.navigationBarBaseHeight +
              (expectedTextGrowth > 0 ? expectedTextGrowth : 0),
          0.001,
        ),
      );
      expect(AppLayout.iconStandard, 24);
      expect(AppLayout.spaceLg, 16);
    });
  }

  testWidgets('大字体按钮保持最小触控高度并允许内容推动高度增长', (tester) async {
    _setViewport(tester, const Size(411, 914));
    await tester.pumpWidget(
      _wrap(
        textScale: 53 / 17,
        child: Center(
          child: FilledButton(onPressed: () {}, child: const Text('继续操作')),
        ),
      ),
    );

    final button = tester.getRect(find.byType(FilledButton));
    expect(button.height, greaterThanOrEqualTo(AppLayout.minimumButtonHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('主导航在极大字体下增高但图标保持结构尺寸', (tester) async {
    _setViewport(tester, const Size(411, 914));
    await tester.pumpWidget(
      _wrap(
        textScale: 53 / 17,
        child: Builder(
          builder: (context) => Align(
            alignment: Alignment.bottomCenter,
            child: NavigationBar(
              height: AppLayout.navigationBarHeight(context),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: '首页'),
                NavigationDestination(icon: Icon(Icons.person), label: '我的'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(NavigationBar)).height,
      greaterThan(AppLayout.navigationBarBaseHeight),
    );
    expect(tester.getSize(find.byIcon(Icons.home)), const Size(24, 24));
    expect(tester.takeException(), isNull);
  });
}
