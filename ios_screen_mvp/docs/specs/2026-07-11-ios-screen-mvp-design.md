# iOS Screen Web MVP Design

## Purpose

Build a standalone proof of concept that displays a physical iPhone screen in
a local web page and sends click, long-press, and single-finger swipe input back
to the running Flutter debug application.

The MVP validates two independent boundaries:

1. A physical iPhone screen can be captured through AVFoundation/CoreMediaIO,
   encoded as a low-latency H.264 stream, and rendered by a browser.
2. Browser pointer input can be translated into Flutter pointer events through
   the Dart VM Service without modifying Ask UI application code.

The project lives under `ios_screen_mvp/` and remains isolated from the Ask UI
web and bridge applications. The existing `screen_recorder` package is a source
reference only; the MVP owns its copied and adapted implementation.

## Scope

The first phase supports:

- a macOS host;
- one physical iPhone connected over USB;
- an unlocked iPhone that trusts the host Mac;
- a browser running on the same Mac;
- a Flutter debug application that registers `ask_ui_runtime`;
- live video, click, long-press, and single-finger swipe;
- one active browser/controller at a time.

The first phase does not support:

- arbitrary native or system iOS applications;
- WebDriverAgent;
- Bluetooth HID;
- audio, recording, remote network access, or multiple viewers;
- multi-touch, keyboard input, or system buttons;
- production packaging or integration into Ask UI sessions.

The second phase replaces only the control backend with Bluetooth HID to test
system-wide iOS control. The browser protocol and video pipeline remain stable.

## Project Structure

```text
ios_screen_mvp/
  native/
    ios_capture.swift
  server/
    bin/server.dart
    lib/video_stream.dart
    lib/control_backend.dart
    lib/flutter_runtime_control.dart
  web/
    src/IosScreenDemo.tsx
    src/video/
    src/gestures/
  docs/specs/
```

The page component composes the connection and rendering hooks. Video parsing,
gesture recognition, coordinate mapping, and control transport remain separate
modules with focused tests.

## Architecture

### Video

```text
USB iPhone
  -> CoreMediaIO screen capture device
  -> AVCaptureSession
  -> AVCaptureVideoDataOutput
  -> CMSampleBuffer / CVPixelBuffer
  -> VideoToolbox VTCompressionSession
  -> H.264 Annex B access units
  -> local Dart WebSocket server
  -> browser WebCodecs VideoDecoder
  -> canvas
```

The Swift helper adapts the physical iOS discovery and capture setup proven by
the reference `screen_recorder` package. It does not write a MOV file. It uses a
real-time VideoToolbox encoder with frame reordering disabled and emits Annex B
access units suitable for the existing style of WebCodecs pipeline.

The helper sends status separately from video bytes so logs cannot corrupt the
binary stream. The server owns helper startup, protocol parsing, browser fanout,
and cleanup.

### Control

```text
browser Pointer Events
  -> gesture state machine
  -> normalized pointer messages
  -> local WebSocket server
  -> Flutter VM Service extension
  -> Flutter logical coordinates
  -> Flutter PointerEvent dispatch
```

The runtime control extension is debug-only and handles down, move, up, and
cancel actions. Gesture semantics remain primarily in Flutter: the browser sends
a pointer stream rather than high-level tap or swipe commands. This lets Flutter
recognizers decide whether a stream is a tap, long press, drag, or scroll.

The browser still recognizes a long-press threshold for visible interaction
feedback, but it does not replace the pointer stream with a `longPress` command.

## Capture Helper

The helper supports these commands:

```text
ios_capture list
ios_capture stream --device-id ID --socket PATH --max-fps 30 --bit-rate 6000000
```

`list` prints recordable iOS capture devices. `stream` connects to a Unix domain
socket created by the Dart server and sends metadata followed by framed H.264
access units.

Initial encoder configuration:

- H.264 real-time encoding;
- H.264 Constrained Baseline profile;
- no B-frames;
- 30 FPS target;
- 6 Mbps average bit rate;
- one-second maximum keyframe interval;
- late capture frames discarded;
- old queued frames dropped instead of increasing latency.

Each IDR includes or is preceded by SPS and PPS. Resolution or orientation
changes produce new metadata and a new decoder configuration boundary.

## WebSocket Protocol

The browser connects to:

```text
ws://127.0.0.1:8765/session
```

The server sends ready metadata as JSON:

