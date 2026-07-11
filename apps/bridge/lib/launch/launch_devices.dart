part of 'launch_command.dart';

class _FlutterDeviceDiscovery {
  const _FlutterDeviceDiscovery({
    required this.listDevices,
  });

  final FlutterDevicesRunner listDevices;

  Future<List<_LaunchDevice>> discoverUsableDevices() async {
    final ProcessResult result = await listDevices(
      'flutter',
      const ['devices', '--machine'],
    );
    if (result.exitCode != 0) {
      throw const _DeviceDiscoveryException();
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(result.stdout.toString());
    } on FormatException {
      throw const _DeviceDiscoveryException();
    }

    if (decoded is! List<Object?>) {
      throw const _DeviceDiscoveryException();
    }

    final List<_LaunchDevice> devices = <_LaunchDevice>[];
    for (final Object? rawDevice in decoded) {
      final _LaunchDevice? device = _LaunchDevice.fromJson(rawDevice);
      if (device != null && device.isUsable) {
        devices.add(device);
      }
    }

    return List<_LaunchDevice>.unmodifiable(devices);
  }
}

List<_LaunchDevice> _matchingDevices(
  List<_LaunchDevice> usableDevices,
  String? requestedDevice,
) {
  final String? trimmedRequest = requestedDevice?.trim();
  if (trimmedRequest == null || trimmedRequest.isEmpty) {
    return const <_LaunchDevice>[];
  }

  final List<_LaunchDevice> idMatches = usableDevices
      .where((device) => device.id == trimmedRequest)
      .toList(growable: false);
  if (idMatches.isNotEmpty) {
    return idMatches;
  }

  final String normalizedRequest = trimmedRequest.toLowerCase();
  return usableDevices
      .where(
        (device) => device.name.toLowerCase().contains(normalizedRequest),
      )
      .toList(growable: false);
}

class _LaunchDevice {
  const _LaunchDevice({
    required this.id,
    required this.name,
    required this.targetPlatform,
    required this.isSupported,
  });

  final String id;
  final String name;
  final String targetPlatform;
  final bool isSupported;

  bool get isUsable {
    return isSupported && targetPlatform.toLowerCase().startsWith('android');
  }

  static _LaunchDevice? fromJson(Object? rawDevice) {
    if (rawDevice is! Map<String, Object?>) {
      return null;
    }

    final Object? rawId = rawDevice['id'];
    final Object? rawTargetPlatform = rawDevice['targetPlatform'];
    if (rawId is! String || rawTargetPlatform is! String) {
      return null;
    }

    final Object? rawName = rawDevice['name'];
    return _LaunchDevice(
      id: rawId,
      name: rawName is String ? rawName : rawId,
      targetPlatform: rawTargetPlatform,
      isSupported: rawDevice['isSupported'] != false,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'targetPlatform': targetPlatform,
    };
  }
}

class _DeviceDiscoveryException implements Exception {
  const _DeviceDiscoveryException();
}
