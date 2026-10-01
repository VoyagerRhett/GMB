import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/services/square_media_policy.dart';

enum SquareMediaDerivativeKind { thumbnail, cover }

final class SquareMediaDerivative {
  const SquareMediaDerivative({
    required this.mediaIndex,
    required this.derivativeKind,
    required this.path,
    required this.contentType,
    required this.byteSize,
  });

  final int mediaIndex;
  final SquareMediaDerivativeKind derivativeKind;
  final String path;
  final String contentType;
  final int byteSize;
}

/// 一次发布所生成的全部临时媒体；主文件和衍生图必须同生共灭。
final class SquareProcessedMediaBatch {
  SquareProcessedMediaBatch({
    required List<SquareLocalMediaDraft> mediaDrafts,
    required List<SquareMediaDerivative> derivatives,
    required this.temporaryDirectory,
  })  : mediaDrafts = List.unmodifiable(mediaDrafts),
        derivatives = List.unmodifiable(derivatives);

  final List<SquareLocalMediaDraft> mediaDrafts;
  final List<SquareMediaDerivative> derivatives;
  final Directory temporaryDirectory;

  Future<void> deleteTemporaryFiles() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }
}

final class SquareVideoCapability {
  const SquareVideoCapability({
    required this.canEncodeHevc,
    required this.canDecodeHevc,
  });

  final bool canEncodeHevc;
  final bool canDecodeHevc;
}

final class SquareVideoTranscodeRequest {
  const SquareVideoTranscodeRequest({
    required this.inputPath,
    required this.outputPath,
    required this.coverPath,
    required this.policy,
  });

  final String inputPath;
  final String outputPath;
  final String coverPath;
  final SquareMediaPolicy policy;

  Map<String, Object?> toChannelArguments() => <String, Object?>{
        'input_path': inputPath,
        'output_path': outputPath,
        'cover_path': coverPath,
        'max_width': policy.videoLongSide,
        'max_height': policy.videoShortSide,
        'video_bitrate': policy.videoBitrate,
        'total_peak_bitrate': policy.videoPeakBitrate,
        'audio_bitrate': policy.audioBitrate,
        'audio_sample_rate': SquareMediaPolicy.audioSampleRate,
        'max_frame_rate': SquareMediaPolicy.videoMaxFrameRate,
        'key_frame_interval_seconds':
            SquareMediaPolicy.videoKeyFrameIntervalSeconds,
        'max_duration_seconds': policy.maxVideoSeconds,
        'max_bytes': policy.maxVideoBytes,
        'cover_max_edge': SquareMediaPolicy.videoCoverMaxEdge,
        'cover_quality': SquareMediaPolicy.videoCoverQuality,
        'cover_max_bytes': SquareMediaPolicy.videoCoverMaxBytes,
      };
}

final class SquareVideoTranscodeResult {
  const SquareVideoTranscodeResult({
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.totalAverageBitrate,
    required this.totalPeakBitrate,
    required this.byteSize,
    required this.coverByteSize,
    required this.videoCodec,
    required this.sampleEntry,
    required this.fastStart,
    required this.isSdr,
  });

  final int durationSeconds;
  final int width;
  final int height;
  final double frameRate;
  final int totalAverageBitrate;
  final int totalPeakBitrate;
  final int byteSize;
  final int coverByteSize;
  final String videoCodec;
  final String sampleEntry;
  final bool fastStart;
  final bool isSdr;

  factory SquareVideoTranscodeResult.fromChannel(Object? value) {
    if (value is! Map) throw const FormatException('视频转码响应不合法');
    int intValue(String key) {
      final raw = value[key];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? -1;
    }

    double doubleValue(String key) {
      final raw = value[key];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '') ?? -1;
    }

    return SquareVideoTranscodeResult(
      durationSeconds: intValue('duration_seconds'),
      width: intValue('width'),
      height: intValue('height'),
      frameRate: doubleValue('frame_rate'),
      totalAverageBitrate: intValue('total_average_bitrate'),
      totalPeakBitrate: intValue('total_peak_bitrate'),
      byteSize: intValue('byte_size'),
      coverByteSize: intValue('cover_byte_size'),
      videoCodec: value['video_codec']?.toString() ?? '',
      sampleEntry: value['sample_entry']?.toString() ?? '',
      fastStart: value['fast_start'] == true,
      isSdr: value['is_sdr'] == true,
    );
  }
}

