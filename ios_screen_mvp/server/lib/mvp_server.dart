import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'flutter_runtime_control.dart';
import 'protocol.dart';
import 'video_stream.dart';

typedef CaptureSessionFactory = Future<CaptureSession> Function();
typedef ControlBackendFactory =
    Future<ControlBackend> Function(DeviceMetadata metadata);

final class MvpServer {
  MvpServer({
    required String webRoot,
    required CaptureSessionFactory captureFactory,
    required ControlBackendFactory controlFactory,
  }) : _controlFactory = controlFactory {
    handler = Cascade()
        .add(_sessionHandler())
        .add(createStaticHandler(webRoot, defaultDocument: 'index.html'))
        .handler;
    _captureStarted = _startCapture(captureFactory);
  }

  late final Handler handler;
  late final Future<void> _captureStarted;
  final ControlBackendFactory _controlFactory;

  CaptureSession? _capture;
  StreamSubscription<VideoFrameEnvelope>? _frameSubscription;
  DeviceMetadata? _metadata;
  ControlBackend? _control;
  WebSocketChannel? _browser;
  PointerMessage? _activePointer;
  Object? _captureError;
  bool _closed = false;

  Handler _sessionHandler() {
    return webSocketHandler((channel, _) {
      unawaited(_runSession(channel));
    });
  }

  Future<void> _startCapture(CaptureSessionFactory captureFactory) async {
    try {
      final capture = await captureFactory();
      _capture = capture;
      final captureMetadata = await capture.metadata;
      final control = await _controlFactory(captureMetadata);
      _control = control;
      _metadata = await control.resolveMetadata();
      _frameSubscription = capture.frames.listen(
        (frame) => _browser?.sink.add(frame.encode()),
        onError: (Object error) {
          _captureError = error;
          final browser = _browser;
          if (browser != null) {
            _sendError(browser, error);
          }
        },
      );
    } catch (error) {
      _captureError = error;
      final browser = _browser;
      if (browser != null) {
        _sendError(browser, error);
      }
    }
  }

  Future<void> _runSession(WebSocketChannel channel) async {
    if (_closed) {
      await channel.sink.close();
      return;
    }
    if (_browser != null) {
      channel.sink.add(
        jsonEncode({
          'type': 'error',
          'code': 'controller_busy',
          'message': 'Another browser already controls this session.',
        }),
      );
      await channel.sink.close();
      return;
    }
    _browser = channel;

    try {
      await _captureStarted;
      if (_captureError case final error?) {
        _sendError(channel, error);
        await channel.sink.close();
        return;
      }
      channel.sink.add(jsonEncode(_metadata!.toJson()));

      await for (final rawMessage in channel.stream) {
        if (rawMessage is! String) {
          _sendError(
            channel,
            const ControlError(
              code: 'invalid_control_message',
              message: 'Control messages must be JSON text.',
            ),
          );
          continue;
        }
        try {
          final message = PointerMessage.parse(rawMessage);
          await _control!.send(message);
          _activePointer = switch (message.action) {
            'down' || 'move' => message,
            _ => null,
          };
        } catch (error) {
          _sendError(channel, error);
        }
      }
    } catch (error) {
      _sendError(channel, error);
      await channel.sink.close();
    } finally {
      await _cancelActivePointer();
      if (identical(_browser, channel)) {
        _browser = null;
      }
    }
  }

  Future<void> _cancelActivePointer() async {
    final pointer = _activePointer;
    _activePointer = null;
    if (pointer == null) return;
    try {
      await _control?.send(
        PointerMessage(
          action: 'cancel',
          x: pointer.x,
          y: pointer.y,
          pointerId: pointer.pointerId,
        ),
      );
    } catch (_) {
      // Resource cleanup continues if the runtime has already disconnected.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _captureStarted;
    await _cancelActivePointer();
    await _browser?.sink.close();
    _browser = null;
    await _frameSubscription?.cancel();
    await _control?.close();
    await _capture?.close();
  }

  static void _sendError(WebSocketChannel channel, Object error) {
    final controlError = error is ControlError
        ? error
        : ControlError(code: 'capture_start_failed', message: '$error');
    channel.sink.add(jsonEncode(controlError.toJson()));
  }
}
