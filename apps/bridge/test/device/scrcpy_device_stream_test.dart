import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:ask_ui_bridge/device/device_stream.dart';
import 'package:ask_ui_bridge/device/scrcpy_device_stream.dart';
import 'package:ask_ui_bridge/sessions/session_store.dart';
import 'package:test/test.dart';

void main() {
  test('generates scrcpy scids inside Java signed int hex range', () {
    final scid = createScrcpyScid(random: MaxValueRandom());

    expect(scid, '7fffffff');
    expect(int.parse(scid, radix: 16), lessThanOrEqualTo(0x7fffffff));
  });

  test('starts official scrcpy server and forwards raw H264 bytes', () async {
    final runner = FakeScrcpyCommandRunner();
    final sink = RecordingDeviceStreamSink();
    final session = BridgeSession(
      id: 'session-1',
      vmServiceUri: 'ws://127.0.0.1:12345/ws',
      projectRoot: '/Users/example/app',
      deviceId: 'device-1',
    );

    final stream = await ScrcpyDeviceStreamFactory(
      commandRunner: runner,
      config: const ScrcpyDeviceStreamConfig(
        adbExecutable: 'adb',
        serverPath: '/opt/scrcpy-server',
        scid: 'abc123',
        maxSize: 1080,
        maxFps: 60,
        videoBitRate: 8000000,
      ),
    ).start(session: session, sink: sink);
    addTearDown(stream.close);

    expect(sink.readyMetadata.single.toJson(), {
      'deviceId': 'device-1',
      'screenWidth': 720,
      'screenHeight': 1280,
      'maxFps': 60,
      'videoCodec': 'h264',
      'controlReady': true,
    });
    expect(
        sink.readyMetadata.single.toJson(), isNot(contains('serverVersion')));
    expect(sink.logs, contains('scrcpy server version=4.0'));
    expect(await sink.nextVideoChunk, [0, 0, 0, 1, 0x65]);
    expect(
        runner.commands,
        contains(equals([
          'adb',
          '-s',
          'device-1',
          'push',
          '/opt/scrcpy-server',
          '/data/local/tmp/scrcpy-server.jar',
        ])));
    expect(
      runner.commands.any((command) {
        return command.contains('reverse') &&
            command.contains('localabstract:scrcpy_abc123');
      }),
      isTrue,
    );
    expect(
      runner.startedCommands.single,
      containsAll([
        'adb',
        '-s',
        'device-1',
        'shell',
        'app_process',
        'com.genymobile.scrcpy.Server',
        'raw_stream=true',
        'control=true',
      ]),
    );
  });

  test('writes touch and system key controls to the scrcpy control socket',
      () async {
    final runner = FakeScrcpyCommandRunner();
    final sink = RecordingDeviceStreamSink();
    final session = BridgeSession(
      id: 'session-1',
      vmServiceUri: 'ws://127.0.0.1:12345/ws',
      projectRoot: '/Users/example/app',
      deviceId: 'device-1',
    );
    final stream = await ScrcpyDeviceStreamFactory(
      commandRunner: runner,
      config: const ScrcpyDeviceStreamConfig(
        adbExecutable: 'adb',
        serverPath: '/opt/scrcpy-server',
        scid: 'abc123',
        maxSize: 1080,
        maxFps: 60,
        videoBitRate: 8000000,
      ),
    ).start(session: session, sink: sink);
    addTearDown(stream.close);
    await runner.socketsReady;

    await stream.handleControl({
      'type': 'touch',
      'action': 'cancel',
      'pointerId': 7,
      'x': 10.4,
      'y': 20.6,
      'screenWidth': 720,
      'screenHeight': 1280,
    });
    await stream.handleControl({
      'type': 'systemKey',
      'key': 'recents',
    });

    final controlBytes = await runner.nextControlBytes;

    expect(controlBytes.take(32).toList(), [
      2, // INJECT_TOUCH_EVENT
      1, // ACTION_UP, because cancel releases the active pointer
      0, 0, 0, 0, 0, 0, 0, 7,
      0, 0, 0, 10,
      0, 0, 0, 21,
      2, 208,
      5, 0,
      0, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
    ]);
    expect(controlBytes.skip(32).toList(), [
      0, // INJECT_KEYCODE
      0, // ACTION_DOWN
      0, 0, 0, 187, // KEYCODE_APP_SWITCH
      0, 0, 0, 0, // repeat
      0, 0, 0, 0, // meta state
      0, // INJECT_KEYCODE
      1, // ACTION_UP
      0, 0, 0, 187,
      0, 0, 0, 0,
      0, 0, 0, 0,
    ]);
  });

  test('serializes rapid control writes to the scrcpy control socket',
      () async {
    final runner = FakeScrcpyCommandRunner();
    final sink = RecordingDeviceStreamSink();
    final session = BridgeSession(
      id: 'session-1',
      vmServiceUri: 'ws://127.0.0.1:12345/ws',
      projectRoot: '/Users/example/app',
      deviceId: 'device-1',
    );
    final stream = await ScrcpyDeviceStreamFactory(
      commandRunner: runner,
      config: const ScrcpyDeviceStreamConfig(
        adbExecutable: 'adb',
        serverPath: '/opt/scrcpy-server',
        scid: 'abc123',
        maxSize: 1080,
        maxFps: 60,
        videoBitRate: 8000000,
      ),
    ).start(session: session, sink: sink);
    addTearDown(stream.close);
    await runner.socketsReady;

    await Future.wait(List.generate(10, (index) {
      return stream.handleControl({
        'type': 'touch',
        'action': 'move',
        'pointerId': 7,
        'x': index,
        'y': index,
        'screenWidth': 720,
        'screenHeight': 1280,
      });
    }));

    final controlBytes = await runner.nextControlBytes;

    expect(controlBytes.length, 32 * 10);
    expect(sink.errors, isEmpty);
  });

  test('cleans up scrcpy process, sockets, and adb reverse on close', () async {
    final runner = FakeScrcpyCommandRunner();
    final sink = RecordingDeviceStreamSink();
    final session = BridgeSession(
      id: 'session-1',
      vmServiceUri: 'ws://127.0.0.1:12345/ws',
      projectRoot: '/Users/example/app',
      deviceId: 'device-1',
    );
    final stream = await ScrcpyDeviceStreamFactory(
      commandRunner: runner,
      config: const ScrcpyDeviceStreamConfig(
        adbExecutable: 'adb',
        serverPath: '/opt/scrcpy-server',
        scid: 'abc123',
        maxSize: 1080,
        maxFps: 60,
        videoBitRate: 8000000,
      ),
    ).start(session: session, sink: sink);

    await stream.close();

    expect(runner.processes.single.killed, isTrue);
    expect(
      runner.commands.where((command) {
        return command.contains('reverse') &&
            command.contains('--remove') &&
            command.contains('localabstract:scrcpy_abc123');
      }),
      hasLength(2),
    );
  });

  test('cleans up partially initialized resources when startup fails',
      () async {
    final runner = FakeScrcpyCommandRunner(failPush: true);
    final sink = RecordingDeviceStreamSink();
    final session = BridgeSession(
      id: 'session-1',
      vmServiceUri: 'ws://127.0.0.1:12345/ws',
      projectRoot: '/Users/example/app',
      deviceId: 'device-1',
    );

    await expectLater(
      ScrcpyDeviceStreamFactory(
        commandRunner: runner,
        config: const ScrcpyDeviceStreamConfig(
          adbExecutable: 'adb',
          serverPath: '/opt/scrcpy-server',
          scid: 'abc123',
          maxSize: 1080,
          maxFps: 60,
          videoBitRate: 8000000,
        ),
      ).start(session: session, sink: sink),
      throwsStateError,
    );

    expect(
      runner.commands.where((command) {
        return command.contains('reverse') &&
            command.contains('--remove') &&
            command.contains('localabstract:scrcpy_abc123');
      }),
      hasLength(2),
    );
  });

  test('fails the device stream when an underlying socket closes', () async {
    final runner = FakeScrcpyCommandRunner();
    final sink = RecordingDeviceStreamSink();
    final session = BridgeSession(
      id: 'session-1',
      vmServiceUri: 'ws://127.0.0.1:12345/ws',
      projectRoot: '/Users/example/app',
      deviceId: 'device-1',
    );
    final stream = await ScrcpyDeviceStreamFactory(
      commandRunner: runner,
      config: const ScrcpyDeviceStreamConfig(
        adbExecutable: 'adb',
        serverPath: '/opt/scrcpy-server',
        scid: 'abc123',
        maxSize: 1080,
        maxFps: 60,
        videoBitRate: 8000000,
      ),
    ).start(session: session, sink: sink);
    addTearDown(stream.close);

    await runner.socketsReady;
    runner.videoSocket!.destroy();
    await sink.failed;

    expect(sink.errors, [
      {'error': 'device_failed', 'message': 'Device failed.'},
    ]);
    expect(sink.closed, isTrue);
  });
}

