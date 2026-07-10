import 'dart:convert';
import 'dart:io';

import 'package:ask_ui_bridge/launch/launch_command.dart';
import 'package:test/test.dart';

void main() {
  group('Launch command contract', () {
    test('auto-selects one usable device and preserves Flutter launch intent',
        () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'device-1',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
      ]);
      final _RecordingBrowserOpener browserOpener = _RecordingBrowserOpener();

      final LaunchCommandResult result = await runLaunchCommand(
        const [
          'launch',
          '--flavor',
          'staging',
          '--target',
          'lib/main_staging.dart',
          '--dart-define',
          'API_HOST=local',
          '--dart-define',
          'FEATURE_X=true',
          '--project-root',
          '/workspace/app',
          '--no-open',
        ],
        listDevices: devices.listDevices,
        appLauncher: _RecordingAppLauncher(
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
        ),
        bridgeLauncher: _RecordingBridgeLauncher(
          bridgeUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
        ),
        browserOpener: browserOpener,
      );

      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(jsonDecode(result.stdout), {
        'status': 'ready',
        'selectedDevice': {
          'id': 'device-1',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
        'launchIntent': {
          'device': null,
          'flavor': 'staging',
          'target': 'lib/main_staging.dart',
          'dartDefines': ['API_HOST=local', 'FEATURE_X=true'],
          'projectRoot': '/workspace/app',
          'open': false,
        },
        'bridgeUrl': 'http://127.0.0.1:8787',
        'sessionId': 'session-1',
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
        'projectRoot': '/workspace/app',
        'flavor': 'staging',
        'target': 'lib/main_staging.dart',
        'agentCommand':
            'dart run ask_ui_bridge agent poll --base-url http://127.0.0.1:8787 --session-id session-1',
        'workbenchUrl':
            'http://127.0.0.1:8787/?bridgeUrl=http%3A%2F%2F127.0.0.1%3A8787&sessionId=session-1&deviceId=device-1&projectRoot=%2Fworkspace%2Fapp&flavor=staging&target=lib%2Fmain_staging.dart',
        'browserOpened': false,
        'nextStep': 'Run the returned agent poll command.',
      });
      expect(browserOpener.openedUrls, isEmpty);
      expect(devices.calls, [
        ['devices', '--machine'],
      ]);
    });

    test('launches Flutter and creates a Bridge Session for a selected device',
        () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'device-1',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
      ]);
      final _RecordingAppLauncher appLauncher = _RecordingAppLauncher(
        vmServiceUri: 'ws://127.0.0.1:44444/ws',
      );
      final _RecordingBridgeLauncher bridgeLauncher = _RecordingBridgeLauncher(
        bridgeUrl: Uri.parse('http://127.0.0.1:9876'),
        sessionId: 'session-7',
      );
      final _RecordingBrowserOpener browserOpener = _RecordingBrowserOpener();

      final LaunchCommandResult result = await runLaunchCommand(
        const [
          'launch',
          '--device',
          'device-1',
          '--flavor',
          'dev',
          '--target',
          'lib/main_dev.dart',
          '--dart-define',
          'API_HOST=local',
          '--project-root',
          '/workspace/app',
        ],
        listDevices: devices.listDevices,
        appLauncher: appLauncher,
        bridgeLauncher: bridgeLauncher,
        browserOpener: browserOpener,
      );

      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(jsonDecode(result.stdout), {
        'status': 'ready',
        'selectedDevice': {
          'id': 'device-1',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
        'launchIntent': {
          'device': 'device-1',
          'flavor': 'dev',
          'target': 'lib/main_dev.dart',
          'dartDefines': ['API_HOST=local'],
          'projectRoot': '/workspace/app',
          'open': true,
        },
        'bridgeUrl': 'http://127.0.0.1:9876',
        'sessionId': 'session-7',
        'vmServiceUri': 'ws://127.0.0.1:44444/ws',
        'projectRoot': '/workspace/app',
        'flavor': 'dev',
        'target': 'lib/main_dev.dart',
        'agentCommand':
            'dart run ask_ui_bridge agent poll --base-url http://127.0.0.1:9876 --session-id session-7',
        'workbenchUrl':
            'http://127.0.0.1:9876/?bridgeUrl=http%3A%2F%2F127.0.0.1%3A9876&sessionId=session-7&deviceId=device-1&projectRoot=%2Fworkspace%2Fapp&flavor=dev&target=lib%2Fmain_dev.dart',
        'browserOpened': true,
        'nextStep': 'Run the returned agent poll command.',
      });
      expect(browserOpener.openedUrls, [
        Uri.parse(
          'http://127.0.0.1:9876/?bridgeUrl=http%3A%2F%2F127.0.0.1%3A9876&sessionId=session-7&deviceId=device-1&projectRoot=%2Fworkspace%2Fapp&flavor=dev&target=lib%2Fmain_dev.dart',
        ),
      ]);
      expect(appLauncher.requests, hasLength(1));
      expect(appLauncher.requests.single.projectRoot, '/workspace/app');
      expect(appLauncher.requests.single.arguments, [
        'run',
        '--device-id',
        'device-1',
        '--flavor',
        'dev',
        '--target',
        'lib/main_dev.dart',
        '--dart-define',
        'API_HOST=local',
      ]);
      expect(bridgeLauncher.requests, [
        (
          vmServiceUri: 'ws://127.0.0.1:44444/ws',
          projectRoot: '/workspace/app',
          deviceId: 'device-1',
        ),
      ]);
    });

    test('workbench URL uses attach bootstrap parameters', () async {
      final Uri workbenchUrl = buildLaunchWorkbenchUrl(
        bridgeUrl: Uri.parse('http://127.0.0.1:8787/'),
        sessionId: 'session-1',
        selectedDeviceId: '19271FDF6007TY',
        projectRoot: '/Users/example app',
        flavor: 'qa flavor',
        target: null,
      );

      expect(workbenchUrl.origin, 'http://127.0.0.1:8787');
      expect(workbenchUrl.path, '/');
      expect(workbenchUrl.queryParameters, {
        'bridgeUrl': 'http://127.0.0.1:8787',
        'sessionId': 'session-1',
        'deviceId': '19271FDF6007TY',
        'projectRoot': '/Users/example app',
        'flavor': 'qa flavor',
      });
    });

    test('reports browser open failures without losing launch details',
        () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'device-1',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
      ]);

      final LaunchCommandResult result = await runLaunchCommand(
        const ['launch', '--device', 'device-1'],
        listDevices: devices.listDevices,
        appLauncher: _RecordingAppLauncher(
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
        ),
        bridgeLauncher: _RecordingBridgeLauncher(
          bridgeUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
        ),
        browserOpener: const _FailingBrowserOpener(),
      );

      final decoded = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(decoded['status'], 'ready');
      expect(decoded['workbenchUrl'], isA<String>());
      expect(decoded['browserOpened'], false);
      expect(decoded['browserOpenError'], 'browser_open_failed');
    });

    test('reports Flutter startup failures before session creation', () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'device-1',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
      ]);
      final _FailingAppLauncher appLauncher = _FailingAppLauncher(
        const LaunchAppException('flutter_run_failed'),
      );
      final _RecordingBridgeLauncher bridgeLauncher = _RecordingBridgeLauncher(
        bridgeUrl: Uri.parse('http://127.0.0.1:9876'),
        sessionId: 'session-7',
      );

      final LaunchCommandResult result = await runLaunchCommand(
        const ['launch', '--device', 'device-1'],
        listDevices: devices.listDevices,
        appLauncher: appLauncher,
        bridgeLauncher: bridgeLauncher,
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr), {
        'status': 'error',
        'error': 'flutter_run_failed',
      });
      expect(bridgeLauncher.requests, isEmpty);
    });

    test('reports Bridge Session creation failures', () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'device-1',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
      ]);
      final _RecordingAppLauncher appLauncher = _RecordingAppLauncher(
        vmServiceUri: 'ws://127.0.0.1:44444/ws',
      );
      final _FailingBridgeLauncher bridgeLauncher = _FailingBridgeLauncher(
        const LaunchBridgeException('session_creation_failed'),
      );

      final LaunchCommandResult result = await runLaunchCommand(
        const ['launch', '--device', 'device-1'],
        listDevices: devices.listDevices,
        appLauncher: appLauncher,
        bridgeLauncher: bridgeLauncher,
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr), {
        'status': 'error',
        'error': 'session_creation_failed',
      });
    });

    test('parses Flutter VM Service output into WebSocket URIs', () {
      expect(
        parseFlutterVmServiceUriFromOutput(
          'A Dart VM Service is available at: '
          'http://127.0.0.1:51234/abc_def=/',
        ),
        'ws://127.0.0.1:51234/abc_def=/ws',
      );
      expect(
        parseFlutterVmServiceUriFromOutput(
          'The Dart VM Service is listening on '
          'ws://127.0.0.1:51234/abc_def=/ws',
        ),
        'ws://127.0.0.1:51234/abc_def=/ws',
      );
      expect(
        parseFlutterVmServiceUriFromOutput('Build failed before service.'),
        isNull,
      );
    });

    test('returns one JSON error object when no usable devices exist',
        () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'offline',
          'name': 'Offline Android',
          'targetPlatform': 'android-arm64',
          'isSupported': false,
        },
        {
          'id': 'macos',
          'name': 'macOS',
          'targetPlatform': 'darwin-arm64',
        },
      ]);

      final LaunchCommandResult result = await runLaunchCommand(
        const ['launch'],
        listDevices: devices.listDevices,
        appLauncher: _FailingAppLauncher.unused(),
        bridgeLauncher: _FailingBridgeLauncher.unused(),
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr), {
        'status': 'error',
        'error': 'no_usable_devices',
      });
    });

    test('returns device choices and preserved rerun commands for selection',
        () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'emulator-5554',
          'name': 'Pixel API 35',
          'targetPlatform': 'android-x64',
        },
        {
          'id': '19271FDF6007TY',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
      ]);

      final LaunchCommandResult result = await runLaunchCommand(
        const [
          'launch',
          '--flavor',
          'dev',
          '--target',
          'lib/main_dev.dart',
          '--dart-define',
          'A=B',
          '--project-root',
          '/workspace/app',
          '--no-open',
        ],
        listDevices: devices.listDevices,
        appLauncher: _FailingAppLauncher.unused(),
        bridgeLauncher: _FailingBridgeLauncher.unused(),
      );

      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      expect(jsonDecode(result.stdout), {
        'status': 'needs_device_selection',
        'devices': [
          {
            'id': 'emulator-5554',
            'name': 'Pixel API 35',
            'targetPlatform': 'android-x64',
            'suggestedCommand':
                'dart run ask_ui_bridge launch --device emulator-5554 --flavor dev --target lib/main_dev.dart --dart-define A=B --project-root /workspace/app --no-open',
          },
          {
            'id': '19271FDF6007TY',
            'name': 'Pixel 6',
            'targetPlatform': 'android-arm64',
            'suggestedCommand':
                'dart run ask_ui_bridge launch --device 19271FDF6007TY --flavor dev --target lib/main_dev.dart --dart-define A=B --project-root /workspace/app --no-open',
          },
        ],
        'launchIntent': {
          'device': null,
          'flavor': 'dev',
          'target': 'lib/main_dev.dart',
          'dartDefines': ['A=B'],
          'projectRoot': '/workspace/app',
          'open': false,
        },
        'nextStep':
            'Ask the user to choose a device, then rerun launch with --device.',
      });
    });

    test('selects an explicit device id from multiple usable devices',
        () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'emulator-5554',
          'name': 'Pixel API 35',
          'targetPlatform': 'android-x64',
        },
        {
          'id': '19271FDF6007TY',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
      ]);

      final LaunchCommandResult result = await runLaunchCommand(
        const ['launch', '--device', '19271FDF6007TY'],
        listDevices: devices.listDevices,
        appLauncher: _RecordingAppLauncher(
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
        ),
        bridgeLauncher: _RecordingBridgeLauncher(
          bridgeUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
        ),
      );

      expect(result.exitCode, 0);
      expect(jsonDecode(result.stdout)['selectedDevice'], {
        'id': '19271FDF6007TY',
        'name': 'Pixel 6',
        'targetPlatform': 'android-arm64',
      });
    });

    test('selects an unambiguous device name and refuses ambiguous names',
        () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'emulator-5554',
          'name': 'Pixel',
          'targetPlatform': 'android-x64',
        },
        {
          'id': '19271FDF6007TY',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
      ]);

      final LaunchCommandResult named = await runLaunchCommand(
        const ['launch', '--device', 'Pixel 6'],
        listDevices: devices.listDevices,
        appLauncher: _RecordingAppLauncher(
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
        ),
        bridgeLauncher: _RecordingBridgeLauncher(
          bridgeUrl: Uri.parse('http://127.0.0.1:8787'),
          sessionId: 'session-1',
        ),
      );
      final LaunchCommandResult ambiguous = await runLaunchCommand(
        const ['launch', '--device', 'Pixel'],
        listDevices: devices.listDevices,
        appLauncher: _FailingAppLauncher.unused(),
        bridgeLauncher: _FailingBridgeLauncher.unused(),
      );

      expect(named.exitCode, 0);
      expect(
          jsonDecode(named.stdout)['selectedDevice']['id'], '19271FDF6007TY');
      expect(ambiguous.exitCode, 0);
      expect(jsonDecode(ambiguous.stdout)['status'], 'needs_device_selection');
    });

    test('reports invalid arguments without listing devices', () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([]);

      final LaunchCommandResult result = await runLaunchCommand(
        const ['launch', '--flavor'],
        listDevices: devices.listDevices,
        appLauncher: _FailingAppLauncher.unused(),
        bridgeLauncher: _FailingBridgeLauncher.unused(),
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr), {
        'status': 'error',
        'error': 'invalid_arguments',
      });
      expect(devices.calls, isEmpty);
    });

    test('binary launch command writes JSON failure to stderr only', () async {
      final ProcessResult result = await Process.run(
        Platform.resolvedExecutable,
        const ['bin/ask_ui_bridge.dart', 'launch', '--flavor'],
        workingDirectory: Directory.current.path,
        environment: const <String, String>{},
        includeParentEnvironment: false,
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr as String), {
        'status': 'error',
        'error': 'invalid_arguments',
      });
    });

    test('reports malformed flutter devices output as JSON', () async {
      final LaunchCommandResult result = await runLaunchCommand(
        const ['launch'],
        listDevices: (executable, arguments) async {
          return ProcessResult(1, 0, '{"devices":[]}', '');
        },
        appLauncher: _FailingAppLauncher.unused(),
        bridgeLauncher: _FailingBridgeLauncher.unused(),
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr), {
        'status': 'error',
        'error': 'device_discovery_failed',
      });
    });
  });
}

