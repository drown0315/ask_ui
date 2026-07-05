import 'dart:async';

import '../sessions/session_store.dart';

/// Metadata sent to the web app when a Device stream becomes usable.
///
/// It contains:
/// - the Target Device id bound to the bridge session
/// - the video coordinate space used by pointer mapping
/// - the first-version H.264/WebCodecs stream settings
///
/// Example:
/// A Pixel-sized stream may report `screenWidth=1080` and
/// `screenHeight=2400`. The web app fits that rectangle into the Device View
/// and maps browser pointer coordinates back into this coordinate space.
class DeviceMetadata {
  const DeviceMetadata({
    required this.deviceId,
    required this.screenWidth,
    required this.screenHeight,
    required this.maxFps,
    required this.videoCodec,
    required this.controlReady,
  });

  final String deviceId;
  final int screenWidth;
  final int screenHeight;
  final int maxFps;
  final String videoCodec;
  final bool controlReady;

  /// Convert the metadata into the Device WebSocket JSON payload shape.
  ///
  /// Returns:
  /// A flat JSON map that can be merged with a message `type`, such as
  /// `ready` or `metadata`.
  ///
  /// Example:
  /// `DeviceMetadata(deviceId: "emulator-5554", ...)` becomes a JSON object
  /// with `deviceId`, `screenWidth`, `screenHeight`, `maxFps`, `videoCodec`,
  /// and `controlReady`.
  Map<String, Object?> toJson() {
    return {
      'deviceId': deviceId,
      'screenWidth': screenWidth,
      'screenHeight': screenHeight,
      'maxFps': maxFps,
      'videoCodec': videoCodec,
      'controlReady': controlReady,
    };
  }
}

/// Output boundary from a bridge-owned Device stream to the WebSocket server.
///
/// Implementations decide how to deliver each event. The production server
/// writes JSON and binary frames to the browser; tests record the same calls
/// without opening a real WebSocket.
///
/// Example:
/// A scrcpy stream calls `sendReady()` after video and control sockets are
/// connected, then calls `sendVideoChunk()` for each raw H.264 Annex B chunk.
abstract interface class DeviceStreamSink {
  void sendReady(DeviceMetadata metadata);

  void sendMetadata(DeviceMetadata metadata);

  void sendVideoChunk(List<int> bytes);

  void fail(String error, String message);

  void log(String message);

  Future<void> close();
}

/// One active Device stream owned by a bridge session.
///
/// It receives already-validated control JSON from the Device WebSocket and
/// owns any resources needed to serve video and input for that session.
///
/// Example:
/// The scrcpy implementation owns the ADB reverse tunnel, scrcpy server
/// process, video socket, and control socket until `close()` is called.
abstract interface class DeviceStream {
  Future<void> handleControl(Map<String, Object?> message);

  Future<void> close();
}

/// Starts a Device stream for one bridge session.
///
/// The server uses this interface so tests can inject shell or fake streams,
/// while production uses the scrcpy-backed stream.
///
/// Example:
/// `AskUiBridgeServer` calls `start(session: session, sink: sink)` when the
/// browser opens `/api/sessions/{sessionId}/device`.
abstract interface class DeviceStreamFactory {
  Future<DeviceStream> start({
    required BridgeSession session,
    required DeviceStreamSink sink,
  });
}

/// Test and shell Device stream that sends fixed metadata without real video.
///
/// This keeps earlier Device WebSocket behavior available for tests and debug
/// metadata paths while the production default can use scrcpy.
class ShellDeviceStreamFactory implements DeviceStreamFactory {
  const ShellDeviceStreamFactory();

  @override
  Future<DeviceStream> start({
    required BridgeSession session,
    required DeviceStreamSink sink,
  }) async {
    sink.sendReady(DeviceMetadata(
      deviceId: session.deviceId,
      screenWidth: 1080,
      screenHeight: 2400,
      maxFps: 60,
      videoCodec: 'h264',
      controlReady: true,
    ));
    return const ShellDeviceStream();
  }
}

/// No-op Device stream used when the server only needs protocol shell behavior.
class ShellDeviceStream implements DeviceStream {
  const ShellDeviceStream();

  @override
  Future<void> handleControl(Map<String, Object?> message) async {}

  @override
  Future<void> close() async {}
}

/// Device stream factory that sends one embedded H.264 Annex B chunk.
///
/// The fixture path exercises the browser WebCodecs pipeline without requiring
/// ADB, scrcpy, or a connected Android device.
class FixtureH264DeviceStreamFactory implements DeviceStreamFactory {
  const FixtureH264DeviceStreamFactory({required this.chunk});

  final List<int> chunk;

  @override
  Future<DeviceStream> start({
    required BridgeSession session,
    required DeviceStreamSink sink,
  }) async {
    sink.sendReady(DeviceMetadata(
      deviceId: session.deviceId,
      screenWidth: 16,
      screenHeight: 16,
      maxFps: 60,
      videoCodec: 'h264',
      controlReady: true,
    ));
    sink.sendVideoChunk(chunk);
    return const ShellDeviceStream();
  }
}
