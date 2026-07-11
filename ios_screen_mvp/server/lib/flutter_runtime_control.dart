import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:vm_service/utils.dart';

import 'protocol.dart';

Uri vmServiceWebSocketUri(Uri serviceUri) =>
    serviceUri.scheme == 'ws' || serviceUri.scheme == 'wss'
    ? serviceUri
    : convertToWebSocketUrl(serviceProtocolUrl: serviceUri);

abstract interface class ControlBackend {
  Future<void> send(PointerMessage message);
  Future<void> close();
}

abstract interface class VmServiceAdapter {
  Future<Map<String, Object?>> callPointerExtension(
    Map<String, String> arguments,
  );

  Future<void> close();
}

final class FlutterRuntimeControl implements ControlBackend {
  FlutterRuntimeControl({required this.metadata, required this.adapter});

  static const extensionName = 'ext.ios_screen_mvp.pointer';

  final DeviceMetadata metadata;
  final VmServiceAdapter adapter;

  Future<void> send(PointerMessage message) async {
    try {
      final response = await adapter.callPointerExtension({
        'action': message.action,
        'x': (message.x * metadata.logicalWidth).toString(),
        'y': (message.y * metadata.logicalHeight).toString(),
        'pointerId': message.pointerId.toString(),
      });
      if (response['ok'] != true) {
        throw const ControlError(
          code: 'runtime_control_unavailable',
          message: 'The Flutter pointer extension rejected the event.',
        );
      }
    } on ControlError {
      rethrow;
    } catch (error) {
      throw ControlError(
        code: 'runtime_control_unavailable',
        message: 'Unable to send pointer input to Flutter: $error',
      );
    }
  }

  Future<void> close() => adapter.close();
}

final class LiveVmServiceAdapter implements VmServiceAdapter {
  LiveVmServiceAdapter._(this._service, this._isolateId);

  static Future<LiveVmServiceAdapter> connect(Uri vmServiceUri) async {
    final service = await vmServiceConnectUri(
      vmServiceWebSocketUri(vmServiceUri).toString(),
    );
    try {
      final vm = await service.getVM();
      final isolates = vm.isolates ?? const <IsolateRef>[];
      final isolate =
          isolates.where((item) => item.name == 'main').firstOrNull ??
          isolates.firstOrNull;
      final isolateId = isolate?.id;
      if (isolateId == null) {
        throw StateError('The Flutter VM has no runnable isolate.');
      }
      return LiveVmServiceAdapter._(service, isolateId);
    } catch (_) {
      await service.dispose();
      rethrow;
    }
  }

  final VmService _service;
  final String _isolateId;

  @override
  Future<Map<String, Object?>> callPointerExtension(
    Map<String, String> arguments,
  ) async {
    final response = await _service.callServiceExtension(
      FlutterRuntimeControl.extensionName,
      isolateId: _isolateId,
      args: arguments,
    );
    return response.json ?? const <String, Object?>{};
  }

  @override
  Future<void> close() => _service.dispose();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
