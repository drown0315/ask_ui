import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../app_controller/flutter_app_controller.dart';
import '../inspector/flutter_inspector_client.dart';
import '../logging/bridge_logger.dart';
import '../server/ask_ui_bridge_server.dart';
import '../sessions/session_store.dart';

typedef FlutterDevicesRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Starts the target Flutter app and returns the VM Service URI it exposes.
abstract interface class LaunchAppLauncher {
  Future<LaunchAppResult> launch({
    required List<String> flutterRunArguments,
    required String projectRoot,
  });
}

/// VM Service details captured from a successful Flutter app startup.
class LaunchAppResult {
  const LaunchAppResult({required this.vmServiceUri});

  final String vmServiceUri;
}

/// Normalized Flutter startup failure for launch command JSON output.
class LaunchAppException implements Exception {
  const LaunchAppException(this.code);

  final String code;
}

/// Starts or reuses the local Bridge Server and creates a Bridge Session.
abstract interface class LaunchBridgeLauncher {
  Future<LaunchBridgeSession> createSession({
    required String vmServiceUri,
    required String projectRoot,
    required String deviceId,
  });
}

/// Bridge Session connection details returned to the launcher.
class LaunchBridgeSession {
  const LaunchBridgeSession({
    required this.bridgeUrl,
    required this.sessionId,
  });

  final Uri bridgeUrl;
  final String sessionId;
}

/// Normalized Bridge startup/session failure for launch command JSON output.
class LaunchBridgeException implements Exception {
  const LaunchBridgeException(this.code);

  final String code;
}

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
  LaunchAppLauncher? appLauncher,
  LaunchBridgeLauncher? bridgeLauncher,
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
    return _launchSelectedDevice(
      options: options,
      selectedDevice: matchingDevices.single,
      appLauncher: appLauncher ?? const _FlutterRunAppLauncher(),
      bridgeLauncher: bridgeLauncher ?? _LocalBridgeLauncher(),
    );
  }

  if (options.requestedDevice != null && matchingDevices.isEmpty) {
    return _LaunchOutput.failure('device_not_found');
  }

  if (usableDevices.length == 1 && options.requestedDevice == null) {
    return _launchSelectedDevice(
      options: options,
      selectedDevice: usableDevices.single,
      appLauncher: appLauncher ?? const _FlutterRunAppLauncher(),
      bridgeLauncher: bridgeLauncher ?? _LocalBridgeLauncher(),
    );
  }

  return _LaunchOutput.needsDeviceSelection(
    options,
    matchingDevices.isEmpty ? usableDevices : matchingDevices,
  );
}

