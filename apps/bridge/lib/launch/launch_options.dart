part of 'launch_command.dart';

class _LaunchOptions {
  const _LaunchOptions({
    required this.requestedDevice,
    required this.flavor,
    required this.target,
    required this.dartDefines,
    required this.projectRoot,
    required this.open,
    required this.webDev,
  });

  final String? requestedDevice;
  final String? flavor;
  final String? target;
  final List<String> dartDefines;
  final String? projectRoot;
  final bool open;
  final bool webDev;

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
    bool webDev = false;

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
      } else if (arg == '--web-dev') {
        webDev = true;
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
      webDev: webDev,
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
      'webDev': webDev,
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
    if (webDev) {
      arguments.add('--web-dev');
    }

    return arguments;
  }
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
