import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:citizenapp/8964/square_models.dart';
import 'package:citizenapp/8964/services/square_media_policy.dart';
import 'package:citizenapp/8964/services/square_media_processor.dart';

void main() {
  group('SquareMediaPolicy', () {
    test('三个会员档位使用唯一确定的图片与视频规则', () {
      expect(
        (
          SquareMediaPolicy.freedom.imageMaxEdge,
          SquareMediaPolicy.freedom.imageQuality,
          SquareMediaPolicy.freedom.imageMaxBytes,
          SquareMediaPolicy.freedom.videoShortSide,
          SquareMediaPolicy.freedom.videoTotalBitrate,
          SquareMediaPolicy.freedom.maxVideoSeconds,
          SquareMediaPolicy.freedom.maxVideoBytes,
        ),
        (1280, 72, 1000000, 480, 600000, 180, 16000000),
      );
      expect(
        (
          SquareMediaPolicy.democracy.imageMaxEdge,
          SquareMediaPolicy.democracy.imageQuality,
          SquareMediaPolicy.democracy.imageMaxBytes,
          SquareMediaPolicy.democracy.videoShortSide,
          SquareMediaPolicy.democracy.videoTotalBitrate,
          SquareMediaPolicy.democracy.maxVideoSeconds,
          SquareMediaPolicy.democracy.maxVideoBytes,
        ),
        (1920, 80, 2000000, 720, 1200000, 1800, 300000000),
      );
      expect(
        (
          SquareMediaPolicy.spark.imageMaxEdge,
          SquareMediaPolicy.spark.imageQuality,
          SquareMediaPolicy.spark.imageMaxBytes,
          SquareMediaPolicy.spark.videoShortSide,
          SquareMediaPolicy.spark.videoTotalBitrate,
          SquareMediaPolicy.spark.maxVideoSeconds,
          SquareMediaPolicy.spark.maxVideoBytes,
        ),
        (2560, 85, 4000000, 1080, 2000000, 10800, 3000000000),
      );
      expect(SquareMediaPolicy.imageThumbnailMaxEdge, 480);
      expect(SquareMediaPolicy.videoCoverMaxBytes, 512000);
      expect(
        () => SquareMediaPolicy.forMembershipLevel('unknown'),
        throwsFormatException,
      );
    });
  });

  group('SquareMediaProcessor', () {
    late Directory root;
    late Directory batchDirectory;
    late File sourceImage;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('square_media_test_');
      batchDirectory = Directory('${root.path}/batch');
      sourceImage = File('${root.path}/source.png');
      await sourceImage.writeAsBytes(
        img.encodePng(img.Image(width: 2000, height: 1000)),
      );
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('图片按会员规则生成 WebP 主文件与缩略图元数据', () async {
      final calls = <({int width, int height, int quality})>[];
      final processor = SquareMediaProcessor(
        videoBridge: _FakeVideoBridge(),
        temporaryDirectoryFactory: () async => batchDirectory,
        imageCompressOperation: ({
          required inputPath,
          required outputPath,
          required width,
          required height,
          required quality,
        }) async {
          calls.add((width: width, height: height, quality: quality));
          final output = File(outputPath);
          await output.writeAsBytes(
            img.encodePng(img.Image(width: width, height: height)),
          );
          return XFile(output.path);
        },
      );

      final batch = await processor.process(
        membershipLevel: 'freedom',
        mediaDrafts: [
          SquareLocalMediaDraft(
            mediaKind: SquareMediaKind.image,
            path: sourceImage.path,
            fileName: 'source.jpg',
            contentType: 'image/jpeg',
            byteSize: await sourceImage.length(),
          ),
        ],
      );

      expect(calls, [
        (width: 1280, height: 640, quality: 72),
        (width: 480, height: 240, quality: 70)
      ]);
      expect(batch.mediaDrafts.single.contentType, 'image/webp');
      expect(batch.mediaDrafts.single.fileName, 'source.webp');
      expect(batch.mediaDrafts.single.width, 1280);
      expect(batch.mediaDrafts.single.height, 640);
      expect(batch.derivatives.single.derivativeKind,
          SquareMediaDerivativeKind.thumbnail);
      expect(await File(batch.derivatives.single.path).exists(), isTrue);

      await batch.deleteTemporaryFiles();
      expect(await batchDirectory.exists(), isFalse);
    });

    test('视频使用单份 HEVC 成品并把原生封面转成 WebP', () async {
      final bridge = _FakeVideoBridge();
      final processor = SquareMediaProcessor(
        videoBridge: bridge,
        temporaryDirectoryFactory: () async => batchDirectory,
        imageCompressOperation: ({
          required inputPath,
          required outputPath,
          required width,
          required height,
          required quality,
        }) async {
          final output = File(outputPath);
          await output.writeAsBytes(
            img.encodePng(img.Image(width: width, height: height)),
          );
          return XFile(output.path);
        },
      );
      final sourceVideo = File('${root.path}/source.mov')
        ..writeAsBytesSync([1]);

      final batch = await processor.process(
        membershipLevel: 'freedom',
        mediaDrafts: [
          SquareLocalMediaDraft(
            mediaKind: SquareMediaKind.video,
            path: sourceVideo.path,
            fileName: 'source.mov',
            contentType: 'video/quicktime',
            byteSize: 1,
            durationSeconds: 120,
          ),
        ],
      );

      expect(bridge.lastRequest?.policy, same(SquareMediaPolicy.freedom));
      expect(batch.mediaDrafts.single.contentType, 'video/mp4');
      expect(batch.mediaDrafts.single.fileName, 'source.mp4');
      expect(batch.mediaDrafts.single.byteSize, 4);
      expect(batch.derivatives.single.derivativeKind,
          SquareMediaDerivativeKind.cover);
      expect(batch.derivatives.single.contentType, 'image/webp');
      expect(await File('${batchDirectory.path}/0_cover_source.png').exists(),
          isFalse);
    });

    test('设备不支持硬件 HEVC 编码或解码时失败关闭并清理整个批次', () async {
      final sourceVideo = File('${root.path}/source.mov')
        ..writeAsBytesSync([1]);
      for (final bridge in [
        _FakeVideoBridge(canEncodeHevc: false),
        _FakeVideoBridge(canDecodeHevc: false),
      ]) {
        final processor = SquareMediaProcessor(
          videoBridge: bridge,
          temporaryDirectoryFactory: () async => batchDirectory,
        );
        await expectLater(
          processor.process(
            membershipLevel: 'freedom',
            mediaDrafts: [
              SquareLocalMediaDraft(
                mediaKind: SquareMediaKind.video,
                path: sourceVideo.path,
                fileName: 'source.mov',
                contentType: 'video/quicktime',
                byteSize: 1,
                durationSeconds: 30,
              ),
            ],
          ),
          throwsFormatException,
        );
        expect(await batchDirectory.exists(), isFalse);
      }
    });
  });
}

