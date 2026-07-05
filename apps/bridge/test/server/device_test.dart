import 'dart:async';
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
      expect(
        fixture.logs,
        contains('[ask_ui_bridge] device websocket session=$sessionId open'),
      );
      expect(
        fixture.logs,
        contains(
          '[ask_ui_bridge] device websocket session=$sessionId ready '
          'deviceId=19271FDF6007TY screenWidth=1080 screenHeight=2400',
        ),
      );
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
      expect(
        fixture.logs,
        contains(
          '[ask_ui_bridge] device websocket session=$sessionId metadata '
          'deviceId=19271FDF6007TY screenWidth=2400 screenHeight=1080',
        ),
      );
    });

    test('accepts a legal touch control message without acking or closing',
        () async {
      final client = HttpClient();
      addTearDown(client.close);
      final sessionId = await createSession(client, fixture.baseUri);
      final deviceUri = fixture.baseUri.replace(
        scheme: 'ws',
        path: '/api/sessions/$sessionId/device',
      );

      final socket = await WebSocket.connect(deviceUri.toString());
      addTearDown(socket.close);
      final messages = socket.asBroadcastStream();
      await messages.first.timeout(const Duration(seconds: 2));

      socket.add(jsonEncode({
        'type': 'touch',
        'action': 'down',
        'pointerId': 1,
        'x': 540,
        'y': 1200,
        'screenWidth': 1080,
        'screenHeight': 2400,
      }));

      bool receivedAck = false;
      try {
        await messages.first.timeout(const Duration(milliseconds: 100));
        receivedAck = true;
      } on TimeoutException {
        receivedAck = false;
      }

      expect(receivedAck, isFalse);
      expect(socket.closeCode, isNull);
      expect(
        fixture.logs,
        contains(
          '[ask_ui_bridge] device control session=$sessionId touch '
          'action=down pointerId=1 x=540 y=1200',
        ),
      );
    });

    test('returns control-error for invalid JSON without closing', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final sessionId = await createSession(client, fixture.baseUri);
      final deviceUri = fixture.baseUri.replace(
        scheme: 'ws',
        path: '/api/sessions/$sessionId/device',
      );

      final socket = await WebSocket.connect(deviceUri.toString());
      addTearDown(socket.close);
      final messages = socket.asBroadcastStream();
      await messages.first.timeout(const Duration(seconds: 2));

      socket.add('{not-json');

      final errorMessage = jsonDecode(await messages.first.timeout(
        const Duration(seconds: 2),
      )) as Map<String, Object?>;

      expect(errorMessage, {
        'type': 'control-error',
        'error': 'invalid_json',
        'message': 'Device control message must be valid JSON.',
      });
      expect(socket.closeCode, isNull);
      expect(
        fixture.logs,
        contains(
          '[ask_ui_bridge] device control session=$sessionId control_error '
          'error=invalid_json',
        ),
      );
    });

    test('returns control-error for unknown control message type', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final sessionId = await createSession(client, fixture.baseUri);
      final deviceUri = fixture.baseUri.replace(
        scheme: 'ws',
        path: '/api/sessions/$sessionId/device',
      );

      final socket = await WebSocket.connect(deviceUri.toString());
      addTearDown(socket.close);
      final messages = socket.asBroadcastStream();
      await messages.first.timeout(const Duration(seconds: 2));

      socket.add(jsonEncode({
        'type': 'rotate',
      }));

      final errorMessage = jsonDecode(await messages.first.timeout(
        const Duration(seconds: 2),
      )) as Map<String, Object?>;

      expect(errorMessage, {
        'type': 'control-error',
        'error': 'unsupported_control_message',
        'message': 'Unsupported Device control message type: rotate.',
      });
      expect(socket.closeCode, isNull);
    });

    test('returns control-error for invalid touch action', () async {
      final client = HttpClient();
      addTearDown(client.close);
      final sessionId = await createSession(client, fixture.baseUri);
      final deviceUri = fixture.baseUri.replace(
        scheme: 'ws',
        path: '/api/sessions/$sessionId/device',
      );

      final socket = await WebSocket.connect(deviceUri.toString());
      addTearDown(socket.close);
      final messages = socket.asBroadcastStream();
      await messages.first.timeout(const Duration(seconds: 2));

      socket.add(jsonEncode({
        'type': 'touch',
        'action': 'tap',
        'pointerId': 1,
        'x': 540,
        'y': 1200,
        'screenWidth': 1080,
        'screenHeight': 2400,
      }));

      final errorMessage = jsonDecode(await messages.first.timeout(
        const Duration(seconds: 2),
      )) as Map<String, Object?>;

      expect(errorMessage, {
        'type': 'control-error',
        'error': 'invalid_touch_action',
        'message': 'Touch action must be down, move, up, or cancel.',
      });
      expect(socket.closeCode, isNull);
    });

    test('returns control-error for out-of-range touch pointer id', () async {
      final readySocket = await openReadyDeviceSocket(fixture);

      readySocket.socket.add(jsonEncode({
        'type': 'touch',
        'action': 'down',
        'pointerId': 4294967296,
        'x': 540,
        'y': 1200,
        'screenWidth': 1080,
        'screenHeight': 2400,
      }));

      final errorMessage = await readJsonMessage(readySocket.messages);

      expect(errorMessage, {
        'type': 'control-error',
        'error': 'invalid_touch_pointer_id',
        'message': 'Touch pointerId must be an integer from 0 to 4294967295.',
      });
      expect(readySocket.socket.closeCode, isNull);
    });

    test('returns control-error for out-of-range touch coordinates', () async {
      final readySocket = await openReadyDeviceSocket(fixture);

      readySocket.socket.add(jsonEncode({
        'type': 'touch',
        'action': 'move',
        'pointerId': 1,
        'x': 1081,
        'y': 1200,
        'screenWidth': 1080,
        'screenHeight': 2400,
      }));

      final errorMessage = await readJsonMessage(readySocket.messages);

      expect(errorMessage, {
        'type': 'control-error',
        'error': 'invalid_touch_coordinates',
        'message': 'Touch coordinates must be inside the screen bounds.',
      });
      expect(readySocket.socket.closeCode, isNull);
    });

    test('returns control-error for invalid touch screen size', () async {
      final readySocket = await openReadyDeviceSocket(fixture);

      readySocket.socket.add(jsonEncode({
        'type': 'touch',
        'action': 'move',
        'pointerId': 1,
        'x': 0,
        'y': 0,
        'screenWidth': 0,
        'screenHeight': 2400,
      }));

      final errorMessage = await readJsonMessage(readySocket.messages);

      expect(errorMessage, {
        'type': 'control-error',
        'error': 'invalid_touch_screen_size',
        'message':
            'Touch screenWidth and screenHeight must be positive integers.',
      });
      expect(readySocket.socket.closeCode, isNull);
    });

    test('accepts a legal system key message without acking or closing',
        () async {
      final readySocket = await openReadyDeviceSocket(fixture);

      readySocket.socket.add(jsonEncode({
        'type': 'systemKey',
        'key': 'back',
      }));

      bool receivedAck = false;
      try {
        await readySocket.messages.first
            .timeout(const Duration(milliseconds: 100));
        receivedAck = true;
      } on TimeoutException {
        receivedAck = false;
      }

      expect(receivedAck, isFalse);
      expect(readySocket.socket.closeCode, isNull);
      expect(
        fixture.logs,
        contains(
          '[ask_ui_bridge] device control session=${readySocket.sessionId} '
          'systemKey key=back',
        ),
      );
    });

    test('returns control-error for invalid system key', () async {
      final readySocket = await openReadyDeviceSocket(fixture);

      readySocket.socket.add(jsonEncode({
        'type': 'systemKey',
        'key': 'power',
      }));

      final errorMessage = await readJsonMessage(readySocket.messages);

      expect(errorMessage, {
        'type': 'control-error',
        'error': 'invalid_system_key',
        'message': 'System key must be back, home, or recents.',
      });
      expect(readySocket.socket.closeCode, isNull);
    });
  });
}

Future<ReadyDeviceSocket> openReadyDeviceSocket(
  BridgeServerFixture fixture,
) async {
  final client = HttpClient();
  addTearDown(client.close);
  final sessionId = await createSession(client, fixture.baseUri);
  final deviceUri = fixture.baseUri.replace(
    scheme: 'ws',
    path: '/api/sessions/$sessionId/device',
  );

  final socket = await WebSocket.connect(deviceUri.toString());
  addTearDown(socket.close);
  final messages = socket.asBroadcastStream();
  await messages.first.timeout(const Duration(seconds: 2));

  return ReadyDeviceSocket(
    sessionId: sessionId,
    socket: socket,
    messages: messages,
  );
}

Future<Map<String, Object?>> readJsonMessage(Stream<dynamic> messages) async {
  return jsonDecode(await messages.first.timeout(const Duration(seconds: 2)))
      as Map<String, Object?>;
}

class ReadyDeviceSocket {
  const ReadyDeviceSocket({
    required this.sessionId,
    required this.socket,
    required this.messages,
  });

  final String sessionId;
  final WebSocket socket;
  final Stream<dynamic> messages;
}
