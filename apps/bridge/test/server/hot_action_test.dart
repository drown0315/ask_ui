import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'bridge_server_test_harness.dart';

void main() {
  group('AskUiBridgeServer hot action API', () {
    late BridgeServerFixture fixture;

    setUp(() async {
      fixture = BridgeServerFixture();
      await fixture.start();
    });

    tearDown(() async {
      await fixture.close();
    });

    test('returns a clear unsupported response for hot restart', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final sessionId = await createSession(client, fixture.baseUri);

      final restartRequest = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/hot-restart'),
      );
      final restartResponse = await restartRequest.close();
      final restartBody = jsonDecode(await utf8.decodeStream(restartResponse))
          as Map<String, Object?>;

      expect(restartResponse.statusCode, HttpStatus.notImplemented);
      expect(fixture.appController.hotRestartSessionIds, [sessionId]);
      expect(
        restartBody,
        containsPair('error', 'hot_restart_not_supported_for_session'),
      );
      expect(
        restartBody['message'],
        'Hot restart is not available for this bridge session.',
      );
      expect(
        fixture.logs,
        contains(
            '[ask_ui_bridge] hot_restart request session=$sessionId start'),
      );
      expect(
        fixture.logs,
        contains(
            '[ask_ui_bridge] hot_restart request session=$sessionId unsupported'),
      );
    });

    test('runs hot reload for an existing session', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final sessionId = await createSession(client, fixture.baseUri);

      final reloadRequest = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/hot-reload'),
      );
      final reloadResponse = await reloadRequest.close();
      final reloadBody = jsonDecode(await utf8.decodeStream(reloadResponse))
          as Map<String, Object?>;

      expect(reloadResponse.statusCode, HttpStatus.ok);
      expect(fixture.appController.hotReloadSessionIds, [sessionId]);
      expect(
        reloadBody,
        {
          'status': 'ok',
          'message': 'Hot reload completed.',
          'reloadReport': {
            'success': true,
          },
        },
      );
      expect(
        fixture.logs,
        contains('[ask_ui_bridge] hot_reload request session=$sessionId start'),
      );
      expect(
        fixture.logs,
        contains(
            '[ask_ui_bridge] hot_reload request session=$sessionId success'),
      );
    });

    test('returns hot restart failures from the app controller', () async {
      final client = HttpClient();
      addTearDown(client.close);
      fixture.appController.hotRestartFailure =
          Exception('Flutter tool disconnected');

      final sessionId = await createSession(client, fixture.baseUri);

      final restartRequest = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/hot-restart'),
      );
      final restartResponse = await restartRequest.close();
      final restartBody = jsonDecode(await utf8.decodeStream(restartResponse))
          as Map<String, Object?>;

      expect(restartResponse.statusCode, HttpStatus.badGateway);
      expect(restartBody, containsPair('error', 'hot_restart_failed'));
      expect(restartBody['message'], contains('Flutter tool disconnected'));
    });

    test('returns hot restart success from the app controller', () async {
      final client = HttpClient();
      addTearDown(client.close);
      fixture.appController.hotRestartSucceeds = true;

      final sessionId = await createSession(client, fixture.baseUri);

      final restartRequest = await client.postUrl(
        fixture.baseUri.resolve('/api/sessions/$sessionId/hot-restart'),
      );
      final restartResponse = await restartRequest.close();
      final restartBody = jsonDecode(await utf8.decodeStream(restartResponse))
          as Map<String, Object?>;

      expect(restartResponse.statusCode, HttpStatus.ok);
      expect(fixture.appController.hotRestartSessionIds, [sessionId]);
      expect(restartBody, {
        'status': 'ok',
        'message': 'Hot restart completed.',
      });
      expect(
        fixture.logs,
        contains(
            '[ask_ui_bridge] hot_restart request session=$sessionId start'),
      );
      expect(
        fixture.logs,
        contains(
            '[ask_ui_bridge] hot_restart request session=$sessionId success'),
      );
    });
  });
}
