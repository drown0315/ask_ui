import 'package:ask_ui_bridge/app_controller/flutter_app_controller.dart';
import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
import 'package:ask_ui_bridge/logging/bridge_logger.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('VmServiceFlutterAppController', () {
    test('runs hot reload through the Flutter tool registered service',
        () async {
      final vmService = RecordingHotReloadVmService(
        registeredServices: {'reloadSources': '_flutter.reloadSources'},
        serviceExtensionResponses: {
          '_flutter.reloadSources': {
            'type': 'ReloadReport',
            'success': true,
            'details': 'Reloaded 1 of 42 libraries.',
          },
        },
      );
      final logs = <String>[];
      final controller = VmServiceFlutterAppController(
        vmServiceFactory: RecordingHotReloadVmServiceFactory(vmService),
        logger: BridgeLogger(write: logs.add),
      );

      final result = await controller.hotReload(
        const BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        ),
      );

      expect(vmService.waitedRegisteredServices, [
        const RecordedRegisteredServiceWait(
          serviceName: 'reloadSources',
          timeout: Duration(seconds: 1),
        ),
      ]);
      expect(vmService.reloadSourceIsolateIds, isEmpty);
      expect(vmService.serviceExtensionCalls, [
        const RecordedServiceExtensionCall(
          method: '_flutter.reloadSources',
          isolateId: 'isolates/1',
          args: {
            'force': false,
            'pause': false,
          },
        ),
      ]);
      expect(vmService.disposed, isTrue);
      expect(result.toJson(), {
        'status': 'ok',
        'message': 'Hot reload completed.',
        'reloadReport': {
          'type': 'ReloadReport',
          'success': true,
          'details': 'Reloaded 1 of 42 libraries.',
        },
      });
      expect(logs, [
        '[ask_ui_bridge] hot_reload session=session-1 connect_vm_service',
        '[ask_ui_bridge] hot_reload session=session-1 isolate=isolates/1',
        '[ask_ui_bridge] hot_reload session=session-1 wait_registered_service service=reloadSources',
        '[ask_ui_bridge] hot_reload session=session-1 use_registered_service method=_flutter.reloadSources',
        '[ask_ui_bridge] hot_reload session=session-1 reload_report success=true details=Reloaded 1 of 42 libraries.',
      ]);
    });

    test('falls back to VM reloadSources when reloadSources is not registered',
        () async {
      final vmService = RecordingHotReloadVmService(
        reloadSourcesResponse: {
          'type': 'ReloadReport',
          'success': false,
          'notices': ['No source changes were accepted.'],
          'details': 'Incremental compiler was unavailable.',
        },
      );
      final logs = <String>[];
      final controller = VmServiceFlutterAppController(
        vmServiceFactory: RecordingHotReloadVmServiceFactory(vmService),
        logger: BridgeLogger(write: logs.add),
      );

      final result = await controller.hotReload(
        const BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        ),
      );

      expect(vmService.reloadSourceIsolateIds, ['isolates/1']);
      expect(vmService.serviceExtensionCalls, [
        const RecordedServiceExtensionCall(
          method: 'ext.flutter.reassemble',
          isolateId: 'isolates/1',
          args: {},
        ),
      ]);
      expect(vmService.disposed, isTrue);
      expect(result.toJson(), {
        'status': 'ok',
        'message': 'Hot reload completed.',
        'reloadReport': {
          'type': 'ReloadReport',
          'success': false,
          'notices': ['No source changes were accepted.'],
          'details': 'Incremental compiler was unavailable.',
        },
      });
      expect(logs, [
        '[ask_ui_bridge] hot_reload session=session-1 connect_vm_service',
        '[ask_ui_bridge] hot_reload session=session-1 isolate=isolates/1',
        '[ask_ui_bridge] hot_reload session=session-1 wait_registered_service service=reloadSources',
        '[ask_ui_bridge] hot_reload session=session-1 fallback_vm_reloadSources',
        '[ask_ui_bridge] hot_reload session=session-1 reload_report success=false notices=[No source changes were accepted.] details=Incremental compiler was unavailable.',
        '[ask_ui_bridge] hot_reload session=session-1 reassemble_completed',
      ]);
    });

    test('runs hot restart through the Flutter tool VM Service callback',
        () async {
      final vmService = RecordingHotReloadVmService(
        registeredServices: {'hotRestart': '_flutter.hotRestart'},
      );
      final logs = <String>[];
      final controller = VmServiceFlutterAppController(
        vmServiceFactory: RecordingHotReloadVmServiceFactory(vmService),
        logger: BridgeLogger(write: logs.add),
      );

      final result = await controller.hotRestart(
        const BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        ),
      );

      expect(vmService.methodCalls, [
        const RecordedMethodCall(
          method: '_flutter.hotRestart',
          args: {'pause': false},
        ),
      ]);
      expect(vmService.disposed, isTrue);
      expect(result.toJson(), {
        'status': 'ok',
        'message': 'Hot restart completed.',
      });
      expect(logs, [
        '[ask_ui_bridge] hot_restart session=session-1 connect_vm_service',
        '[ask_ui_bridge] hot_restart session=session-1 wait_registered_service service=hotRestart',
        '[ask_ui_bridge] hot_restart session=session-1 use_registered_service method=_flutter.hotRestart',
        '[ask_ui_bridge] hot_restart session=session-1 completed',
      ]);
    });

    test('falls back to hotRestart when hotRestart is not registered',
        () async {
      final vmService = RecordingHotReloadVmService();
      final logs = <String>[];
      final controller = VmServiceFlutterAppController(
        vmServiceFactory: RecordingHotReloadVmServiceFactory(vmService),
        logger: BridgeLogger(write: logs.add),
      );

      final result = await controller.hotRestart(
        const BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        ),
      );

      expect(vmService.methodCalls, [
        const RecordedMethodCall(
          method: 'hotRestart',
          args: {'pause': false},
        ),
      ]);
      expect(vmService.disposed, isTrue);
      expect(result.toJson(), {
        'status': 'ok',
        'message': 'Hot restart completed.',
      });
      expect(logs, [
        '[ask_ui_bridge] hot_restart session=session-1 connect_vm_service',
        '[ask_ui_bridge] hot_restart session=session-1 wait_registered_service service=hotRestart',
        '[ask_ui_bridge] hot_restart session=session-1 fallback_callMethod hotRestart',
        '[ask_ui_bridge] hot_restart session=session-1 completed',
      ]);
    });

    test('reports hot restart as unsupported when fallback method is absent',
        () async {
      final vmService = RecordingHotReloadVmService(
        hasHotRestartFallback: false,
      );
      final logs = <String>[];
      final controller = VmServiceFlutterAppController(
        vmServiceFactory: RecordingHotReloadVmServiceFactory(vmService),
        logger: BridgeLogger(write: logs.add),
      );

      await expectLater(
        controller.hotRestart(
          const BridgeSession(
            id: 'session-1',
            vmServiceUri: 'ws://127.0.0.1:12345/ws',
            projectRoot: '/Users/example/app',
            deviceId: '19271FDF6007TY',
          ),
        ),
        throwsA(isA<HotRestartUnsupportedException>()),
      );

      expect(vmService.disposed, isTrue);
      expect(logs, [
        '[ask_ui_bridge] hot_restart session=session-1 connect_vm_service',
        '[ask_ui_bridge] hot_restart session=session-1 wait_registered_service service=hotRestart',
        '[ask_ui_bridge] hot_restart session=session-1 fallback_callMethod hotRestart',
        '[ask_ui_bridge] hot_restart session=session-1 unsupported',
      ]);
    });
  });
}

