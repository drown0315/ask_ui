import 'dart:async';
import 'dart:convert';

import '../device_control/device_control_protocol.dart';
import '../logging/bridge_logger.dart';
import '../sessions/session_store.dart';
import 'device_stream.dart';

class DeviceWebSocketSession {
  DeviceWebSocketSession({
    required DeviceStreamFactory deviceStreamFactory,
    required BridgeLogger logger,
  })  : _deviceStreamFactory = deviceStreamFactory,
        _logger = logger;

  final DeviceStreamFactory _deviceStreamFactory;
  final BridgeLogger _logger;
  final Set<String> _activeSessionIds = {};

  Future<void> open({
    required BridgeSession session,
    required DeviceWebSocketTransport transport,
    bool debugVideoFixture = false,
    bool debugMetadataRotation = false,
  }) async {
    final sessionId = session.id;
    _logger.info('device websocket session=$sessionId open');
    if (_activeSessionIds.contains(sessionId)) {
      _logger.info('device websocket session=$sessionId already_active');
      transport.add(jsonEncode({
        'type': 'error',
        'error': 'device_already_active',
        'message': 'Device is already active for this bridge session.',
      }));
      await transport.close();
      return;
    }

    _activeSessionIds.add(sessionId);
    DeviceStream? deviceStream;
    var socketClosed = false;
    var deviceStreamClosed = false;
    Future<void> closeDeviceStream() async {
      final stream = deviceStream;
      if (stream == null || deviceStreamClosed) {
        return;
      }
      deviceStreamClosed = true;
      await stream.close();
    }

    transport.incoming.listen(
      (message) {
        if (message is! String) {
          return;
        }

        final Map<String, Object?>? controlError =
            DeviceControlProtocol.validateTextMessage(message);
        if (controlError != null) {
          _logger.info(
            'device control session=$sessionId control_error '
            'error=${controlError['error']}',
          );
          transport.add(jsonEncode(controlError));
          return;
        }
        _logAcceptedDeviceControl(sessionId: sessionId, rawMessage: message);
        final decoded = jsonDecode(message);
        if (decoded is Map<String, Object?>) {
          unawaited(deviceStream?.handleControl(decoded));
        }
      },
      onDone: () async {
        socketClosed = true;
        _activeSessionIds.remove(sessionId);
        await closeDeviceStream();
        _logger.info('device websocket session=$sessionId close');
      },
      onError: (error) async {
        socketClosed = true;
        _activeSessionIds.remove(sessionId);
        await closeDeviceStream();
        _logger.info('device websocket session=$sessionId error=$error');
      },
    );

    final streamSink = _TransportDeviceStreamSink(
      transport: transport,
      logger: _logger,
      sessionId: sessionId,
    );
    final streamFactory = debugVideoFixture
        ? FixtureH264DeviceStreamFactory(chunk: fixtureH264AnnexBChunk)
        : _deviceStreamFactory;

    try {
      deviceStream = await streamFactory.start(
        session: session,
        sink: streamSink,
      );
      if (socketClosed) {
        await closeDeviceStream();
        return;
      }
      if (debugMetadataRotation) {
        streamSink.sendMetadata(DeviceMetadata(
          deviceId: session.deviceId,
          screenWidth: 2400,
          screenHeight: 1080,
          maxFps: 60,
          videoCodec: 'h264',
          controlReady: true,
        ));
      }
    } catch (error, stackTrace) {
      _logger.info(
        'device websocket session=$sessionId start_failed '
        'error=$error\nStack trace:\n$stackTrace',
      );
      if (socketClosed) {
        return;
      }
      transport.add(jsonEncode({
        'type': 'error',
        'error': 'device_start_failed',
        'message': 'Device failed to start.',
      }));
      await transport.close();
    }
  }

  void _logAcceptedDeviceControl({
    required String sessionId,
    required String rawMessage,
  }) {
    final decoded = jsonDecode(rawMessage);
    if (decoded is! Map<String, Object?>) {
      return;
    }

    if (decoded['type'] == DeviceControlProtocol.systemKeyType) {
      _logger.info(
        'device control session=$sessionId systemKey key=${decoded['key']}',
      );
      return;
    }

    if (decoded['type'] != DeviceControlProtocol.touchType) {
      return;
    }

    final action = decoded['action'];
    if (action == 'move') {
      return;
    }

    _logger.info(
      'device control session=$sessionId touch action=$action '
      'pointerId=${decoded['pointerId']} x=${decoded['x']} y=${decoded['y']}',
    );
  }
}

