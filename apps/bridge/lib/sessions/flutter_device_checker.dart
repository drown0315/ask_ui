import 'dart:convert';
import 'dart:io';

typedef FlutterDevicesRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

abstract interface class FlutterDeviceChecker {
  Future<FlutterDeviceAvailability> checkDeviceId(String deviceId);
}

enum FlutterDeviceAvailability {
  available,
  notFound,
  unavailable,
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
  Future<FlutterDeviceAvailability> checkDeviceId(String deviceId) async {
    final trimmedDeviceId = deviceId.trim();
    if (trimmedDeviceId.isEmpty) {
      return FlutterDeviceAvailability.notFound;
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
      final availability = _targetDeviceAvailability(device, trimmedDeviceId);
      if (availability != FlutterDeviceAvailability.notFound) {
        return availability;
      }
    }

    return FlutterDeviceAvailability.notFound;
  }

  FlutterDeviceAvailability _targetDeviceAvailability(
    Object? device,
    String deviceId,
  ) {
    if (device is! Map<String, Object?>) {
      return FlutterDeviceAvailability.notFound;
    }

    final listedDeviceId = device['id'];
    final targetPlatform = device['targetPlatform'];
    if (listedDeviceId is! String || targetPlatform is! String) {
      return FlutterDeviceAvailability.notFound;
    }

    final normalizedTargetPlatform = targetPlatform.toLowerCase();
    if (listedDeviceId != deviceId ||
        !normalizedTargetPlatform.startsWith('android')) {
      return FlutterDeviceAvailability.notFound;
    }

    if (device['isSupported'] == false) {
      return FlutterDeviceAvailability.unavailable;
    }

    return FlutterDeviceAvailability.available;
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
  Future<FlutterDeviceAvailability> checkDeviceId(String deviceId) async {
    final trimmedDeviceId = deviceId.trim();
    if (!deviceIds.contains(trimmedDeviceId)) {
      return FlutterDeviceAvailability.notFound;
    }
    if (unavailableDeviceIds.contains(trimmedDeviceId)) {
      return FlutterDeviceAvailability.unavailable;
    }
    return FlutterDeviceAvailability.available;
  }
}