Future<LaunchCommandResult> _launchSelectedDevice({
  required _LaunchOptions options,
  required _LaunchDevice selectedDevice,
  required LaunchAppLauncher appLauncher,
  required LaunchBridgeLauncher bridgeLauncher,
}) async {
  final String projectRoot =
      options.projectRoot ?? Directory.current.absolute.path;
  late final LaunchAppResult appResult;
  try {
    appResult = await appLauncher.launch(
      flutterRunArguments: options.flutterRunArguments(selectedDevice.id),
      projectRoot: projectRoot,
    );
  } on LaunchAppException catch (error) {
    return _LaunchOutput.failure(error.code);
  }

  late final LaunchBridgeSession bridgeSession;
  try {
    bridgeSession = await bridgeLauncher.createSession(
      vmServiceUri: appResult.vmServiceUri,
      projectRoot: projectRoot,
      deviceId: selectedDevice.id,
    );
  } on LaunchBridgeException catch (error) {
    return _LaunchOutput.failure(error.code);
  }

  return _LaunchOutput.ready(
    options: options,
    selectedDevice: selectedDevice,
    appResult: appResult,
    bridgeSession: bridgeSession,
    projectRoot: projectRoot,
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

class _FlutterRunAppLauncher implements LaunchAppLauncher {
  const _FlutterRunAppLauncher();

  @override
  Future<LaunchAppResult> launch({
    required List<String> flutterRunArguments,
    required String projectRoot,
  }) async {
    late final Process process;
    try {
      process = await Process.start(
        'flutter',
        flutterRunArguments,
        workingDirectory: projectRoot,
      );
    } catch (_) {
      throw const LaunchAppException('flutter_run_failed');
    }

    final Completer<LaunchAppResult> vmServiceCompleter =
        Completer<LaunchAppResult>();
    final StringBuffer startupOutput = StringBuffer();

    void observeOutput(List<int> data) {
      final String text = utf8.decode(data, allowMalformed: true);
      startupOutput.write(text);
      final String? vmServiceUri =
          parseFlutterVmServiceUriFromOutput(startupOutput.toString());
      if (vmServiceUri != null && !vmServiceCompleter.isCompleted) {
        vmServiceCompleter
            .complete(LaunchAppResult(vmServiceUri: vmServiceUri));
      }
    }

    process.stdout.listen(observeOutput);
    process.stderr.listen(observeOutput);
    process.exitCode.then((int exitCode) {
      if (!vmServiceCompleter.isCompleted) {
        vmServiceCompleter.completeError(
          const LaunchAppException('flutter_run_failed'),
        );
      }
    });

    try {
      return await vmServiceCompleter.future.timeout(
        const Duration(minutes: 2),
      );
    } on LaunchAppException {
      rethrow;
    } on TimeoutException {
      process.kill();
      throw const LaunchAppException('flutter_vm_service_not_found');
    } catch (_) {
      throw const LaunchAppException('flutter_run_failed');
    }
  }
}

/// Extract the VM Service WebSocket URI from Flutter startup output.
///
/// Flutter commonly prints an HTTP service URI ending in the auth-code path,
/// while the existing Bridge Session contract stores the WebSocket URI. Already
/// normalized `ws` and `wss` URIs are returned unchanged.
String? parseFlutterVmServiceUriFromOutput(String output) {
  final RegExp uriPattern = RegExp(r'(wss?|https?)://[^\s]+');
  for (final RegExpMatch match in uriPattern.allMatches(output)) {
    final String rawUri = match.group(0)!.replaceFirst(RegExp(r'[),.;]+$'), '');
    final Uri? uri = Uri.tryParse(rawUri);
    if (uri == null || uri.host.isEmpty) {
      continue;
    }
    if (uri.scheme == 'ws' || uri.scheme == 'wss') {
      return uri.toString();
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final String websocketScheme = uri.scheme == 'https' ? 'wss' : 'ws';
      final String normalizedPath = uri.path.endsWith('/ws')
          ? uri.path
          : '${uri.path.endsWith('/') ? uri.path : '${uri.path}/'}ws';
      return uri
          .replace(
            scheme: websocketScheme,
            path: normalizedPath,
          )
          .toString();
    }
  }

  return null;
}

class _LocalBridgeLauncher implements LaunchBridgeLauncher {
  _LocalBridgeLauncher({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  AskUiBridgeServer? _server;

  @override
  Future<LaunchBridgeSession> createSession({
    required String vmServiceUri,
    required String projectRoot,
    required String deviceId,
  }) async {
    final Uri bridgeUrl = await _startOrReuseServer();
    final Uri sessionUri = bridgeUrl.resolve('/api/sessions');

    try {
      final HttpClientRequest request = await _httpClient.postUrl(sessionUri);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'vmServiceUri': vmServiceUri,
          'projectRoot': projectRoot,
          'deviceId': deviceId,
        }),
      );
      final HttpClientResponse response = await request.close();
      final String responseBody = await utf8.decodeStream(response);
      final Object? decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Expected session JSON object');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const LaunchBridgeException('session_creation_failed');
      }
      final Object? sessionId = decoded['sessionId'];
      if (sessionId is! String || sessionId.trim().isEmpty) {
        throw const LaunchBridgeException('session_creation_failed');
      }
      return LaunchBridgeSession(
        bridgeUrl: bridgeUrl,
        sessionId: sessionId,
      );
    } on LaunchBridgeException {
      rethrow;
    } catch (_) {
      throw const LaunchBridgeException('session_creation_failed');
    }
  }

  Future<Uri> _startOrReuseServer() async {
    final Uri bridgeUrl = Uri.parse('http://127.0.0.1:8787');
    if (_server != null) {
      return bridgeUrl;
    }

    final BridgeLogger logger = BridgeLogger(write: stderr.writeln);
    final Directory packagedWebRoot = await _resolvePackagedWebRoot();
    final AskUiBridgeServer server = AskUiBridgeServer(
      sessionStore: SessionStore(),
      inspectorClient: VmServiceFlutterInspectorClient(
        vmServiceFactory: VmServiceFactory(),
      ),
      appController: VmServiceFlutterAppController(
        vmServiceFactory: VmServiceFactory(),
        logger: logger,
      ),
      packagedWebRoot: packagedWebRoot,
      logger: logger,
    );

    try {
      await server.start(host: '127.0.0.1', port: 8787);
      _server = server;
      return bridgeUrl;
    } on SocketException {
      return bridgeUrl;
    } catch (_) {
      throw const LaunchBridgeException('bridge_start_failed');
    }
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

  static LaunchCommandResult ready({
    required _LaunchOptions options,
    required _LaunchDevice selectedDevice,
    required LaunchAppResult appResult,
    required LaunchBridgeSession bridgeSession,
    required String projectRoot,
  }) {
    final String agentCommand = _commandString([
      'dart',
      'run',
      'ask_ui_bridge',
      'agent',
      'poll',
      '--base-url',
      bridgeSession.bridgeUrl.toString(),
      '--session-id',
      bridgeSession.sessionId,
    ]);
    return LaunchCommandResult(
      exitCode: 0,
      stdout: jsonEncode({
        'status': 'ready',
        'selectedDevice': selectedDevice.toJson(),
        'launchIntent': options.toJson(),
        'bridgeUrl': bridgeSession.bridgeUrl.toString(),
        'sessionId': bridgeSession.sessionId,
        'vmServiceUri': appResult.vmServiceUri,
        'projectRoot': projectRoot,
        'flavor': options.flavor,
        'target': options.target,
        'agentCommand': agentCommand,
        'nextStep': 'Run the returned agent poll command.',
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

Future<Directory> _resolvePackagedWebRoot() async {
  final Uri? serverLibraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:ask_ui_bridge/server/ask_ui_bridge_server.dart'),
  );
  if (serverLibraryUri == null) {
    return Directory('web');
  }

  return Directory.fromUri(serverLibraryUri.resolve('../../web'));
}
