import 'package:ask_ui_bridge/app_controller/flutter_app_controller.dart';
import 'package:ask_ui_bridge/inspector/flutter_inspector_client.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('VmServiceFlutterAppController', () {
    test('runs hot reload through VM Service reloadSources', () async {
      final vmService = RecordingHotReloadVmService();
      final controller = VmServiceFlutterAppController(
        vmServiceFactory: RecordingHotReloadVmServiceFactory(vmService),
      );

      final result = await controller.hotReload(
        const BridgeSession(
          id: 'session-1',
          vmServiceUri: 'ws://127.0.0.1:12345/ws',
          projectRoot: '/Users/example/app',
        ),
      );

      expect(vmService.reloadSourceIsolateIds, ['isolates/1']);
      expect(vmService.disposed, isTrue);
      expect(result.toJson(), {
        'status': 'ok',
        'message': 'Hot reload completed.',
        'reloadReport': {
          'success': true,
        },
      });
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
  final reloadSourceIsolateIds = <String>[];
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> reloadSources(String isolateId) async {
    reloadSourceIsolateIds.add(isolateId);
    return {
      'success': true,
    };
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