class MaxValueRandom implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 1;

  @override
  int nextInt(int max) => max - 1;
}

class RecordingDeviceStreamSink implements DeviceStreamSink {
  final readyMetadata = <DeviceMetadata>[];
  final metadata = <DeviceMetadata>[];
  final videoChunks = StreamController<List<int>>();
  final errors = <Map<String, String>>[];
  final logs = <String>[];
  final _failed = Completer<void>();
  bool closed = false;

  Future<List<int>> get nextVideoChunk {
    return videoChunks.stream.first.timeout(const Duration(seconds: 2));
  }

  Future<void> get failed {
    return _failed.future.timeout(const Duration(seconds: 2));
  }

  @override
  void fail(String error, String message) {
    errors.add({'error': error, 'message': message});
    if (!_failed.isCompleted) {
      _failed.complete();
    }
  }

  @override
  void log(String message) {
    logs.add(message);
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  void sendMetadata(DeviceMetadata metadata) {
    this.metadata.add(metadata);
  }

  @override
  void sendReady(DeviceMetadata metadata) {
    readyMetadata.add(metadata);
  }

  @override
  void sendVideoChunk(List<int> bytes) {
    videoChunks.add(bytes);
  }
}

class FakeScrcpyCommandRunner implements ScrcpyCommandRunner {
  FakeScrcpyCommandRunner({this.failPush = false});

