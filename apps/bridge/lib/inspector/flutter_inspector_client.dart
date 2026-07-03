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
/// - disposal of the underlying connection
///
/// Example:
/// Tests provide a fake implementation to assert that Ask UI requests
/// `isSummaryTree=true` without connecting to a real Flutter app.
abstract class FlutterInspectorVmService {
  Future<String> findMainIsolateId();

  Future<Map<String, Object?>> callServiceExtension(
    String method, {
    required String isolateId,
    Map<String, Object?>? args,
  });

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
  Future<void> dispose() => _vmService.dispose();
}