class RecordingHotReloadVmServiceFactory
    implements FlutterInspectorVmServiceFactory {
  RecordingHotReloadVmServiceFactory(this.vmService);

  final RecordingHotReloadVmService vmService;

  @override
  Future<FlutterInspectorVmService> connect(String vmServiceUri) async {
    return vmService;
  }
}

class RecordingHotReloadVmService implements FlutterInspectorVmService {
  RecordingHotReloadVmService({
    this.hasHotRestartFallback = true,
    this.registeredServices = const {},
    this.serviceExtensionResponses = const {},
    this.reloadSourcesResponse = const {
      'type': 'ReloadReport',
      'success': true,
    },
  });

  final bool hasHotRestartFallback;
  final Map<String, String> registeredServices;
  final Map<String, Map<String, Object?>> serviceExtensionResponses;
  final Map<String, Object?> reloadSourcesResponse;
  final reloadSourceIsolateIds = <String>[];
  final waitedRegisteredServices = <RecordedRegisteredServiceWait>[];
  final serviceExtensionCalls = <RecordedServiceExtensionCall>[];
  final methodCalls = <RecordedMethodCall>[];
  bool disposed = false;

  @override
  Future<String> findMainIsolateId() async {
    return 'isolates/1';
  }

  @override
  Future<Map<String, Object?>> callServiceExtension(
    String method, {
    required String isolateId,
    Map<String, Object?>? args,
  }) async {
    serviceExtensionCalls.add(RecordedServiceExtensionCall(
      method: method,
      isolateId: isolateId,
      args: args ?? {},
    ));
    return serviceExtensionResponses[method] ?? {'result': <String, Object?>{}};
  }

