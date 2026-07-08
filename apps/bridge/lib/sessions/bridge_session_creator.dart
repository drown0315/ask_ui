import 'flutter_device_checker.dart';
import 'session_store.dart';

/// Creates Bridge Sessions after validating the requested Target Device.
///
/// The HTTP server owns transport details such as JSON decoding and status
/// codes. This object owns the Bridge Session startup contract: required
/// fields, local project root validation, Target Device availability, and
/// SessionStore creation.
class BridgeSessionCreator {
  const BridgeSessionCreator({
    required SessionStore sessionStore,
    required FlutterDeviceChecker flutterDeviceChecker,
    required bool Function(String projectRoot) projectRootExists,
    required void Function(String message) log,
  })  : _sessionStore = sessionStore,
        _flutterDeviceChecker = flutterDeviceChecker,
        _projectRootExists = projectRootExists,
        _log = log;

  final SessionStore _sessionStore;
  final FlutterDeviceChecker _flutterDeviceChecker;
  final bool Function(String projectRoot) _projectRootExists;
  final void Function(String message) _log;

  Future<BridgeSessionCreationResult> create(
    Map<String, Object?> body,
  ) async {
    final Object? vmServiceUri = body['vmServiceUri'];
    final Object? projectRoot = body['projectRoot'];
    final Object? deviceId = body['deviceId'];
    final Object? clientId = body['clientId'];

    if (vmServiceUri is! String ||
        projectRoot is! String ||
        deviceId is! String) {
      _log('session create failed error=missing_session_parameters');
      return const BridgeSessionCreationFailure(
        error: 'missing_session_parameters',
      );
    }

    if (vmServiceUri.trim().isEmpty ||
        projectRoot.trim().isEmpty ||
        deviceId.trim().isEmpty) {
      _log('session create failed error=missing_session_parameters');
      return const BridgeSessionCreationFailure(
        error: 'missing_session_parameters',
      );
    }

    final String trimmedProjectRoot = projectRoot.trim();
    if (!_projectRootExists(trimmedProjectRoot)) {
      _log(
        'session create failed error=invalid_project_root '
        'projectRoot=$trimmedProjectRoot',
      );
      return BridgeSessionCreationFailure(
        error: 'invalid_project_root',
        message: 'Project root $trimmedProjectRoot does not exist.',
        projectRoot: trimmedProjectRoot,
      );
    }

    late final FlutterDeviceCheckResult targetDeviceCheck;
    try {
      targetDeviceCheck = await _flutterDeviceChecker.checkDeviceId(deviceId);
    } catch (error, stackTrace) {
      _log(
        'target_device_check_failed command="flutter devices --machine" '
        'deviceId=$deviceId error=$error\n'
        'Stack trace:\n$stackTrace',
      );
      return BridgeSessionCreationFailure(
        error: 'target_device_check_failed',
        message: 'Ask UI could not check Flutter target devices.',
        deviceId: deviceId,
      );
    }

    if (targetDeviceCheck.availability == FlutterDeviceAvailability.notFound) {
      _log(
        'session create failed error=target_device_not_found deviceId=$deviceId',
      );
      return BridgeSessionCreationFailure(
        error: 'target_device_not_found',
        message: 'Target Device $deviceId is not listed by Flutter.',
        deviceId: deviceId,
      );
    }

    if (targetDeviceCheck.availability ==
        FlutterDeviceAvailability.unavailable) {
      _log(
        'session create failed error=target_device_unavailable deviceId=$deviceId',
      );
      return BridgeSessionCreationFailure(
        error: 'target_device_unavailable',
        message: 'Target Device $deviceId is not available.',
        deviceId: deviceId,
      );
    }

    try {
      final BridgeSession session = _sessionStore.createSession(
        vmServiceUri: vmServiceUri,
        projectRoot: projectRoot,
        deviceId: deviceId,
        deviceDisplayName: targetDeviceCheck.device?.displayName ?? '',
        clientId: clientId is String ? clientId : null,
      );
      _log(
        'session create success session=${session.id} deviceId=${session.deviceId}',
      );
      return BridgeSessionCreationSuccess(
        session: session,
        readOnly:
            session.isReadOnlyClient(clientId is String ? clientId : null),
      );
    } on InvalidSessionRequest {
      _log('session create failed error=missing_session_parameters');
      return const BridgeSessionCreationFailure(
        error: 'missing_session_parameters',
      );
    } on DeviceMismatchForSession catch (error) {
      _log(
        'session create failed error=device_mismatch_for_session '
        'expectedDeviceId=${error.expectedDeviceId} '
        'requestedDeviceId=${error.requestedDeviceId}',
      );
      return BridgeSessionCreationFailure(
        error: 'device_mismatch_for_session',
        message: 'VM Service device does not match Target Device '
            '${error.requestedDeviceId}.',
        expectedDeviceId: error.expectedDeviceId,
        requestedDeviceId: error.requestedDeviceId,
      );
    }
  }
}

sealed class BridgeSessionCreationResult {
  const BridgeSessionCreationResult();
}

class BridgeSessionCreationSuccess extends BridgeSessionCreationResult {
  const BridgeSessionCreationSuccess({
    required this.session,
    required this.readOnly,
  });

  final BridgeSession session;
  final bool readOnly;
}

class BridgeSessionCreationFailure extends BridgeSessionCreationResult {
  const BridgeSessionCreationFailure({
    required this.error,
    this.message,
    this.deviceId,
    this.projectRoot,
    this.expectedDeviceId,
    this.requestedDeviceId,
  });

  final String error;
  final String? message;
  final String? deviceId;
  final String? projectRoot;
  final String? expectedDeviceId;
  final String? requestedDeviceId;
}