  final bool failPush;
  final commands = <List<String>>[];
  final startedCommands = <List<String>>[];
  final processes = <FakeScrcpyServerProcess>[];
  final _controlBytes = StreamController<List<int>>();
  Socket? videoSocket;
  Socket? controlSocket;
  final _socketsReady = Completer<void>();

  Future<void> get socketsReady => _socketsReady.future;

  Future<List<int>> get nextControlBytes {
    return _controlBytes.stream.first.timeout(const Duration(seconds: 2));
  }

  @override
  Future<ScrcpyCommandResult> run(String executable, List<String> args) async {
    commands.add([executable, ...args]);
    if (args.contains('wm') && args.contains('size')) {
      return const ScrcpyCommandResult(stdout: 'Physical size: 720x1280\n');
    }
    if (failPush && args.contains('push')) {
      throw StateError('push failed');
    }
    return const ScrcpyCommandResult(stdout: '');
  }

  @override
  ScrcpyServerProcess start(String executable, List<String> args) {
    startedCommands.add([executable, ...args]);
    _connectScrcpySockets();
    final process = FakeScrcpyServerProcess();
    processes.add(process);
    return process;
  }

  void _connectScrcpySockets() {
    final reverseCommand = commands.lastWhere((command) {
      return command.contains('reverse');
    });
    final portArg = reverseCommand.last;
    final port = int.parse(portArg.substring('tcp:'.length));
    scheduleMicrotask(() async {
      final video = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final control = await Socket.connect(InternetAddress.loopbackIPv4, port);
      videoSocket = video;
      controlSocket = control;
      _socketsReady.complete();
      final controlChunks = <int>[];
      control.listen((chunk) {
        controlChunks.addAll(chunk);
        if (controlChunks.length >= 60 && !_controlBytes.isClosed) {
          _controlBytes.add(List<int>.from(controlChunks));
        }
      });
      video.add([0, 0, 0, 1, 0x65]);
      await video.flush();
      addTearDown(video.destroy);
      addTearDown(control.destroy);
    });
  }
}

class FakeScrcpyServerProcess implements ScrcpyServerProcess {
  final _stderr = StreamController<List<int>>();
  bool killed = false;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }
}
