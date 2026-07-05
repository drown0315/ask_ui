import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../sessions/session_store.dart';
import 'device_stream.dart';

/// Runtime configuration for one official scrcpy server stream.
///
/// It tells the bridge:
/// - which `adb` executable to run
/// - which official scrcpy server file to push to the device
/// - which scrcpy socket id and video settings to use
///
/// Example:
/// With `scid=abc123`, the bridge opens
/// `localabstract:scrcpy_abc123` through `adb reverse` and starts
/// `com.genymobile.scrcpy.Server` with matching `scid=abc123`.
class ScrcpyDeviceStreamConfig {
  const ScrcpyDeviceStreamConfig({
    required this.adbExecutable,
    required this.serverPath,
    required this.scid,
    required this.maxSize,
    required this.maxFps,
    required this.videoBitRate,
  });

  /// Read scrcpy stream settings from the bridge process environment.
  ///
  /// This method:
  /// 1. uses `ADB` when provided, otherwise `adb`
  /// 2. uses `SCRCPY_SERVER` when provided, otherwise the calibrated Homebrew
  ///    scrcpy 4.0 server path
  /// 3. parses optional video tuning values and falls back to MVP defaults
  /// 4. generates a random scrcpy socket id for the session
  ///
  /// Returns:
  /// A complete config that can start one scrcpy stream.
  ///
  /// Example:
  /// `SCRCPY_SERVER=/tmp/scrcpy-server MAX_FPS=30` returns a config that
  /// pushes `/tmp/scrcpy-server` and starts scrcpy with `max_fps=30`.
  factory ScrcpyDeviceStreamConfig.fromEnvironment({
    Map<String, String>? environment,
    String Function()? scidFactory,
  }) {
    final effectiveEnvironment = environment ?? Platform.environment;
    return ScrcpyDeviceStreamConfig(
      adbExecutable: effectiveEnvironment['ADB'] ?? 'adb',
      serverPath: effectiveEnvironment['SCRCPY_SERVER'] ??
          '/opt/homebrew/Cellar/scrcpy/4.0/share/scrcpy/scrcpy-server',
      scid: scidFactory?.call() ?? createScrcpyScid(),
      maxSize: int.tryParse(effectiveEnvironment['MAX_SIZE'] ?? '') ?? 0,
      maxFps: int.tryParse(effectiveEnvironment['MAX_FPS'] ?? '') ?? 60,
      videoBitRate:
          int.tryParse(effectiveEnvironment['VIDEO_BIT_RATE'] ?? '') ?? 8000000,
    );
  }

  final String adbExecutable;
  final String serverPath;
  final String scid;
  final int maxSize;
  final int maxFps;
  final int videoBitRate;
}

/// Result from a completed local command.
///
/// It carries stdout and stderr as strings so tests can fake ADB responses and
/// production code can parse command output such as `adb shell wm size`.
class ScrcpyCommandResult {
  const ScrcpyCommandResult({required this.stdout, this.stderr = ''});

  final String stdout;
  final String stderr;
}

/// Runs local ADB commands for the scrcpy stream.
///
/// Tests implement this interface without spawning processes. Production uses
/// `Process.run` for short commands and `Process.start` for the long-lived
/// scrcpy server process.
abstract interface class ScrcpyCommandRunner {
  Future<ScrcpyCommandResult> run(String executable, List<String> args);

  ScrcpyServerProcess start(String executable, List<String> args);
}

/// Long-lived scrcpy server process started through ADB.
///
/// The stream listens to `stderr` for bridge diagnostics and kills the process
/// during Device cleanup.
abstract interface class ScrcpyServerProcess {
  Stream<List<int>> get stderr;

  Future<int> get exitCode;

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

/// Command runner backed by `dart:io` processes.
class ProcessScrcpyCommandRunner implements ScrcpyCommandRunner {
  const ProcessScrcpyCommandRunner();

  @override
  Future<ScrcpyCommandResult> run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        args,
        '${result.stderr}${result.stdout}',
        result.exitCode,
      );
    }
    return ScrcpyCommandResult(
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  @override
  ScrcpyServerProcess start(String executable, List<String> args) {
    return _StartedScrcpyServerProcess(Process.start(executable, args));
  }
}

