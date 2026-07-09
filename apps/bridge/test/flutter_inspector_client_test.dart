import 'dart:async';

import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
import 'package:ask_ui_bridge/logging/bridge_logger.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('VmServiceFlutterInspectorClient', () {
    test('configures pub roots and fetches the summary widget tree', () async {
      final vmService = RecordingFlutterInspectorVmService({
        'result': {
          'valueId': 'inspector-1',
          'description': 'MaterialApp',
          'children': [
            {
              'valueId': 'inspector-2',
              'description': 'Scaffold',
              'creationLocation': {
                'file': 'file:///Users/example/app/lib/home.dart',
                'line': 9,
                'column': 7,
              },
              'textPreview': 'Home',
            },
          ],
        },
      });
      final client = VmServiceFlutterInspectorClient(
        vmServiceFactory: RecordingFlutterInspectorVmServiceFactory(vmService),
      );

      final root = await client.fetchRootWidgetTree(
        BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        ),
      );

      expect(root.toJson(), {
        'id': 'inspector-1',
        'label': 'MaterialApp',
        'children': [
          {
            'id': 'inspector-2',
            'label': 'Scaffold',
            'sourceLocation': 'lib/home.dart:9:7',
            'visibleText': 'Home',
            'children': <Object?>[],
          },
        ],
      });
      expect(vmService.disposed, isTrue);
      expect(vmService.didFindMainIsolateId, isTrue);
      expect(vmService.calls, [
        const FlutterInspectorVmServiceCall(
          method: 'ext.flutter.inspector.setPubRootDirectories',
          isolateId: 'isolates/main',
          args: {'arg0': '/Users/example/app'},
        ),
        const FlutterInspectorVmServiceCall(
          method: 'ext.flutter.inspector.getRootWidgetTree',
          isolateId: 'isolates/main',
          args: {
            'groupName': 'ask_ui_widget_tree',
            'isSummaryTree': 'true',
            'withPreviews': 'true',
            'fullDetails': 'true',
          },
        ),
        const FlutterInspectorVmServiceCall(
          method: 'ext.ask_ui.widgetBounds',
          isolateId: 'isolates/main',
          args: {
            'id': 'inspector-1',
            'groupName': 'ask_ui_widget_tree',
          },
        ),
      ]);
    });

    test('decodes widget tree responses returned as JSON strings', () async {
      final vmService = RecordingFlutterInspectorVmService({
        'result':
            '{"valueId":"inspector-1","description":"MaterialApp","children":[]}',
      });
      final client = VmServiceFlutterInspectorClient(
        vmServiceFactory: RecordingFlutterInspectorVmServiceFactory(vmService),
      );

      final root = await client.fetchRootWidgetTree(
        BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        ),
      );

      expect(root.toJson(), {
        'id': 'inspector-1',
        'label': 'MaterialApp',
        'children': <Object?>[],
      });
    });

    test('enriches widget tree nodes with app-side widget bounds', () async {
      final vmService = RecordingFlutterInspectorVmService(
        {
          'result': {
            'valueId': 'inspector-1',
            'description': 'MaterialApp',
            'children': [
              {
                'valueId': 'inspector-2',
                'description': 'FilledButton',
              },
            ],
          },
        },
        serviceExtensionResponses: {
          'ext.ask_ui.widgetBounds': [
            {
              'result': {
                'x': 4,
                'y': 8,
                'width': 120,
                'height': 48,
                'devicePixelRatio': 2.5,
              },
            },
            {
              'result':
                  '{"x":24,"y":36,"width":80,"height":20,"devicePixelRatio":2.5}',
            },
          ],
        },
      );
      final client = VmServiceFlutterInspectorClient(
        vmServiceFactory: RecordingFlutterInspectorVmServiceFactory(vmService),
      );

      final root = await client.fetchRootWidgetTree(
        BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        ),
      );

      expect(root.toJson(), {
        'id': 'inspector-1',
        'label': 'MaterialApp',
        'bounds': {
          'x': 10.0,
          'y': 20.0,
          'width': 300.0,
          'height': 120.0,
        },
        'children': [
          {
            'id': 'inspector-2',
            'label': 'FilledButton',
            'bounds': {
              'x': 60.0,
              'y': 90.0,
              'width': 200.0,
              'height': 50.0,
            },
            'children': <Object?>[],
          },
        ],
      });
      expect(vmService.calls, [
        const FlutterInspectorVmServiceCall(
          method: 'ext.flutter.inspector.setPubRootDirectories',
          isolateId: 'isolates/main',
          args: {'arg0': '/Users/example/app'},
        ),
        const FlutterInspectorVmServiceCall(
          method: 'ext.flutter.inspector.getRootWidgetTree',
          isolateId: 'isolates/main',
          args: {
            'groupName': 'ask_ui_widget_tree',
            'isSummaryTree': 'true',
            'withPreviews': 'true',
            'fullDetails': 'true',
          },
        ),
        const FlutterInspectorVmServiceCall(
          method: 'ext.ask_ui.widgetBounds',
          isolateId: 'isolates/main',
          args: {
            'id': 'inspector-1',
            'groupName': 'ask_ui_widget_tree',
          },
        ),
        const FlutterInspectorVmServiceCall(
          method: 'ext.ask_ui.widgetBounds',
          isolateId: 'isolates/main',
          args: {
            'id': 'inspector-2',
            'groupName': 'ask_ui_widget_tree',
          },
        ),
      ]);
    });

    test('keeps widget tree available when app-side bounds extension is absent',
        () async {
      final vmService = RecordingFlutterInspectorVmService({
        'result': {
          'valueId': 'inspector-1',
          'description': 'MaterialApp',
          'children': [
            {
              'valueId': 'inspector-2',
              'description': 'Scaffold',
            },
          ],
        },
      }, unavailableServiceExtensions: {
        'ext.ask_ui.widgetBounds'
      });
      final client = VmServiceFlutterInspectorClient(
        vmServiceFactory: RecordingFlutterInspectorVmServiceFactory(vmService),
      );

      final root = await client.fetchRootWidgetTree(
        BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        ),
      );

      expect(root.toJson(), {
        'id': 'inspector-1',
        'label': 'MaterialApp',
        'children': [
          {
            'id': 'inspector-2',
            'label': 'Scaffold',
            'children': <Object?>[],
          },
        ],
      });
      expect(
        vmService.calls
            .where((call) => call.method == 'ext.ask_ui.widgetBounds'),
        [
          const FlutterInspectorVmServiceCall(
            method: 'ext.ask_ui.widgetBounds',
            isolateId: 'isolates/main',
            args: {
              'id': 'inspector-1',
              'groupName': 'ask_ui_widget_tree',
            },
          ),
        ],
      );
    });

    test('sets Flutter Inspector select widget mode through inspector.show',
        () async {
      final vmService = RecordingFlutterInspectorVmService({'result': null});
      final logs = <String>[];
      final client = VmServiceFlutterInspectorClient(
        vmServiceFactory: RecordingFlutterInspectorVmServiceFactory(vmService),
        logger: BridgeLogger(write: logs.add),
      );

      final result = await client.setSelectWidgetMode(
        BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: '19271FDF6007TY',
        ),
        enabled: true,
      );

      expect(vmService.calls, [
        const FlutterInspectorVmServiceCall(
          method: 'ext.flutter.inspector.show',
          isolateId: 'isolates/main',
          args: {
            'enabled': 'true',
          },
        ),
      ]);
      expect(vmService.disposed, isTrue);
      expect(result.toJson(), {
        'status': 'ok',
        'enabled': true,
        'message': 'Select Widget mode enabled.',
      });
      expect(logs, [
        '[ask_ui_bridge] select_widget session=session-1 connect_vm_service enabled=true',
        '[ask_ui_bridge] select_widget session=session-1 isolate=isolates/main',
        '[ask_ui_bridge] select_widget session=session-1 inspector_show enabled=true',
      ]);
    });

    test('sets Flutter Inspector selection by widget id', () async {
      final vmService = RecordingFlutterInspectorVmService({'result': null});
      final logs = <String>[];
      final client = VmServiceFlutterInspectorClient(
        vmServiceFactory: RecordingFlutterInspectorVmServiceFactory(vmService),
        logger: BridgeLogger(write: logs.add),
      );

      final result = await client.selectWidgetById(
        BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
          deviceId: 'android-1',
        ),
        widgetId: 'inspector-2',
      );

      expect(vmService.calls, [
        const FlutterInspectorVmServiceCall(
          method: 'ext.flutter.inspector.setSelectionById',
          isolateId: 'isolates/main',
          args: {
            'arg': 'inspector-2',
            'objectGroup': 'ask_ui_widget_tree',
          },
        ),
      ]);
      expect(vmService.disposed, isTrue);
      expect(result.toJson(), {
        'status': 'ok',
        'widgetId': 'inspector-2',
        'message': 'Widget selected.',
      });
      expect(logs, [
        '[ask_ui_bridge] widget_selection session=session-1 connect_vm_service widget=inspector-2',
        '[ask_ui_bridge] widget_selection session=session-1 isolate=isolates/main widget=inspector-2',
        '[ask_ui_bridge] widget_selection session=session-1 selected widget=inspector-2',
      ]);
    });

    test('updates Select Widget mode status from service extension events',
        () async {
      final vmService = RecordingFlutterInspectorVmService({'result': null});
      final logs = <String>[];
      final client = VmServiceFlutterInspectorClient(
        vmServiceFactory: RecordingFlutterInspectorVmServiceFactory(vmService),
        logger: BridgeLogger(write: logs.add),
      );
      final session = BridgeSession(
        id: 'session-1',
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
      );

      final initialStatus = await client.getSelectWidgetModeStatus(session);
      vmService.emitServiceExtensionStateChange(
        const FlutterServiceExtensionStateChange(
          extension: 'ext.flutter.inspector.show',
          value: true,
        ),
      );
      final updatedStatus = await client.getSelectWidgetModeStatus(session);

      expect(initialStatus.toJson(), {
        'status': 'ok',
        'known': false,
      });
      expect(updatedStatus.toJson(), {
        'status': 'ok',
        'known': true,
        'enabled': true,
      });
      expect(
        logs,
        contains(
            '[ask_ui_bridge] select_widget session=session-1 monitor_start'),
      );
      expect(
        logs,
        contains(
          '[ask_ui_bridge] select_widget session=session-1 monitor_update extension=ext.flutter.inspector.show enabled=true',
        ),
      );
    });

    test('publishes Widget Selection status from Inspector inspect events',
        () async {
      final vmService = RecordingFlutterInspectorVmService(
        {'result': null},
        serviceExtensionResponses: {
          'ext.flutter.inspector.getSelectedSummaryWidget': [
            {
              'result': {
                'valueId': 'inspector-2',
                'description': 'PrimaryButton',
                'children': <Object?>[],
              },
            },
          ],
        },
      );
      final logs = <String>[];
      final client = VmServiceFlutterInspectorClient(
        vmServiceFactory: RecordingFlutterInspectorVmServiceFactory(vmService),
        logger: BridgeLogger(write: logs.add),
      );
      final session = BridgeSession(
        id: 'session-1',
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
      );
      final emittedSelections = <WidgetSelectionStatus>[];
      final subscription = client
          .watchWidgetSelectionStatus(session)
          .listen(emittedSelections.add);

      await Future<void>.delayed(Duration.zero);
      await vmService.emitInspectorSelectionChange();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(
        emittedSelections.map((status) => status.widgetId),
        ['inspector-2'],
      );
      expect(
        vmService.calls,
        contains(
          const FlutterInspectorVmServiceCall(
            method: 'ext.flutter.inspector.getSelectedSummaryWidget',
            isolateId: 'isolates/main',
            args: {
              'objectGroup': 'ask_ui_widget_tree',
            },
          ),
        ),
      );
      expect(
        logs,
        contains(
          '[ask_ui_bridge] widget_selection session=session-1 monitor_update widget=inspector-2',
        ),
      );
    });
  });
}

