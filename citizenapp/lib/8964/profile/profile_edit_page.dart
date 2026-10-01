import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:citizenapp/8964/profile/models/citizen_profile.dart';
import 'package:citizenapp/8964/profile/models/profile_presentation.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_api.dart';
import 'package:citizenapp/8964/profile/services/citizen_profile_cache.dart';
import 'package:citizenapp/8964/profile/services/profile_asset_service.dart';
import 'package:citizenapp/8964/profile/services/square_session_provider.dart';
import 'package:citizenapp/8964/services/square_api_client.dart';
import 'package:citizenapp/ui/app_theme.dart';
import 'package:citizenapp/ui/app_layout.dart';

/// 编辑本人公开资料：公开昵称 + 签名 + 头像 + 背景。
///
/// 公开昵称唯一真源是按 `cid_number` 寻址的 `display_name`；本机钱包名只是
/// 钱包标签，本页不得读取或修改它。
/// 头像/背景上传到 R2（不上链），保存时随 `PUT /profile` 写入 object_key。
class CitizenProfileEditPage extends StatefulWidget {
  const CitizenProfileEditPage({
    super.key,
    required this.cidNumber,
    this.initialProfile,
    this.api,
    this.cache,
    this.sessionProvider,
    this.assetService,
    this.imagePicker,
  });

  /// 主页身份主键 cid_number（默认头像/背景的稳定派生种子，也是资料寻址主键）。
  final String cidNumber;
  final CitizenProfile? initialProfile;
  final CitizenProfileApi? api;
  final CitizenProfileCache? cache;
  final SquareSessionProvider? sessionProvider;
  final ProfileAssetService? assetService;
  final ImagePicker? imagePicker;

  @override
  State<CitizenProfileEditPage> createState() => _CitizenProfileEditPageState();
}

class _PendingImage {
  const _PendingImage({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

class _CitizenProfileEditPageState extends State<CitizenProfileEditPage> {
  static const int _displayNameMax = 40;
  static const int _bioMax = 160;

  late final CitizenProfileApi _api;
  late final CitizenProfileCache _cache;
  late final SquareSessionProvider _sessionProvider;
  late final ProfileAssetService _assetService;
  late final ImagePicker _imagePicker;
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;

  _PendingImage? _pendingAvatar;
  _PendingImage? _pendingBanner;
  CitizenProfileMediaSnapshot _media = const CitizenProfileMediaSnapshot();
  CitizenProfile? _savedRemotely;
  bool _saving = false;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? CitizenProfileApi();
    _cache = widget.cache ?? const CitizenProfileCache();
    _assetService = widget.assetService ?? ProfileAssetService();
    _imagePicker = widget.imagePicker ?? ImagePicker();
    // 公开昵称只从资料真源预填；空资料使用稳定默认昵称，不读取本机钱包标签。
    _nameController = TextEditingController(
      text: widget.initialProfile?.displayName ?? '',
    );
    _bioController = TextEditingController(
      text: widget.initialProfile?.bio ?? '',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _sessionProvider =
        widget.sessionProvider ?? context.read<SquareSessionProvider>();
    _dependenciesReady = true;
    _loadLocalMedia();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalMedia() async {
    final profile = widget.initialProfile;
    if (profile == null) return;
    try {
      final local = await CitizenProfileMediaCache().read(profile);
      if (mounted) setState(() => _media = local);
    } catch (_) {
      /* 缺失时保持占位，编辑页不自动下载。 */
    }
  }

  Future<void> _pickImage(bool isAvatar) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: isAvatar ? 1024 : 1920,
        maxHeight: isAvatar ? 1024 : 720,
        imageQuality: isAvatar ? 70 : 75,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      final pending = _PendingImage(
        bytes: bytes,
        contentType: _contentTypeForPath(picked.path),
      );
      setState(() {
        if (isAvatar) {
          _pendingAvatar = pending;
        } else {
          _pendingBanner = pending;
        }
      });
    } on Exception catch (error) {
      _snack('选择图片失败：$error');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final pending = await _cache.readUpdate(widget.cidNumber);
      if (pending?.operationState == 'confirmed') {
        await _saveLocal();
        return;
      }
      final session = await _sessionProvider.ensureSession();
      if (session == null) {
        _snack('请先在「我的 → 我的钱包」创建热钱包');
        return;
      }
      if (session.cidNumber != widget.cidNumber || !session.isUsable) {
        throw StateError('资料修改身份已变化');
      }
      if (pending != null) {
        // 重启后先读取远端事实；未能证明成功时不自动重放PUT。
        final remote = await _api.fetchProfile(
          widget.cidNumber,
          session: session,
        );
        if (_cache.updateMatches(pending, remote)) {
          await _cache.confirmUpdate(remote);
          await _saveLocal();
          return;
        }
        if (!mounted) return;
        final resume = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('恢复上次修改'),
            content: const Text('远端资料与上次待保存内容不同，是否继续保存上次修改？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续保存'),
              ),
            ],
          ),
        );
        if (resume != true) return;
        final request = Map<String, String>.from(
          jsonDecode(pending.requestJson) as Map,
        );
        final updated = await _sendUpdate(session, request);
        await _cache.confirmUpdate(updated);
        _savedRemotely = updated;
        await _saveLocal();
        return;
      }