  @override
  Future<Map<String, Object?>> reloadSources(String isolateId) async {
    reloadSourceIsolateIds.add(isolateId);
    return reloadSourcesResponse;
  }

  @override
  Future<Map<String, Object?>> callMethod(
    String method, {
    Map<String, Object?>? args,
  }) async {
    if (method == 'hotRestart' && !hasHotRestartFallback) {
      throw const FlutterInspectorServiceUnavailableException(
        'hotRestart service is not registered by the Flutter tool.',
      );
    }

    methodCalls.add(RecordedMethodCall(
      method: method,
      args: args ?? {},
    ));
    return {
      'type': 'Success',
    };
  }

  @override
  Future<String?> waitForRegisteredService({
    required String serviceName,
    required Duration timeout,
  }) async {
    waitedRegisteredServices.add(RecordedRegisteredServiceWait(
      serviceName: serviceName,
      timeout: timeout,
    ));
    return registeredServices[serviceName];
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> listenToServiceExtensionStateChanges(
    void Function(FlutterServiceExtensionStateChange change) onChange,
  ) {
    throw UnimplementedError();
  }
}

class RecordedRegisteredServiceWait {
  const RecordedRegisteredServiceWait({
    required this.serviceName,
    required this.timeout,
  });

  final String serviceName;
  final Duration timeout;

  @override
  bool operator ==(Object other) {
    return other is RecordedRegisteredServiceWait &&
        other.serviceName == serviceName &&
        other.timeout == timeout;
  }

  @override
  int get hashCode => Object.hash(serviceName, timeout);
}

class RecordedMethodCall {
  const RecordedMethodCall({
    required this.method,
    required this.args,
  });

  final String method;
  final Map<String, Object?> args;

  @override
  bool operator ==(Object other) {
    return other is RecordedMethodCall &&
        other.method == method &&
        _mapEquals(other.args, args);
  }

  @override
  int get hashCode => Object.hash(method, Object.hashAll(args.entries));
}

class RecordedServiceExtensionCall {
  const RecordedServiceExtensionCall({
    required this.method,
    required this.isolateId,
    required this.args,
  });

  final String method;
  final String isolateId;
  final Map<String, Object?> args;

  @override
  bool operator ==(Object other) {
    return other is RecordedServiceExtensionCall &&
        other.method == method &&
        other.isolateId == isolateId &&
        _mapEquals(other.args, args);
  }

  @override
  int get hashCode =>
      Object.hash(method, isolateId, Object.hashAll(args.entries));
}

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) {
    return false;
  }

  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }

  return true;
}