class RecordingFlutterInspectorVmServiceFactory
    implements FlutterInspectorVmServiceFactory {
  RecordingFlutterInspectorVmServiceFactory(this.vmService);

  final RecordingFlutterInspectorVmService vmService;

  @override
  Future<FlutterInspectorVmService> connect(String vmServiceUri) async {
    return vmService;
  }
}

class RecordingFlutterInspectorVmService implements FlutterInspectorVmService {
  RecordingFlutterInspectorVmService(
    this.widgetTreeResponse, {
    Map<String, List<Map<String, Object?>>> serviceExtensionResponses =
        const {},
    Set<String> unavailableServiceExtensions = const {},
  })  : _serviceExtensionResponses = {
          for (final entry in serviceExtensionResponses.entries)
            entry.key: List<Map<String, Object?>>.of(entry.value),
        },
        _unavailableServiceExtensions = unavailableServiceExtensions;

  final Map<String, Object?> widgetTreeResponse;
  final Map<String, List<Map<String, Object?>>> _serviceExtensionResponses;
  final Set<String> _unavailableServiceExtensions;
  final calls = <FlutterInspectorVmServiceCall>[];
  final serviceExtensionStateListeners =
      <void Function(FlutterServiceExtensionStateChange change)>[];
  final inspectorSelectionListeners = <FutureOr<void> Function()>[];
  bool didFindMainIsolateId = false;
  bool disposed = false;

