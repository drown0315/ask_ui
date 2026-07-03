import '../sessions/session_store.dart';
import '../inspector/flutter_inspector_client.dart';
import '../logging/bridge_logger.dart';

/// Result returned after the bridge asks Flutter to hot reload one session.
///
/// It contains:
/// - a user-facing message for the web action state
/// - the normalized VM Service reload report when available
///
/// Example:
/// A successful hot reload returns `status=ok`, a completion message, and
/// `reloadReport.success=true`.
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

/// Result returned after the bridge asks Flutter to hot restart one session.
///
/// It contains a user-facing message for the web action state.
///
/// Example:
/// A future runner-backed implementation can return `status=ok` and
/// `message=Hot restart completed.`
class HotRestartResult {
  const HotRestartResult({
    required this.message,
  });

  final String message;

  Map<String, Object?> toJson() {
    return {
      'status': 'ok',
      'message': message,
    };
  }
}

/// Error thrown when one bridge session cannot perform hot restart.
///
/// The bridge server maps this exception to HTTP 501 with the stable
/// `hot_restart_not_supported_for_session` error code consumed by the web UI.
class HotRestartUnsupportedException implements Exception {
  const HotRestartUnsupportedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs Flutter app actions for one Ask UI bridge session.
///
/// The web UI calls bridge HTTP endpoints. The bridge uses this controller to
/// perform runtime actions against the Flutter app identified by the session.
abstract class FlutterAppController {
  Future<HotReloadResult> hotReload(BridgeSession session);

  Future<HotRestartResult> hotRestart(BridgeSession session);
}

/// Flutter app action controller backed by Dart VM Service.
///
/// It performs:
/// 1. VM Service connection using the session URI
/// 2. main isolate lookup
/// 3. Flutter tool registered hot action lookup
/// 4. registered hot action call, or VM Service fallback when unavailable
///
/// Example:
/// Calling `hotReload` for `session-1` connects to that session's VM Service
/// URI, prefers Flutter tool `reloadSources`, and returns a normalized
/// `HotReloadResult`.
class VmServiceFlutterAppController implements FlutterAppController {
  VmServiceFlutterAppController({
    required FlutterInspectorVmServiceFactory vmServiceFactory,
    BridgeLogger? logger,
  })  : _vmServiceFactory = vmServiceFactory,
        _logger = logger ?? BridgeLogger(write: print);

  final FlutterInspectorVmServiceFactory _vmServiceFactory;
  final BridgeLogger _logger;

  @override
  Future<HotReloadResult> hotReload(BridgeSession session) async {
    _logger.info('hot_reload session=${session.id} connect_vm_service');
    final vmService = await _vmServiceFactory.connect(session.vmServiceUri);

    try {
      final isolateId = await vmService.findMainIsolateId();
      _logger.info('hot_reload session=${session.id} isolate=$isolateId');

      _logger.info(
        'hot_reload session=${session.id} '
        'wait_registered_service service=reloadSources',
      );
      final registeredMethod = await vmService.waitForRegisteredService(
        serviceName: 'reloadSources',
        timeout: const Duration(seconds: 1),
      );

      final Map<String, Object?> reloadReport;
      if (registeredMethod != null) {
        _logger.info(
          'hot_reload session=${session.id} '
          'use_registered_service method=$registeredMethod',
        );
        final response = await vmService.callServiceExtension(
          registeredMethod,
          isolateId: isolateId,
          args: {
            'force': false,
            'pause': false,
          },
        );
        reloadReport = _normalizeHotReloadReport(response);
        _logger.info(_formatHotReloadReportLog(session.id, reloadReport));
      } else {
        _logger.info(
          'hot_reload session=${session.id} fallback_vm_reloadSources',
        );
        reloadReport = await vmService.reloadSources(isolateId);
        _logger.info(_formatHotReloadReportLog(session.id, reloadReport));
        await vmService.callServiceExtension(
          'ext.flutter.reassemble',
          isolateId: isolateId,
        );
        _logger.info('hot_reload session=${session.id} reassemble_completed');
      }

      return HotReloadResult(
        message: 'Hot reload completed.',
        reloadReport: reloadReport,
      );
    } finally {
      await vmService.dispose();
    }
  }

  @override
  Future<HotRestartResult> hotRestart(BridgeSession session) async {
    _logger.info('hot_restart session=${session.id} connect_vm_service');
    final vmService = await _vmServiceFactory.connect(session.vmServiceUri);

    try {
      _logger.info(
        'hot_restart session=${session.id} '
        'wait_registered_service service=hotRestart',
      );
      final registeredMethod = await vmService.waitForRegisteredService(
        serviceName: 'hotRestart',
        timeout: const Duration(milliseconds: 800),
      );
      final method = registeredMethod ?? 'hotRestart';
      if (registeredMethod != null) {
        _logger.info(
          'hot_restart session=${session.id} '
          'use_registered_service method=$registeredMethod',
        );
      } else {
        _logger.info(
          'hot_restart session=${session.id} fallback_callMethod hotRestart',
        );
      }
      await vmService.callMethod(
        method,
        args: {'pause': false},
      );
      _logger.info('hot_restart session=${session.id} completed');

      return const HotRestartResult(
        message: 'Hot restart completed.',
      );
    } on FlutterInspectorServiceUnavailableException {
      _logger.info('hot_restart session=${session.id} unsupported');
      throw const HotRestartUnsupportedException(
        'Hot restart is not available for this bridge session.',
      );
    } finally {
      await vmService.dispose();
    }
  }
}

/// Returns a stable reload report map from Flutter tool hot reload responses.
///
/// The Flutter tool registered service can answer with either `Success` or
/// `ReloadReport`. This helper preserves every raw response field, including
/// diagnostic fields such as `notices` and `details`, while ensuring callers
/// can always read a boolean-like `success` value for known response types.
///
/// Args:
/// - `response`: Raw JSON map returned by the registered hot reload service.
///
/// Returns:
/// The original response plus a default `success` value for `Success` and
/// `ReloadReport` records. Unknown response shapes are returned unchanged.
///
/// Example:
/// `{type: Success}` becomes `{type: Success, success: true}`.
Map<String, Object?> _normalizeHotReloadReport(
  Map<String, Object?> response,
) {
  final type = response['type'];
  final success = response['success'];

  if (type == 'Success') {
    return {
      ...response,
      'success': success ?? true,
    };
  }

  if (type == 'ReloadReport') {
    return {
      ...response,
      'success': success ?? false,
    };
  }

  return response;
}

/// Builds the log line for one hot reload report.
///
/// The line always includes the session id and success value. It also appends
/// `notices` and `details` when the VM Service response includes them because
/// those fields explain why a reload was rejected.
///
/// Args:
/// - `sessionId`: Bridge session that received the hot reload request.
/// - `reloadReport`: Normalized or raw reload report returned by Flutter.
///
/// Returns:
/// One log line without the `[ask_ui_bridge]` prefix; `BridgeLogger` adds the
/// prefix before writing it.
///
/// Example:
/// A failed report with `details=compile failed` returns a line containing
/// `reload_report success=false details=compile failed`.
String _formatHotReloadReportLog(
  String sessionId,
  Map<String, Object?> reloadReport,
) {
  final details = reloadReport['details'];
  final notices = reloadReport['notices'];
  final buffer = StringBuffer(
    'hot_reload session=$sessionId '
    'reload_report success=${reloadReport['success']}',
  );

  if (notices != null) {
    buffer.write(' notices=$notices');
  }
  if (details != null) {
    buffer.write(' details=$details');
  }

  return buffer.toString();
}
