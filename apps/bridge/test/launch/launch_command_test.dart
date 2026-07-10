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
        'flutterRunArguments': [
          'run',
          '--device-id',
          'device-1',
          '--flavor',
          'staging',
          '--target',
          'lib/main_staging.dart',
          '--dart-define',
          'API_HOST=local',
          '--dart-define',
          'FEATURE_X=true',
        ],
        'nextStep': 'Launch Flutter app for selected device device-1.',
      });
      expect(devices.calls, [
        ['devices', '--machine'],
      ]);
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
      );
      final LaunchCommandResult ambiguous = await runLaunchCommand(
        const ['launch', '--device', 'Pixel'],
        listDevices: devices.listDevices,
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
