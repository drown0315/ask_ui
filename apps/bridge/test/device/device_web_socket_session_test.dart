import 'dart:async';
import 'dart:convert';

import 'package:ask_ui_bridge/device/device_stream.dart';
import 'package:ask_ui_bridge/device/device_web_socket_session.dart';
import 'package:ask_ui_bridge/logging/bridge_logger.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceWebSocketSession', () {
    late BridgeSession session;
    late List<String> logs;
    late RecordingDeviceStreamFactory streamFactory;
    late DeviceWebSocketSession deviceSession;

    setUp(() {
      session = BridgeSession(
        id: 'session-1',
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
      );
      logs = <String>[];
      streamFactory = RecordingDeviceStreamFactory();
      deviceSession = DeviceWebSocketSession(
        deviceStreamFactory: streamFactory,
        logger: BridgeLogger(write: logs.add),
      );
    });

    test('starts a Device stream and sends ready metadata', () async {
      final transport = MemoryDeviceWebSocketTransport();

      await deviceSession.open(
        session: session,
        transport: transport,
      );

      expect(jsonDecode(transport.sent.single as String), {
        'type': 'ready',
        'deviceId': '19271FDF6007TY',
        'screenWidth': 1080,
        'screenHeight': 2400,
        'maxFps': 60,
        'videoCodec': 'h264',
        'controlReady': true,
      });
      expect(
        logs,
        contains('[ask_ui_bridge] device websocket session=session-1 open'),
      );
    });

    test('rejects a second active WebSocket until the first closes', () async {
      final first = MemoryDeviceWebSocketTransport();
      final second = MemoryDeviceWebSocketTransport();
      final third = MemoryDeviceWebSocketTransport();

      await deviceSession.open(session: session, transport: first);
      await deviceSession.open(session: session, transport: second);
      await first.closeFromBrowser();
      await waitForLog(
        logs,
        '[ask_ui_bridge] device websocket session=session-1 close',
      );
      await deviceSession.open(session: session, transport: third);

      expect(jsonDecode(second.sent.single as String), {
        'type': 'error',
        'error': 'device_already_active',
        'message': 'Device is already active for this bridge session.',
      });
      expect(second.closed, isTrue);
      expect(jsonDecode(third.sent.single as String),
          containsPair('type', 'ready'));
    });

    test('returns control-error for invalid controls without closing',
        () async {
      final transport = MemoryDeviceWebSocketTransport();
      await deviceSession.open(session: session, transport: transport);
      transport.sent.clear();

      transport.receiveFromBrowser('{not-json');
      await waitForSentCount(transport, 1);

      expect(jsonDecode(transport.sent.single as String), {
        'type': 'control-error',
        'error': 'invalid_json',
        'message': 'Device control message must be valid JSON.',
      });
      expect(transport.closed, isFalse);
    });

    test('logs accepted non-move touch and system key controls', () async {
      final transport = MemoryDeviceWebSocketTransport();
      await deviceSession.open(session: session, transport: transport);

      transport.receiveFromBrowser(jsonEncode({
        'type': 'touch',
        'action': 'down',
        'pointerId': 1,
        'x': 540,
        'y': 1200,
        'screenWidth': 1080,
        'screenHeight': 2400,
      }));
      transport.receiveFromBrowser(jsonEncode({
        'type': 'systemKey',
        'key': 'back',
      }));

      await waitForLog(
        logs,
        '[ask_ui_bridge] device control session=session-1 touch '
        'action=down pointerId=1 x=540 y=1200',
      );
      expect(
        logs,
        contains(
          '[ask_ui_bridge] device control session=session-1 systemKey key=back',
        ),
      );
    });

    test('closes the underlying Device stream on disconnect', () async {
      final transport = MemoryDeviceWebSocketTransport();
      await deviceSession.open(session: session, transport: transport);

      await transport.closeFromBrowser();

      await streamFactory.stream.closed.future.timeout(
        const Duration(seconds: 2),
      );
    });

    test('reports startup failure and closes the WebSocket', () async {
      streamFactory.startFailure = StateError('cannot start');
      final transport = MemoryDeviceWebSocketTransport();

      await deviceSession.open(session: session, transport: transport);

      expect(jsonDecode(transport.sent.single as String), {
        'type': 'error',
        'error': 'device_start_failed',
        'message': 'Device failed to start.',
      });
      expect(transport.closed, isTrue);
    });
  });
}

Future<void> waitForSentCount(
  MemoryDeviceWebSocketTransport transport,
  int count,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (transport.sent.length >= count) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Expected at least $count sent messages.');
}

Future<void> waitForLog(List<String> logs, String expected) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (logs.contains(expected)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Expected log not found: $expected');
}

class MemoryDeviceWebSocketTransport implements DeviceWebSocketTransport {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final List<Object?> sent = <Object?>[];
  bool closed = false;

  @override
  Stream<dynamic> get incoming => _incoming.stream;

  @override
  void add(Object? message) {
    sent.add(message);
  }

  void receiveFromBrowser(Object? message) {
    _incoming.add(message);
  }

  Future<void> closeFromBrowser() async {
    await _incoming.close();
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) {
      unawaited(_incoming.close());
    }
  }
}

class RecordingDeviceStreamFactory implements DeviceStreamFactory {
  RecordingDeviceStream stream = RecordingDeviceStream();
  Object? startFailure;

  @override
  Future<DeviceStream> start({
    required BridgeSession session,
    required DeviceStreamSink sink,
  }) async {
    final failure = startFailure;
    if (failure != null) {
      throw failure;
    }
    sink.sendReady(DeviceMetadata(
      deviceId: session.deviceId,
      screenWidth: 1080,
      screenHeight: 2400,
      maxFps: 60,
      videoCodec: 'h264',
      controlReady: true,
    ));
    return stream;
  }
}

class RecordingDeviceStream implements DeviceStream {
  final closed = Completer<void>();

  @override
  Future<void> handleControl(Map<String, Object?> message) async {}

  @override
  Future<void> close() async {
    if (!closed.isCompleted) {
      closed.complete();
    }
  }
}
