import 'dart:io';

import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:ask_ui_bridge/snapshots/snapshot_capture.dart';
import 'package:file_testkit/file_testkit.dart';
import 'package:test/test.dart';

void main() {
  group('AdbSnapshotCapture', () {
    test(
        'captures an explicit device screenshot as a session-scoped compressed PNG',
        () async {
      await FileTestkit.runZoned(() async {
        final rootDirectory = Directory('/ask-ui-snapshot-capture-test');
        final session = BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        );
        final runner = RecordingSnapshotCommandRunner(
          pngBytesByCompression: [List<int>.filled(1200, 0x50)],
        );
        final capture = AdbSnapshotCapture(
          commandRunner: runner,
          rootDirectory: rootDirectory,
        );

        final result = await capture.capture(
          SnapshotCaptureRequest(
            session: session,
            commentId: 'selection-comment-1',
            maxSizeBytes: 1258291,
          ),
        );

        expect(result.isAvailable, isTrue);
        expect(result.mimeType, 'image/png');
        expect(result.sizeBytes, 1200);
        expect(
          result.path,
          endsWith('session-1/snapshots/selection-comment-1.png'),
        );
        expect(await File(result.path).readAsBytes(), runner.lastPngBytes);
        await session.destroy();
        expect(await rootDirectory.exists(), isTrue);
        expect(
          await Directory('${rootDirectory.path}/session-1').exists(),
          isFalse,
        );
        expect(runner.commands, [
          [
            'adb',
            '-s',
            '19271FDF6007TY',
            'exec-out',
            'screencap',
            '-p',
          ],
          [
            'ffmpeg',
            '-y',
            '-i',
            '${rootDirectory.path}/session-1/snapshots/selection-comment-1.raw.png',
            '-frames:v',
            '1',
            '-compression_level',
            '6',
            '${rootDirectory.path}/session-1/snapshots/selection-comment-1.png',
          ],
        ]);
      });
    });

    test('retries PNG compression when the first output is too large',
        () async {
      await FileTestkit.runZoned(() async {
        final rootDirectory = Directory('/ask-ui-snapshot-capture-test');
        final session = BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        );
        final runner = RecordingSnapshotCommandRunner(
          pngBytesByCompression: [
            List<int>.filled(1500, 0x50),
            List<int>.filled(900, 0x51),
          ],
        );
        final capture = AdbSnapshotCapture(
          commandRunner: runner,
          rootDirectory: rootDirectory,
        );

        final result = await capture.capture(
          SnapshotCaptureRequest(
            session: session,
            commentId: 'selection-comment-1',
            maxSizeBytes: 1000,
          ),
        );

        expect(result.isAvailable, isTrue);
        expect(result.sizeBytes, 900);
        expect(await File(result.path).readAsBytes(), runner.lastPngBytes);
        expect(
          runner.commands.where((command) => command.first == 'ffmpeg').map(
                (command) => command[command.indexOf('-compression_level') + 1],
              ),
          ['6', '9'],
        );
      });
    });

    test('reports unavailable when the explicit screenshot command fails',
        () async {
      await FileTestkit.runZoned(() async {
        final rootDirectory = Directory('/ask-ui-snapshot-capture-test');
        final session = BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        );
        final capture = AdbSnapshotCapture(
          commandRunner: ThrowingSnapshotCommandRunner(),
          rootDirectory: rootDirectory,
        );

        final result = await capture.capture(
          SnapshotCaptureRequest(
            session: session,
            commentId: 'selection-comment-1',
            maxSizeBytes: 1000,
          ),
        );

        expect(result.isAvailable, isFalse);
      });
    });
  });
}

class ThrowingSnapshotCommandRunner implements SnapshotCommandRunner {
  @override
  Future<SnapshotCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    throw const ProcessException('adb', ['exec-out', 'screencap']);
  }
}

class RecordingSnapshotCommandRunner implements SnapshotCommandRunner {
  RecordingSnapshotCommandRunner({required this.pngBytesByCompression});

  final List<List<int>> pngBytesByCompression;
  final commands = <List<String>>[];
  int _compressionCount = 0;

  List<int> get lastPngBytes => pngBytesByCompression[_compressionCount - 1];

  @override
  Future<SnapshotCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    commands.add([executable, ...arguments]);

    if (executable == 'adb') {
      return SnapshotCommandResult(
        exitCode: 0,
        stdoutBytes: [0x89, 0x50, 0x4e, 0x47],
        stderr: '',
      );
    }

    if (executable == 'ffmpeg') {
      await File(arguments.last).writeAsBytes(
        pngBytesByCompression[_compressionCount++],
      );
      return const SnapshotCommandResult(
        exitCode: 0,
        stdoutBytes: [],
        stderr: '',
      );
    }

    return SnapshotCommandResult(
      exitCode: 1,
      stdoutBytes: const [],
      stderr: 'Unexpected command: $executable',
    );
  }
}