abstract interface class SquareVideoBridge {
  Future<SquareVideoCapability> capabilities();
  Future<SquareVideoTranscodeResult> transcode(
    SquareVideoTranscodeRequest request,
  );
  Future<void> cancel();
}

final class MethodChannelSquareVideoBridge implements SquareVideoBridge {
  const MethodChannelSquareVideoBridge();

  static const _channel = MethodChannel('citizenapp/square_media');

  @override
  Future<SquareVideoCapability> capabilities() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('capabilities');
    if (raw == null) throw const FormatException('设备媒体能力响应为空');
    return SquareVideoCapability(
      canEncodeHevc: raw['can_encode_hevc'] == true,
      canDecodeHevc: raw['can_decode_hevc'] == true,
    );
  }

  @override
  Future<SquareVideoTranscodeResult> transcode(
    SquareVideoTranscodeRequest request,
  ) async {
    final raw = await _channel.invokeMethod<Object?>(
      'transcode_video',
      request.toChannelArguments(),
    );
    return SquareVideoTranscodeResult.fromChannel(raw);
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel_video');
}

typedef SquareTemporaryDirectoryFactory = Future<Directory> Function();
typedef SquareImageCompressOperation = Future<XFile?> Function({
  required String inputPath,
  required String outputPath,
  required int width,
  required int height,
  required int quality,
});

/// 广场唯一手机端媒体处理入口；原始草稿永不原地覆盖。
final class SquareMediaProcessor {
  SquareMediaProcessor({
    SquareVideoBridge? videoBridge,
    SquareTemporaryDirectoryFactory? temporaryDirectoryFactory,
    SquareImageCompressOperation? imageCompressOperation,
  })  : _videoBridge = videoBridge ?? const MethodChannelSquareVideoBridge(),
        _temporaryDirectoryFactory =
            temporaryDirectoryFactory ?? _defaultTemporaryDirectory,
        _imageCompressOperation =
            imageCompressOperation ?? _defaultImageCompress;

  final SquareVideoBridge _videoBridge;
  final SquareTemporaryDirectoryFactory _temporaryDirectoryFactory;
  final SquareImageCompressOperation _imageCompressOperation;

