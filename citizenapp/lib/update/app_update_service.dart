import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:citizenapp/app_log.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'app_update_installer.dart';
import 'app_update_manifest.dart';

typedef AppUpdateDownloadProgress = void Function(
  int receivedBytes,
  int? totalBytes,
);

class AppUpdateService {
  AppUpdateService({
    AppUpdateInstaller? installer,
    http.Client? client,
  })  : _installer = installer ?? AppUpdateInstaller(),
        _client = client ?? http.Client();

  static final Uri _releasesUri =
      Uri.parse('https://api.github.com/repos/VoyagerRhett/GMB/releases');
  static const String _manifestAssetName = 'citizenapp-android-update.json';

  final AppUpdateInstaller _installer;
  final http.Client _client;

  /// 本机安装包版本读取与联网更新检查必须分离；关于页不能因为远端失败丢失本机版本。
  Future<AppVersionInfo> readCurrentVersion() => _installer.getPackageInfo();

  /// Android APK 更新专用入口。调用方必须先完成平台门禁，iOS 不得请求 Android 清单。
  Future<AppUpdateInfo?> checkAndroidUpdate(AppVersionInfo currentVersion) =>
      _findLatestAndroidUpdate(currentVersion);

  Future<File> downloadUpdate(
    AppUpdateInfo update, {
    AppUpdateDownloadProgress? onProgress,
  }) async {
    final request = http.Request('GET', update.apkDownloadUrl);
    final response = await _client.send(request);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        '下载 APK 失败：HTTP ${response.statusCode}',
        uri: update.apkDownloadUrl,
      );
    }

    final tempDir = await getTemporaryDirectory();
    final apkFile = File(
      '${tempDir.path}/citizenapp-update-${update.manifest.versionCode}.apk',
    );
    final output = apkFile.openWrite();
    final digestSink = _DigestSink();
    final hashInput = sha256.startChunkedConversion(digestSink);
    var receivedBytes = 0;

    try {
      await for (final chunk in response.stream) {
        receivedBytes += chunk.length;
        output.add(chunk);
        hashInput.add(chunk);
        onProgress?.call(receivedBytes, response.contentLength);
      }
    } finally {
      await output.flush();
      await output.close();
      hashInput.close();
    }

    final actualSha256 = digestSink.digest?.toString();
    if (actualSha256 != update.manifest.apkSha256) {
      await apkFile.delete().catchError((_) => apkFile);
      throw StateError('APK SHA-256 校验失败，已拒绝安装');
    }

    return apkFile;
  }

  Future<bool> installApk(File apkFile) {
    return _installer.installApk(apkFile.path);
  }

  Future<AppUpdateInfo?> _findLatestAndroidUpdate(
    AppVersionInfo currentVersion,
  ) async {
    final response = await _client.get(
      _releasesUri.replace(queryParameters: {'per_page': '20'}),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'citizenapp-android-updater',
      },
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        '检查更新失败：HTTP ${response.statusCode}',
        uri: _releasesUri,
      );
    }

    final releases = jsonDecode(response.body);
    if (releases is! List) {
      throw const FormatException('GitHub Release 列表格式无效');
    }

    for (final release in releases) {
      if (release is! Map<String, dynamic>) {
        continue;
      }
      if (release['draft'] == true || release['prerelease'] == true) {
        continue;
      }

      final assets = release['assets'];
      if (assets is! List) {
        continue;
      }
      final assetByName = <String, Map<String, dynamic>>{};
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = asset['name'] as String?;
          if (name != null) {
            assetByName[name] = asset;
          }
        }
      }

      final manifestAsset = assetByName[_manifestAssetName];
      if (manifestAsset == null) {
        continue;
      }
      final manifestUrl = Uri.tryParse(
        manifestAsset['browser_download_url'] as String? ?? '',
      );
      if (manifestUrl == null) {
        continue;
      }

      final manifest = await _fetchManifest(manifestUrl);
      if (!manifest.matchesAndroidPackage(currentVersion.packageName)) {
        continue;
      }
      if (manifest.versionCode <= currentVersion.versionCode) {
        return null;
      }

      final apkAsset = assetByName[manifest.apkAsset];
      final apkUrl = Uri.tryParse(
        apkAsset?['browser_download_url'] as String? ?? '',
      );
      if (apkUrl == null) {
        AppLog.d('[AppUpdate] Release 缺少 APK asset: ${manifest.apkAsset}');
        continue;
      }

      return AppUpdateInfo(
        manifest: manifest,
        apkDownloadUrl: apkUrl,
      );
    }

    return null;
  }

  Future<AppUpdateManifest> _fetchManifest(Uri manifestUrl) async {
    final response = await _client.get(
      manifestUrl,
      headers: const {'User-Agent': 'citizenapp-android-updater'},
    );
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        '下载更新清单失败：HTTP ${response.statusCode}',
        uri: manifestUrl,
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw const FormatException('更新清单 JSON 格式无效');
    }
    return AppUpdateManifest.fromJson(body);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}
