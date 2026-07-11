import 'dart:async';
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
          'webDev': false,
        },
        'bridgeUrl': 'http://127.0.0.1:8787',
        'sessionId': 'session-1',
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
        'projectRoot': '/workspace/app',
        'flavor': 'staging',
        'target': 'lib/main_staging.dart',
        'agentCommand':
            'ask_ui_bridge agent poll --base-url http://127.0.0.1:8787 --session-id session-1',
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
          'webDev': false,
        },
        'bridgeUrl': 'http://127.0.0.1:9876',
        'sessionId': 'session-7',
        'vmServiceUri': 'ws://127.0.0.1:44444/ws',
        'projectRoot': '/workspace/app',
        'flavor': 'dev',
        'target': 'lib/main_dev.dart',
        'agentCommand':
            'ask_ui_bridge agent poll --base-url http://127.0.0.1:9876 --session-id session-7',
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
        '--machine',
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
          requirePackagedWeb: true,
        ),
      ]);
    });

    test('web dev mode opens Vite workbench with session attach parameters',
        () async {
      final _FakeFlutterDevices devices = _FakeFlutterDevices([
        {
          'id': 'device-1',
          'name': 'Pixel 6',
          'targetPlatform': 'android-arm64',
        },
      ]);
      final _RecordingBrowserOpener browserOpener = _RecordingBrowserOpener();
      final _RecordingWebDevServer webDevServer = _RecordingWebDevServer(
        devServerUrl: Uri.parse('http://127.0.0.1:5174'),
      );
      final _RecordingBridgeLauncher bridgeLauncher = _RecordingBridgeLauncher(
        bridgeUrl: Uri.parse('http://127.0.0.1:9876'),
        sessionId: 'session-7',
      );

      final LaunchCommandResult result = await runLaunchCommand(
        const [
          'launch',
          '--device',
          'device-1',
          '--project-root',
          '/workspace/app',
          '--web-dev',
        ],
        listDevices: devices.listDevices,
        appLauncher: _RecordingAppLauncher(
          vmServiceUri: 'ws://127.0.0.1:44444/ws',
        ),
        bridgeLauncher: bridgeLauncher,
        browserOpener: browserOpener,
        webDevServer: webDevServer,
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
          'flavor': null,
          'target': null,
          'dartDefines': <String>[],
          'projectRoot': '/workspace/app',
          'open': true,
          'webDev': true,
        },
        'bridgeUrl': 'http://127.0.0.1:9876',
        'sessionId': 'session-7',
        'vmServiceUri': 'ws://127.0.0.1:44444/ws',
        'projectRoot': '/workspace/app',
        'flavor': null,
        'target': null,
        'agentCommand':
            'ask_ui_bridge agent poll --base-url http://127.0.0.1:9876 --session-id session-7',
        'workbenchUrl':
            'http://127.0.0.1:5174/?bridgeUrl=http%3A%2F%2F127.0.0.1%3A9876&sessionId=session-7&deviceId=device-1&projectRoot=%2Fworkspace%2Fapp',
        'browserOpened': true,
        'nextStep': 'Run the returned agent poll command.',
      });
      expect(webDevServer.startRequests, ['/workspace/app']);
      expect(bridgeLauncher.requests.single.requirePackagedWeb, false);
      expect(browserOpener.openedUrls, [
        Uri.parse(
          'http://127.0.0.1:5174/?bridgeUrl=http%3A%2F%2F127.0.0.1%3A9876&sessionId=session-7&deviceId=device-1&projectRoot=%2Fworkspace%2Fapp',
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

    test('reports missing packaged Web when default launch has no workbench',
        () async {
      final Directory packagedWebRoot =
          await Directory.systemTemp.createTemp('ask-ui-empty-web-');
      addTearDown(() async {
        if (await packagedWebRoot.exists()) {
          await packagedWebRoot.delete(recursive: true);
        }
      });
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
          vmServiceUri: 'ws://127.0.0.1:44444/ws',
        ),
        bridgeLauncher: LocalBridgeLauncher(packagedWebRoot: packagedWebRoot),
        browserOpener: _RecordingBrowserOpener(),
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr), {
        'status': 'error',
        'error': 'packaged_web_not_found',
      });
    });

    test('reports Web dev startup failures before opening the browser',
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
        const ['launch', '--device', 'device-1', '--web-dev'],
        listDevices: devices.listDevices,
        appLauncher: _RecordingAppLauncher(
          vmServiceUri: 'ws://127.0.0.1:44444/ws',
        ),
        bridgeLauncher: _RecordingBridgeLauncher(
          bridgeUrl: Uri.parse('http://127.0.0.1:9876'),
          sessionId: 'session-7',
        ),
        browserOpener: browserOpener,
        webDevServer: const _FailingWebDevServer(
          LaunchWebDevException('web_dev_start_failed'),
        ),
      );

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(jsonDecode(result.stderr), {
        'status': 'error',
        'error': 'web_dev_start_failed',
      });
      expect(browserOpener.openedUrls, isEmpty);
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
        parseFlutterVmServiceUriFromOutput(
          'See https://flutter.dev/to/flutter-gradle-plugin-apply '
          'for migration details.',
        ),
        isNull,
      );
      expect(
        parseFlutterVmServiceUriFromOutput(
          'See https://flutter.dev/to/flutter-gradle-plugin-apply '
          'for migration details.\n'
          'A Dart VM Service is available at: '
          'http://127.0.0.1:51234/abc_def=/',
        ),
        'ws://127.0.0.1:51234/abc_def=/ws',
      );
      expect(
        parseFlutterVmServiceUriFromOutput('Build failed before service.'),
        isNull,
      );
    });

    test('parses Flutter machine output into WebSocket URIs', () {
      expect(
        parseFlutterVmServiceUriFromMachineOutput(
          jsonEncode([
            {
              'event': 'app.debugPort',
              'params': {
                'wsUri': 'ws://127.0.0.1:51234/abc_def=/ws',
              },
            },
          ]),
        ),
        'ws://127.0.0.1:51234/abc_def=/ws',
      );
      expect(
        parseFlutterVmServiceUriFromMachineOutput(
          jsonEncode([
            {
              'id': 0,
              'result': {
                'started': true,
                'vmServiceUri': 'http://127.0.0.1:51234/abc_def=/',
              },
            },
          ]),
        ),
        'ws://127.0.0.1:51234/abc_def=/ws',
      );
      expect(
        parseFlutterVmServiceUriFromMachineOutput(
          jsonEncode([
            {
              'event': 'daemon.logMessage',
              'params': {
                'message':
                    'See https://flutter.dev/to/flutter-gradle-plugin-apply',
              },
            },
          ]),
        ),
        isNull,
      );
    });

    test('parses Vite dev server output into localhost URLs', () {
      expect(
        parseViteDevServerUrlFromOutput('  Local:   http://127.0.0.1:5174/'),
        Uri.parse('http://127.0.0.1:5174/'),
      );
      expect(
        parseViteDevServerUrlFromOutput(
          'Port 5173 is in use, trying another one...\n'
          '  Local:   http://localhost:5175/',
        ),
        Uri.parse('http://localhost:5175/'),
      );
      expect(
        parseViteDevServerUrlFromOutput('ready in 312 ms'),
        isNull,
      );
    });

    test('starts Vite from the Web app package and returns its printed URL',
        () async {
      final _RecordingProcessStarter processStarter = _RecordingProcessStarter(
        stdoutChunks: [
          utf8.encode('Port 5173 is in use, trying another one...\n'),
          utf8.encode('  Local:   http://127.0.0.1:5174/\n'),
        ],
      );
      final NpmViteWebDevServer webDevServer = NpmViteWebDevServer(
        webAppRoot: Directory('/workspace/ask_ui/apps/web'),
        startProcess: processStarter.start,
      );

      final Uri devServerUrl = await webDevServer.start(
        projectRoot: '/workspace/flutter_app',
      );

      expect(devServerUrl, Uri.parse('http://127.0.0.1:5174/'));
      expect(processStarter.requests, hasLength(1));
      expect(processStarter.requests.single.executable, 'npm');
      expect(processStarter.requests.single.arguments, [
        'run',
        'dev',
        '--',
        '--host',
        '127.0.0.1',
      ]);
      expect(
        processStarter.requests.single.workingDirectory,
        '/workspace/ask_ui/apps/web',
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
                'ask_ui_bridge launch --device emulator-5554 --flavor dev --target lib/main_dev.dart --dart-define A=B --project-root /workspace/app --no-open',
          },
          {
            'id': '19271FDF6007TY',
            'name': 'Pixel 6',
            'targetPlatform': 'android-arm64',
            'suggestedCommand':
                'ask_ui_bridge launch --device 19271FDF6007TY --flavor dev --target lib/main_dev.dart --dart-define A=B --project-root /workspace/app --no-open',
          },
        ],
        'launchIntent': {
          'device': null,
          'flavor': 'dev',
          'target': 'lib/main_dev.dart',
          'dartDefines': ['A=B'],
          'projectRoot': '/workspace/app',
          'open': false,
          'webDev': false,
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
  final List<
      ({
        String vmServiceUri,
        String projectRoot,
        String deviceId,
        bool requirePackagedWeb,
      })> requests = <({
    String vmServiceUri,
    String projectRoot,
    String deviceId,
    bool requirePackagedWeb,
  })>[];

  @override
  Future<LaunchBridgeSession> createSession({
    required String vmServiceUri,
    required String projectRoot,
    required String deviceId,
    required bool requirePackagedWeb,
  }) async {
    requests.add((
      vmServiceUri: vmServiceUri,
      projectRoot: projectRoot,
      deviceId: deviceId,
      requirePackagedWeb: requirePackagedWeb,
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
    required bool requirePackagedWeb,
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

class _RecordingWebDevServer implements LaunchWebDevServer {
  _RecordingWebDevServer({required this.devServerUrl});

  final Uri devServerUrl;
  final List<String> startRequests = <String>[];

  @override
  Future<Uri> start({required String projectRoot}) async {
    startRequests.add(projectRoot);
    return devServerUrl;
  }
}

class _FailingWebDevServer implements LaunchWebDevServer {
  const _FailingWebDevServer(this.exception);

  final LaunchWebDevException exception;

  @override
  Future<Uri> start({required String projectRoot}) async {
    throw exception;
  }
}

class _RecordingProcessStarter {
  _RecordingProcessStarter({required this.stdoutChunks});

  final List<List<int>> stdoutChunks;
  final List<
      ({
        String executable,
        List<String> arguments,
        String? workingDirectory,
      })> requests = <({
    String executable,
    List<String> arguments,
    String? workingDirectory,
  })>[];

  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    requests.add((
      executable: executable,
      arguments: List<String>.from(arguments),
      workingDirectory: workingDirectory,
    ));
    return _FakeProcess(stdoutChunks: stdoutChunks);
  }
}

class _FakeProcess implements Process {
  _FakeProcess({required List<List<int>> stdoutChunks})
      : stdout = Stream<List<int>>.fromIterable(stdoutChunks),
        stderr = const Stream<List<int>>.empty(),
        stdin = _FakeIOSink(),
        exitCode = Completer<int>().future;

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  @override
  final IOSink stdin;

  @override
  final Future<int> exitCode;

  @override
  int get pid => 1;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return true;
  }
}

class _FakeIOSink implements IOSink {
  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}
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
