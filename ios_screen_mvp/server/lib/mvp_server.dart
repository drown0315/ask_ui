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
  }) : handler = Cascade()
           .add(_sessionHandler(captureFactory, controlFactory))
           .add(createStaticHandler(webRoot, defaultDocument: 'index.html'))
           .handler;

  final Handler handler;

  static bool _controllerActive = false;

  static Handler _sessionHandler(
    CaptureSessionFactory captureFactory,
    ControlBackendFactory controlFactory,
  ) {
    return webSocketHandler((channel, _) {
      unawaited(_runSession(channel, captureFactory, controlFactory));
    });
  }

  static Future<void> _runSession(
    WebSocketChannel channel,
    CaptureSessionFactory captureFactory,
    ControlBackendFactory controlFactory,
  ) async {
    if (_controllerActive) {
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
    _controllerActive = true;

    CaptureSession? capture;
    ControlBackend? control;
    StreamSubscription<VideoFrameEnvelope>? frameSubscription;
    PointerMessage? activePointer;
    try {
      capture = await captureFactory();
      final metadata = await capture.metadata;
      control = await controlFactory(metadata);
      channel.sink.add(jsonEncode(metadata.toJson()));
      frameSubscription = capture.frames.listen(
        (frame) => channel.sink.add(frame.encode()),
        onError: (Object error) {
          _sendError(channel, error);
          unawaited(channel.sink.close());
        },
      );

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
          await control.send(message);
          activePointer = switch (message.action) {
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
      if (activePointer case final pointer?) {
        try {
          await control?.send(
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
      await frameSubscription?.cancel();
      await control?.close();
      await capture?.close();
      _controllerActive = false;
    }
  }

  static void _sendError(WebSocketChannel channel, Object error) {
    final controlError = error is ControlError
        ? error
        : ControlError(code: 'capture_start_failed', message: '$error');
    channel.sink.add(jsonEncode(controlError.toJson()));
  }
}
