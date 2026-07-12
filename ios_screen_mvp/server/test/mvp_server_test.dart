import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ios_screen_mvp_server/flutter_runtime_control.dart';
import 'package:ios_screen_mvp_server/mvp_server.dart';
import 'package:ios_screen_mvp_server/protocol.dart';
import 'package:ios_screen_mvp_server/video_stream.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test(
    'orchestrates one controller and cleans resources on disconnect',
    () async {
      final webRoot = await Directory.systemTemp.createTemp('mvp_web_test_');
      await File('${webRoot.path}/index.html').writeAsString('MVP');
      final capture = FakeCaptureSession();
      final control = FakeControlBackend();
      final mvp = MvpServer(
        webRoot: webRoot.path,
        captureFactory: () async => capture,
        controlFactory: (_) async => control,
      );
      final server = await shelf_io.serve(mvp.handler, '127.0.0.1', 0);
      addTearDown(() async {
        await server.close(force: true);
        await webRoot.delete(recursive: true);
      });

      final first = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/session'),
      );
      final firstMessages = StreamIterator(first.stream);
      expect(await firstMessages.moveNext(), isTrue);
      final ready = jsonDecode(firstMessages.current as String);
      expect(ready['type'], 'ready');
      expect(ready['logicalWidth'], 375);
      expect(ready['logicalHeight'], 667);
      expect(ready['devicePixelRatio'], 2);

      capture.framesController.add(
        VideoFrameEnvelope(
          flags: 1,
          ptsMicros: 10,
          payload: Uint8List.fromList([1, 2]),
        ),
      );
      expect(await firstMessages.moveNext(), isTrue);
      expect(firstMessages.current, isA<List<int>>());

      first.sink.add(
        jsonEncode({
          'type': 'pointer',
          'action': 'down',
          'x': 0.2,
          'y': 0.3,
          'pointerId': 0,
        }),
      );
      await pumpUntil(() => control.messages.isNotEmpty);
      expect(control.messages.single.action, 'down');

      final second = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/session'),
      );
      final busy = jsonDecode(await second.stream.first as String);
      expect(busy['code'], 'controller_busy');
      await second.sink.close();

      await first.sink.close();
      await pumpUntil(() => capture.closed && control.closed);
      expect(control.messages.last.action, 'cancel');
    },
  );
}

final class FakeCaptureSession implements CaptureSession {
  final framesController = StreamController<VideoFrameEnvelope>();
  bool closed = false;

  @override
  Future<DeviceMetadata> get metadata async => testMetadata;

  @override
  Stream<VideoFrameEnvelope> get frames => framesController.stream;

  @override
  Future<void> get completion => Completer<void>().future;

  @override
  Future<String> get diagnostics async => '';

  @override
  Future<void> close() async {
    closed = true;
    await framesController.close();
  }
}

final class FakeControlBackend implements ControlBackend {
  final messages = <PointerMessage>[];
  bool closed = false;

  @override
  Future<DeviceMetadata> resolveMetadata() async {
    return DeviceMetadata(
      deviceId: testMetadata.deviceId,
      screenWidth: testMetadata.screenWidth,
      screenHeight: testMetadata.screenHeight,
      logicalWidth: 375,
      logicalHeight: 667,
      devicePixelRatio: 2,
      videoCodec: testMetadata.videoCodec,
      controlBackend: testMetadata.controlBackend,
    );
  }

  @override
  Future<void> send(PointerMessage message) async => messages.add(message);

  @override
  Future<void> close() async => closed = true;
}

const testMetadata = DeviceMetadata(
  deviceId: 'ios-1',
  screenWidth: 1170,
  screenHeight: 2532,
  logicalWidth: 390,
  logicalHeight: 844,
  devicePixelRatio: 3,
  videoCodec: 'h264',
  controlBackend: 'flutterRuntime',
);

Future<void> pumpUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}