  Future<SquareProcessedMediaBatch> process({
    required List<SquareLocalMediaDraft> mediaDrafts,
    required String membershipLevel,
  }) async {
    final policy = SquareMediaPolicy.forMembershipLevel(membershipLevel);
    final temporaryDirectory = await _temporaryDirectoryFactory();
    await temporaryDirectory.create(recursive: true);
    final processed = <SquareLocalMediaDraft>[];
    final derivatives = <SquareMediaDerivative>[];
    try {
      for (var index = 0; index < mediaDrafts.length; index++) {
        final draft = mediaDrafts[index];
        if (draft.mediaKind == SquareMediaKind.image) {
          final item = await _processImage(
            draft: draft,
            mediaIndex: index,
            policy: policy,
            temporaryDirectory: temporaryDirectory,
          );
          processed.add(item.$1);
          derivatives.add(item.$2);
        } else {
          final item = await _processVideo(
            draft: draft,
            mediaIndex: index,
            policy: policy,
            temporaryDirectory: temporaryDirectory,
          );
          processed.add(item.$1);
          derivatives.add(item.$2);
        }
      }
      return SquareProcessedMediaBatch(
        mediaDrafts: processed,
        derivatives: derivatives,
        temporaryDirectory: temporaryDirectory,
      );
    } catch (_) {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> cancel() => _videoBridge.cancel();

  Future<(SquareLocalMediaDraft, SquareMediaDerivative)> _processImage({
    required SquareLocalMediaDraft draft,
    required int mediaIndex,
    required SquareMediaPolicy policy,
    required Directory temporaryDirectory,
  }) async {
    final sourceSize = _readImageSize(draft.path);
    final primarySize = _fitLongestEdge(
      sourceSize.width,
      sourceSize.height,
      policy.imageMaxEdge,
    );
    final primaryPath = path.join(temporaryDirectory.path, '$mediaIndex.webp');
    final primary = await _compressImageWithinLimit(
      inputPath: draft.path,
      outputPath: primaryPath,
      width: primarySize.width,
      height: primarySize.height,
      quality: policy.imageQuality,
      maxBytes: policy.imageMaxBytes,
    );
    final primaryOutputSize = _readImageSize(primary.path);

    final thumbnailSize = _fitLongestEdge(
      primaryOutputSize.width,
      primaryOutputSize.height,
      SquareMediaPolicy.imageThumbnailMaxEdge,
    );
    final thumbnailPath =
        path.join(temporaryDirectory.path, '${mediaIndex}_thumbnail.webp');
    final thumbnail = await _compressImageWithinLimit(
      inputPath: primary.path,
      outputPath: thumbnailPath,
      width: thumbnailSize.width,
      height: thumbnailSize.height,
      quality: SquareMediaPolicy.imageThumbnailQuality,
      maxBytes: SquareMediaPolicy.imageThumbnailMaxBytes,
    );
    return (
      SquareLocalMediaDraft(
        mediaKind: SquareMediaKind.image,
        path: primary.path,
        fileName: '${path.basenameWithoutExtension(draft.fileName)}.webp',
        contentType: 'image/webp',
        byteSize: primary.byteSize,
        width: primaryOutputSize.width,
        height: primaryOutputSize.height,
        photoManagerAssetId: draft.photoManagerAssetId,
      ),
      SquareMediaDerivative(
        mediaIndex: mediaIndex,
        derivativeKind: SquareMediaDerivativeKind.thumbnail,
        path: thumbnail.path,
        contentType: 'image/webp',
        byteSize: thumbnail.byteSize,
      ),
    );
  }

  Future<(SquareLocalMediaDraft, SquareMediaDerivative)> _processVideo({
    required SquareLocalMediaDraft draft,
    required int mediaIndex,
    required SquareMediaPolicy policy,
    required Directory temporaryDirectory,
  }) async {
    final duration = draft.durationSeconds ?? 0;
    if (duration <= 0 || duration > policy.maxVideoSeconds) {
      throw const FormatException('视频时长超出当前会员档位上限');
    }
    final capability = await _videoBridge.capabilities();
    if (!capability.canEncodeHevc) {
      throw const FormatException('当前设备没有可用的硬件 HEVC 编码器，不能发布视频');
    }
    if (!capability.canDecodeHevc) {
      throw const FormatException('当前设备不能可靠解码 HEVC，不能发布视频');
    }
    final outputPath = path.join(temporaryDirectory.path, '$mediaIndex.mp4');
    final coverSourcePath =
        path.join(temporaryDirectory.path, '${mediaIndex}_cover_source.png');
    final result = await _videoBridge.transcode(
      SquareVideoTranscodeRequest(
        inputPath: draft.path,
        outputPath: outputPath,
        coverPath: coverSourcePath,
        policy: policy,
      ),
    );
    _validateVideoResult(result, policy);
    if (!await File(outputPath).exists() ||
        !await File(coverSourcePath).exists()) {
      throw const FormatException('视频转码没有生成完整成品');
    }
    final actualBytes = await File(outputPath).length();
    final actualCoverSourceBytes = await File(coverSourcePath).length();
    if (actualBytes != result.byteSize ||
        actualCoverSourceBytes != result.coverByteSize) {
      throw const FormatException('视频转码文件大小与原生校验结果不一致');
    }
    final coverSourceSize = _readImageSize(coverSourcePath);
    final coverSize = _fitLongestEdge(
      coverSourceSize.width,
      coverSourceSize.height,
      SquareMediaPolicy.videoCoverMaxEdge,
    );
    final coverPath =
        path.join(temporaryDirectory.path, '${mediaIndex}_cover.webp');
    final cover = await _compressImageWithinLimit(
      inputPath: coverSourcePath,
      outputPath: coverPath,
      width: coverSize.width,
      height: coverSize.height,
      quality: SquareMediaPolicy.videoCoverQuality,
      maxBytes: SquareMediaPolicy.videoCoverMaxBytes,
    );
    await File(coverSourcePath).delete();
    return (
      SquareLocalMediaDraft(
        mediaKind: SquareMediaKind.video,
        path: outputPath,
        fileName: '${path.basenameWithoutExtension(draft.fileName)}.mp4',
        contentType: 'video/mp4',
        byteSize: actualBytes,
        durationSeconds: result.durationSeconds,
        width: result.width,
        height: result.height,
        photoManagerAssetId: draft.photoManagerAssetId,
      ),
      SquareMediaDerivative(
        mediaIndex: mediaIndex,
        derivativeKind: SquareMediaDerivativeKind.cover,
        path: cover.path,
        contentType: 'image/webp',
        byteSize: cover.byteSize,
      ),
    );
  }

  void _validateVideoResult(
    SquareVideoTranscodeResult result,
    SquareMediaPolicy policy,
  ) {
    if (result.videoCodec != 'hevc' || result.sampleEntry != 'hvc1') {
      throw const FormatException('视频成品不是唯一允许的 HEVC/hvc1');
    }
    if (!result.fastStart || !result.isSdr) {
      throw const FormatException('视频成品不满足 SDR 或快速起播要求');
    }
    if (result.durationSeconds <= 0 ||
        result.durationSeconds > policy.maxVideoSeconds ||
        result.width <= 0 ||
        result.height <= 0 ||
        result.width > policy.videoLongSide ||
        result.height > policy.videoLongSide ||
        result.width > policy.videoShortSide &&
            result.height > policy.videoShortSide ||
        result.frameRate <= 0 ||
        result.frameRate > SquareMediaPolicy.videoMaxFrameRate + 0.01 ||
        result.totalAverageBitrate > policy.videoTotalBitrate * 1.08 ||
        result.totalPeakBitrate > policy.videoPeakBitrate ||
        result.byteSize <= 0 ||
        result.byteSize > policy.maxVideoBytes ||
        result.coverByteSize <= 0) {
      throw const FormatException('视频成品参数超出当前会员档位');
    }
  }

  Future<({String path, int byteSize})> _compressImageWithinLimit({
    required String inputPath,
    required String outputPath,
    required int width,
    required int height,
    required int quality,
    required int maxBytes,
  }) async {
    var attemptWidth = width;
    var attemptHeight = height;
    var attemptQuality = quality;
    for (var attempt = 0; attempt < 12; attempt++) {
      final attemptPath = '${path.withoutExtension(outputPath)}_$attempt.webp';
      final result = await _imageCompressOperation(
        inputPath: inputPath,
        outputPath: attemptPath,
        width: attemptWidth,
        height: attemptHeight,
        quality: attemptQuality,
      );
      if (result == null) throw const FormatException('图片压缩失败');
      final byteSize = await result.length();
      if (byteSize > 0 && byteSize <= maxBytes) {
        final finalFile = await File(result.path).rename(outputPath);
        return (path: finalFile.path, byteSize: byteSize);
      }
      try {
        await File(result.path).delete();
      } on FileSystemException {
        // 失败尝试仍位于本批次临时目录，批次结束时递归清理。
      }
      if (attemptQuality > 45) {
        attemptQuality -= 5;
      } else {
        attemptWidth = (attemptWidth * 0.85).round().clamp(2, width);
        attemptHeight = (attemptHeight * 0.85).round().clamp(2, height);
      }
    }
    throw const FormatException('图片无法压缩到当前会员档位上限');
  }

  ({int width, int height}) _readImageSize(String filePath) {
    final result = ImageSizeGetter.getSizeResult(FileInput(File(filePath)));
    final size = result.size;
    final width = size.needRotate ? size.height : size.width;
    final height = size.needRotate ? size.width : size.height;
    if (width <= 0 || height <= 0) throw const FormatException('图片尺寸不合法');
    return (width: width, height: height);
  }

  ({int width, int height}) _fitLongestEdge(
    int width,
    int height,
    int maxEdge,
  ) {
    final longest = width > height ? width : height;
    if (longest <= maxEdge) return (width: width, height: height);
    final scale = maxEdge / longest;
    return (
      width: _even((width * scale).round()),
      height: _even((height * scale).round()),
    );
  }

  int _even(int value) {
    final bounded = value < 2 ? 2 : value;
    return bounded.isEven ? bounded : bounded - 1;
  }

  static Future<Directory> _defaultTemporaryDirectory() async {
    final root = await getTemporaryDirectory();
    return Directory(
      path.join(
        root.path,
        'square_media',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
  }

  static Future<XFile?> _defaultImageCompress({
    required String inputPath,
    required String outputPath,
    required int width,
    required int height,
    required int quality,
  }) {
    return FlutterImageCompress.compressAndGetFile(
      inputPath,
      outputPath,
      minWidth: width,
      minHeight: height,
      quality: quality,
      format: CompressFormat.webp,
      autoCorrectionAngle: true,
      keepExif: false,
    );
  }
}
