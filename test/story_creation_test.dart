import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eazy_mobile_v1/app/theme/eazy_theme.dart';
import 'package:eazy_mobile_v1/core/media/media_service.dart';
import 'package:eazy_mobile_v1/core/network/api_client.dart';
import 'package:eazy_mobile_v1/features/social/stories_tray.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient()
      : super(client: MockClient((_) async => http.Response('{}', 200)));

  Map<String, dynamic>? submittedStory;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    bool auth = false,
    Map<String, String>? headers,
  }) async {
    if (path == 'stories/feed') return {'items': <dynamic>[]};
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    Map<String, String>? headers,
  }) async {
    if (path == 'stories') submittedStory = body;
    return <String, dynamic>{};
  }
}

class _FakeMediaService extends EazyMediaService {
  _FakeMediaService(super.api);

  @override
  Future<MediaUpload?> pickAndUpload({
    required String kind,
    ImageSource source = ImageSource.gallery,
    void Function(double progress)? onProgress,
  }) async {
    return MediaUpload(
      path: 'stories/test-image.jpg',
      contentType: 'image/jpeg',
      kind: kind,
      byteSize: 128,
      fileName: 'test-image.jpg',
    );
  }
}

void main() {
  testWidgets(
    'story caption is submitted before the dialog controller is disposed',
    (tester) async {
      final api = _FakeApiClient();
      final media = _FakeMediaService(api);

      Future<void> pumpTransition() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: EazyTheme.light(),
          home: Scaffold(body: StoriesTray(api: api, media: media)),
        ),
      );
      await pumpTransition();

      await tester.tap(find.text('Your story'));
      await pumpTransition();
      await tester.tap(find.text('Photo story'));
      await pumpTransition();

      await tester.enterText(find.byType(TextField), 'A caption from the test');
      await tester.tap(find.text('Continue'));
      // The tray contains ongoing visual animations; pump the completed async
      // submission without waiting for every animation/timer to become idle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(api.submittedStory?['caption'], 'A caption from the test');
      expect(api.submittedStory?['storageKey'], 'stories/test-image.jpg');
      expect(tester.takeException(), isNull);
    },
  );
}