```json
{
  "type": "ready",
  "deviceId": "ios-capture-1",
  "screenWidth": 1170,
  "screenHeight": 2532,
  "logicalWidth": 390,
  "logicalHeight": 844,
  "devicePixelRatio": 3,
  "videoCodec": "h264",
  "controlBackend": "flutterRuntime"
}
```

Binary video messages use this framing:

```text
u32 big-endian payload length
u8 frame flags
u64 big-endian presentation timestamp in microseconds
H.264 Annex B access unit
```

Frame flags:

- `0x01`: keyframe;
- `0x02`: access unit contains SPS/PPS.

The browser sends normalized pointer messages:

```json
{
  "type": "pointer",
  "action": "down",
  "x": 0.42,
  "y": 0.31,
  "pointerId": 0
}
```

Supported actions are `down`, `move`, `up`, and `cancel`. Coordinates must be in
the inclusive range `[0, 1]`. The first phase accepts only pointer id `0`.

The server maps normalized coordinates to Flutter logical coordinates using the
runtime view dimensions. It does not infer the logical size only from the video
resolution because capture scaling and Retina density may differ.

## Web Interaction

The video occupies a stable phone-shaped canvas with aspect ratio derived from
metadata. Pointer events outside the fitted video rectangle are ignored.

Gesture behavior:

- click: down and up below the movement and duration thresholds;
- long press: down held for at least 600 ms without exceeding the movement
  threshold;
- swipe: down, zero or more coalesced move messages, then up;
- pointer cancellation: browser cancellation sends `cancel` before local state
  resets;
- one pointer owns the gesture until up or cancel.

Move events may be rate-limited to the video/control target frame rate, while
down, up, and cancel are never dropped.

## Errors And Cleanup

Errors are JSON messages:

```json
{
  "type": "error",
  "code": "capture_unavailable",
  "message": "No trusted physical iOS capture device found."
}
```

Stable first-phase error codes include:

- `capture_dependency_missing`;
- `capture_permission_denied`;
- `capture_device_not_found`;
- `capture_device_busy`;
- `capture_start_failed`;
- `video_encode_failed`;
- `vm_service_unavailable`;
- `runtime_control_unavailable`;
- `invalid_control_message`.

Browser disconnect closes its active pointer with `cancel`, disconnects the VM
Service client, stops the Swift helper, closes the Unix socket, and releases the
AVCapture device. Helper failure closes the WebSocket after sending a diagnostic
error. Reconnection is manual in the MVP.

## Testing

Development follows vertical TDD slices through public boundaries.

Automated tests cover:

- capture-device list parsing;
- native stream frame-envelope parsing;
- H.264 Annex B access-unit handling and decoder configuration;
- video rectangle fitting and normalized coordinate mapping;
- click, long-press, swipe, and cancellation pointer sequences;
- malformed or out-of-range control messages;
- helper and VM Service cleanup after browser disconnect;
- user-facing mapping of missing permission, missing device, and busy device
  failures.

Native encoding correctness receives a focused helper test where practical, but
real device support is established by a manual smoke test rather than mocks.

## Acceptance Criteria

The first phase is complete when:

1. Connecting an unlocked and trusted USB iPhone displays its live screen in the
   local browser page.
2. The page reports device connection state and real video dimensions.
3. A newly connected browser receives a decodable keyframe within one second.
4. Clicking a Flutter button through the video triggers the target action.
5. Holding for at least 600 ms triggers a Flutter long-press recognizer.
6. A single-finger swipe scrolls a Flutter `Scrollable` in the expected
   direction.
7. Input remains aligned after fitting the video into the browser viewport.
8. Closing the browser releases native capture and VM Service resources.
9. Missing, untrusted, permission-denied, and busy-device conditions produce a
   diagnostic page state.
10. A future `BluetoothHidControlBackend` can replace the runtime backend without
    changing the browser pointer protocol.

## Phase Two Boundary

Bluetooth HID is a separate spike. It may use a macOS Bluetooth helper or an
ESP32/nRF52840 USB dongle that exposes mouse, wheel/pan, and keyboard reports to
iOS. Phase two must first prove pairing, click, long-press, and scroll behavior
on the supported iOS range before it becomes an implementation commitment.

The phase-one runtime backend remains useful as the low-setup control path for
Flutter debug applications even if Bluetooth HID succeeds.
