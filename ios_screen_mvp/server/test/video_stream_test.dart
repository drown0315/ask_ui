import 'dart:convert';
import 'dart:typed_data';

import 'package:ios_screen_mvp_server/protocol.dart';
import 'package:ios_screen_mvp_server/video_stream.dart';
import 'package:test/test.dart';

void main() {
  const metadata = DeviceMetadata(
    deviceId: 'ios-device-1',
    screenWidth: 1170,
    screenHeight: 2532,
    logicalWidth: 390,
    logicalHeight: 844,
    devicePixelRatio: 3,
    videoCodec: 'h264',
    controlBackend: 'flutterRuntime',
  );

  test('parses chunked metadata and complete frames in order', () async {
    final first = VideoFrameEnvelope(
      flags: 0x03,
      ptsMicros: 1000,
      payload: Uint8List.fromList([1, 2]),
    );
    final second = VideoFrameEnvelope(
      flags: 0,
      ptsMicros: 2000,
      payload: Uint8List.fromList([3, 4, 5]),
    );
    final output = <int>[
      ...utf8.encode('${jsonEncode(metadata.toJson())}\n'),
      ...first.encode(),
      ...second.encode(),
    ];

    final stream = NativeHelperStream.parse(
      stdout: Stream.fromIterable(chunk(output, [3, 17, 5, 29])),
      stderr: Stream.value(utf8.encode('capture warming up\n')),
    );

    expect(await stream.metadata, metadata);
    final frames = await stream.frames.toList();
    expect(frames.map((frame) => frame.ptsMicros), [1000, 2000]);
    expect(frames[0].payload, [1, 2]);
    expect(frames[1].payload, [3, 4, 5]);
    expect(await stream.diagnostics, 'capture warming up\n');
  });

  test('reports a truncated frame as capture_start_failed', () async {
    final complete = VideoFrameEnvelope(
      flags: 1,
      ptsMicros: 1000,
      payload: Uint8List.fromList([1, 2, 3]),
    ).encode();
    final output = <int>[
      ...utf8.encode('${jsonEncode(metadata.toJson())}\n'),
      ...complete.sublist(0, complete.length - 1),
    ];
    final stream = NativeHelperStream.parse(
      stdout: Stream.value(output),
      stderr: const Stream.empty(),
    );

    await stream.metadata;
    await expectLater(
      stream.frames.toList(),
      throwsA(
        isA<ControlError>().having(
          (error) => error.code,
          'code',
          'capture_start_failed',
        ),
      ),
    );
  });

  test('parses machine-readable capture device records', () {
    final devices = CaptureDevice.parseList('''
id\tname\tmodel\tmanufacturer
ios-1\tTest iPhone\tiOS Device\tApple Inc.
malformed
''');

    expect(devices, [
      const CaptureDevice(
        id: 'ios-1',
        name: 'Test iPhone',
        model: 'iOS Device',
        manufacturer: 'Apple Inc.',
      ),
    ]);
  });
}

List<List<int>> chunk(List<int> bytes, List<int> sizes) {
  final chunks = <List<int>>[];
  var offset = 0;
  for (final size in sizes) {
    if (offset >= bytes.length) break;
    final end = (offset + size).clamp(0, bytes.length);
    chunks.add(bytes.sublist(offset, end));
    offset = end;
  }
  if (offset < bytes.length) chunks.add(bytes.sublist(offset));
  return chunks;
}