abstract interface class DeviceWebSocketTransport {
  Stream<dynamic> get incoming;

  void add(Object? message);

  Future<void> close();
}

class _TransportDeviceStreamSink implements DeviceStreamSink {
  _TransportDeviceStreamSink({
    required this.transport,
    required this.logger,
    required this.sessionId,
  });

  final DeviceWebSocketTransport transport;
  final BridgeLogger logger;
  final String sessionId;

  @override
  void sendReady(DeviceMetadata metadata) {
    transport.add(jsonEncode({
      'type': 'ready',
      ...metadata.toJson(),
    }));
    logger.info(
      'device websocket session=$sessionId ready '
      'deviceId=${metadata.deviceId} '
      'screenWidth=${metadata.screenWidth} '
      'screenHeight=${metadata.screenHeight}',
    );
  }

  @override
  void sendMetadata(DeviceMetadata metadata) {
    transport.add(jsonEncode({
      'type': 'metadata',
      ...metadata.toJson(),
    }));
    logger.info(
      'device websocket session=$sessionId metadata '
      'deviceId=${metadata.deviceId} '
      'screenWidth=${metadata.screenWidth} '
      'screenHeight=${metadata.screenHeight}',
    );
  }

  @override
  void sendVideoChunk(List<int> bytes) {
    transport.add(bytes);
  }

  @override
  void fail(String error, String message) {
    transport.add(jsonEncode({
      'type': 'error',
      'error': error,
      'message': message,
    }));
  }

  @override
  void log(String message) {
    logger.info('device websocket session=$sessionId $message');
  }

  @override
  Future<void> close() async {
    await transport.close();
  }
}

/// Single-frame Annex B H.264 byte fixture for the Device WebSocket shell.
///
/// The bytes are a 16x16 Constrained Baseline IDR frame generated by ffmpeg.
/// They prove that the bridge can send decodable binary video bytes over the
/// same WebSocket as JSON protocol messages.
final List<int> fixtureH264AnnexBChunk = [
  ...base64Decode(
    'AAAAAWdCwArd7ARAAAADAEAAAAMAo8SJ4AAAAAFozg/IAAABBgX//03cRem95tlIt5Ys2CDZI+7veDI2NCAtIGNvcmUgMTY1IHIzMjIyIGIzNTYwNWEgLSBILjI2NC9NUEVHLTQgQVZDIGNvZGVjIC0gQ29weWxlZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2FiYWM9MCByZWY9MSBkZWJsb2NrPTA6MDowIGFuYWx5c2U9MDowIG1lPWRpYSBzdWJtZT0wIHBzeT0xIHBzeV9yZD0xLjAwOjAuMDAgbWl4ZWRfcmVmPTAgbWVfcmFuZ2U9MTYgY2hyb21hX21lPTEgdHJlbGxpcz0wIDh4OGRjdD0wIGNxbT0wIGRlYWR6b25lPTIxLDExIGZhc3RfcHNraXA9MSBjaHJvbWFfcXBfb2Zmc2V0PTAgdGhyZWFkcz0xIGxvb2thaGVhZF90aHJlYWRzPTEgc2xpY2VkX3RocmVhZHM9MCBucj0wIGRlY2ltYXRlPTEgaW50ZXJsYWNlZD0wIGJsdXJheV9jb21wYXQ9MCBjb25zdHJhaW5lZF9pbnRyYT0wIGJmcmFtZXM9MCB3ZWlnaHRwPTAga2V5aW50PTEga2V5aW50X21pbj0xIHNjZW5lY3V0PTAgaW50cmFfcmVmcmVzaD0wIHJjPWNyZiBtYnRyZWU9MCBjcmY9MjMuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89MS40MCBhcT0wAIAAAAFliIQ6JigACQLg',
  ),
  0x00,
  0x00,
  0x01,
  0x09,
  0xf0,
];
