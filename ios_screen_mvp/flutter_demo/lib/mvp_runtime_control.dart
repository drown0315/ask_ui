import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/gestures.dart';

const mvpPointerExtension = 'ext.ios_screen_mvp.pointer';

Map<String, Object> encodeViewMetrics({
  required double physicalWidth,
  required double physicalHeight,
  required double devicePixelRatio,
}) =>
    {
      'ok': true,
      'logicalWidth': physicalWidth / devicePixelRatio,
      'logicalHeight': physicalHeight / devicePixelRatio,
      'devicePixelRatio': devicePixelRatio,
    };

void registerMvpRuntimeControl() {
  assert(() {
    final dispatcher = _PointerDispatcher();
    developer.registerExtension(mvpPointerExtension, dispatcher.handle);
    return true;
  }());
}

final class _PointerDispatcher {
  Offset? _lastPosition;

  Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> parameters,
  ) async {
    try {
      final action = parameters['action'];
      if (action == 'view') {
        final view = GestureBinding.instance.platformDispatcher.views.first;
        return developer.ServiceExtensionResponse.result(
          jsonEncode(
            encodeViewMetrics(
              physicalWidth: view.physicalSize.width,
              physicalHeight: view.physicalSize.height,
              devicePixelRatio: view.devicePixelRatio,
            ),
          ),
        );
      }
      final x = double.parse(parameters['x'] ?? '');
      final y = double.parse(parameters['y'] ?? '');
      final pointerId = int.parse(parameters['pointerId'] ?? '');
      if (pointerId != 0 ||
          !x.isFinite ||
          !y.isFinite ||
          !const {'down', 'move', 'up', 'cancel'}.contains(action)) {
        throw const FormatException('Invalid pointer parameters.');
      }

      final position = Offset(x, y);
      final event = switch (action) {
        'down' => PointerDownEvent(
            pointer: pointerId,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        'move' => PointerMoveEvent(
            pointer: pointerId,
            position: position,
            delta: position - (_lastPosition ?? position),
            kind: PointerDeviceKind.touch,
          ),
        'up' => PointerUpEvent(
            pointer: pointerId,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        'cancel' => PointerCancelEvent(
            pointer: pointerId,
            position: position,
            kind: PointerDeviceKind.touch,
          ),
        _ => throw const FormatException('Invalid pointer action.'),
      };

      GestureBinding.instance.handlePointerEvent(event);
      _lastPosition = action == 'up' || action == 'cancel' ? null : position;
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'ok': true}),
      );
    } catch (error) {
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'ok': false, 'error': error.toString()}),
      );
    }
  }
}
