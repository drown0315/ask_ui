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
  test('starts capture once and reuses it across browser reconnects', () async {
    final harness = await TestHarness.start();
    addTearDown(harness.close);

    final first = await harness.connect();
    expect((await nextJson(first))['type'], 'ready');
    expect((await nextJson(first))['state'], 'unavailable');
    await first.channel.sink.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final second = await harness.connect();
    expect((await nextJson(second))['type'], 'ready');
    expect(harness.captureFactoryCalls, 1);
    expect(harness.capture.closed, isFalse);
    await second.channel.sink.close();

    await harness.mvp.close();
    expect(harness.capture.closed, isTrue);
  });

  test('PUT control attaches after capture and publishes ready state', () async {
    final harness = await TestHarness.start();
    addTearDown(harness.close);
    final browser = await harness.connect();
    await nextJson(browser);
    await nextJson(browser);

    final uri = Uri.parse('http://127.0.0.1:62076/token=/');
    final response = await putControl(harness.port, uri);
    expect(response.statusCode, HttpStatus.ok);
    expect(harness.controlUris, [uri]);
    expect((await nextJson(browser))['state'], 'connecting');
    final ready = await nextJson(browser);
    expect(ready['type'], 'ready');
    expect(ready['logicalWidth'], 375);
    expect((await nextJson(browser))['state'], 'ready');
  });

  test('failed replacement preserves the previous ready control', () async {
    final harness = await TestHarness.start();
    addTearDown(harness.close);
    final firstUri = Uri.parse('http://127.0.0.1:62076/first=/');
    final secondUri = Uri.parse('http://127.0.0.1:62077/second=/');

    expect((await putControl(harness.port, firstUri)).statusCode, HttpStatus.ok);
    final firstControl = harness.controls.single;
    harness.controlFactoryError = StateError('new VM unavailable');
    final response = await putControl(harness.port, secondUri);

    expect(response.statusCode, HttpStatus.serviceUnavailable);
    expect(firstControl.closed, isFalse);
  });

  test('DELETE control cancels pointer and leaves capture live', () async {
    final harness = await TestHarness.start();
    addTearDown(harness.close);
    final browser = await harness.connect();
    await nextJson(browser);
    await nextJson(browser);
    await putControl(
      harness.port,
      Uri.parse('http://127.0.0.1:62076/token=/'),
    );
    await nextJson(browser);
    await nextJson(browser);
    await nextJson(browser);

    browser.channel.sink.add(pointerJson('down'));
    await pumpUntil(() => harness.controls.single.messages.isNotEmpty);
    final response = await deleteControl(harness.port);

    expect(response.statusCode, HttpStatus.ok);
    expect(harness.controls.single.messages.last.action, 'cancel');
    expect(harness.controls.single.closed, isTrue);
    expect(harness.capture.closed, isFalse);
    expect((await nextJson(browser))['state'], 'unavailable');

    browser.channel.sink.add(pointerJson('down'));
    final error = await nextJson(browser);
    expect(error['code'], 'runtime_control_unavailable');
    harness.capture.framesController.add(
      VideoFrameEnvelope(
        flags: 1,
        ptsMicros: 10,
        payload: Uint8List.fromList([1, 2]),
      ),
    );
    expect(await browser.messages.moveNext(), isTrue);
    expect(browser.messages.current, isA<List<int>>());
  });
}

final class TestHarness {
  TestHarness._(this.webRoot, this.capture);

  static Future<TestHarness> start() async {
    final webRoot = await Directory.systemTemp.createTemp('mvp_web_test_');
    await File('${webRoot.path}/index.html').writeAsString('MVP');
    final harness = TestHarness._(webRoot, FakeCaptureSession());
    harness.mvp = MvpServer(
      webRoot: webRoot.path,
      captureFactory: () async {
        harness.captureFactoryCalls++;
        return harness.capture;
      },
      controlFactory: (metadata, uri) async {
        harness.controlUris.add(uri);
        final error = harness.controlFactoryError;
        if (error != null) throw error;
        final control = FakeControlBackend();
        harness.controls.add(control);
        return control;
      },
    );
    harness.server = await shelf_io.serve(
      harness.mvp.handler,
      '127.0.0.1',
      0,
    );
    return harness;
  }

  final Directory webRoot;
  final FakeCaptureSession capture;
  final controlUris = <Uri>[];
  final controls = <FakeControlBackend>[];
  late final MvpServer mvp;
  late final HttpServer server;
  Object? controlFactoryError;
  int captureFactoryCalls = 0;

  int get port => server.port;

  Future<BrowserConnection> connect() async {
    final channel = IOWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:$port/session'),
    );
    return BrowserConnection(channel, StreamIterator(channel.stream));
  }

  Future<void> close() async {
    await server.close(force: true);
    await mvp.close();
    await webRoot.delete(recursive: true);
  }
}

final class BrowserConnection {
  BrowserConnection(this.channel, this.messages);

  final IOWebSocketChannel channel;
  final StreamIterator<dynamic> messages;
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
    if (closed) return;
    closed = true;
    await framesController.close();
  }
}

final class FakeControlBackend implements ControlBackend {
  final messages = <PointerMessage>[];
  bool closed = false;

  @override
  Future<DeviceMetadata> resolveMetadata() async => runtimeMetadata;

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

const runtimeMetadata = DeviceMetadata(
  deviceId: 'ios-1',
  screenWidth: 1170,
  screenHeight: 2532,
  logicalWidth: 375,
  logicalHeight: 667,
  devicePixelRatio: 2,
  videoCodec: 'h264',
  controlBackend: 'flutterRuntime',
);

Future<Map<String, dynamic>> nextJson(BrowserConnection browser) async {
  expect(await browser.messages.moveNext(), isTrue);
  return jsonDecode(browser.messages.current as String) as Map<String, dynamic>;
}

Future<HttpClientResponse> putControl(int port, Uri vmServiceUri) async {
  final client = HttpClient();
  final request = await client.put('127.0.0.1', port, '/control');
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'vmServiceUri': vmServiceUri.toString()}));
  final response = await request.close();
  await response.drain<void>();
  client.close();
  return response;
}

Future<HttpClientResponse> deleteControl(int port) async {
  final client = HttpClient();
  final request = await client.delete('127.0.0.1', port, '/control');
  final response = await request.close();
  await response.drain<void>();
  client.close();
  return response;
}

String pointerJson(String action) => jsonEncode({
  'type': 'pointer',
  'action': action,
  'x': 0.2,
  'y': 0.3,
  'pointerId': 0,
});

Future<void> pumpUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}
