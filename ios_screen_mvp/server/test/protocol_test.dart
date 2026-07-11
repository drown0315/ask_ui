import 'dart:convert';
import 'dart:typed_data';

import 'package:ios_screen_mvp_server/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceMetadata', () {
    test('ready metadata round trips all display and control fields', () {
      const metadata = DeviceMetadata(
        deviceId: 'ios-capture-1',
        screenWidth: 1170,
        screenHeight: 2532,
        logicalWidth: 390,
        logicalHeight: 844,
        devicePixelRatio: 3,
        videoCodec: 'h264',
        controlBackend: 'flutterRuntime',
      );

      final decoded = DeviceMetadata.fromJson(
        jsonDecode(jsonEncode(metadata.toJson())) as Map<String, Object?>,
      );

      expect(decoded, metadata);
      expect(metadata.toJson()['type'], 'ready');
    });
  });

  group('PointerMessage', () {
    test('accepts every supported pointer action', () {
      for (final action in ['down', 'move', 'up', 'cancel']) {
        final message = PointerMessage.parse(
          jsonEncode({
            'type': 'pointer',
            'action': action,
            'x': 0.25,
            'y': 0.75,
            'pointerId': 0,
          }),
        );

        expect(message.action, action);
        expect(message.pointerId, 0);
      }
    });

    test('rejects invalid JSON with a stable error code', () {
      expectControlError('{', 'invalid_control_message');
    });

    test('rejects unsupported actions with a stable error code', () {
      expectControlError(
        jsonEncode(pointerJson(action: 'tap')),
        'invalid_control_message',
      );
    });

    test('rejects non-zero pointer ids with a stable error code', () {
      expectControlError(
        jsonEncode(pointerJson(pointerId: 1)),
        'invalid_control_message',
      );
    });

    test('rejects coordinates outside the normalized range', () {
      for (final coordinates in [(-0.01, 0.5), (0.5, 1.01)]) {
        expectControlError(
          jsonEncode(pointerJson(x: coordinates.$1, y: coordinates.$2)),
          'invalid_control_message',
        );
      }
    });
  });

  group('VideoFrameEnvelope', () {
    test('parses an exact 13-byte header and payload', () {
      final bytes = Uint8List(16);
      final data = ByteData.sublistView(bytes);
      data.setUint32(0, 3, Endian.big);
      data.setUint8(4, 0x03);
      data.setUint64(5, 42000, Endian.big);
      bytes.setRange(13, 16, [1, 2, 3]);

      final frame = VideoFrameEnvelope.parse(bytes);

      expect(frame.isKeyFrame, isTrue);
      expect(frame.hasDecoderConfig, isTrue);
      expect(frame.ptsMicros, 42000);
      expect(frame.payload, [1, 2, 3]);
    });

    test('rejects truncated headers', () {
      expect(
        () => VideoFrameEnvelope.parse(Uint8List(12)),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects payload lengths that do not match the header', () {
      final bytes = Uint8List(14);
      ByteData.sublistView(bytes).setUint32(0, 2, Endian.big);

      expect(
        () => VideoFrameEnvelope.parse(bytes),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Map<String, Object?> pointerJson({
  String action = 'down',
  double x = 0.5,
  double y = 0.5,
  int pointerId = 0,
}) => {
  'type': 'pointer',
  'action': action,
  'x': x,
  'y': y,
  'pointerId': pointerId,
};

void expectControlError(String source, String code) {
  expect(
    () => PointerMessage.parse(source),
    throwsA(isA<ControlError>().having((error) => error.code, 'code', code)),
  );
}
