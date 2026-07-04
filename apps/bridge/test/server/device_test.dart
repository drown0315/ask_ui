import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'bridge_server_test_harness.dart';

void main() {
  group('AskUiBridgeServer device WebSocket', () {
    late BridgeServerFixture fixture;

    setUp(() async {
      fixture = BridgeServerFixture();
      await fixture.start();
    });

    tearDown(() async {
      await fixture.close();
    });

    test('opens a device WebSocket with ready metadata', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final sessionId = await createSession(client, fixture.baseUri);
      final deviceUri = fixture.baseUri.replace(
        scheme: 'ws',
        path: '/api/sessions/$sessionId/device',
      );

      final socket = await WebSocket.connect(deviceUri.toString());
      addTearDown(socket.close);

      final message = jsonDecode(await socket.first.timeout(
        const Duration(seconds: 2),
      )) as Map<String, Object?>;

      expect(message, {
        'type': 'ready',
        'deviceId': '19271FDF6007TY',
        'screenWidth': 1080,
        'screenHeight': 2400,
        'maxFps': 60,
        'videoCodec': 'h264',
        'controlReady': true,
      });
    });

    test('rejects a second active device WebSocket for one session', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final sessionId = await createSession(client, fixture.baseUri);
      final deviceUri = fixture.baseUri.replace(
        scheme: 'ws',
        path: '/api/sessions/$sessionId/device',
      );

      final firstSocket = await WebSocket.connect(deviceUri.toString());
      addTearDown(firstSocket.close);
      await firstSocket.first.timeout(const Duration(seconds: 2));

      final secondSocket = await WebSocket.connect(deviceUri.toString());
      addTearDown(secondSocket.close);
      final message = jsonDecode(await secondSocket.first.timeout(
        const Duration(seconds: 2),
      )) as Map<String, Object?>;

      expect(message, {
        'type': 'error',
        'error': 'device_already_active',
        'message': 'Device is already active for this bridge session.',
      });
    });

    test('allows a new device WebSocket after the active one closes', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final sessionId = await createSession(client, fixture.baseUri);
      final deviceUri = fixture.baseUri.replace(
        scheme: 'ws',
        path: '/api/sessions/$sessionId/device',
      );

      final firstSocket = await WebSocket.connect(deviceUri.toString());
      await firstSocket.first.timeout(const Duration(seconds: 2));
      await firstSocket.close();

      final secondSocket = await WebSocket.connect(deviceUri.toString());
      addTearDown(secondSocket.close);
      final message = jsonDecode(await secondSocket.first.timeout(
        const Duration(seconds: 2),
      )) as Map<String, Object?>;

      expect(message, containsPair('type', 'ready'));
      expect(message, containsPair('deviceId', '19271FDF6007TY'));
    });

    test('rejects a device WebSocket for an unknown session', () async {
      final deviceUri = fixture.baseUri.replace(
        scheme: 'ws',
        path: '/api/sessions/session-missing/device',
      );

      await expectLater(
        WebSocket.connect(deviceUri.toString()),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('sends a complete device metadata update in shell mode', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final sessionId = await createSession(client, fixture.baseUri);
      final deviceUri = fixture.baseUri.replace(
        scheme: 'ws',
        path: '/api/sessions/$sessionId/device',
        queryParameters: {'debugMetadata': 'rotation'},
      );

      final socket = await WebSocket.connect(deviceUri.toString());
      addTearDown(socket.close);
      final messages = <Map<String, Object?>>[];

      await for (final rawMessage
          in socket.timeout(const Duration(seconds: 2))) {
        messages.add(jsonDecode(rawMessage as String) as Map<String, Object?>);
        if (messages.length == 2) {
          break;
        }
      }

      expect(messages.first, containsPair('type', 'ready'));
      expect(messages.last, {
        'type': 'metadata',
        'deviceId': '19271FDF6007TY',
        'screenWidth': 2400,
        'screenHeight': 1080,
        'maxFps': 60,
        'videoCodec': 'h264',
        'controlReady': true,
      });
    });
  });
}
