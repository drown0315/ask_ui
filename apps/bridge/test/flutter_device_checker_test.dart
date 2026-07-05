import 'dart:io';

import 'package:ask_ui_bridge/sessions/flutter_device_checker.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterDevicesCommandChecker', () {
    test('finds exact Android device ids from flutter devices machine output',
        () async {
      final recordedArguments = <List<String>>[];
      final checker = FlutterDevicesCommandChecker(
        runProcess: (executable, arguments) async {
          recordedArguments.add(arguments);
          return ProcessResult(
            1,
            0,
            '''
[
  {
    "name": "Pixel 6",
    "id": "19271FDF6007TY",
    "targetPlatform": "android-arm64"
  },
  {
    "name": "macOS",
    "id": "macos",
    "targetPlatform": "darwin-arm64"
  }
]
''',
            '',
          );
        },
      );

      expect(
        await checker.checkDeviceId('19271FDF6007TY'),
        FlutterDeviceAvailability.available,
      );
      expect(recordedArguments, [
        ['devices', '--machine'],
      ]);
    });

    test('does not match device ids by substring', () async {
      final checker = FlutterDevicesCommandChecker(
        runProcess: (executable, arguments) async => ProcessResult(
          1,
          0,
          '[{"id":"device-10","targetPlatform":"android-arm64"}]',
          '',
        ),
      );

      expect(
        await checker.checkDeviceId('device-1'),
        FlutterDeviceAvailability.notFound,
      );
    });

    test('does not accept non-Android Flutter devices', () async {
      final checker = FlutterDevicesCommandChecker(
        runProcess: (executable, arguments) async => ProcessResult(
          1,
          0,
          '''
[
  {"id": "macos", "targetPlatform": "darwin-arm64"},
  {"id": "chrome", "targetPlatform": "web-javascript"}
]
''',
          '',
        ),
      );

      expect(
        await checker.checkDeviceId('macos'),
        FlutterDeviceAvailability.notFound,
      );
      expect(
        await checker.checkDeviceId('chrome'),
        FlutterDeviceAvailability.notFound,
      );
    });

    test('matches Android targetPlatform case-insensitively', () async {
      final checker = FlutterDevicesCommandChecker(
        runProcess: (executable, arguments) async => ProcessResult(
          1,
          0,
          '''
[
  {"id": "device-1", "targetPlatform": "Android-arm64"}
]
''',
          '',
        ),
      );

      expect(
        await checker.checkDeviceId('device-1'),
        FlutterDeviceAvailability.available,
      );
    });

    test('treats missing isSupported as available', () async {
      final checker = FlutterDevicesCommandChecker(
        runProcess: (executable, arguments) async => ProcessResult(
          1,
          0,
          '''
[
  {"id": "device-1", "targetPlatform": "android-arm64"}
]
''',
          '',
        ),
      );

      expect(
        await checker.checkDeviceId('device-1'),
        FlutterDeviceAvailability.available,
      );
    });

    test('marks unsupported Android devices unavailable', () async {
      final checker = FlutterDevicesCommandChecker(
        runProcess: (executable, arguments) async => ProcessResult(
          1,
          0,
          '''
[
  {
    "id": "offline-device",
    "targetPlatform": "android-arm64",
    "isSupported": false
  }
]
''',
          '',
        ),
      );

      expect(
        await checker.checkDeviceId('offline-device'),
        FlutterDeviceAvailability.unavailable,
      );
    });

    test('throws when flutter devices exits unsuccessfully', () async {
      final checker = FlutterDevicesCommandChecker(
        runProcess: (executable, arguments) async => ProcessResult(
          1,
          1,
          '',
          'Flutter failed to list devices',
        ),
      );

      await expectLater(
        checker.checkDeviceId('device-1'),
        throwsA(isA<FlutterDeviceCheckFailed>()),
      );
    });

    test('throws when flutter devices returns malformed JSON', () async {
      final checker = FlutterDevicesCommandChecker(
        runProcess: (executable, arguments) async => ProcessResult(
          1,
          0,
          'not json',
          '',
        ),
      );

      await expectLater(
        checker.checkDeviceId('device-1'),
        throwsA(isA<FlutterDeviceCheckFailed>()),
      );
    });

    test('throws when flutter devices returns an unexpected shape', () async {
      final checker = FlutterDevicesCommandChecker(
        runProcess: (executable, arguments) async => ProcessResult(
          1,
          0,
          '{"devices":[]}',
          '',
        ),
      );

      await expectLater(
        checker.checkDeviceId('device-1'),
        throwsA(isA<FlutterDeviceCheckFailed>()),
      );
    });
  });
}
