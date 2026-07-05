import 'dart:convert';
import 'dart:io';

typedef FlutterDevicesRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

abstract interface class FlutterDeviceChecker {
  Future<FlutterDeviceCheckResult> checkDeviceId(String deviceId);
}

enum FlutterDeviceAvailability {
  available,
  notFound,
  unavailable,
}

class FlutterDeviceInfo {
  const FlutterDeviceInfo({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
}

class FlutterDeviceCheckResult {
  const FlutterDeviceCheckResult({
    required this.availability,
    this.device,
  });

  const FlutterDeviceCheckResult.notFound()
      : availability = FlutterDeviceAvailability.notFound,
        device = null;

  const FlutterDeviceCheckResult.available(this.device)
      : availability = FlutterDeviceAvailability.available;

  const FlutterDeviceCheckResult.unavailable(this.device)
      : availability = FlutterDeviceAvailability.unavailable;

  final FlutterDeviceAvailability availability;
  final FlutterDeviceInfo? device;
}

class FlutterDeviceCheckFailed implements Exception {
  const FlutterDeviceCheckFailed(this.message);

  final String message;

  @override
  String toString() => 'FlutterDeviceCheckFailed: $message';
}

class FlutterDevicesCommandChecker implements FlutterDeviceChecker {
  const FlutterDevicesCommandChecker({
    this.executable = 'flutter',
    this.runProcess = Process.run,
  });

  final String executable;
  final FlutterDevicesRunner runProcess;

  @override
  Future<FlutterDeviceCheckResult> checkDeviceId(String deviceId) async {
    final trimmedDeviceId = deviceId.trim();
    if (trimmedDeviceId.isEmpty) {
      return const FlutterDeviceCheckResult.notFound();
    }

    final result = await runProcess(executable, const ['devices', '--machine']);
    final output = '${result.stdout}\n${result.stderr}';

    if (result.exitCode != 0) {
      throw FlutterDeviceCheckFailed(
        '`$executable devices --machine` exited with ${result.exitCode}: ${output.trim()}',
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout.toString());
    } on FormatException catch (error) {
      throw FlutterDeviceCheckFailed(
        '`$executable devices --machine` returned malformed JSON: $error',
      );
    }

    if (decoded is! List<Object?>) {
      throw FlutterDeviceCheckFailed(
        '`$executable devices --machine` did not return a device list',
      );
    }

    for (final device in decoded) {
      final result = _targetDeviceResult(device, trimmedDeviceId);
      if (result.availability != FlutterDeviceAvailability.notFound) {
        return result;
      }
    }

    return const FlutterDeviceCheckResult.notFound();
  }

  FlutterDeviceCheckResult _targetDeviceResult(
    Object? device,
    String deviceId,
  ) {
    if (device is! Map<String, Object?>) {
      return const FlutterDeviceCheckResult.notFound();
    }

    final listedDeviceId = device['id'];
    final targetPlatform = device['targetPlatform'];
    if (listedDeviceId is! String || targetPlatform is! String) {
      return const FlutterDeviceCheckResult.notFound();
    }

    final normalizedTargetPlatform = targetPlatform.toLowerCase();
    if (listedDeviceId != deviceId ||
        !normalizedTargetPlatform.startsWith('android')) {
      return const FlutterDeviceCheckResult.notFound();
    }

    final displayName =
        device['name'] is String ? (device['name']! as String).trim() : '';
    final deviceInfo = FlutterDeviceInfo(
      id: listedDeviceId,
      displayName: displayName,
    );

    if (device['isSupported'] == false) {
      return FlutterDeviceCheckResult.unavailable(deviceInfo);
    }

    return FlutterDeviceCheckResult.available(deviceInfo);
  }
}

class FakeFlutterDeviceChecker implements FlutterDeviceChecker {
  const FakeFlutterDeviceChecker(
    this.deviceIds, {
    this.unavailableDeviceIds = const {},
  });

  final Set<String> deviceIds;
  final Set<String> unavailableDeviceIds;

  @override
  Future<FlutterDeviceCheckResult> checkDeviceId(String deviceId) async {
    final trimmedDeviceId = deviceId.trim();
    if (!deviceIds.contains(trimmedDeviceId)) {
      return const FlutterDeviceCheckResult.notFound();
    }
    final deviceInfo = FlutterDeviceInfo(
      id: trimmedDeviceId,
      displayName:
          trimmedDeviceId == '19271FDF6007TY' ? 'Pixel 6' : trimmedDeviceId,
    );
    if (unavailableDeviceIds.contains(trimmedDeviceId)) {
      return FlutterDeviceCheckResult.unavailable(deviceInfo);
    }
    return FlutterDeviceCheckResult.available(deviceInfo);
  }
}