  @override
  Future<String> findMainIsolateId() async {
    didFindMainIsolateId = true;
    return 'isolates/main';
  }

  @override
  Future<Map<String, Object?>> callServiceExtension(
    String method, {
    required String isolateId,
    Map<String, Object?>? args,
  }) async {
    calls.add(FlutterInspectorVmServiceCall(
      method: method,
      isolateId: isolateId,
      args: args ?? {},
    ));

    if (method == 'ext.flutter.inspector.getRootWidgetTree') {
      return widgetTreeResponse;
    }
    if (_unavailableServiceExtensions.contains(method)) {
      throw const FlutterInspectorServiceUnavailableException(
        'Service extension is not registered.',
      );
    }
    final responses = _serviceExtensionResponses[method];
    if (responses != null && responses.isNotEmpty) {
      return responses.removeAt(0);
    }
    if (method == 'ext.ask_ui.widgetBounds') {
      throw const FlutterInspectorServiceUnavailableException(
        'Service extension is not registered.',
      );
    }

    return {'result': null};
  }

  @override
  Future<Map<String, Object?>> callMethod(
    String method, {
    Map<String, Object?>? args,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String?> waitForRegisteredService({
    required String serviceName,
    required Duration timeout,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> reloadSources(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Future<void> listenToServiceExtensionStateChanges(
    void Function(FlutterServiceExtensionStateChange change) onChange,
  ) async {
    serviceExtensionStateListeners.add(onChange);
  }

  @override
  Future<void> listenToInspectorSelectionChanges(
    FutureOr<void> Function() onSelectionChanged,
  ) async {
    inspectorSelectionListeners.add(onSelectionChanged);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  void emitServiceExtensionStateChange(
    FlutterServiceExtensionStateChange change,
  ) {
    for (final listener in serviceExtensionStateListeners) {
      listener(change);
    }
  }

  Future<void> emitInspectorSelectionChange() async {
    for (final listener in inspectorSelectionListeners) {
      await listener();
    }
  }
}

class FlutterInspectorVmServiceCall {
  const FlutterInspectorVmServiceCall({
    required this.method,
    required this.isolateId,
    required this.args,
  });

  final String method;
  final String isolateId;
  final Map<String, Object?> args;

  @override
  bool operator ==(Object other) {
    return other is FlutterInspectorVmServiceCall &&
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