/// Starts scrcpy-backed Device streams for bridge sessions.
///
/// This factory is responsible for cleanup on startup failure. If any startup
/// step fails after partial resources were created, it closes the stream before
/// rethrowing so the server can return `device_start_failed`.
class ScrcpyDeviceStreamFactory implements DeviceStreamFactory {
  ScrcpyDeviceStreamFactory({
    ScrcpyCommandRunner commandRunner = const ProcessScrcpyCommandRunner(),
    ScrcpyDeviceStreamConfig? config,
    ScrcpyDeviceStreamConfig Function()? configFactory,
    Duration startupTimeout = const Duration(seconds: 10),
  })  : _commandRunner = commandRunner,
        _createConfig = configFactory ??
            (() => config ?? ScrcpyDeviceStreamConfig.fromEnvironment()),
        _startupTimeout = startupTimeout;

  final ScrcpyCommandRunner _commandRunner;
  final ScrcpyDeviceStreamConfig Function() _createConfig;
  final Duration _startupTimeout;

  @override
  Future<DeviceStream> start({
    required BridgeSession session,
    required DeviceStreamSink sink,
  }) async {
    final stream = ScrcpyDeviceStream(
      session: session,
      sink: sink,
      commandRunner: _commandRunner,
      config: _createConfig(),
      startupTimeout: _startupTimeout,
    );
    try {
      await stream.start();
      return stream;
    } catch (_) {
      await stream.close();
      rethrow;
    }
  }
}

/// Device stream backed by the official scrcpy Android server.
///
/// It owns:
/// - the ADB reverse tunnel from Android `localabstract:scrcpy_<scid>`
/// - the pushed scrcpy server file on the Android device
/// - the scrcpy server process started through `app_process`
/// - the video and control sockets created by the scrcpy server
///
/// Example:
/// When the browser opens the Device WebSocket, this stream starts scrcpy,
/// forwards raw H.264 Annex B bytes to the web app, and writes browser control
/// messages to the scrcpy control socket.
class ScrcpyDeviceStream implements DeviceStream {
  ScrcpyDeviceStream({
    required this.session,
    required this.sink,
    required ScrcpyCommandRunner commandRunner,
    required ScrcpyDeviceStreamConfig config,
    required Duration startupTimeout,
  })  : _commandRunner = commandRunner,
        _config = config,
        _startupTimeout = startupTimeout;

  final BridgeSession session;
  final DeviceStreamSink sink;
  final ScrcpyCommandRunner _commandRunner;
  final ScrcpyDeviceStreamConfig _config;
  final Duration _startupTimeout;
  final _deviceServerPath = '/data/local/tmp/scrcpy-server.jar';
  ServerSocket? _captureServer;
  Socket? _videoSocket;
  Socket? _controlSocket;
  ScrcpyServerProcess? _serverProcess;
  StreamSubscription<List<int>>? _videoSubscription;
  StreamSubscription<List<int>>? _controlSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  bool _closed = false;
  bool _runtimeFailed = false;
  Future<void> _controlWriteQueue = Future.value();

