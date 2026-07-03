/// One Ask UI workbench session for a Flutter app target.
///
/// It records:
/// - the session id returned to the web page
/// - the Flutter VM Service URI used to identify the running app
/// - the Flutter project root used to identify the local source workspace
///
/// Example:
/// A page opened with `ws://127.0.0.1:12345/ws` and `/Users/example/app`
/// receives one `BridgeSession`. Another tab with the same two values receives
/// the same session because Ask UI treats that target as a singleton session.
class BridgeSession {
  const BridgeSession({
    required this.id,
    required this.vmServiceUri,
    required this.projectRoot,
  });

  final String id;
  final String vmServiceUri;
  final String projectRoot;
}

class InvalidSessionRequest implements Exception {
  const InvalidSessionRequest(this.message);

  final String message;

  @override
  String toString() => 'InvalidSessionRequest: $message';
}

class SessionStore {
  final Map<String, BridgeSession> _sessions = {};
  final Map<String, String> _sessionIdsByTarget = {};
  int _nextId = 1;

  int get sessionCount => _sessions.length;

  /// Return the singleton session for one Flutter app target.
  ///
  /// This method:
  /// 1. trims `vmServiceUri` and `projectRoot`
  /// 2. rejects blank values because both fields are required to identify the
  ///    target Flutter app
  /// 3. returns an existing session when the same target was already opened
  /// 4. creates a new session only for a target that has not been seen before
  ///
  /// Args:
  /// - `vmServiceUri`: VM Service WebSocket URI for the running Flutter app.
  ///   Blank values are rejected.
  /// - `projectRoot`: Local Flutter project root for the same app. Blank
  ///   values are rejected.
  ///
  /// Returns:
  /// The existing or newly-created `BridgeSession` for the target. Repeated
  /// calls with the same trimmed `vmServiceUri` and `projectRoot` return the
  /// same object.
  ///
  /// Example:
  /// Calling this twice with `ws://127.0.0.1:12345/ws` and
  /// `/Users/example/app` returns `session-1` both times, even if the duplicate
  /// call comes from React StrictMode, a browser refresh, or another tab.
  BridgeSession createSession({
    required String vmServiceUri,
    required String projectRoot,
  }) {
    final trimmedVmServiceUri = vmServiceUri.trim();
    final trimmedProjectRoot = projectRoot.trim();

    if (trimmedVmServiceUri.isEmpty || trimmedProjectRoot.isEmpty) {
      throw const InvalidSessionRequest(
        'vmServiceUri and projectRoot are required',
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
        return existingSession;
      }
    }

    final session = BridgeSession(
      id: 'session-${_nextId++}',
      vmServiceUri: trimmedVmServiceUri,
      projectRoot: trimmedProjectRoot,
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