      String? avatarKey;
      String? avatarHash;
      if (_pendingAvatar != null) {
        final result = await _assetService.upload(
          session: session,
          kind: 'avatar',
          bytes: _pendingAvatar!.bytes,
          contentType: _pendingAvatar!.contentType,
        );
        avatarKey = result.objectKey;
        avatarHash = result.contentHash;
      }

      String? bannerKey;
      String? bannerHash;
      if (_pendingBanner != null) {
        final result = await _assetService.upload(
          session: session,
          kind: 'banner',
          bytes: _pendingBanner!.bytes,
          contentType: _pendingBanner!.contentType,
        );
        bannerKey = result.objectKey;
        bannerHash = result.contentHash;
      }

      final nickname = _nameController.text.trim();
      final request = <String, String>{
        'display_name': nickname,
        'bio': _bioController.text.trim(),
        'avatar_object_key': ?avatarKey,
        'avatar_content_hash': ?avatarHash,
        'banner_object_key': ?bannerKey,
        'banner_content_hash': ?bannerHash,
      };
      await _cache.prepareUpdate(
        widget.cidNumber,
        request: request,
        avatarBytes: _pendingAvatar?.bytes,
        bannerBytes: _pendingBanner?.bytes,
      );
      final updated = await _sendUpdate(session, request);

      // 远端成功后保留响应；本地失败时只重试本地事务，不再次上传或修改远端。
      _savedRemotely = updated;
      await _cache.confirmUpdate(updated);
      await _saveLocal();
    } on SquareApiException catch (error) {
      if (!mounted) return;
      _snack(error.message);
    } catch (_) {
      if (!mounted) return;
      _snack(
        _savedRemotely == null ? '保存未完成，点击保存可恢复上次修改' : '远端已保存，本机收尾未完成，点击保存可恢复',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 远端成功后的本地收尾只提交一次资料和图片，失败保持页面供重试。
  Future<CitizenProfile> _sendUpdate(
    SquareSession session,
    Map<String, String> request,
  ) => _api.updateProfile(
    session: session,
    displayName: request['display_name'],
    bio: request['bio'],
    avatarObjectKey: request['avatar_object_key'],
    avatarContentHash: request['avatar_content_hash'],
    bannerObjectKey: request['banner_object_key'],
    bannerContentHash: request['banner_content_hash'],
  );

  Future<void> _saveLocal() async {
    final profile = await _cache.finishUpdate(widget.cidNumber);
    if (mounted) Navigator.of(context).pop(profile);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _contentTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final avatarKey = widget.initialProfile?.avatarObjectKey;
    final bannerKey = widget.initialProfile?.bannerObjectKey;
    final defaults = ProfilePresentation.forIdentityKey(widget.cidNumber);
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑资料'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: AppLayout.scaled(context, 18),
                    height: AppLayout.scaled(context, 18),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: IgnorePointer(
        ignoring: _saving || _savedRemotely != null,
        child: ListView(
          padding: EdgeInsets.all(AppLayout.scaled(context, 16)),
          children: [
            _AssetRow(
              label: '背景',
              width: double.infinity,
              height: AppLayout.scaled(context, 120),
              radius: AppTheme.radiusMd,
              preview: _pendingBanner?.bytes,
              imagePath: _media.bannerPath,
              userImageSet: bannerKey != null,
              fallbackAsset: defaults.bannerAsset,
              onTap: () => _pickImage(false),
            ),
            SizedBox(height: AppLayout.scaled(context, 16)),
            _AssetRow(
              label: '头像',
              width: AppLayout.scaled(context, 84),
              height: AppLayout.scaled(context, 84),
              radius: AppLayout.scaled(context, 16),
              preview: _pendingAvatar?.bytes,
              imagePath: _media.avatarPath,
              userImageSet: avatarKey != null,
              fallbackAsset: defaults.avatarAsset,
              onTap: () => _pickImage(true),
            ),
            SizedBox(height: AppLayout.scaled(context, 20)),
            TextField(
              controller: _nameController,
              maxLength: _displayNameMax,
              decoration: const InputDecoration(
                labelText: '公开昵称',
                hintText: '给自己起个名字',
              ),
            ),
            SizedBox(height: AppLayout.scaled(context, 16)),
            TextField(
              controller: _bioController,
              maxLength: _bioMax,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '个性签名',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.label,
    required this.width,
    required this.height,
    required this.radius,
    required this.preview,
    required this.imagePath,
    required this.userImageSet,
    required this.fallbackAsset,
    required this.onTap,
  });

  final String label;
  final double width;
  final double height;
  final double radius;
  final Uint8List? preview;
  final String? imagePath;
  final bool userImageSet;
  final String fallbackAsset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppLayout.scaled(context, 15),
            color: AppTheme.textPrimary,
          ),
        ),
        const Spacer(),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            width: width == double.infinity ? 200 : width,
            height: height,
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: AppTheme.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final bytes = preview;
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover);
    }
    final path = imagePath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Center(child: Text('本地图片读取失败')),
      );
    }
    if (userImageSet) return const Center(child: Text('本地尚未保存图片'));
    return _fallback();
  }

  Widget _fallback() {
    return Image.asset(fallbackAsset, fit: BoxFit.cover);
  }
}