class _RecordingAppLauncher implements LaunchAppLauncher {
  _RecordingAppLauncher({required this.vmServiceUri});

  final String vmServiceUri;
  final List<({List<String> arguments, String projectRoot})> requests =
      <({List<String> arguments, String projectRoot})>[];

  @override
  Future<LaunchAppResult> launch({
    required List<String> flutterRunArguments,
    required String projectRoot,
  }) async {
    requests.add((
      arguments: List<String>.from(flutterRunArguments),
      projectRoot: projectRoot,
    ));
    return LaunchAppResult(vmServiceUri: vmServiceUri);
  }
}

class _FailingAppLauncher implements LaunchAppLauncher {
  const _FailingAppLauncher(this.exception);

  const _FailingAppLauncher.unused()
      : exception = const LaunchAppException('unexpected_app_launch');

  final LaunchAppException exception;

  @override
  Future<LaunchAppResult> launch({
    required List<String> flutterRunArguments,
    required String projectRoot,
  }) async {
    throw exception;
  }
}

class _RecordingBridgeLauncher implements LaunchBridgeLauncher {
  _RecordingBridgeLauncher({
    required this.bridgeUrl,
    required this.sessionId,
  });

  final Uri bridgeUrl;
  final String sessionId;
  final List<({String vmServiceUri, String projectRoot, String deviceId})>
      requests =
      <({String vmServiceUri, String projectRoot, String deviceId})>[];

