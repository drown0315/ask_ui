import 'package:ask_ui_bridge/sessions/bridge_session_creator.dart';
import 'package:ask_ui_bridge/sessions/flutter_device_checker.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('BridgeSessionCreator', () {
    late SessionStore sessionStore;
    late RecordingFlutterDeviceChecker deviceChecker;
    late List<String> logs;

    setUp(() {
      sessionStore = SessionStore();
      deviceChecker = RecordingFlutterDeviceChecker(
        devices: {
          '19271FDF6007TY': const FlutterDeviceInfo(
            id: '19271FDF6007TY',
            displayName: 'Pixel 6',
          ),
          'unavailable-device': const FlutterDeviceInfo(
            id: 'unavailable-device',
            displayName: 'Offline Phone',
          ),
          'device-1': const FlutterDeviceInfo(
            id: 'device-1',
            displayName: 'Device 1',
          ),
          'device-2': const FlutterDeviceInfo(
            id: 'device-2',
            displayName: 'Device 2',
          ),
        },
        unavailableDeviceIds: {'unavailable-device'},
      );
      logs = <String>[];
    });

    BridgeSessionCreator creator({
      bool Function(String projectRoot)? projectRootExists,
    }) {
      return BridgeSessionCreator(
        sessionStore: sessionStore,
        flutterDeviceChecker: deviceChecker,
        projectRootExists: projectRootExists ?? (_) => true,
        log: logs.add,
      );
    }

    test('creates a Bridge Session with Target Device details', () async {
      final BridgeSessionCreationResult result = await creator().create({
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
        'projectRoot': '/Users/example/app',
        'deviceId': '19271FDF6007TY',
        'clientId': 'browser-1',
      });

      expect(result, isA<BridgeSessionCreationSuccess>());
      final BridgeSessionCreationSuccess success =
          result as BridgeSessionCreationSuccess;
      expect(success.session.id, isNotEmpty);
      expect(success.session.deviceId, '19271FDF6007TY');
      expect(success.session.deviceDisplayName, 'Pixel 6');
      expect(success.readOnly, isFalse);
    });

    test('rejects missing or blank required parameters', () async {
      final BridgeSessionCreationResult missing = await creator().create({
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
      });
      final BridgeSessionCreationResult blank = await creator().create({
        'vmServiceUri': ' ',
        'projectRoot': '/Users/example/app',
        'deviceId': '19271FDF6007TY',
      });

      expect(
        (missing as BridgeSessionCreationFailure).error,
        'missing_session_parameters',
      );
      expect(
        (blank as BridgeSessionCreationFailure).error,
        'missing_session_parameters',
      );
    });

    test('rejects invalid project roots before checking Target Device',
        () async {
      final BridgeSessionCreationResult result = await creator(
        projectRootExists: (_) => false,
      ).create({
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
        'projectRoot': ' /Users/example/missing ',
        'deviceId': '19271FDF6007TY',
      });

      expect(result, isA<BridgeSessionCreationFailure>());
      final BridgeSessionCreationFailure failure =
          result as BridgeSessionCreationFailure;
      expect(failure.error, 'invalid_project_root');
      expect(failure.projectRoot, '/Users/example/missing');
      expect(deviceChecker.checkedDeviceIds, isEmpty);
    });

    test('rejects Target Device checker failures without leaking internals',
        () async {
      deviceChecker.failure = StateError('flutter devices exploded');

      final BridgeSessionCreationResult result = await creator().create({
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
        'projectRoot': '/Users/example/app',
        'deviceId': '19271FDF6007TY',
      });

      expect(result, isA<BridgeSessionCreationFailure>());
      final BridgeSessionCreationFailure failure =
          result as BridgeSessionCreationFailure;
      expect(failure.error, 'target_device_check_failed');
      expect(failure.message, 'Ask UI could not check Flutter target devices.');
      expect(failure.message, isNot(contains('flutter devices')));
      expect(failure.message, isNot(contains('exploded')));
      expect(logs, contains(contains('flutter devices --machine')));
      expect(logs, contains(contains('flutter devices exploded')));
    });

    test('rejects missing and unavailable Target Devices', () async {
      final BridgeSessionCreationResult missing = await creator().create({
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
        'projectRoot': '/Users/example/app',
        'deviceId': 'missing-device',
      });
      final BridgeSessionCreationResult unavailable = await creator().create({
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
        'projectRoot': '/Users/example/app',
        'deviceId': 'unavailable-device',
      });

      expect(
        (missing as BridgeSessionCreationFailure).error,
        'target_device_not_found',
      );
      expect(
        (unavailable as BridgeSessionCreationFailure).error,
        'target_device_unavailable',
      );
    });

    test('rejects device mismatch for an existing Flutter app session',
        () async {
      await creator().create({
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
        'projectRoot': '/Users/example/app',
        'deviceId': 'device-1',
      });

      final BridgeSessionCreationResult result = await creator().create({
        'vmServiceUri': 'ws://127.0.0.1:12345/ws',
        'projectRoot': '/Users/example/app',
        'deviceId': 'device-2',
      });

      expect(result, isA<BridgeSessionCreationFailure>());
      final BridgeSessionCreationFailure failure =
          result as BridgeSessionCreationFailure;
      expect(failure.error, 'device_mismatch_for_session');
      expect(failure.expectedDeviceId, 'device-1');
      expect(failure.requestedDeviceId, 'device-2');
    });
  });
}

class RecordingFlutterDeviceChecker implements FlutterDeviceChecker {
  RecordingFlutterDeviceChecker({
    required this.devices,
    this.unavailableDeviceIds = const <String>{},
  });

  final Map<String, FlutterDeviceInfo> devices;
  final Set<String> unavailableDeviceIds;
  final List<String> checkedDeviceIds = <String>[];
  Object? failure;

  @override
  Future<FlutterDeviceCheckResult> checkDeviceId(String deviceId) async {
    checkedDeviceIds.add(deviceId);

    final Object? failure = this.failure;
    if (failure != null) {
      throw failure;
    }

    final FlutterDeviceInfo? device = devices[deviceId];
    if (device == null) {
      return const FlutterDeviceCheckResult(
        availability: FlutterDeviceAvailability.notFound,
      );
    }

    if (unavailableDeviceIds.contains(deviceId)) {
      return FlutterDeviceCheckResult(
        availability: FlutterDeviceAvailability.unavailable,
        device: device,
      );
    }

    return FlutterDeviceCheckResult(
      availability: FlutterDeviceAvailability.available,
      device: device,
    );
  }
}
