import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:citizenapp/8964/compose/video/video_compose_body.dart';
import 'package:citizenapp/8964/compose/widgets/compose_media_widgets.dart';
import 'package:citizenapp/8964/models/square_models.dart';

const _video = SquareLocalMediaDraft(
  mediaKind: SquareMediaKind.video,
  path: '/tmp/video.mp4',
  fileName: 'video.mp4',
  contentType: 'video/mp4',
  byteSize: 1024,
  durationSeconds: 30,
);

class _VideoPickerFake extends ImagePicker {
  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async =>
      XFile(_video.path);
}

void main() {
  testWidgets('视频发布必须且只带一个视频', (tester) async {
    final key = GlobalKey<SquareVideoComposeBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SquareVideoComposeBody(
            key: key,
            initialText: '视频配文',
            initialMedia: const [_video],
          ),
        ),
      ),
    );

    final payload = key.currentState!.collect();
    expect(key.currentState!.isContentValid, isTrue);
    expect(payload.isValid, isTrue);
    expect(payload.text, '视频配文');
    expect(payload.mediaDrafts, const [_video]);
  });

  testWidgets('视频缺失或配文超过300字时拒绝', (tester) async {
    final emptyKey = GlobalKey<SquareVideoComposeBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SquareVideoComposeBody(key: emptyKey)),
      ),
    );
    expect(emptyKey.currentState!.collect().error, '请选择1个视频');
    expect(emptyKey.currentState!.isContentValid, isFalse);

    final overflowKey = GlobalKey<SquareVideoComposeBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SquareVideoComposeBody(
            key: overflowKey,
            initialText: '甲' * (videoTextMax + 1),
            initialMedia: const [_video],
          ),
        ),
      ),
    );
    expect(overflowKey.currentState!.collect().error, '视频配文不能超过300字');
    expect(overflowKey.currentState!.isContentValid, isFalse);
  });

  testWidgets('选中后显示真实视频区域并使用统一圆形叉号删除', (tester) async {
    final key = GlobalKey<SquareVideoComposeBodyState>();
    final changes = <SquareLocalMediaDraft?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SquareVideoComposeBody(
            key: key,
            imagePicker: _VideoPickerFake(),
            mediaDraftBuilder: (_, _) async => _video,
            onVideoChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.pump();

    await key.currentState!.pickVideo();
    await tester.pump();

    expect(find.byType(ComposeLocalVideoPreview), findsOneWidget);
    expect(find.byType(ComposeMediaRemoveButton), findsOneWidget);
    expect(changes.last, _video);

    await tester.tap(find.byType(ComposeMediaRemoveButton));
    await tester.pump();
    expect(find.byType(ComposeLocalVideoPreview), findsNothing);
    expect(changes.last, isNull);
  });
}
