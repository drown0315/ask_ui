import 'dart:convert';
import 'dart:typed_data';

final class DeviceMetadata {
  const DeviceMetadata({
    required this.deviceId,
    required this.screenWidth,
    required this.screenHeight,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
    required this.videoCodec,
    required this.controlBackend,
  });

  factory DeviceMetadata.fromJson(Map<String, Object?> json) {
    return DeviceMetadata(
      deviceId: json['deviceId'] as String,
      screenWidth: json['screenWidth'] as int,
      screenHeight: json['screenHeight'] as int,
      logicalWidth: (json['logicalWidth'] as num).toDouble(),
      logicalHeight: (json['logicalHeight'] as num).toDouble(),
      devicePixelRatio: (json['devicePixelRatio'] as num).toDouble(),
      videoCodec: json['videoCodec'] as String,
      controlBackend: json['controlBackend'] as String,
    );
  }

  final String deviceId;
  final int screenWidth;
  final int screenHeight;
  final double logicalWidth;
  final double logicalHeight;
  final double devicePixelRatio;
  final String videoCodec;
  final String controlBackend;

  Map<String, Object> toJson() => {
    'type': 'ready',
    'deviceId': deviceId,
    'screenWidth': screenWidth,
    'screenHeight': screenHeight,
    'logicalWidth': logicalWidth,
    'logicalHeight': logicalHeight,
    'devicePixelRatio': devicePixelRatio,
    'videoCodec': videoCodec,
    'controlBackend': controlBackend,
  };

  @override
  bool operator ==(Object other) =>
      other is DeviceMetadata &&
      other.deviceId == deviceId &&
      other.screenWidth == screenWidth &&
      other.screenHeight == screenHeight &&
      other.logicalWidth == logicalWidth &&
      other.logicalHeight == logicalHeight &&
      other.devicePixelRatio == devicePixelRatio &&
      other.videoCodec == videoCodec &&
      other.controlBackend == controlBackend;

  @override
  int get hashCode => Object.hash(
    deviceId,
    screenWidth,
    screenHeight,
    logicalWidth,
    logicalHeight,
    devicePixelRatio,
    videoCodec,
    controlBackend,
  );
}

final class PointerMessage {
  const PointerMessage({
    required this.action,
    required this.x,
    required this.y,
    required this.pointerId,
  });

  factory PointerMessage.parse(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?> || decoded['type'] != 'pointer') {
        throw const FormatException();
      }

      final action = decoded['action'];
      final x = decoded['x'];
      final y = decoded['y'];
      final pointerId = decoded['pointerId'];
      if (action is! String ||
          !_actions.contains(action) ||
          x is! num ||
          y is! num ||
          !x.isFinite ||
          !y.isFinite ||
          x < 0 ||
          x > 1 ||
          y < 0 ||
          y > 1 ||
          pointerId != 0) {
        throw const FormatException();
      }

      return PointerMessage(
        action: action,
        x: x.toDouble(),
        y: y.toDouble(),
        pointerId: 0,
      );
    } on ControlError {
      rethrow;
    } catch (_) {
      throw const ControlError(
        code: 'invalid_control_message',
        message: 'Expected a normalized single-pointer control message.',
      );
    }
  }

  static const _actions = {'down', 'move', 'up', 'cancel'};

  final String action;
  final double x;
  final double y;
  final int pointerId;

  Map<String, Object> toJson() => {
    'type': 'pointer',
    'action': action,
    'x': x,
    'y': y,
    'pointerId': pointerId,
  };
}

final class ControlError implements Exception {
  const ControlError({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, Object> toJson() => {
    'type': 'error',
    'code': code,
    'message': message,
  };

  @override
  String toString() => '$code: $message';
}

final class VideoFrameEnvelope {
  const VideoFrameEnvelope({
    required this.flags,
    required this.ptsMicros,
    required this.payload,
  });

  factory VideoFrameEnvelope.parse(Uint8List bytes) {
    if (bytes.length < headerLength) {
      throw const FormatException('Truncated video frame header.');
    }

    final header = ByteData.sublistView(bytes, 0, headerLength);
    final payloadLength = header.getUint32(0, Endian.big);
    if (bytes.length != headerLength + payloadLength) {
      throw const FormatException('Video frame payload length mismatch.');
    }

    return VideoFrameEnvelope(
      flags: header.getUint8(4),
      ptsMicros: header.getUint64(5, Endian.big),
      payload: Uint8List.sublistView(bytes, headerLength),
    );
  }

  static const headerLength = 13;

  final int flags;
  final int ptsMicros;
  final Uint8List payload;

  bool get isKeyFrame => flags & 0x01 != 0;
  bool get hasDecoderConfig => flags & 0x02 != 0;

  Uint8List encode() {
    final bytes = Uint8List(headerLength + payload.length);
    final header = ByteData.sublistView(bytes, 0, headerLength);
    header.setUint32(0, payload.length, Endian.big);
    header.setUint8(4, flags);
    header.setUint64(5, ptsMicros, Endian.big);
    bytes.setRange(headerLength, bytes.length, payload);
    return bytes;
  }
}