  /// Start scrcpy and emit `ready` after both video and control are connected.
  ///
  /// This method:
  /// 1. reads the Android display size with `adb shell wm size`
  /// 2. opens a local TCP server and maps it with `adb reverse`
  /// 3. pushes and starts the official scrcpy server through `app_process`
  /// 4. waits for the first scrcpy connection as video and the second as
  ///    control
  /// 5. starts forwarding H.264 bytes and sends ready metadata
  ///
  /// Returns:
  /// Nothing. Startup failures throw and are cleaned up by the factory.
  ///
  /// Example:
  /// The browser receives no `ready` message while only the video socket is
  /// connected. `ready` is sent only after the control socket is also usable.
  Future<void> start() async {
    sink.log('scrcpy server version=4.0');
    final screenSize = await _readScreenSize();
    final captureServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    _captureServer = captureServer;

    final videoConnected = Completer<Socket>();
    final controlConnected = Completer<Socket>();
    captureServer.listen((socket) {
      if (!videoConnected.isCompleted) {
        videoConnected.complete(socket);
        return;
      }
      if (!controlConnected.isCompleted) {
        controlConnected.complete(socket);
        return;
      }
      socket.destroy();
    });

    await _removeTunnel();
    await _commandRunner.run(_config.adbExecutable, [
      '-s',
      session.deviceId,
      'push',
      _config.serverPath,
      _deviceServerPath,
    ]);
    await _commandRunner.run(_config.adbExecutable, [
      '-s',
      session.deviceId,
      'reverse',
      'localabstract:scrcpy_${_config.scid}',
      'tcp:${captureServer.port}',
    ]);

    _serverProcess = _commandRunner.start(
      _config.adbExecutable,
      _serverArgs(),
    );
    _stderrSubscription = _serverProcess!.stderr.listen((chunk) {
      final message = utf8.decode(chunk, allowMalformed: true).trim();
      if (message.isNotEmpty) {
        sink.log('scrcpy stderr=$message');
      }
    }, onError: (Object error) {
      sink.log('scrcpy stderr error=$error');
    });

    _videoSocket = await _waitForStartupSocket(videoConnected, 'video');
    _controlSocket = await _waitForStartupSocket(controlConnected, 'control');
    _videoSubscription = _videoSocket!.listen(
      sink.sendVideoChunk,
      onDone: _failRuntime,
      onError: (_) => _failRuntime(),
    );
    _controlSubscription = _controlSocket!.listen(
      (_) {},
      onDone: _failRuntime,
      onError: (_) => _failRuntime(),
    );
    sink.sendReady(DeviceMetadata(
      deviceId: session.deviceId,
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
      maxFps: _config.maxFps,
      videoCodec: 'h264',
      controlReady: true,
    ));
  }

  /// Write one validated Device control message to the scrcpy control socket.
  ///
  /// Args:
  /// - `message`: JSON object already validated by `DeviceControlProtocol`.
  ///   Touch messages contain `action`, `pointerId`, coordinates, and screen
  ///   size. System key messages contain `key`.
  ///
  /// Returns:
  /// Nothing. Unknown values are ignored defensively because the WebSocket
  /// layer is responsible for returning `control-error` before this method is
  /// called.
  ///
  /// Example:
  /// `{type: "systemKey", key: "recents"}` writes key down and key up messages
  /// for Android `KEYCODE_APP_SWITCH`.
  @override
  Future<void> handleControl(Map<String, Object?> message) async {
    if (message['type'] == 'touch') {
      await _enqueueControlWrite([_buildTouchMessage(message)]);
      return;
    }

    if (message['type'] == 'systemKey') {
      final key = message['key'];
      final keyCode = switch (key) {
        'back' => 4,
        'home' => 3,
        'recents' => 187,
        _ => null,
      };
      if (keyCode == null) {
        return;
      }
      await _enqueueControlWrite([
        _buildKeyCodeMessage(action: 0, keyCode: keyCode),
        _buildKeyCodeMessage(action: 1, keyCode: keyCode),
      ]);
    }
  }

