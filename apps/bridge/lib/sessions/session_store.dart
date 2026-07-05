/// One Ask UI workbench session for a Flutter app target.
///
/// It records:
/// - the session id returned to the web page
/// - the Flutter VM Service URI used to identify the running app
/// - the Flutter project root used to identify the local source workspace
/// - the Android device id bound to the running app
///
/// Example:
/// A page opened with `ws://127.0.0.1:12345/ws` and `/Users/example/app`
/// on device `19271FDF6007TY` receives one `BridgeSession`. Another tab with
/// the same values receives the same session because Ask UI treats that target
/// as a singleton session.
class BridgeSession {
  const BridgeSession({
    required this.id,
    required this.vmServiceUri,
    required this.projectRoot,
    required this.deviceId,
  });

  final String id;
  final String vmServiceUri;
  final String projectRoot;
  final String deviceId;
}

class InvalidSessionRequest implements Exception {
  const InvalidSessionRequest(this.message);

  final String message;

  @override
  String toString() => 'InvalidSessionRequest: $message';
}

class DeviceMismatchForSession implements Exception {
  const DeviceMismatchForSession({
    required this.expectedDeviceId,
    required this.requestedDeviceId,
  });

  final String expectedDeviceId;
  final String requestedDeviceId;

  @override
  String toString() => 'DeviceMismatchForSession: expected $expectedDeviceId, '
      'requested $requestedDeviceId';
}

class SessionStore {
  final Map<String, BridgeSession> _sessions = {};
  final Map<String, String> _sessionIdsByTarget = {};
  int _nextId = 1;

  int get sessionCount => _sessions.length;

  /// Return the singleton session for one Flutter app target.
  ///
  /// This method:
  /// 1. trims `vmServiceUri`, `projectRoot`, and `deviceId`
  /// 2. rejects blank values because all fields are required to identify the
  ///    workbench session
  /// 3. returns an existing session when the same target was already opened
  /// 4. rejects a different `deviceId` for an existing Flutter app session
  /// 5. creates a new session only for a target that has not been seen before
  ///
  /// Args:
  /// - `vmServiceUri`: VM Service WebSocket URI for the running Flutter app.
  ///   Blank values are rejected.
  /// - `projectRoot`: Local Flutter project root for the same app. Blank
  ///   values are rejected.
  /// - `deviceId`: Stable Android device serial for the same running app.
  ///   Blank values are rejected.
  ///
  /// Returns:
  /// The existing or newly-created `BridgeSession` for the target. Repeated
  /// calls with the same trimmed `vmServiceUri`, `projectRoot`, and `deviceId`
  /// return the same object.
  ///
  /// Example:
  /// Calling this twice with `ws://127.0.0.1:12345/ws` and
  /// `/Users/example/app` returns `session-1` both times, even if the duplicate
  /// call comes from React StrictMode, a browser refresh, or another tab.
  BridgeSession createSession({
    required String vmServiceUri,
    required String projectRoot,
    required String deviceId,
  }) {
    final trimmedVmServiceUri = vmServiceUri.trim();
    final trimmedProjectRoot = projectRoot.trim();
    final trimmedDeviceId = deviceId.trim();

    if (trimmedVmServiceUri.isEmpty ||
        trimmedProjectRoot.isEmpty ||
        trimmedDeviceId.isEmpty) {
      throw const InvalidSessionRequest(
        'vmServiceUri, projectRoot, and deviceId are required',
      );
    }

    final targetKey = _targetKey(
      vmServiceUri: trimmedVmServiceUri,
      projectRoot: trimmedProjectRoot,
    );
    final existingSessionId = _sessionIdsByTarget[targetKey];
    if (existingSessionId != null) {
      final existingSession = _sessions[existingSessionId];
      if (existingSession != null) {
        if (existingSession.deviceId != trimmedDeviceId) {
          throw DeviceMismatchForSession(
            expectedDeviceId: existingSession.deviceId,
            requestedDeviceId: trimmedDeviceId,
          );
        }
        return existingSession;
      }
    }

    final session = BridgeSession(
      id: 'session-${_nextId++}',
      vmServiceUri: trimmedVmServiceUri,
      projectRoot: trimmedProjectRoot,
      deviceId: trimmedDeviceId,
    );
    _sessions[session.id] = session;
    _sessionIdsByTarget[targetKey] = session.id;
    return session;
  }

  BridgeSession? find(String id) => _sessions[id];

  /// Build the lookup key for one singleton Flutter app target.
  ///
  /// Args:
  /// - `vmServiceUri`: Trimmed VM Service URI.
  /// - `projectRoot`: Trimmed local Flutter project root.
  ///
  /// Returns:
  /// A string key that is unique for the ordered pair of VM Service URI and
  /// project root.
  ///
  /// Example:
  /// `ws://127.0.0.1:12345/ws` plus `/Users/example/app` maps to a different
  /// key than the same VM Service URI plus `/Users/example/other_app`.
  String _targetKey({
    required String vmServiceUri,
    required String projectRoot,
  }) {
    return '$vmServiceUri\n$projectRoot';
  }
}
