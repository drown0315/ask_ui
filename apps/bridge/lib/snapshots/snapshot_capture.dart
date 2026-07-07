import 'dart:convert';
import 'dart:io';

import '../sessions/session_store.dart';

class SnapshotCaptureRequest {
  const SnapshotCaptureRequest({
    required this.session,
    required this.commentId,
    required this.maxSizeBytes,
  });

  final BridgeSession session;
  final String commentId;
  final int maxSizeBytes;
}

class SnapshotCaptureResult {
  const SnapshotCaptureResult.available({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  }) : isAvailable = true;

  const SnapshotCaptureResult.unavailable()
      : isAvailable = false,
        path = '',
        mimeType = '',
        sizeBytes = 0;

  final bool isAvailable;
  final String path;
  final String mimeType;
  final int sizeBytes;
}

typedef SnapshotCapture = Future<SnapshotCaptureResult> Function(
  SnapshotCaptureRequest request,
);

class SnapshotCommandResult {
  const SnapshotCommandResult({
    required this.exitCode,
    required this.stdoutBytes,
    required this.stderr,
  });

  final int exitCode;
  final List<int> stdoutBytes;
  final String stderr;
}

abstract interface class SnapshotCommandRunner {
  Future<SnapshotCommandResult> run(
    String executable,
    List<String> arguments,
  );
}

class ProcessSnapshotCommandRunner implements SnapshotCommandRunner {
  const ProcessSnapshotCommandRunner();

  @override
  Future<SnapshotCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(
      executable,
      arguments,
      stdoutEncoding: null,
      stderrEncoding: utf8,
    );
    final stdout = result.stdout;
    final stderr = result.stderr;

    return SnapshotCommandResult(
      exitCode: result.exitCode,
      stdoutBytes: stdout is List<int> ? stdout : utf8.encode('$stdout'),
      stderr: stderr is String ? stderr : utf8.decode(stderr as List<int>),
    );
  }
}

class AdbSnapshotCapture {
  AdbSnapshotCapture({
    SnapshotCommandRunner commandRunner = const ProcessSnapshotCommandRunner(),
    Directory? rootDirectory,
    this.adbExecutable = 'adb',
    this.ffmpegExecutable = 'ffmpeg',
  })  : _commandRunner = commandRunner,
        _rootDirectory = rootDirectory ??
            Directory('${Directory.systemTemp.path}/ask-ui-snapshots');

  final SnapshotCommandRunner _commandRunner;
  final Directory _rootDirectory;
  final String adbExecutable;
  final String ffmpegExecutable;

  Future<SnapshotCaptureResult> capture(SnapshotCaptureRequest request) async {
    try {
      final snapshotDirectory = Directory(
        '${_rootDirectory.path}/${request.session.id}/snapshots',
      );
      await snapshotDirectory.create(recursive: true);
      request.session
          .manageLocalPath('${_rootDirectory.path}/${request.session.id}');

      final safeCommentId = _safeSnapshotFileName(request.commentId);
      final rawPngFile =
          File('${snapshotDirectory.path}/$safeCommentId.raw.png');
      final compressedPngFile =
          File('${snapshotDirectory.path}/$safeCommentId.png');

      final screenshot = await _commandRunner.run(adbExecutable, [
        '-s',
        request.session.deviceId,
        'exec-out',
        'screencap',
        '-p',
      ]);
      if (screenshot.exitCode != 0 || screenshot.stdoutBytes.isEmpty) {
        return const SnapshotCaptureResult.unavailable();
      }
      await rawPngFile.writeAsBytes(screenshot.stdoutBytes);

      const compressionLevelAttempts = [6, 9];
      for (final compressionLevel in compressionLevelAttempts) {
        final converted = await _commandRunner.run(ffmpegExecutable, [
          '-y',
          '-i',
          rawPngFile.path,
          '-frames:v',
          '1',
          '-compression_level',
          '$compressionLevel',
          compressedPngFile.path,
        ]);
        if (converted.exitCode != 0 || !await compressedPngFile.exists()) {
          return const SnapshotCaptureResult.unavailable();
        }

        final sizeBytes = await compressedPngFile.length();
        if (sizeBytes <= request.maxSizeBytes) {
          return SnapshotCaptureResult.available(
            path: compressedPngFile.path,
            mimeType: 'image/png',
            sizeBytes: sizeBytes,
          );
        }
      }

      return const SnapshotCaptureResult.unavailable();
    } on Object {
      return const SnapshotCaptureResult.unavailable();
    }
  }

  String _safeSnapshotFileName(String rawName) {
    return rawName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}