  /// Stop scrcpy and release all Device resources owned by this stream.
  ///
  /// This method:
  /// 1. cancels socket and stderr subscriptions
  /// 2. destroys video and control sockets
  /// 3. closes the local capture server
  /// 4. kills the scrcpy server process
  /// 5. removes the ADB reverse tunnel
  ///
  /// Returns:
  /// Nothing. Calling it more than once is safe.
  ///
  /// Example:
  /// Closing the browser Device WebSocket calls this method so a later retry
  /// can start a fresh scrcpy stream for the same bridge session.
  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _videoSubscription?.cancel();
    await _controlSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _videoSocket?.destroy();
    _controlSocket?.destroy();
    await _captureServer?.close();
    _serverProcess?.kill();
    await _removeTunnel();
  }

  /// Read the Android physical display size used for Device View coordinates.
  ///
  /// Returns:
  /// Width and height parsed from `adb shell wm size`.
  ///
  /// Example:
  /// `Physical size: 1080x2400` returns `width=1080` and `height=2400`.
  Future<_ScreenSize> _readScreenSize() async {
    final result = await _commandRunner.run(_config.adbExecutable, [
      '-s',
      session.deviceId,
      'shell',
      'wm',
      'size',
    ]);
    final match = RegExp(r'Physical size:\s*(\d+)x(\d+)').firstMatch(
      result.stdout,
    );
    if (match == null) {
      throw StateError('Could not read Android screen size.');
    }
    return _ScreenSize(
      width: int.parse(match.group(1)!),
      height: int.parse(match.group(2)!),
    );
  }

  Future<Socket> _waitForStartupSocket(
    Completer<Socket> socketCompleter,
    String socketName,
  ) {
    final serverProcess = _serverProcess;
    if (serverProcess == null) {
      throw StateError('scrcpy server process was not started.');
    }

    return Future.any([
      socketCompleter.future,
      serverProcess.exitCode.then<Socket>((exitCode) {
        throw StateError(
          'scrcpy exited before $socketName socket connected '
          'exitCode=$exitCode.',
        );
      }),
      Future<Socket>.delayed(_startupTimeout, () {
        throw StateError(
          'Timed out waiting for scrcpy $socketName socket.',
        );
      }),
    ]);
  }

  /// Remove the current ADB reverse tunnel if it exists.
  ///
  /// Returns:
  /// Nothing. Missing tunnels are ignored because cleanup runs before startup,
  /// after normal close, and after partial startup failure.
  ///
  /// Example:
  /// For `scid=abc123`, this removes `localabstract:scrcpy_abc123`.
  Future<void> _removeTunnel() async {
    await Future.wait([
      _commandRunner.run(_config.adbExecutable, [
        '-s',
        session.deviceId,
        'reverse',
        '--remove',
        'localabstract:scrcpy_${_config.scid}',
      ]).catchError((_) => const ScrcpyCommandResult(stdout: '')),
    ]);
  }

  /// Build the `adb shell app_process` arguments for the scrcpy server.
  ///
  /// Returns:
  /// A complete ADB argument list that starts official scrcpy 4.0 with raw
  /// H.264 video and the control socket enabled.
  ///
  /// Example:
  /// The returned list includes `raw_stream=true` so the video socket carries
  /// Annex B H.264 bytes instead of scrcpy frame metadata.
  List<String> _serverArgs() {
    final args = [
      '-s',
      session.deviceId,
      'shell',
      'CLASSPATH=$_deviceServerPath',
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      '4.0',
      'scid=${_config.scid}',
      'log_level=debug',
      'audio=false',
      'control=true',
      'raw_stream=true',
      if (_config.maxSize > 0) 'max_size=${_config.maxSize}',
      'max_fps=${_config.maxFps}',
      'video_bit_rate=${_config.videoBitRate}',
      'cleanup=false',
      'power_on=false',
    ];

    return args;
  }

  /// Encode one validated touch message as a scrcpy control packet.
  ///
  /// Args:
  /// - `message`: Validated `touch` control JSON. `cancel` is encoded as
  ///   `ACTION_UP` so the device releases the active pointer.
  ///
  /// Returns:
  /// A 32-byte `INJECT_TOUCH_EVENT` packet for the scrcpy control socket.
  ///
  /// Example:
  /// `{action: "cancel", pointerId: 7, x: 10, y: 21}` produces action `1`
  /// (`ACTION_UP`) with pressure `0`.
  List<int> _buildTouchMessage(Map<String, Object?> message) {
    final action = switch (message['action']) {
      'down' => 0,
      'up' || 'cancel' => 1,
      'move' => 2,
      _ => 1,
    };
    final pointerId = message['pointerId'] as int;
    final x = (message['x'] as num).round();
    final y = (message['y'] as num).round();
    final screenWidth = message['screenWidth'] as int;
    final screenHeight = message['screenHeight'] as int;
    final pressure = action == 1 ? 0 : 0xffff;
    final bytes = ByteData(32);
    var offset = 0;
    bytes.setUint8(offset, 2);
    offset += 1;
    bytes.setUint8(offset, action);
    offset += 1;
    bytes.setUint64(offset, pointerId);
    offset += 8;
    bytes.setInt32(offset, x);
    offset += 4;
    bytes.setInt32(offset, y);
    offset += 4;
    bytes.setUint16(offset, screenWidth);
    offset += 2;
    bytes.setUint16(offset, screenHeight);
    offset += 2;
    bytes.setUint16(offset, pressure);
    offset += 2;
    bytes.setUint32(offset, 0);
    offset += 4;
    bytes.setUint32(offset, 0);
    return bytes.buffer.asUint8List();
  }

  /// Encode one Android key action as a scrcpy control packet.
  ///
  /// Args:
  /// - `action`: Android key action, `0` for down and `1` for up.
  /// - `keyCode`: Android keycode such as `4` for Back or `187` for Recents.
  ///
  /// Returns:
  /// A 14-byte `INJECT_KEYCODE` packet for the scrcpy control socket.
  ///
  /// Example:
  /// Recents sends two packets: `action=0,keyCode=187` followed by
  /// `action=1,keyCode=187`.
  List<int> _buildKeyCodeMessage({
    required int action,
    required int keyCode,
  }) {
    final bytes = ByteData(14);
    var offset = 0;
    bytes.setUint8(offset, 0);
    offset += 1;
    bytes.setUint8(offset, action);
    offset += 1;
    bytes.setInt32(offset, keyCode);
    offset += 4;
    bytes.setInt32(offset, 0);
    offset += 4;
    bytes.setInt32(offset, 0);
    return bytes.buffer.asUint8List();
  }

  /// Write scrcpy control packets one at a time.
  ///
  /// Device WebSocket messages can arrive faster than `Socket.flush()`
  /// completes. Dart sockets reject overlapping sink writes in that state, so
  /// control packets are serialized through one Future chain.
  ///
  /// Args:
  /// - `packets`: Already encoded scrcpy control packets. A system key sends
  ///   two packets, key down followed by key up.
  ///
  /// Returns:
  /// Nothing. Write failures fail the Device session instead of escaping into
  /// the WebSocket listener.
  ///
  /// Example:
  /// Ten rapid pointer moves enqueue ten 32-byte touch packets and write them
  /// to the control socket in order.
  Future<void> _enqueueControlWrite(List<List<int>> packets) {
    final nextWrite = _controlWriteQueue.then((_) async {
      if (_closed || _runtimeFailed) {
        return;
      }
      final controlSocket = _controlSocket;
      if (controlSocket == null) {
        return;
      }

      try {
        for (final packet in packets) {
          controlSocket.add(packet);
        }
        await controlSocket.flush();
      } catch (error) {
        sink.log('scrcpy control write failed error=$error');
        _failRuntime();
      }
    });
    _controlWriteQueue = nextWrite.catchError((_) {});
    return nextWrite;
  }

  /// Fail the browser-visible Device session after a video or control error.
  ///
  /// Returns:
  /// Nothing. It sends one `device_failed` error, closes the WebSocket sink,
  /// and releases scrcpy resources. Repeated socket errors are ignored.
  ///
  /// Example:
  /// If the video socket closes while the browser is connected, the web app
  /// sees `device_failed` and can offer retry against the same bridge session.
  void _failRuntime() {
    if (_closed || _runtimeFailed) {
      return;
    }
    _runtimeFailed = true;
    sink.fail('device_failed', 'Device failed.');
    unawaited(sink.close());
    unawaited(close());
  }
}

