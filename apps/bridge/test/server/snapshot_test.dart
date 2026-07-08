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
            path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
            mimeType: 'image/png',
            sizeBytes: 120000,
          ),
        ),
      );
    });

    tearDown(() async {
      await fixture.close();
    });

    test('captures a session-scoped PNG snapshot for a Selection Comment',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);
      final snapshotRoot = '/tmp/ask-ui-snapshots/$sessionId';
      final snapshotPath = '$snapshotRoot/snapshots/selection-comment-1.png';
      fixture.existingSnapshotPaths.add(snapshotPath);
      fixture.snapshotCapture.managedLocalPath = snapshotRoot;
      fixture.snapshotCapture.result = SnapshotCaptureResult.available(
        path: snapshotPath,
        mimeType: 'image/png',
        sizeBytes: 120000,
      );

      final request = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/snapshots'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'commentId': 'selection-comment-1',
        'format': 'png',
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
          'path': snapshotPath,
          'mimeType': 'image/png',
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

    test('rejects snapshots outside capture-managed local paths', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'ask-ui-unowned-snapshot-',
      );
      final snapshotPath = '${tempDirectory.path}/selection-comment-1.png';
      await File(snapshotPath).writeAsBytes([1, 2, 3]);
      fixture.existingSnapshotPaths.add(snapshotPath);
      fixture.snapshotCapture.result = SnapshotCaptureResult.available(
        path: snapshotPath,
        mimeType: 'image/png',
        sizeBytes: 3,
      );

      final request = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/snapshots'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'commentId': 'selection-comment-1',
        'format': 'png',
        'maxSizeBytes': 1258291,
        'scope': 'full_device',
      }));

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;
      await fixture.close();

      expect(response.statusCode, HttpStatus.ok);
      expect(body, {'status': 'unavailable'});
      expect(await tempDirectory.exists(), isTrue);

      await tempDirectory.delete(recursive: true);
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
        'format': 'png',
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

    test('reports unavailable when capture returns a missing snapshot file',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      final String sessionId = await createSession(client, fixture.baseUri);
      fixture.snapshotCapture.result = const SnapshotCaptureResult.available(
        path: '/tmp/ask-ui/session-1/snapshots/missing.png',
        mimeType: 'image/png',
        sizeBytes: 120000,
      );

      final request = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/snapshots'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'commentId': 'selection-comment-1',
        'format': 'png',
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
