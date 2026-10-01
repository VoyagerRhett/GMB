import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/ui/app_theme.dart';

/// 发布页相册返回值：文件与资源类型在离开相册前已经确定。
class ComposePickedMedia {
  const ComposePickedMedia({
    required this.file,
    required this.mediaKind,
    this.photoManagerAssetId,
  });

  final XFile file;
  final SquareMediaKind mediaKind;
  final String? photoManagerAssetId;
}

/// 已确认的纯图片选择；无法在相册恢复的既有资源由调用方继续保留。
class ComposeImageSelection {
  const ComposeImageSelection({
    required this.selected,
    this.unavailablePhotoManagerAssetIds = const <String>[],
  });

  final List<ComposePickedMedia> selected;
  final List<String> unavailablePhotoManagerAssetIds;
}

/// 公文与文章共用的设备相册边界，测试可注入假实现而不唤起系统权限。
abstract class ComposeMediaPicker {
  const ComposeMediaPicker();

  /// 只允许选择图片，[maxImages] 是当前编辑器剩余可选数量。
  Future<List<XFile>> pickImages(BuildContext context, int maxImages);

  /// 带既有相册资源预选的纯图片选择。返回 null 表示用户取消。
  Future<ComposeImageSelection?> pickImagesWithSelection(
    BuildContext context,
    int maxImages, {
    List<String> selectedPhotoManagerAssetIds = const <String>[],
  }) async {
    final files = await pickImages(context, maxImages);
    if (files.isEmpty) return null;
    return ComposeImageSelection(
      selected: [
        for (final file in files)
          ComposePickedMedia(
            file: file,
            mediaKind: SquareMediaKind.image,
          ),
      ],
    );
  }

  /// 第一个选中项决定类型：一次返回最多九张图片或一个视频，两者不能混选。
  Future<List<ComposePickedMedia>> pickArticleMedia(BuildContext context);
}

/// 发布页唯一相册实现。Android 与 iOS 都使用同一 Flutter 相册网格，避免 Android
/// 回落到文件管理器，也避免平台系统选择器忽略数量或允许图片/视频混选。
class DeviceComposeMediaPicker extends ComposeMediaPicker {
  const DeviceComposeMediaPicker();

  @override
  Future<List<XFile>> pickImages(
    BuildContext context,
    int maxImages,
  ) async {
    if (maxImages <= 0) return const <XFile>[];
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: maxImages,
        requestType: RequestType.image,
        themeColor: AppTheme.primary,
        textDelegate: const AssetPickerTextDelegate(),
      ),
    );
    if (assets == null || assets.isEmpty) return const <XFile>[];
    final files = <XFile>[];
    for (final asset in assets.take(maxImages)) {
      final file = await asset.file;
      if (file == null) continue;
      files.add(await _toXFile(asset, file.path));
    }
    return files;
  }

  @override
  Future<ComposeImageSelection?> pickImagesWithSelection(
    BuildContext context,
    int maxImages, {
    List<String> selectedPhotoManagerAssetIds = const <String>[],
  }) async {
    if (maxImages <= 0) return null;
    final selectedAssets = <AssetEntity>[];
    final unavailableIds = <String>[];
    for (final id in selectedPhotoManagerAssetIds) {
      final asset = await AssetEntity.fromId(id);
      if (asset == null || asset.type != AssetType.image) {
        unavailableIds.add(id);
      } else {
        selectedAssets.add(asset);
      }
    }
    final pickerMaximum = maxImages - unavailableIds.length;
    if (pickerMaximum <= 0) {
      throw const FormatException('现有照片已达到9张，请先删除一张再增加');
    }
    if (!context.mounted) return null;
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        selectedAssets: selectedAssets,
        maxAssets: pickerMaximum,
        requestType: RequestType.image,
        themeColor: AppTheme.primary,
        textDelegate: const AssetPickerTextDelegate(),
      ),
    );
    if (assets == null) return null;
    final selected = <ComposePickedMedia>[];
    for (final asset in assets.take(pickerMaximum)) {
      final file = await asset.file;
      if (file == null) continue;
      selected.add(
        ComposePickedMedia(
          file: await _toXFile(asset, file.path),
          mediaKind: SquareMediaKind.image,
          photoManagerAssetId: asset.id,
        ),
      );
    }
    return ComposeImageSelection(
      selected: selected,
      unavailablePhotoManagerAssetIds: unavailableIds,
    );
  }

  @override
  Future<List<ComposePickedMedia>> pickArticleMedia(
    BuildContext context,
  ) async {
    final assets = await AssetPicker.pickAssets(
      context,
      // wechat_assets_picker 的 const assert 会触发 Dart 3.11 非原始相等限制，运行值保持不变。
      // ignore: prefer_const_constructors
      pickerConfig: AssetPickerConfig(
        maxAssets: 9,
        requestType: RequestType.common,
        specialPickerType: SpecialPickerType.wechatMoment,
        themeColor: AppTheme.primary,
        textDelegate: const AssetPickerTextDelegate(),
      ),
    );
    if (assets == null || assets.isEmpty) {
      return const <ComposePickedMedia>[];
    }
    final selectedKind = assets.first.type;
    // 组件已在选择界面内互斥；返回边界仍失败关闭，避免异常平台数据进入编辑器。
    if ((selectedKind != AssetType.image && selectedKind != AssetType.video) ||
        assets.any((asset) => asset.type != selectedKind) ||
        (selectedKind == AssetType.video && assets.length != 1) ||
        (selectedKind == AssetType.image && assets.length > 9)) {
      throw const FormatException('一次只能选择 1 个视频，或 1–9 张图片');
    }
    final files = <ComposePickedMedia>[];
    for (final asset in assets) {
      final file = await asset.file;
      if (file == null) continue;
      files.add(
        ComposePickedMedia(
          file: await _toXFile(asset, file.path),
          mediaKind: asset.type == AssetType.video
              ? SquareMediaKind.video
              : SquareMediaKind.image,
          photoManagerAssetId: asset.id,
        ),
      );
    }
    return files;
  }

  Future<XFile> _toXFile(AssetEntity asset, String filePath) async {
    final title = await asset.titleAsync;
    return XFile(
      filePath,
      name: title.isEmpty ? null : title,
      mimeType: await asset.mimeTypeAsync,
    );
  }
}
