import 'dart:convert';
import 'dart:io';
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

  group('capture discovery', () {
    const recordable = CaptureDevice(
      id: '086CB555-1500-48BB-8F7A-51BF5F6C90C5',
      name: 'Test iPhone',
      model: 'iOS Device',
      manufacturer: 'Apple Inc.',
    );
    const connected = DevelopmentDevice(
      id: '269bfd1ccaa634d5f2250efe6a22016b18fd16da',
      name: 'Test iPhone',
    );

    test('parses physical iPhones from xctrace device output', () {
      final devices = DevelopmentDevice.parseXctrace('''
== Devices ==
Test Mac (413457E0-CF99-52D4-A082-30349AC884F5)
Test iPhone (15.8.8) (269bfd1ccaa634d5f2250efe6a22016b18fd16da)

== Simulators ==
iPhone 17 Simulator (26.4) (58CC29EF-4758-4E4E-A79A-398E4A26C91F)
''');

      expect(devices, [connected]);
    });

    test('maps a development UDID to the matching recordable capture ID', () {
      final target = CaptureTarget.resolve(
        connected.id,
        recordableDevices: const [recordable],
        developmentDevices: const [connected],
      );

      expect(target.captureId, recordable.id);
      expect(target.developmentId, connected.id);
      expect(target.name, 'Test iPhone');
    });

    test('resolves exact names and case-insensitive name prefixes', () {
      for (final selector in ['Test iPhone', 'test iph']) {
        final target = CaptureTarget.resolve(
          selector,
          recordableDevices: const [recordable],
          developmentDevices: const [connected],
        );

        expect(target.captureId, recordable.id);
      }
    });

    test(
      'retains a development target while capture publication is pending',
      () {
        final target = CaptureTarget.resolve(
          connected.id,
          recordableDevices: const [],
          developmentDevices: const [connected],
        );

        expect(target.captureId, isNull);
        expect(target.developmentId, connected.id);
        expect(target.name, connected.name);
      },
    );

    test('rejects ambiguous duplicate device names', () {
      expect(
        () => CaptureTarget.resolve(
          'Shared iPhone',
          recordableDevices: const [
            CaptureDevice(
              id: 'capture-1',
              name: 'Shared iPhone',
              model: 'iOS Device',
              manufacturer: 'Apple Inc.',
            ),
            CaptureDevice(
              id: 'capture-2',
              name: 'Shared iPhone',
              model: 'iOS Device',
              manufacturer: 'Apple Inc.',
            ),
          ],
          developmentDevices: const [],
        ),
        throwsA(
          isA<ControlError>().having(
            (error) => error.code,
            'code',
            'capture_device_not_found',
          ),
        ),
      );
    });
  });

  test(
    'launcher discovers a development device before starting its stream',
    () async {
      final runner = FakeCaptureCommandRunner(
        helperListOutput: 'id\tname\tmodel\tmanufacturer\n',
        xctraceOutput: '''
== Devices ==
Test iPhone (15.8.8) (269bfd1ccaa634d5f2250efe6a22016b18fd16da)
''',
        streamOutput: utf8.encode('${jsonEncode(metadata.toJson())}\n'),
      );
      final launcher = NativeCaptureLauncher(
        helperPath: '/tmp/ios_capture',
        runner: runner,
      );

      final session = await launcher.start(
        '269bfd1ccaa634d5f2250efe6a22016b18fd16da',
      );
      expect(await session.metadata, metadata);
      expect(runner.runCalls, [
        ['/tmp/ios_capture', 'list'],
        ['xcrun', 'xctrace', 'list', 'devices'],
      ]);
      expect(runner.startCalls.single, [
        '/tmp/ios_capture',
        'stream',
        '--device-id',
        '269bfd1ccaa634d5f2250efe6a22016b18fd16da',
        '--device-name',
        'Test iPhone',
        '--max-fps',
        '30',
        '--bit-rate',
        '6000000',
      ]);
      await session.close();
      expect(runner.process.killed, isTrue);
    },
  );

  test(
    'session preserves the helper error when metadata never starts',
    () async {
      final runner = FakeCaptureCommandRunner(
        helperListOutput: 'id\tname\tmodel\tmanufacturer\n',
        xctraceOutput: '''
== Devices ==
Test iPhone (15.8.8) (269bfd1ccaa634d5f2250efe6a22016b18fd16da)
''',
        streamOutput: const [],
        streamError:
            'capture_device_not_found: no capture device matched Test iPhone\n',
        streamExitCode: 4,
      );
      final launcher = NativeCaptureLauncher(
        helperPath: '/tmp/ios_capture',
        runner: runner,
      );

      final session = await launcher.start('Test iPhone');

      await expectLater(
        session.metadata,
        throwsA(
          isA<ControlError>()
              .having((error) => error.code, 'code', 'capture_device_not_found')
              .having(
                (error) => error.message,
                'message',
                contains('no capture device matched'),
              ),
        ),
      );
      await session.close();
    },
  );
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

final class FakeCaptureCommandRunner implements CaptureCommandRunner {
  FakeCaptureCommandRunner({
    required this.helperListOutput,
    required this.xctraceOutput,
    required List<int> streamOutput,
    String streamError = '',
    int streamExitCode = 0,
  }) : process = FakeCaptureProcess(
         streamOutput,
         error: streamError,
         exitCode: streamExitCode,
       );

  final String helperListOutput;
  final String xctraceOutput;
  final FakeCaptureProcess process;
  final List<List<String>> runCalls = [];
  final List<List<String>> startCalls = [];

  @override
  Future<CaptureCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    runCalls.add([executable, ...arguments]);
    if (executable == 'xcrun') {
      return CaptureCommandResult(
        exitCode: 0,
        stdout: xctraceOutput,
        stderr: '',
      );
    }
    return CaptureCommandResult(
      exitCode: 0,
      stdout: helperListOutput,
      stderr: '',
    );
  }

  @override
  Future<CaptureProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    startCalls.add([executable, ...arguments]);
    return process;
  }
}

final class FakeCaptureProcess implements CaptureProcess {
  FakeCaptureProcess(List<int> output, {String error = '', int exitCode = 0})
    : stdout = Stream.value(output),
      stderr = Stream.value(utf8.encode(error)),
      _exitCode = exitCode;

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  final int _exitCode;

  bool killed = false;

  @override
  Future<int> get exitCode async => _exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }
}
