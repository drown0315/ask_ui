import '../sessions/session_store.dart';
import '../inspector/flutter_inspector_client.dart';

/// Result returned after the bridge asks Flutter to hot reload one session.
///
/// It contains:
/// - a user-facing message for the web action state
/// - the normalized VM Service reload report when available
///
/// Example:
/// A successful `reloadSources` call returns `status=ok`, a completion message,
/// and `reloadReport.success=true`.
class HotReloadResult {
  const HotReloadResult({
    required this.message,
    this.reloadReport,
  });

  final String message;
  final Map<String, Object?>? reloadReport;

  Map<String, Object?> toJson() {
    return {
      'status': 'ok',
      'message': message,
      if (reloadReport != null) 'reloadReport': reloadReport,
    };
  }
}

/// Runs Flutter app actions for one Ask UI bridge session.
///
/// The web UI calls bridge HTTP endpoints. The bridge uses this controller to
/// perform runtime actions against the Flutter app identified by the session.
abstract class FlutterAppController {
  Future<HotReloadResult> hotReload(BridgeSession session);
}

/// Flutter app action controller backed by Dart VM Service.
///
/// It performs:
/// 1. VM Service connection using the session URI
/// 2. main isolate lookup
/// 3. `reloadSources` for that isolate group
///
/// Example:
/// Calling `hotReload` for `session-1` connects to that session's VM Service
/// URI, calls `reloadSources`, and returns a normalized `HotReloadResult`.
class VmServiceFlutterAppController implements FlutterAppController {
  VmServiceFlutterAppController({
    required FlutterInspectorVmServiceFactory vmServiceFactory,
  }) : _vmServiceFactory = vmServiceFactory;

  final FlutterInspectorVmServiceFactory _vmServiceFactory;

  @override
  Future<HotReloadResult> hotReload(BridgeSession session) async {
    final vmService = await _vmServiceFactory.connect(session.vmServiceUri);

    try {
      final isolateId = await vmService.findMainIsolateId();
      final reloadReport = await vmService.reloadSources(isolateId);

      return HotReloadResult(
        message: 'Hot reload completed.',
        reloadReport: reloadReport,
      );
    } finally {
      await vmService.dispose();
    }
  }
}
