import 'dart:convert';
import 'dart:io';

typedef FlutterDevicesRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Result returned by the launch command runner.
///
/// The binary writes `stdout`, `stderr`, and `exitCode` directly. Tests use the
/// same object to verify the JSON contract without spawning a subprocess.
class LaunchCommandResult {
  const LaunchCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Parses the first Ask UI launch contract and selects a Flutter device.
///
/// This slice does not start Flutter yet. It returns machine-readable launch
/// intent and device-selection output so later launch phases can continue from
/// the same CLI contract.
Future<LaunchCommandResult> runLaunchCommand(
  List<String> args, {
  FlutterDevicesRunner listDevices = Process.run,
}) async {
  late final _LaunchOptions options;
  try {
    options = _LaunchOptions.parse(args);
  } on _LaunchValidationError {
    return _LaunchOutput.failure('invalid_arguments');
  }

  late final List<_LaunchDevice> usableDevices;
  try {
    usableDevices = await _FlutterDeviceDiscovery(
      listDevices: listDevices,
    ).discoverUsableDevices();
  } on _DeviceDiscoveryException {
    return _LaunchOutput.failure('device_discovery_failed');
  }

  if (usableDevices.isEmpty) {
    return _LaunchOutput.failure('no_usable_devices');
  }

  final List<_LaunchDevice> matchingDevices = _matchingDevices(
    usableDevices,
    options.requestedDevice,
  );
  if (matchingDevices.length == 1) {
    return _LaunchOutput.ready(options, matchingDevices.single);
  }

  if (options.requestedDevice != null && matchingDevices.isEmpty) {
    return _LaunchOutput.failure('device_not_found');
  }

  if (usableDevices.length == 1 && options.requestedDevice == null) {
    return _LaunchOutput.ready(options, usableDevices.single);
  }

  return _LaunchOutput.needsDeviceSelection(
    options,
    matchingDevices.isEmpty ? usableDevices : matchingDevices,
  );
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

class _LaunchOptions {
  const _LaunchOptions({
    required this.requestedDevice,
    required this.flavor,
    required this.target,
    required this.dartDefines,
    required this.projectRoot,
    required this.open,
  });

  final String? requestedDevice;
  final String? flavor;
  final String? target;
  final List<String> dartDefines;
  final String? projectRoot;
  final bool open;

  static _LaunchOptions parse(List<String> args) {
    if (args.isEmpty || args.first != 'launch') {
      throw const _LaunchValidationError();
    }

    String? requestedDevice;
    String? flavor;
    String? target;
    final List<String> dartDefines = <String>[];
    String? projectRoot;
    bool open = true;

    for (var index = 1; index < args.length; index += 1) {
      final String arg = args[index];
      if (arg == '--device' && index + 1 < args.length) {
        index += 1;
        requestedDevice = args[index];
      } else if (arg == '--flavor' && index + 1 < args.length) {
        index += 1;
        flavor = args[index];
      } else if (arg == '--target' && index + 1 < args.length) {
        index += 1;
        target = args[index];
      } else if (arg == '--dart-define' && index + 1 < args.length) {
        index += 1;
        dartDefines.add(args[index]);
      } else if (arg == '--project-root' && index + 1 < args.length) {
        index += 1;
        projectRoot = args[index];
      } else if (arg == '--no-open') {
        open = false;
      } else {
        throw const _LaunchValidationError();
      }
    }

    return _LaunchOptions(
      requestedDevice: _emptyToNull(requestedDevice),
      flavor: _emptyToNull(flavor),
      target: _emptyToNull(target),
      dartDefines: List<String>.unmodifiable(dartDefines),
      projectRoot: _emptyToNull(projectRoot),
      open: open,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'device': requestedDevice,
      'flavor': flavor,
      'target': target,
      'dartDefines': dartDefines,
      'projectRoot': projectRoot,
      'open': open,
    };
  }

  List<String> flutterRunArguments(String deviceId) {
    final List<String> arguments = <String>[
      'run',
      '--device-id',
      deviceId,
    ];

    if (flavor != null) {
      arguments.addAll(['--flavor', flavor!]);
    }
    if (target != null) {
      arguments.addAll(['--target', target!]);
    }
    for (final String dartDefine in dartDefines) {
      arguments.addAll(['--dart-define', dartDefine]);
    }

    return arguments;
  }

  List<String> rerunArguments(String deviceId) {
    final List<String> arguments = <String>[
      'dart',
      'run',
      'ask_ui_bridge',
      'launch',
      '--device',
      deviceId,
    ];

    if (flavor != null) {
      arguments.addAll(['--flavor', flavor!]);
    }
    if (target != null) {
      arguments.addAll(['--target', target!]);
    }
    for (final String dartDefine in dartDefines) {
      arguments.addAll(['--dart-define', dartDefine]);
    }
    if (projectRoot != null) {
      arguments.addAll(['--project-root', projectRoot!]);
    }
    if (!open) {
      arguments.add('--no-open');
    }

    return arguments;
  }
}

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

class _LaunchOutput {
  _LaunchOutput._();

  static LaunchCommandResult ready(
    _LaunchOptions options,
    _LaunchDevice selectedDevice,
  ) {
    return LaunchCommandResult(
      exitCode: 0,
      stdout: jsonEncode({
        'status': 'ready',
        'selectedDevice': selectedDevice.toJson(),
        'launchIntent': options.toJson(),
        'flutterRunArguments': options.flutterRunArguments(selectedDevice.id),
        'nextStep':
            'Launch Flutter app for selected device ${selectedDevice.id}.',
      }),
    );
  }

  static LaunchCommandResult needsDeviceSelection(
    _LaunchOptions options,
    List<_LaunchDevice> devices,
  ) {
    return LaunchCommandResult(
      exitCode: 0,
      stdout: jsonEncode({
        'status': 'needs_device_selection',
        'devices': devices
            .map((device) => {
                  ...device.toJson(),
                  'suggestedCommand': _commandString(
                    options.rerunArguments(device.id),
                  ),
                })
            .toList(growable: false),
        'launchIntent': options.toJson(),
        'nextStep':
            'Ask the user to choose a device, then rerun launch with --device.',
      }),
    );
  }

  static LaunchCommandResult failure(String code) {
    return LaunchCommandResult(
      exitCode: 1,
      stderr: jsonEncode({
        'status': 'error',
        'error': code,
      }),
    );
  }
}

String _commandString(List<String> arguments) {
  return arguments.map(_shellQuote).join(' ');
}

String _shellQuote(String argument) {
  if (RegExp(r'^[A-Za-z0-9_./:=@+-]+$').hasMatch(argument)) {
    return argument;
  }

  return "'${argument.replaceAll("'", r"'\''")}'";
}

String? _emptyToNull(String? value) {
  final String? trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  return trimmed;
}

class _LaunchValidationError implements Exception {
  const _LaunchValidationError();
}

class _DeviceDiscoveryException implements Exception {
  const _DeviceDiscoveryException();
}