final class _FakeVideoBridge implements SquareVideoBridge {
  _FakeVideoBridge({this.canEncodeHevc = true, this.canDecodeHevc = true});

  final bool canEncodeHevc;
  final bool canDecodeHevc;
  SquareVideoTranscodeRequest? lastRequest;

  @override
  Future<SquareVideoCapability> capabilities() async => SquareVideoCapability(
        canEncodeHevc: canEncodeHevc,
        canDecodeHevc: canDecodeHevc,
      );

  @override
  Future<void> cancel() async {}

  @override
  Future<SquareVideoTranscodeResult> transcode(
    SquareVideoTranscodeRequest request,
  ) async {
    lastRequest = request;
    await File(request.outputPath).writeAsBytes([1, 2, 3, 4]);
    final cover = img.encodePng(img.Image(width: 1280, height: 720));
    await File(request.coverPath).writeAsBytes(cover);
    return SquareVideoTranscodeResult(
      durationSeconds: 120,
      width: 854,
      height: 480,
      frameRate: 30,
      totalAverageBitrate: 580000,
      totalPeakBitrate: 850000,
      byteSize: 4,
      coverByteSize: cover.length,
      videoCodec: 'hevc',
      sampleEntry: 'hvc1',
      fastStart: true,
      isSdr: true,
    );
  }
}
