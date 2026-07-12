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

final class CaptureCommandResult {
  const CaptureCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class CaptureProcess {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

abstract interface class CaptureCommandRunner {
  Future<CaptureCommandResult> run(String executable, List<String> arguments);
  Future<CaptureProcess> start(String executable, List<String> arguments);
}

final class SystemCaptureCommandRunner implements CaptureCommandRunner {
  const SystemCaptureCommandRunner();

  @override
  Future<CaptureCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return CaptureCommandResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }

  @override
  Future<CaptureProcess> start(
    String executable,
    List<String> arguments,
  ) async => _SystemCaptureProcess(await Process.start(executable, arguments));
}

final class _SystemCaptureProcess implements CaptureProcess {
  const _SystemCaptureProcess(this._process);

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);
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

final class DevelopmentDevice {
  const DevelopmentDevice({required this.id, required this.name});

  final String id;
  final String name;

  static List<DevelopmentDevice> parseXctrace(String output) {
    final devices = <DevelopmentDevice>[];
    var inDevicesSection = false;
    final devicePattern = RegExp(
      r'^(.*?)(?: \([^)]+\))? \(([0-9a-fA-F]{40})\)$',
    );
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed == '== Devices ==') {
        inDevicesSection = true;
        continue;
      }
      if (trimmed.startsWith('== ') && trimmed.endsWith(' ==')) {
        inDevicesSection = false;
        continue;
      }
      if (!inDevicesSection || trimmed.isEmpty) continue;
      final match = devicePattern.firstMatch(trimmed);
      if (match == null) continue;
      devices.add(
        DevelopmentDevice(id: match.group(2)!, name: match.group(1)!.trim()),
      );
    }
    return devices;
  }

  @override
  bool operator ==(Object other) =>
      other is DevelopmentDevice && id == other.id && name == other.name;

  @override
  int get hashCode => Object.hash(id, name);
}

final class CaptureTarget {
  const CaptureTarget({required this.name, this.captureId, this.developmentId});

  final String name;
  final String? captureId;
  final String? developmentId;

  static CaptureTarget resolve(
    String selector, {
    required List<CaptureDevice> recordableDevices,
    required List<DevelopmentDevice> developmentDevices,
  }) {
    for (final device in recordableDevices) {
      if (device.id == selector) {
        return _fromCapture(device, developmentDevices);
      }
    }
    for (final device in developmentDevices) {
      if (device.id == selector) {
        return _fromDevelopment(device, recordableDevices);
      }
    }

    final lowerSelector = selector.toLowerCase();
    for (final exact in [true, false]) {
      final captureMatches = recordableDevices.where((device) {
        final name = device.name.toLowerCase();
        return exact ? name == lowerSelector : name.startsWith(lowerSelector);
      }).toList();
      if (captureMatches.isNotEmpty) {
        if (captureMatches.length != 1) _throwAmbiguous(selector);
        return _fromCapture(captureMatches.single, developmentDevices);
      }

      final developmentMatches = developmentDevices.where((device) {
        final name = device.name.toLowerCase();
        return exact ? name == lowerSelector : name.startsWith(lowerSelector);
      }).toList();
      if (developmentMatches.isNotEmpty) {
        if (developmentMatches.length != 1) _throwAmbiguous(selector);
        return _fromDevelopment(developmentMatches.single, recordableDevices);
      }
    }

    throw ControlError(
      code: 'capture_device_not_found',
      message: 'No connected or recordable iPhone matched "$selector".',
    );
  }

  static CaptureTarget _fromCapture(
    CaptureDevice device,
    List<DevelopmentDevice> developmentDevices,
  ) {
    final developmentMatches = developmentDevices.where(
      (candidate) => candidate.name == device.name,
    );
    return CaptureTarget(
      name: device.name,
      captureId: device.id,
      developmentId: developmentMatches.length == 1
          ? developmentMatches.single.id
          : null,
    );
  }

  static CaptureTarget _fromDevelopment(
    DevelopmentDevice device,
    List<CaptureDevice> recordableDevices,
  ) {
    final captureMatches = recordableDevices.where(
      (candidate) => candidate.name == device.name,
    );
    if (captureMatches.length > 1) _throwAmbiguous(device.name);
    return CaptureTarget(
      name: device.name,
      captureId: captureMatches.isEmpty ? null : captureMatches.single.id,
      developmentId: device.id,
    );
  }

