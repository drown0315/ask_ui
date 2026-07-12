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
- the included Flutter debug demo application, which registers an MVP-only VM
  Service control extension;
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
  flutter_demo/
    lib/mvp_runtime_control.dart
    lib/main.dart
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

### Validated Capture Adaptation

The physical `screen_recorder` package is the proven starting point for device
discovery and `AVCaptureSession` lifecycle. The MVP retains its CoreMediaIO
screen-capture enablement, `AVCaptureDeviceInput`, and
`AVCaptureVideoDataOutput` setup. It replaces only the file sink:

```text
screen_recorder: CMSampleBuffer -> AVAssetWriter -> MOV file
iOS Screen MVP:  CMSampleBuffer -> VTCompressionSession -> Annex B stream
```

The MVP is real-time streaming. It does not create a MOV file or wait for a
recording to finish before delivering frames.

The Dart server remains the orchestration process. Go is not used in this
phase: Dart already owns the official `vm_service` integration, and binary
WebSocket forwarding is not the expected performance bottleneck.

### Device Discovery Contract

Device discovery crosses two different macOS boundaries:

- `xcrun xctrace list devices` reports connected Xcode development devices and
  their 40-character UDIDs;
- AVFoundation/CoreMediaIO reports recordable `AVCaptureDevice` instances and
  their capture-specific unique IDs.

An xctrace result proves that an iPhone is connected, but it is not itself a
video source and its UDID must not be assumed to equal
`AVCaptureDevice.uniqueID`. The final, physical-device-validated discovery flow
must:

1. compile the Swift helper once for the server process;
2. run `xcrun xctrace list devices` for connected-device metadata;
3. resolve a development UDID or device-name selector to an exact device name
   when possible;
4. pass an unmatched selector through as a possible AVFoundation capture ID;
5. start exactly one `stream` helper, including the device name only when
   xctrace resolved it;
6. let that same Swift process enable CoreMediaIO, wait for publication, match
   capture ID first and exact device name second, and own `AVCaptureSession`;
7. report `capture_device_not_found` only after bounded in-process discovery.

The server must not run helper `list` as a preflight before `stream`. Physical
testing showed that a successful short-lived AVFoundation discovery can be
followed by `capture_device_not_found` in a new process. Keeping discovery and
capture in the same stream helper avoids that cross-process publication issue.
The standalone `list` command remains a manual diagnostic only.

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

The runtime control extension lives inside the standalone Flutter demo, is
debug-only, and handles down, move, up, and cancel actions. It does not modify
the Ask UI runtime package during the spike. Gesture semantics remain primarily
in Flutter: the browser sends a pointer stream rather than high-level tap or
swipe commands. This lets Flutter recognizers decide whether a stream is a tap,
long press, drag, or scroll.

The browser still recognizes a long-press threshold for visible interaction
feedback, but it does not replace the pointer stream with a `longPress` command.

### Independent Lifecycles

Starting the iPhone screen capture can terminate or disconnect a Flutter debug
application the first time the capture device is activated. Video and control
therefore have independent lifecycles:

```text
Dart server lifetime
  -> one persistent CaptureSession
     -> zero or one BrowserSession
  -> zero or one replaceable ControlSession
```

The server starts capture initialization with the HTTP service and keeps
consuming the hot frame stream until server shutdown. HTTP remains available
while capture is connecting or failed so the browser can render diagnostics.
Browser disconnect cancels its active pointer and removes only the browser sink;
it does not restart or stop capture. A newly connected browser waits at most one
keyframe interval for a decodable IDR.

`--vm-service-uri` is optional. When supplied, the server attempts an initial
control attachment after capture starts, but attachment failure does not stop
capture or HTTP service. The normal first-activation workflow is:

1. start the server and let capture stabilize;
2. launch or relaunch the Flutter demo;
3. attach its current VM Service URI through `PUT /control`;
4. open or reconnect the browser.

The loopback-only control endpoint accepts:

```http
PUT /control
Content-Type: application/json

{"vmServiceUri":"http://127.0.0.1:62076/token=/"}
```

A successful response reports `{"state":"ready"}`. `DELETE /control` closes
the current VM Service connection without affecting video. Repeated `PUT`
atomically replaces the previous control backend after canceling any active
pointer. Invalid or unreachable URIs return a diagnostic response while the
previous ready backend, if any, remains usable.

WebSocket clients receive control state messages independently of video:

```json
{"type":"control","state":"unavailable"}
{"type":"control","state":"connecting"}
{"type":"control","state":"ready"}
```

Capture metadata may initially contain only video dimensions. When control
attaches, the server queries Flutter view dimensions, updates its logical
metadata, and sends a new `ready` message before reporting control `ready`.
Pointer messages received without a ready backend fail with
`runtime_control_unavailable` and never tear down the video session.

## Capture Helper

The helper supports these commands:

```text
ios_capture list
ios_capture stream --device-id ID --device-name NAME --max-fps 30 --bit-rate 6000000
```

`list` prints recordable iOS capture devices for manual diagnostics; the server
does not call it before streaming. `stream` performs its own discovery and
writes one metadata line followed by framed H.264 access units to stdout.
Diagnostics go only to stderr.
The Dart server owns the child process and forwards complete frame envelopes to
the browser WebSocket.

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

Browser disconnect closes its active pointer with `cancel` and removes its frame
sink. It does not stop capture or disconnect a ready control backend. Control
replacement or deletion cancels an active pointer before closing VM Service.
Server shutdown closes browser and control resources, stops the Swift helper and
its stdout stream, and releases the AVCapture device. Helper failure closes the
WebSocket after sending a diagnostic error. Browser and control reconnection are
manual in the MVP.

## Testing

Development follows vertical TDD slices through public boundaries.

Automated tests cover:

- capture-device list parsing;
- native stream frame-envelope parsing;
- H.264 Annex B access-unit handling and decoder configuration;
- video rectangle fitting and normalized coordinate mapping;
- click, long-press, swipe, and cancellation pointer sequences;
- malformed or out-of-range control messages;
- persistent capture across browser disconnect and reconnect;
- control attachment, replacement, failure isolation, and deletion;
- helper and VM Service cleanup at their owning lifecycle boundaries;
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
8. Closing and reopening the browser does not restart capture and receives a
   decodable keyframe within one second.
9. Missing, untrusted, permission-denied, and busy-device conditions produce a
   diagnostic page state.
10. A future `BluetoothHidControlBackend` can replace the runtime backend without
    changing the browser pointer protocol.
11. Capture remains live when Flutter exits; attaching the relaunched demo's new
    VM Service URI restores click, long press, and swipe without restarting the
    server or helper.
12. Server shutdown releases native capture and VM Service resources.

## Phase Two Boundary

Bluetooth HID is a separate spike. It may use a macOS Bluetooth helper or an
ESP32/nRF52840 USB dongle that exposes mouse, wheel/pan, and keyboard reports to
iOS. Phase two must first prove pairing, click, long-press, and scroll behavior
on the supported iOS range before it becomes an implementation commitment.

The phase-one runtime backend remains useful as the low-setup control path for
Flutter debug applications even if Bluetooth HID succeeds.
