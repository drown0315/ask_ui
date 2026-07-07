import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'bridge_server_test_harness.dart';

void main() {
  group('AskUiBridgeServer snapshot API', () {
    late BridgeServerFixture fixture;

    setUp(() async {
      fixture = BridgeServerFixture();
      await fixture.start(
        snapshotCapture: RecordingSnapshotCapture(
          result: const SnapshotCaptureResult.available(
            path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 120000,
          ),
        ),
      );
    });

    tearDown(() async {
      await fixture.close();
    });

    test('captures a session-scoped JPEG snapshot for a Selection Comment',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);

      final request = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/snapshots'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'commentId': 'selection-comment-1',
        'format': 'jpeg',
        'maxSizeBytes': 1258291,
        'scope': 'full_device',
      }));

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.ok);
      expect(body, {
        'status': 'ok',
        'snapshot': {
          'path': '/tmp/ask-ui/session-1/snapshots/selection-comment-1.jpg',
          'mimeType': 'image/jpeg',
          'sizeBytes': 120000,
        },
      });
      expect(fixture.snapshotCapture.requests, [
        RecordedSnapshotCaptureRequest(
          sessionId: sessionId,
          commentId: 'selection-comment-1',
          maxSizeBytes: 1258291,
        ),
      ]);
    });

    test('reports snapshot capture unavailable without failing the session',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);
      fixture.snapshotCapture.result =
          const SnapshotCaptureResult.unavailable();

      final request = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/snapshots'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'commentId': 'selection-comment-1',
        'format': 'jpeg',
        'maxSizeBytes': 1258291,
        'scope': 'full_device',
      }));

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.ok);
      expect(body, {
        'status': 'unavailable',
      });
    });
  });
}