  @override
  Future<LaunchBridgeSession> createSession({
    required String vmServiceUri,
    required String projectRoot,
    required String deviceId,
  }) async {
    requests.add((
      vmServiceUri: vmServiceUri,
      projectRoot: projectRoot,
      deviceId: deviceId,
    ));
    return LaunchBridgeSession(
      bridgeUrl: bridgeUrl,
      sessionId: sessionId,
    );
  }
}

class _FailingBridgeLauncher implements LaunchBridgeLauncher {
  const _FailingBridgeLauncher(this.exception);

  const _FailingBridgeLauncher.unused()
      : exception = const LaunchBridgeException('unexpected_bridge_launch');

  final LaunchBridgeException exception;

  @override
  Future<LaunchBridgeSession> createSession({
    required String vmServiceUri,
    required String projectRoot,
    required String deviceId,
  }) async {
    throw exception;
  }
}

class _RecordingBrowserOpener implements LaunchBrowserOpener {
  final List<Uri> openedUrls = <Uri>[];

  @override
  Future<void> open(Uri url) async {
    openedUrls.add(url);
  }
}

class _FailingBrowserOpener implements LaunchBrowserOpener {
  const _FailingBrowserOpener();

  @override
  Future<void> open(Uri url) async {
    throw const LaunchBrowserOpenException('browser_open_failed');
  }
}

class _FakeFlutterDevices {
  _FakeFlutterDevices(this.devices);

  final List<Map<String, Object?>> devices;
  final List<List<String>> calls = <List<String>>[];

  Future<ProcessResult> listDevices(
    String executable,
    List<String> arguments,
  ) async {
    calls.add(arguments);
    return ProcessResult(1, 0, jsonEncode(devices), '');
  }
}
