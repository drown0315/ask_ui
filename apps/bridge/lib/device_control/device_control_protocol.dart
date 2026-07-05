import 'dart:convert';

/// Validates text control messages received on the Device WebSocket.
///
/// The shell accepts valid control messages without ACK frames. Protocol
/// mistakes return a `control-error` JSON object and keep the WebSocket open.
class DeviceControlProtocol {
  DeviceControlProtocol._();

  static const String errorType = 'control-error';
  static const String invalidJsonError = 'invalid_json';
  static const String touchType = 'touch';
  static const String systemKeyType = 'systemKey';
  static const String unsupportedControlMessageError =
      'unsupported_control_message';
  static const Set<String> touchActions = {
    'down',
    'move',
    'up',
    'cancel',
  };
  static const Set<String> systemKeys = {
    'back',
    'home',
    'recents',
  };
  static const int minPointerId = 0;
  static const int maxPointerId = 0xffffffff;

  static Map<String, Object?>? validateTextMessage(String rawMessage) {
    try {
      final Object? decoded = jsonDecode(rawMessage);
      if (decoded is Map<String, Object?>) {
        final Object? type = decoded['type'];
        if (type == touchType) {
          return _validateTouchMessage(decoded);
        }
        if (type == systemKeyType) {
          return _validateSystemKeyMessage(decoded);
        }
        return _controlError(
          error: unsupportedControlMessageError,
          message: 'Unsupported Device control message type: $type.',
        );
      }
      if (decoded is Map) {
        return null;
      }
      return _controlError(
        error: invalidJsonError,
        message: 'Device control message must be a JSON object.',
      );
    } on FormatException {
      return _controlError(
        error: invalidJsonError,
        message: 'Device control message must be valid JSON.',
      );
    }
  }

  static Map<String, Object?>? _validateTouchMessage(
    Map<String, Object?> message,
  ) {
    final Object? action = message['action'];
    if (action is! String || !touchActions.contains(action)) {
      return _controlError(
        error: 'invalid_touch_action',
        message: 'Touch action must be down, move, up, or cancel.',
      );
    }

    final Object? pointerId = message['pointerId'];
    if (pointerId is! int ||
        pointerId < minPointerId ||
        pointerId > maxPointerId) {
      return _controlError(
        error: 'invalid_touch_pointer_id',
        message: 'Touch pointerId must be an integer from 0 to 4294967295.',
      );
    }

    final Object? screenWidth = message['screenWidth'];
    final Object? screenHeight = message['screenHeight'];
    if (screenWidth is! int ||
        screenHeight is! int ||
        screenWidth <= 0 ||
        screenHeight <= 0) {
      return _controlError(
        error: 'invalid_touch_screen_size',
        message:
            'Touch screenWidth and screenHeight must be positive integers.',
      );
    }

    final Object? x = message['x'];
    final Object? y = message['y'];
    if (x is! num ||
        y is! num ||
        x < 0 ||
        x > screenWidth ||
        y < 0 ||
        y > screenHeight) {
      return _controlError(
        error: 'invalid_touch_coordinates',
        message: 'Touch coordinates must be inside the screen bounds.',
      );
    }

    return null;
  }

  static Map<String, Object?>? _validateSystemKeyMessage(
    Map<String, Object?> message,
  ) {
    final Object? key = message['key'];
    if (key is! String || !systemKeys.contains(key)) {
      return _controlError(
        error: 'invalid_system_key',
        message: 'System key must be back, home, or recents.',
      );
    }

    return null;
  }

  static Map<String, Object?> _controlError({
    required String error,
    required String message,
  }) {
    return {
      'type': errorType,
      'error': error,
      'message': message,
    };
  }
}
