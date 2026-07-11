import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'protocol.dart';

abstract interface class CaptureSession {
  Future<DeviceMetadata> get metadata;
  Stream<VideoFrameEnvelope> get frames;
  Future<String> get diagnostics;
  Future<void> get completion;
  Future<void> close();
}

final class CaptureDevice {
  const CaptureDevice({
    required this.id,
    required this.name,
    required this.model,
    required this.manufacturer,
  });

  final String id;
  final String name;
  final String model;
  final String manufacturer;

  static List<CaptureDevice> parseList(String output) {
    return output
        .split('\n')
        .skip(1)
        .map((line) => line.trim().split('\t'))
        .where((columns) => columns.length == 4)
        .map(
          (columns) => CaptureDevice(
            id: columns[0],
            name: columns[1],
            model: columns[2],
            manufacturer: columns[3],
          ),
        )
        .toList(growable: false);
  }

  @override
  bool operator ==(Object other) =>
      other is CaptureDevice &&
      id == other.id &&
      name == other.name &&
      model == other.model &&
      manufacturer == other.manufacturer;

  @override
  int get hashCode => Object.hash(id, name, model, manufacturer);
}

final class NativeHelperStream {
  NativeHelperStream._({
    required this.metadata,
    required this.frames,
    required this.diagnostics,
  });

  factory NativeHelperStream.parse({
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
  }) {
    final metadata = Completer<DeviceMetadata>();
    final frames = StreamController<VideoFrameEnvelope>();
    final diagnostics = stderr.transform(utf8.decoder).join();
    unawaited(_parseStdout(stdout, metadata, frames));
    return NativeHelperStream._(
      metadata: metadata.future,
      frames: frames.stream,
      diagnostics: diagnostics,
    );
  }

  final Future<DeviceMetadata> metadata;
  final Stream<VideoFrameEnvelope> frames;
  final Future<String> diagnostics;

  static Future<void> _parseStdout(
    Stream<List<int>> stdout,
    Completer<DeviceMetadata> metadata,
    StreamController<VideoFrameEnvelope> frames,
  ) async {
    var buffer = Uint8List(0);
    var receivedMetadata = false;
    try {
      await for (final chunk in stdout) {
        buffer = Uint8List.fromList([...buffer, ...chunk]);
        if (!receivedMetadata) {
          final newline = buffer.indexOf(0x0a);
          if (newline < 0) continue;
          final decoded = jsonDecode(utf8.decode(buffer.sublist(0, newline)));
          if (decoded is! Map<String, Object?>) {
            throw const FormatException('Invalid native metadata.');
          }
          metadata.complete(DeviceMetadata.fromJson(decoded));
          receivedMetadata = true;
          buffer = Uint8List.fromList(buffer.sublist(newline + 1));
        }

        while (buffer.length >= VideoFrameEnvelope.headerLength) {
          final payloadLength = ByteData.sublistView(
            buffer,
          ).getUint32(0, Endian.big);
          final envelopeLength =
              VideoFrameEnvelope.headerLength + payloadLength;
          if (buffer.length < envelopeLength) break;
          frames.add(
            VideoFrameEnvelope.parse(
              Uint8List.fromList(buffer.sublist(0, envelopeLength)),
            ),
          );
          buffer = Uint8List.fromList(buffer.sublist(envelopeLength));
        }
      }

      if (!receivedMetadata || buffer.isNotEmpty) {
        throw const FormatException('Native helper output ended early.');
      }
      await frames.close();
    } catch (error, stackTrace) {
      final controlError = ControlError(
        code: 'capture_start_failed',
        message: 'Invalid native capture stream: $error',
      );
      if (!metadata.isCompleted) {
        metadata.completeError(controlError, stackTrace);
      }
      frames.addError(controlError, stackTrace);
      await frames.close();
    }
  }
}

final class NativeCaptureSession implements CaptureSession {
  NativeCaptureSession._(this._process, this._temporaryDirectory, this._stream);

  static Future<NativeCaptureSession> start({
    required String sourcePath,
    required String deviceId,
    int maxFps = 30,
    int bitRate = 6000000,
  }) async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'ios_screen_mvp_capture_',
    );
    final executable = '${temporaryDirectory.path}/ios_capture';
    try {
      final compile = await Process.run('swiftc', [
        '-parse-as-library',
        sourcePath,
        '-o',
        executable,
      ]);
      if (compile.exitCode != 0) {
        throw ControlError(
          code: 'capture_dependency_missing',
          message:
              'Failed to compile the native capture helper: '
              '${compile.stderr}',
        );
      }

      final process = await Process.start(executable, [
        'stream',
        '--device-id',
        deviceId,
        '--max-fps',
        '$maxFps',
        '--bit-rate',
        '$bitRate',
      ]);
      final stream = NativeHelperStream.parse(
        stdout: process.stdout,
        stderr: process.stderr,
      );
      return NativeCaptureSession._(process, temporaryDirectory, stream);
    } on ControlError {
      await temporaryDirectory.delete(recursive: true);
      rethrow;
    } on ProcessException catch (error) {
      await temporaryDirectory.delete(recursive: true);
      throw ControlError(
        code: 'capture_dependency_missing',
        message: 'Unable to run the native capture toolchain: $error',
      );
    } catch (error) {
      await temporaryDirectory.delete(recursive: true);
      throw ControlError(
        code: 'capture_start_failed',
        message: 'Unable to start native capture: $error',
      );
    }
  }

  final Process _process;
  final Directory _temporaryDirectory;
  final NativeHelperStream _stream;
  bool _closed = false;

  Future<DeviceMetadata> get metadata => _stream.metadata;
  Stream<VideoFrameEnvelope> get frames => _stream.frames;
  Future<String> get diagnostics => _stream.diagnostics;

  Future<void> get completion async {
    final exitCode = await _process.exitCode;
    if (!_closed && exitCode != 0) {
      final diagnostic = await diagnostics;
      throw ControlError(
        code: _errorCodeFor(diagnostic),
        message: diagnostic.trim().isEmpty
            ? 'Native capture helper exited with code $exitCode.'
            : diagnostic.trim(),
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _process.kill(ProcessSignal.sigterm);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode;
    }
    if (await _temporaryDirectory.exists()) {
      await _temporaryDirectory.delete(recursive: true);
    }
  }

  static String _errorCodeFor(String diagnostic) {
    if (diagnostic.contains('capture_permission_denied')) {
      return 'capture_permission_denied';
    }
    if (diagnostic.contains('capture_device_not_found')) {
      return 'capture_device_not_found';
    }
    if (diagnostic.contains('capture_device_busy')) {
      return 'capture_device_busy';
    }
    if (diagnostic.contains('video_encode_failed')) {
      return 'video_encode_failed';
    }
    return 'capture_start_failed';
  }
}
