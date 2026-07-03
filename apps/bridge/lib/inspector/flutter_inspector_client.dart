import 'dart:async';
import 'dart:convert';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../sessions/session_store.dart';
import '../widget_tree/widget_tree_snapshot.dart';

/// Client interface for reading Flutter Inspector data for one bridge session.
///
/// It receives the session that identifies:
/// - the running Flutter app VM Service URI
/// - the local Flutter project root used by Inspector summary filtering
///
/// Example:
/// A server route for `session-1` calls `fetchRootWidgetTree` and receives one
/// normalized `WidgetTreeNode` tree for the web Widget Context Panel.
abstract class FlutterInspectorClient {
  Future<WidgetTreeNode> fetchRootWidgetTree(BridgeSession session);
}

/// Flutter Inspector client backed by Dart VM Service extension calls.
///
/// It performs:
/// 1. VM Service connection using the session URI
/// 2. Inspector pub-root configuration using the session project root
/// 3. summary Widget Tree fetch and normalization
///
/// Example:
/// For `/Users/example/app`, the client calls
/// `ext.flutter.inspector.setPubRootDirectories` with `arg0` set to that path
/// before fetching `ext.flutter.inspector.getRootWidgetTree`.
class VmServiceFlutterInspectorClient implements FlutterInspectorClient {
  VmServiceFlutterInspectorClient({
    required FlutterInspectorVmServiceFactory vmServiceFactory,
  }) : _vmServiceFactory = vmServiceFactory;

  final FlutterInspectorVmServiceFactory _vmServiceFactory;

  @override
  Future<WidgetTreeNode> fetchRootWidgetTree(BridgeSession session) async {
    final vmService = await _vmServiceFactory.connect(session.vmServiceUri);

    try {
      final isolateId = await vmService.findMainIsolateId();

      await vmService.callServiceExtension(
        'ext.flutter.inspector.setPubRootDirectories',
        isolateId: isolateId,
        args: {'arg0': session.projectRoot},
      );

      final response = await vmService.callServiceExtension(
        'ext.flutter.inspector.getRootWidgetTree',
        isolateId: isolateId,
        args: {
          'groupName': 'ask_ui_widget_tree',
          'isSummaryTree': 'true',
          'withPreviews': 'true',
          'fullDetails': 'false',
        },
      );
      final result = _decodeInspectorResult(response);

      if (result is! Map<String, Object?>) {
        throw const FlutterInspectorException(
          'getRootWidgetTree did not return a diagnostics object',
        );
      }

      return WidgetTreeNode.fromFlutterDiagnostics(result);
    } finally {
      await vmService.dispose();
    }
  }
}

Object? _decodeInspectorResult(Map<String, Object?> response) {
  final result = response['result'] ?? response['object'] ?? response['value'];

  if (result is String) {
    return jsonDecode(result);
  }

  return result ?? response;
}

class FlutterInspectorException implements Exception {
  const FlutterInspectorException(this.message);

  final String message;

  @override
  String toString() => 'FlutterInspectorException: $message';
}

/// Error thrown when a VM Service method is not available for the app.
///
/// It usually means the Flutter tool did not register the hot action service
/// for this VM Service connection, and the bridge cannot use that path.
///
/// Example:
/// Calling fallback `hotRestart` against an app that has no registered restart
/// method throws this exception so the HTTP server can return a stable
/// unsupported response.
class FlutterInspectorServiceUnavailableException implements Exception {
  const FlutterInspectorServiceUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Factory that opens one VM Service connection for a Flutter app target.
///
/// Args:
/// - `vmServiceUri`: WebSocket URI printed by `flutter run --debug`.
///
/// Returns:
/// A small VM Service adapter that can call Flutter Inspector extensions.
abstract class FlutterInspectorVmServiceFactory {
  Future<FlutterInspectorVmService> connect(String vmServiceUri);
}

/// Narrow adapter over the VM Service API used by Flutter Inspector access.
///
/// It exposes only:
/// - service extension calls with string keys and JSON-compatible values
/// - Flutter tool registered service discovery and calls
/// - source reload for one isolate group
/// - disposal of the underlying connection
///
/// Example:
/// Tests provide a fake implementation to assert that Ask UI requests
/// `isSummaryTree=true` or waits for `reloadSources` registration without
/// connecting to a real Flutter app.
abstract class FlutterInspectorVmService {
  Future<String> findMainIsolateId();

