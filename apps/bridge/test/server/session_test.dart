import 'dart:convert';
import 'dart:io';

import 'package:ask_ui_bridge/sessions/flutter_device_checker.dart';
import 'package:test/test.dart';

import 'bridge_server_test_harness.dart';

void main() {
  group('AskUiBridgeServer session API', () {
    late BridgeServerFixture fixture;

    setUp(() async {
      fixture = BridgeServerFixture();
      await fixture.start();
    });

    tearDown(() async {
      await fixture.close();
    });

    test('returns 400 when creating a session without required parameters',
        () async {
      final client = HttpClient();
      addTearDown(client.close);

      final request =
          await client.postUrl(fixture.baseUri.resolve('/api/sessions'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'vmServiceUri': 'ws://127.0.0.1:12345/ws'}));

      final response = await request.close();
      final body = await utf8.decodeStream(response);

      expect(response.statusCode, HttpStatus.badRequest);
      expect(jsonDecode(body),
          containsPair('error', 'missing_session_parameters'));
    });

    test('returns 400 when creating a session with a blank deviceId', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final request =
          await client.postUrl(fixture.baseUri.resolve('/api/sessions'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
          'deviceId': '  ',
        }),
      );

      final response = await request.close();
      final body = await utf8.decodeStream(response);

      expect(response.statusCode, HttpStatus.badRequest);
      expect(jsonDecode(body),
          containsPair('error', 'missing_session_parameters'));
    });

    test('creates a session from vmServiceUri and projectRoot', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final request =
          await client.postUrl(fixture.baseUri.resolve('/api/sessions'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
          'deviceId': '19271FDF6007TY',
        }),
      );

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.ok);
      expect(body['sessionId'], isA<String>());
      expect(body['sessionId'], isNotEmpty);
    });

    test('returns 400 when target device is not visible to Flutter', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final request =
          await client.postUrl(fixture.baseUri.resolve('/api/sessions'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
          'deviceId': 'missing-device',
        }),
      );

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.badRequest);
      expect(body, containsPair('error', 'target_device_not_found'));
      expect(
        body,
        containsPair(
          'message',
          'Target Device missing-device is not listed by Flutter.',
        ),
      );
      expect(body, containsPair('deviceId', 'missing-device'));
    });

    test('returns 400 when target device is visible but unavailable', () async {
      await fixture.restartWithDeviceChecker(
        const FakeFlutterDeviceChecker(
          {'unavailable-device'},
          unavailableDeviceIds: {'unavailable-device'},
        ),
      );

      final client = HttpClient();
      addTearDown(client.close);

      final request =
          await client.postUrl(fixture.baseUri.resolve('/api/sessions'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
          'deviceId': 'unavailable-device',
        }),
      );

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.badRequest);
      expect(body, containsPair('error', 'target_device_unavailable'));
      expect(
        body,
        containsPair(
          'message',
          'Target Device unavailable-device is not available.',
        ),
      );
      expect(body, containsPair('deviceId', 'unavailable-device'));
    });

    test('returns 400 and logs when target device check fails', () async {
      await fixture.restartWithDeviceChecker(FailingFlutterDeviceChecker());

      final client = HttpClient();
      addTearDown(client.close);

      final request =
          await client.postUrl(fixture.baseUri.resolve('/api/sessions'));
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'vmServiceUri': 'ws://127.0.0.1:12345/ws',
          'projectRoot': '/Users/example/app',
          'deviceId': 'device-1',
        }),
      );

      final response = await request.close();
      final body =
          jsonDecode(await utf8.decodeStream(response)) as Map<String, Object?>;

      expect(response.statusCode, HttpStatus.badRequest);
      expect(body, containsPair('error', 'target_device_check_failed'));
      expect(
        body,
        containsPair(
          'message',
          'Ask UI could not check Flutter target devices.',
        ),
      );
      expect(jsonEncode(body), isNot(contains('flutter devices --machine')));
      expect(jsonEncode(body), isNot(contains('Flutter devices exploded')));
      expect(fixture.logs, contains(contains('target_device_check_failed')));
      expect(fixture.logs, contains(contains('flutter devices --machine')));
      expect(fixture.logs, contains(contains('Flutter devices exploded')));
      expect(fixture.logs, contains(contains('Stack trace')));
    });

    test('returns the same session for repeated target parameters', () async {
      final client = HttpClient();
      addTearDown(client.close);

      final firstSessionId = await createSession(client, fixture.baseUri);
      final secondSessionId = await createSession(client, fixture.baseUri);

      expect(secondSessionId, firstSessionId);
    });

    test('rejects a different deviceId for an existing Flutter app session',
        () async {
      final client = HttpClient();
      addTearDown(client.close);

      Future<HttpClientResponse> createSessionWithDevice(
        String deviceId,
      ) async {
        final request =
            await client.postUrl(fixture.baseUri.resolve('/api/sessions'));
        request.headers.contentType = ContentType.json;
        request.write(
          jsonEncode({
            'vmServiceUri': 'ws://127.0.0.1:12345/ws',
            'projectRoot': '/Users/example/app',
            'deviceId': deviceId,
          }),
        );
        return request.close();
      }

      final firstResponse = await createSessionWithDevice('device-1');
      await utf8.decodeStream(firstResponse);

      final secondResponse = await createSessionWithDevice('device-2');
      final secondBody = jsonDecode(await utf8.decodeStream(secondResponse))
          as Map<String, Object?>;

      expect(firstResponse.statusCode, HttpStatus.ok);
      expect(secondResponse.statusCode, HttpStatus.badRequest);
      expect(secondBody, containsPair('error', 'device_mismatch_for_session'));
      expect(
        secondBody,
        containsPair(
          'message',
          'VM Service device does not match Target Device device-2.',
        ),
      );
      expect(secondBody, containsPair('expectedDeviceId', 'device-1'));
      expect(secondBody, containsPair('requestedDeviceId', 'device-2'));
    });
  });
}
