import 'dart:async';
import 'dart:convert';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../logging/bridge_logger.dart';
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

  Future<SelectWidgetModeResult> setSelectWidgetMode(
    BridgeSession session, {
    required bool enabled,
  });

  Future<SelectWidgetModeStatus> getSelectWidgetModeStatus(
    BridgeSession session,
  );

  /// Watch Select Widget mode changes observed for one bridge session.
  ///
  /// Args:
  /// - `session`: Existing bridge session whose VM Service extension stream is
  ///   monitored. If the monitor is not running yet, this method starts it.
  ///
  /// Returns:
  /// A broadcast stream of cached Inspector mode values. The stream emits only
  /// changes observed after the caller subscribes; callers that need an initial
  /// value should first call `getSelectWidgetModeStatus`.
  ///
  /// Example:
  /// The bridge SSE endpoint calls `getSelectWidgetModeStatus` for the first
  /// event, then forwards this stream as later `select_widget_mode_changed`
  /// events.
  Stream<SelectWidgetModeStatus> watchSelectWidgetModeStatus(
    BridgeSession session,
  );
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
    BridgeLogger? logger,
  })  : _vmServiceFactory = vmServiceFactory,
        _logger = logger ?? BridgeLogger(write: print);

  final FlutterInspectorVmServiceFactory _vmServiceFactory;
  final BridgeLogger _logger;
  final _selectWidgetModeBySession = <String, bool?>{};
  final _selectWidgetMonitorStarts = <String, Future<void>>{};
  final _selectWidgetMonitorServices = <String, FlutterInspectorVmService>{};
  final _selectWidgetModeControllers =
      <String, StreamController<SelectWidgetModeStatus>>{};

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

  @override
  Future<SelectWidgetModeResult> setSelectWidgetMode(
    BridgeSession session, {
    required bool enabled,
  }) async {
    _logger.info(
      'select_widget session=${session.id} '
      'connect_vm_service enabled=$enabled',
    );
    final vmService = await _vmServiceFactory.connect(session.vmServiceUri);

    try {
      final isolateId = await vmService.findMainIsolateId();
      _logger.info('select_widget session=${session.id} isolate=$isolateId');
      await vmService.callServiceExtension(
        'ext.flutter.inspector.show',
        isolateId: isolateId,
        args: {
          'enabled': enabled ? 'true' : 'false',
        },
      );
      _logger.info(
        'select_widget session=${session.id} '
        'inspector_show enabled=$enabled',
      );
      _selectWidgetModeBySession[session.id] = enabled;
      _publishSelectWidgetModeStatus(session.id, enabled);

      return SelectWidgetModeResult(
        enabled: enabled,
        message: enabled
            ? 'Select Widget mode enabled.'
            : 'Select Widget mode disabled.',
      );
    } finally {
      await vmService.dispose();
    }
  }

  @override
  Future<SelectWidgetModeStatus> getSelectWidgetModeStatus(
    BridgeSession session,
  ) async {
    await _ensureSelectWidgetModeMonitor(session);

    return SelectWidgetModeStatus(
      enabled: _selectWidgetModeBySession[session.id],
    );
  }

  @override
  Stream<SelectWidgetModeStatus> watchSelectWidgetModeStatus(
    BridgeSession session,
  ) {
    unawaited(_ensureSelectWidgetModeMonitor(session));
    return _selectWidgetModeController(session.id).stream;
  }

  Future<void> _ensureSelectWidgetModeMonitor(BridgeSession session) {
    return _selectWidgetMonitorStarts.putIfAbsent(session.id, () async {
      _logger.info('select_widget session=${session.id} monitor_start');
      final vmService = await _vmServiceFactory.connect(session.vmServiceUri);
      _selectWidgetMonitorServices[session.id] = vmService;
      await vmService.listenToServiceExtensionStateChanges((change) {
        if (!_isSelectWidgetModeExtension(change.extension)) {
          return;
        }

        final enabled = _parseServiceExtensionBool(change.value);
        if (enabled == null) {
          _logger.info(
            'select_widget session=${session.id} '
            'monitor_ignore extension=${change.extension} value=${change.value}',
          );
          return;
        }

        _selectWidgetModeBySession[session.id] = enabled;
        _publishSelectWidgetModeStatus(session.id, enabled);
        _logger.info(
          'select_widget session=${session.id} '
          'monitor_update extension=${change.extension} enabled=$enabled',
        );
      });
    });
  }

  /// Return the broadcast controller for Select Widget mode events.
  ///
  /// Args:
  /// - `sessionId`: Bridge session id whose browser subscribers should receive
  ///   Inspector state changes.
  ///
  /// Returns:
  /// A broadcast controller so multiple browser tabs can watch the same bridge
  /// session without competing for a single-subscription stream.
  ///
  /// Example:
  /// Two tabs connected to `session-1` both receive the next
  /// `SelectWidgetModeStatus(enabled: true)` event.
  StreamController<SelectWidgetModeStatus> _selectWidgetModeController(
    String sessionId,
  ) {
    return _selectWidgetModeControllers.putIfAbsent(
      sessionId,
      () => StreamController<SelectWidgetModeStatus>.broadcast(),
    );
  }

  /// Publish one Select Widget mode value to active browser subscribers.
  ///
  /// Args:
  /// - `sessionId`: Bridge session whose SSE clients should receive the event.
  /// - `enabled`: Current Inspector mode value reported by the app or accepted
  ///   by a bridge request.
  ///
  /// Returns:
  /// Nothing. If no browser has subscribed yet, the value stays only in
  /// `_selectWidgetModeBySession` and will be sent later as the SSE snapshot.
  ///
  /// Example:
  /// Calling this with `enabled=false` sends one
  /// `SelectWidgetModeStatus(enabled: false)` to current subscribers.
  void _publishSelectWidgetModeStatus(String sessionId, bool enabled) {
    final controller = _selectWidgetModeControllers[sessionId];
    if (controller == null || controller.isClosed) {
      return;
    }

    controller.add(SelectWidgetModeStatus(enabled: enabled));
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

/// Result returned after the bridge changes Flutter Inspector select mode.
///
/// It contains:
/// - the enabled state requested by the web UI
/// - a user-facing message for the top bar status area
///
/// Example:
/// Enabling Select Widget returns `status=ok`, `enabled=true`, and
/// `message=Select Widget mode enabled.`
class SelectWidgetModeResult {
  const SelectWidgetModeResult({
    required this.enabled,
    required this.message,
  });

  final bool enabled;
  final String message;

  Map<String, Object?> toJson() {
    return {
      'status': 'ok',
      'enabled': enabled,
      'message': message,
    };
  }
}

/// Cached Select Widget mode state observed from Flutter Inspector.
///
/// It contains the last known `enabled` value reported by the app. When the
/// bridge has not observed a state event yet, `enabled` is `null` and `known`
/// is `false`.
///
/// Example:
/// After DevTools enables Select Widget mode, the bridge returns
/// `{status: ok, known: true, enabled: true}`.
class SelectWidgetModeStatus {
  const SelectWidgetModeStatus({
    required this.enabled,
  });

  final bool? enabled;

  Map<String, Object?> toJson() {
    return {
      'status': 'ok',
      'known': enabled != null,
      if (enabled != null) 'enabled': enabled,
    };
  }
}

/// Change event emitted when Flutter reports a service extension value update.
///
/// It contains the extension name and raw value reported by
/// `Flutter.ServiceExtensionStateChanged`.
///
/// Example:
/// Flutter sends `extension=ext.flutter.inspector.show` and `value=true` when
/// another client enables on-device Select Widget mode.
class FlutterServiceExtensionStateChange {
  const FlutterServiceExtensionStateChange({
    required this.extension,
    required this.value,
  });

  final String extension;
  final Object? value;
}

bool _isSelectWidgetModeExtension(String extension) {
  return extension == 'ext.flutter.inspector.show' ||
      extension == 'ext.flutter.inspector.selectMode';
}

bool? _parseServiceExtensionBool(Object? value) {
  if (value is bool) {
    return value;
  }

  if (value is String) {
    if (value == 'true') {
      return true;
    }
    if (value == 'false') {
      return false;
    }
  }

  return null;
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

  Future<void> listenToServiceExtensionStateChanges(
    void Function(FlutterServiceExtensionStateChange change) onChange,
  );

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
  Future<void> listenToServiceExtensionStateChanges(
    void Function(FlutterServiceExtensionStateChange change) onChange,
  ) async {
    _vmService.onEvent(EventStreams.kExtension).listen((event) {
      if (event.extensionKind != 'Flutter.ServiceExtensionStateChanged') {
        return;
      }

      final data = event.extensionData?.data;
      final extension = data?['extension'];
      if (extension is! String) {
        return;
      }

      onChange(FlutterServiceExtensionStateChange(
        extension: extension,
        value: data?['value'],
      ));
    });

    await _vmService.streamListen(EventStreams.kExtension);
  }

  @override
  Future<void> dispose() => _vmService.dispose();
}