  /// Waits for a Flutter tool service to be registered on the VM Service.
  ///
  /// Args:
  /// - `serviceName`: Service identifier announced by the Flutter tool, such
  ///   as `reloadSources` or `hotRestart`.
  /// - `timeout`: Maximum time to listen before returning `null`.
  ///
  /// Returns:
  /// The VM Service method name to call, or `null` when the tool does not
  /// announce the service before the timeout.
  ///
  /// Example:
  /// When Flutter tool announces `service=reloadSources` and
  /// `method=_flutter.reloadSources`, this returns `_flutter.reloadSources`.
  Future<String?> waitForRegisteredService({
    required String serviceName,
    required Duration timeout,
  });

  Future<Map<String, Object?>> callServiceExtension(
    String method, {
    required String isolateId,
    Map<String, Object?>? args,
  });

  Future<Map<String, Object?>> callMethod(
    String method, {
    Map<String, Object?>? args,
  });

  Future<Map<String, Object?>> reloadSources(String isolateId);

  Future<void> dispose();
}

/// Production VM Service factory using the `vm_service` package.
class VmServiceFactory implements FlutterInspectorVmServiceFactory {
  @override
  Future<FlutterInspectorVmService> connect(String vmServiceUri) async {
    final vmService = await vmServiceConnectUri(vmServiceUri);
    return VmServiceAdapter(vmService);
  }
}

/// Adapter from `package:vm_service` responses to plain JSON maps.
class VmServiceAdapter implements FlutterInspectorVmService {
  VmServiceAdapter(this._vmService);

  final VmService _vmService;

  @override
  Future<String> findMainIsolateId() async {
    final vm = await _vmService.getVM();
    final isolates = vm.isolates ?? const <IsolateRef>[];

    for (final isolate in isolates) {
      final isolateId = isolate.id;
      if (isolateId != null) {
        return isolateId;
      }
    }

    throw const FlutterInspectorException('No runnable Dart isolate found');
  }

  /// Waits for the Flutter tool to announce a service method.
  ///
  /// This method listens to the VM Service `Service` stream and returns the
  /// `method` field from the first `ServiceRegistered` event whose `service`
  /// matches the requested name. It always cancels the stream subscription
  /// before returning.
  ///
  /// Args:
  /// - `serviceName`: Flutter tool service name to match, such as
  ///   `reloadSources` or `hotRestart`.
  /// - `timeout`: How long to listen before treating the service as absent.
  ///
  /// Returns:
  /// The registered VM Service method name, or `null` when no matching service
  /// is announced before the timeout.
  ///
  /// Example:
  /// A `ServiceRegistered` event with `service=hotRestart` and
  /// `method=_flutter.hotRestart` returns `_flutter.hotRestart`.
  @override
  Future<String?> waitForRegisteredService({
    required String serviceName,
    required Duration timeout,
  }) async {
    final registeredMethod = Completer<String?>();
    late final StreamSubscription<Event> subscription;

    subscription = _vmService.onEvent(EventStreams.kService).listen((event) {
      final method = event.method;
      if (event.kind == EventKind.kServiceRegistered &&
          event.service == serviceName &&
          method != null &&
          !registeredMethod.isCompleted) {
        registeredMethod.complete(method);
      }
    });

    try {
      await _vmService.streamListen(EventStreams.kService);
      return await registeredMethod.future.timeout(
        timeout,
        onTimeout: () => null,
      );
    } finally {
      await subscription.cancel();
      try {
        await _vmService.streamCancel(EventStreams.kService);
      } catch (_) {
        // The VM Service stream may already be closed while the app reloads or
        // restarts. Discovery is best-effort, so cleanup errors are ignored.
      }
    }
  }

  @override
  Future<Map<String, Object?>> callServiceExtension(
    String method, {
    required String isolateId,
    Map<String, Object?>? args,
  }) async {
    final response = await _vmService.callServiceExtension(
      method,
      isolateId: isolateId,
      args: args?.cast<String, dynamic>(),
    );

    return response.json?.cast<String, Object?>() ?? <String, Object?>{};
  }

  @override
  Future<Map<String, Object?>> callMethod(
    String method, {
    Map<String, Object?>? args,
  }) async {
    try {
      final response = await _vmService.callMethod(
        method,
        args: args?.cast<String, dynamic>(),
      );
      return response.json?.cast<String, Object?>() ?? <String, Object?>{};
    } on RPCError catch (error) {
      if (error.code == RPCErrorKind.kMethodNotFound.code) {
        throw FlutterInspectorServiceUnavailableException(
          '$method service is not registered by the Flutter tool.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, Object?>> reloadSources(String isolateId) async {
    final response = await _vmService.reloadSources(isolateId);
    return response.toJson().cast<String, Object?>();
  }

  @override
  Future<void> dispose() => _vmService.dispose();
}
