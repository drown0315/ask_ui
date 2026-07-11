import 'package:ios_screen_mvp_server/flutter_runtime_control.dart';
import 'package:ios_screen_mvp_server/protocol.dart';
import 'package:test/test.dart';

void main() {
  const metadata = DeviceMetadata(
    deviceId: 'device',
    screenWidth: 1170,
    screenHeight: 2532,
    logicalWidth: 390,
    logicalHeight: 844,
    devicePixelRatio: 3,
    videoCodec: 'h264',
    controlBackend: 'flutterRuntime',
  );

  test(
    'maps a normalized pointer sequence to Flutter logical coordinates',
    () async {
      final adapter = FakeVmServiceAdapter();
      final control = FlutterRuntimeControl(
        metadata: metadata,
        adapter: adapter,
      );

      for (final action in ['down', 'move', 'up', 'cancel']) {
        await control.send(
          PointerMessage(action: action, x: 0.25, y: 0.75, pointerId: 0),
        );
      }

      expect(adapter.calls, [
        for (final action in ['down', 'move', 'up', 'cancel'])
          {'action': action, 'x': '97.5', 'y': '633.0', 'pointerId': '0'},
      ]);
    },
  );

  test(
    'maps a rejected extension response to a stable control error',
    () async {
      final adapter = FakeVmServiceAdapter(response: {'ok': false});
      final control = FlutterRuntimeControl(
        metadata: metadata,
        adapter: adapter,
      );

      await expectLater(
        control.send(
          const PointerMessage(action: 'down', x: 0.5, y: 0.5, pointerId: 0),
        ),
        throwsA(
          isA<ControlError>().having(
            (error) => error.code,
            'code',
            'runtime_control_unavailable',
          ),
        ),
      );
    },
  );

  test('close disconnects the VM Service adapter', () async {
    final adapter = FakeVmServiceAdapter();
    final control = FlutterRuntimeControl(metadata: metadata, adapter: adapter);

    await control.close();

    expect(adapter.closed, isTrue);
  });
}

final class FakeVmServiceAdapter implements VmServiceAdapter {
  FakeVmServiceAdapter({this.response = const {'ok': true}});

  final Map<String, Object?> response;
  final List<Map<String, String>> calls = [];
  bool closed = false;

  @override
  Future<Map<String, Object?>> callPointerExtension(
    Map<String, String> arguments,
  ) async {
    calls.add(arguments);
    return response;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
