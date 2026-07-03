import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
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
            },
          ],
        },
      });
      final client = VmServiceFlutterInspectorClient(
        vmServiceFactory: RecordingFlutterInspectorVmServiceFactory(vmService),
      );

      final root = await client.fetchRootWidgetTree(
        const BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
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
            'fullDetails': 'false',
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
        const BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
        ),
      );

      expect(root.toJson(), {
        'id': 'inspector-1',
        'label': 'MaterialApp',
        'children': <Object?>[],
      });
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
  RecordingFlutterInspectorVmService(this.widgetTreeResponse);

  final Map<String, Object?> widgetTreeResponse;
  final calls = <FlutterInspectorVmServiceCall>[];
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

    return {'result': null};
  }

  @override
  Future<void> dispose() async {
    disposed = true;
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