class _StartedScrcpyServerProcess implements ScrcpyServerProcess {
  _StartedScrcpyServerProcess(Future<Process> process) : _process = process;

  final Future<Process> _process;

  @override
  Stream<List<int>> get stderr async* {
    yield* (await _process).stderr;
  }

  @override
  Future<int> get exitCode async {
    return (await _process).exitCode;
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    unawaited(_process.then((process) {
      process.kill(signal);
    }));
    return true;
  }
}

class _ScreenSize {
  const _ScreenSize({required this.width, required this.height});

  final int width;
  final int height;
}

/// Create an 8-character scrcpy socket id accepted by the Android server.
///
/// The official scrcpy 4.0 server parses `scid` with Java
/// `Integer.parseInt(value, 16)`, so values above `7fffffff` fail even though
/// they are valid unsigned 32-bit hex strings.
///
/// Args:
/// - `random`: Random source used to generate a positive 31-bit value. Tests
///   pass a deterministic random source to cover the upper bound.
///
/// Returns:
/// An 8-character lowercase hex string in the range `00000000..7fffffff`.
///
/// Example:
/// A generated integer value of `0x1234` returns `00001234`.
String createScrcpyScid({Random? random}) {
  final source = random ?? Random.secure();
  final value = source.nextInt(0x80000000);
  return value.toRadixString(16).padLeft(8, '0');
}
