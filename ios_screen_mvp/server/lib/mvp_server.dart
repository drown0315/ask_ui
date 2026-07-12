import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'flutter_runtime_control.dart';
import 'protocol.dart';
import 'video_stream.dart';

typedef CaptureSessionFactory = Future<CaptureSession> Function();
typedef ControlBackendFactory =
    Future<ControlBackend> Function(DeviceMetadata metadata, Uri vmServiceUri);

final class MvpServer {
  MvpServer({
    required String webRoot,
    required CaptureSessionFactory captureFactory,
    required ControlBackendFactory controlFactory,
  }) : _controlFactory = controlFactory {
    handler = Cascade()
        .add(_controlHandler)
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
  DeviceMetadata? _captureMetadata;
  DeviceMetadata? _metadata;
  ControlBackend? _control;
  WebSocketChannel? _browser;
  PointerMessage? _activePointer;
  Object? _captureError;
  String _controlState = 'unavailable';
  bool _closed = false;

  Handler _sessionHandler() {
    return webSocketHandler((channel, _) {
      unawaited(_runSession(channel));
    });
  }

  Future<void> _startCapture(CaptureSessionFactory captureFactory) async {
    try {
      final capture = await captureFactory();
      if (_closed) {
        await capture.close();
        return;
      }
      _capture = capture;
      final captureMetadata = await capture.metadata;
      if (_closed) {
        await capture.close();
        return;
      }
      _captureMetadata = captureMetadata;
      _metadata = captureMetadata;
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
      _sendControlState(channel, _controlState);

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
          final control = _control;
          if (control == null) {
            throw const ControlError(
              code: 'runtime_control_unavailable',
              message: 'Flutter runtime control is not attached.',
            );
          }
          await control.send(message);
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

  Future<Response> _controlHandler(Request request) async {
    if (request.url.path != 'control') return Response.notFound('');
    if (request.method == 'DELETE') {
      await _detachControl();
      return _jsonResponse(HttpStatus.ok, {'state': 'unavailable'});
    }
    if (request.method != 'PUT') {
      return Response(
        HttpStatus.methodNotAllowed,
        headers: {'allow': 'PUT, DELETE'},
      );
    }

    try {
      final decoded = jsonDecode(await request.readAsString());
      if (decoded is! Map<String, Object?> ||
          decoded['vmServiceUri'] is! String) {
        throw const FormatException();
      }
      final uri = Uri.parse(decoded['vmServiceUri'] as String);
      if (!uri.hasAuthority ||
          !const {'http', 'https', 'ws', 'wss'}.contains(uri.scheme)) {
        throw const FormatException();
      }
      await attachControl(uri);
      return _jsonResponse(HttpStatus.ok, {'state': 'ready'});
    } on FormatException {
      return _jsonResponse(HttpStatus.badRequest, {
        'state': 'error',
        'code': 'invalid_control_message',
      });
    } catch (error) {
      return _jsonResponse(HttpStatus.serviceUnavailable, {
        'state': 'error',
        'code': 'runtime_control_unavailable',
        'message': '$error',
      });
    }
  }

  Future<void> attachControl(Uri vmServiceUri) async {
    await _captureStarted;
    if (_closed) throw StateError('The MVP server is closed.');
    if (_captureError != null || _captureMetadata == null) {
      throw StateError('Video capture is unavailable: $_captureError');
    }

    final previousState = _control == null ? 'unavailable' : 'ready';
    _controlState = 'connecting';
    _sendControlStateToBrowser('connecting');
    ControlBackend? candidate;
    try {
      candidate = await _controlFactory(_captureMetadata!, vmServiceUri);
      final metadata = await candidate.resolveMetadata();
      await _cancelActivePointer();
      final previous = _control;
      _control = candidate;
      _metadata = metadata;
      _controlState = 'ready';
      final browser = _browser;
      if (browser != null) {
        browser.sink.add(jsonEncode(metadata.toJson()));
        _sendControlState(browser, 'ready');
      }
      if (previous != null && !identical(previous, candidate)) {
        await previous.close();
      }
    } catch (_) {
      if (candidate != null && !identical(candidate, _control)) {
        await candidate.close();
      }
      _controlState = previousState;
      _sendControlStateToBrowser(previousState);
      rethrow;
    }
  }

  Future<void> _detachControl() async {
    await _captureStarted;
    await _cancelActivePointer();
    final control = _control;
    _control = null;
    _metadata = _captureMetadata;
    _controlState = 'unavailable';
    await control?.close();
    _sendControlStateToBrowser('unavailable');
  }

  void _sendControlStateToBrowser(String state) {
    final browser = _browser;
    if (browser != null) _sendControlState(browser, state);
  }

  static void _sendControlState(WebSocketChannel channel, String state) {
    channel.sink.add(jsonEncode({'type': 'control', 'state': state}));
  }

  static Response _jsonResponse(int statusCode, Map<String, Object> body) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _cancelActivePointer();
    final browser = _browser;
    _browser = null;
    await browser?.sink.close();
    await _frameSubscription?.cancel();
    await _control?.close();
    await _capture?.close();
  }

  static void _sendError(WebSocketChannel channel, Object error) {
    final controlError = error is ControlError
        ? error
        : ControlError(code: 'capture_start_failed', message: '$error');
    try {
      channel.sink.add(jsonEncode(controlError.toJson()));
    } on StateError {
      // A browser can disconnect while capture or control is still settling.
    }
  }
}
