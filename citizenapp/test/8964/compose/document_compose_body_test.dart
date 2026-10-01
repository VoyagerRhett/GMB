import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:citizenapp/8964/compose/compose_media_picker.dart';
import 'package:citizenapp/8964/compose/document_compose_body.dart';
import 'package:citizenapp/8964/compose/compose_media_widgets.dart';
import 'package:citizenapp/8964/square_models.dart';

class _ImagePickerFake extends ComposeMediaPicker {
  _ImagePickerFake(this.files);

  final List<XFile> files;
  int callCount = 0;
  final List<int> requestedLimits = [];

  @override
  Future<List<XFile>> pickImages(BuildContext context, int maxImages) async {
    callCount += 1;
    requestedLimits.add(maxImages);
    return files;
  }

  @override
  Future<List<ComposePickedMedia>> pickArticleMedia(BuildContext context) =>
      throw UnimplementedError();
}

SquareLocalMediaDraft _draftFor(XFile file) => SquareLocalMediaDraft(
      mediaKind: SquareMediaKind.image,
      path: file.path,
      fileName: file.name,
      contentType: 'image/jpeg',
      byteSize: 1,
    );

void main() {
  testWidgets('公文支持纯文字并固定300字上限', (tester) async {
    final key = GlobalKey<SquareDocumentComposeBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SquareDocumentComposeBody(key: key, initialText: '公文正文'),
        ),
      ),
    );

    final valid = key.currentState!.collect();
    expect(valid.isValid, isTrue);
    expect(valid.text, '公文正文');
    expect(valid.mediaDrafts, isEmpty);

    final overflowKey = GlobalKey<SquareDocumentComposeBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SquareDocumentComposeBody(
            key: overflowKey,
            initialText: '甲' * (documentTextMax + 1),
          ),
        ),
      ),
    );
    expect(overflowKey.currentState!.collect().error, '公文文字不能超过300字');
  });

  testWidgets('公文不允许空内容', (tester) async {
    final key = GlobalKey<SquareDocumentComposeBodyState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SquareDocumentComposeBody(key: key)),
      ),
    );

    expect(key.currentState!.collect().error, '公文内容不能为空');
  });

  testWidgets('公文选择器和本地状态双重限制最多9张', (tester) async {
    final key = GlobalKey<SquareDocumentComposeBodyState>();
    final picker = _ImagePickerFake(
      List<XFile>.generate(12, (index) => XFile('/tmp/image-$index.jpg')),
    );
    final counts = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SquareDocumentComposeBody(
            key: key,
            mediaPicker: picker,
            mediaDraftBuilder: (file, mediaKind) async => _draftFor(file),
            onMediaCountChanged: counts.add,
          ),
        ),
      ),
    );
    await tester.pump();

    await key.currentState!.pickImages();

    expect(picker.requestedLimits.single, documentMaxImages);
    expect(
      key.currentState!.collect().mediaDrafts,
      hasLength(documentMaxImages),
    );
    expect(counts.last, documentMaxImages);

    // 达到上限后不再唤起系统相册，防止继续选择。
    await key.currentState!.pickImages();
    expect(picker.callCount, 1);
  });

  testWidgets('公文9张删除1张后可立即补选1张', (tester) async {
    final key = GlobalKey<SquareDocumentComposeBodyState>();
    final picker = _ImagePickerFake(
      List<XFile>.generate(12, (index) => XFile('/tmp/image-$index.jpg')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SquareDocumentComposeBody(
            key: key,
            mediaPicker: picker,
            mediaDraftBuilder: (file, mediaKind) async => _draftFor(file),
          ),
        ),
      ),
    );
    await key.currentState!.pickImages();
    await tester.pump();
    await tester.tap(find.byType(ComposeMediaRemoveButton).first);
    await tester.pump();
    await key.currentState!.pickImages();

    expect(picker.requestedLimits, [9, 1]);
    expect(key.currentState!.collect().mediaDrafts, hasLength(9));
  });
}