  static Never _throwAmbiguous(String selector) {
    throw ControlError(
      code: 'capture_device_not_found',
      message: 'Multiple iPhones matched "$selector"; use a capture ID.',
    );
  }
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

final class NativeCaptureLauncher {
  NativeCaptureLauncher({
    required this.helperPath,
    this.runner = const SystemCaptureCommandRunner(),
    Directory? temporaryDirectory,
  }) : _temporaryDirectory = temporaryDirectory;

  static Future<NativeCaptureLauncher> build({
    required String sourcePath,
    CaptureCommandRunner runner = const SystemCaptureCommandRunner(),
  }) async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'ios_screen_mvp_capture_',
    );
    final helperPath = '${temporaryDirectory.path}/ios_capture';
    try {
      final compile = await runner.run('swiftc', [
        '-parse-as-library',
        sourcePath,
        '-o',
        helperPath,
      ]);
      if (compile.exitCode != 0) {
        throw ControlError(
          code: 'capture_dependency_missing',
          message:
              'Failed to compile the native capture helper: '
              '${compile.stderr}',
        );
      }
      return NativeCaptureLauncher(
        helperPath: helperPath,
        runner: runner,
        temporaryDirectory: temporaryDirectory,
      );
    } catch (_) {
      await temporaryDirectory.delete(recursive: true);
      rethrow;
    }
  }

  final String helperPath;
  final CaptureCommandRunner runner;
  final Directory? _temporaryDirectory;

  Future<NativeCaptureSession> start(
    String selector, {
    int maxFps = 30,
    int bitRate = 6000000,
  }) async {
    final helperList = await runner.run(helperPath, const ['list']);
    if (helperList.exitCode != 0) {
      throw ControlError(
        code: 'capture_start_failed',
        message: 'Native capture discovery failed: ${helperList.stderr}',
      );
    }
    final xctrace = await runner.run('xcrun', const [
      'xctrace',
      'list',
      'devices',
    ]);
    final recordableDevices = CaptureDevice.parseList(helperList.stdout);
    final developmentDevices = xctrace.exitCode == 0
        ? DevelopmentDevice.parseXctrace(xctrace.stdout)
        : const <DevelopmentDevice>[];
    final target = CaptureTarget.resolve(
      selector,
      recordableDevices: recordableDevices,
      developmentDevices: developmentDevices,
    );
    final process = await runner.start(helperPath, [
      'stream',
      '--device-id',
      target.captureId ?? target.developmentId!,
      '--device-name',
      target.name,
      '--max-fps',
      '$maxFps',
      '--bit-rate',
      '$bitRate',
    ]);
    return NativeCaptureSession._(
      process,
      NativeHelperStream.parse(stdout: process.stdout, stderr: process.stderr),
    );
  }

  Future<void> close() async {
    final temporaryDirectory = _temporaryDirectory;
    if (temporaryDirectory != null && await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }
}

final class NativeCaptureSession implements CaptureSession {
  NativeCaptureSession._(
    this._process,
    this._stream, [
    this._temporaryDirectory,
  ]);

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
      const runner = SystemCaptureCommandRunner();
      final compile = await runner.run('swiftc', [
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

      final process = await runner.start(executable, [
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
      return NativeCaptureSession._(process, stream, temporaryDirectory);
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

  final CaptureProcess _process;
  final Directory? _temporaryDirectory;
  final NativeHelperStream _stream;
  bool _closed = false;

  Future<DeviceMetadata> get metadata async {
    try {
      return await _stream.metadata;
    } catch (_) {
      final exitCode = await _process.exitCode;
      final diagnostic = await diagnostics;
      if (exitCode != 0 || diagnostic.trim().isNotEmpty) {
        throw ControlError(
          code: _errorCodeFor(diagnostic),
          message: diagnostic.trim().isEmpty
              ? 'Native capture helper exited with code $exitCode.'
              : diagnostic.trim(),
        );
      }
      rethrow;
    }
  }

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
    final temporaryDirectory = _temporaryDirectory;
    if (temporaryDirectory != null && await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
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
