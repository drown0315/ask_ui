# iOS Screen Web MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone macOS MVP that streams a USB iPhone screen to a local web page and controls an included Flutter debug demo with click, long-press, and single-finger swipe.

**Architecture:** A Swift helper discovers the iPhone as an AVFoundation/CoreMediaIO capture device and emits framed H.264 Annex B access units. A Dart local server owns the helper process, exposes one WebSocket, and forwards normalized pointer messages to a VM Service extension in the standalone Flutter demo. The browser uses WebCodecs and a canvas; the control backend is replaceable by Bluetooth HID in a later phase.

**Tech Stack:** Swift 5 + AVFoundation/CoreMediaIO/VideoToolbox, Dart (`shelf`, `shelf_web_socket`, `vm_service`), Vite + React + TypeScript, browser WebCodecs, Flutter debug demo.

---

## File Map

Create all MVP files below; do not modify `apps/web`, `apps/bridge`, or
`packages/ask_ui_runtime`.

- `ios_screen_mvp/native/ios_capture.swift`: device discovery, capture session,
  VideoToolbox encoding, binary stdout protocol.
- `ios_screen_mvp/server/pubspec.yaml`: Dart server dependencies and scripts.
- `ios_screen_mvp/server/bin/server.dart`: CLI entry point and lifecycle.
- `ios_screen_mvp/server/lib/protocol.dart`: metadata, frame envelope, and
  pointer validation/serialization.
- `ios_screen_mvp/server/lib/video_stream.dart`: Swift helper process startup,
  stdout frame parsing, and error translation.
- `ios_screen_mvp/server/lib/flutter_runtime_control.dart`: VM Service client and
  pointer extension calls.
- `ios_screen_mvp/server/lib/mvp_server.dart`: HTTP static serving and WebSocket
  session orchestration.
- `ios_screen_mvp/server/test/protocol_test.dart`: protocol behavior tests.
- `ios_screen_mvp/server/test/gesture_control_test.dart`: control backend tests.
- `ios_screen_mvp/web/package.json`, `vite.config.ts`, `index.html`: web app.
- `ios_screen_mvp/web/src/main.tsx`, `IosScreenDemo.tsx`, `IosScreenDemo.css`:
  page composition and status/error UI.
- `ios_screen_mvp/web/src/video/h264AnnexB.ts`, `deviceVideoPipeline.ts`:
  Annex B parser and WebCodecs adapter.
- `ios_screen_mvp/web/src/gestures/pointerGestureState.ts`: pointer sequence and
  long-press state machine.
- `ios_screen_mvp/web/src/geometry/deviceViewGeometry.ts`: fitted canvas and
  normalized coordinate mapping.
- `ios_screen_mvp/web/src/**/*.test.ts`: focused browser tests.
- `ios_screen_mvp/flutter_demo/pubspec.yaml`, `lib/main.dart`,
  `lib/mvp_runtime_control.dart`: standalone debug target and VM extension.
- `ios_screen_mvp/README.md`: prerequisites, commands, troubleshooting, and
  manual acceptance checklist.

### Task 1: Scaffold the standalone workspace and protocol tests

**Files:**
- Create: `ios_screen_mvp/server/pubspec.yaml`
- Create: `ios_screen_mvp/server/lib/protocol.dart`
- Create: `ios_screen_mvp/server/test/protocol_test.dart`
- Create: `ios_screen_mvp/web/package.json`
- Create: `ios_screen_mvp/web/vite.config.ts`
- Create: `ios_screen_mvp/web/index.html`
- Create: `ios_screen_mvp/web/src/main.tsx`
- Create: `ios_screen_mvp/flutter_demo/pubspec.yaml`
- Create: `ios_screen_mvp/README.md`

- [ ] **Step 1: Write protocol tests first.** Test that ready metadata round
  trips with `screenWidth`, `logicalWidth`, `devicePixelRatio`, and
  `controlBackend`; pointer actions accept only `down|move|up|cancel`, pointer
  id `0`, and normalized coordinates; invalid JSON, actions, ids, and bounds
  produce stable error codes; binary frame parsing rejects truncated headers.

- [ ] **Step 2: Run the tests and verify RED.**

Run: `cd ios_screen_mvp/server && dart test test/protocol_test.dart`

Expected: FAIL because the protocol types and parser do not exist.

- [ ] **Step 3: Implement the minimal protocol types.** Define immutable
  `DeviceMetadata`, `PointerMessage`, `ControlError`, and `VideoFrameEnvelope`.
  Encode metadata and errors as JSON. Parse the 13-byte video header as
  big-endian `u32 length`, `u8 flags`, and `u64 ptsMicros`, then require exactly
  `length` payload bytes.

- [ ] **Step 4: Run the tests and verify GREEN.**

Run: `cd ios_screen_mvp/server && dart test test/protocol_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the standalone skeleton.**

Run: `git add ios_screen_mvp && git commit -m "feat: scaffold ios screen mvp"`

### Task 2: Add the Flutter debug control target

**Files:**
- Create: `ios_screen_mvp/flutter_demo/lib/mvp_runtime_control.dart`
- Create: `ios_screen_mvp/flutter_demo/lib/main.dart`
- Modify: `ios_screen_mvp/flutter_demo/pubspec.yaml`
- Create: `ios_screen_mvp/server/lib/flutter_runtime_control.dart`
- Create: `ios_screen_mvp/server/test/gesture_control_test.dart`

- [ ] **Step 1: Write the control contract tests.** Use a fake VM Service
  adapter to assert that a normalized `down`, `move`, `up`, and `cancel` sequence
  is converted to logical coordinates using the metadata dimensions, and that
  a rejected extension response becomes `runtime_control_unavailable`.

- [ ] **Step 2: Run the focused test and verify RED.**

Run: `cd ios_screen_mvp/server && dart test test/gesture_control_test.dart`

Expected: FAIL because the adapter and fake are not defined.

- [ ] **Step 3: Implement the debug-only Flutter extension.** Register
  `ext.ios_screen_mvp.pointer` with `dart:developer.registerExtension` inside an
  `assert` block. Decode `action`, `x`, `y`, and `pointerId`; map normalized values
  to `logicalWidth/logicalHeight`; dispatch `PointerDownEvent`,
  `PointerMoveEvent`, `PointerUpEvent`, or `PointerCancelEvent` through
  `GestureBinding.instance.handlePointerEvent`. Reject malformed messages with
  a JSON error. Build a demo app containing a button, a long-press target, and a
  scrollable list so each acceptance gesture has an observable result.

- [ ] **Step 4: Implement the Dart VM Service adapter.** Connect to the demo
  `vmServiceUri`, find the main isolate, call `ext.ios_screen_mvp.pointer` with
  JSON parameters, and expose a small `FlutterRuntimeControl` interface so tests
  never depend on a live device.

- [ ] **Step 5: Run tests and compile the demo.**

Run: `cd ios_screen_mvp/server && dart test test/gesture_control_test.dart`

Expected: PASS.

Run: `cd ios_screen_mvp/flutter_demo && flutter analyze`

Expected: no analyzer errors.

- [ ] **Step 6: Commit the control slice.**

Run: `git add ios_screen_mvp/flutter_demo ios_screen_mvp/server && git commit -m "feat: add flutter runtime pointer control"`

### Task 3: Build the native iOS capture helper

**Files:**
- Create: `ios_screen_mvp/native/ios_capture.swift`
- Create: `ios_screen_mvp/server/lib/video_stream.dart`
- Modify: `ios_screen_mvp/server/lib/protocol.dart`
- Create: `ios_screen_mvp/server/test/video_stream_test.dart`

- [ ] **Step 1: Write helper and discovery tests.** Feed a fake helper byte stream
  containing a metadata line and complete/truncated frame envelopes. Assert
  complete frames are emitted in order, a truncated frame reports
  `capture_start_failed`, and stderr text is retained as diagnostics. Test
  xctrace parsing separately from recordable helper output. Test selector
  resolution by capture ID, development UDID, exact name, and name prefix, and
  reject ambiguous duplicate names.

- [ ] **Step 2: Run tests and verify RED.**

Run: `cd ios_screen_mvp/server && dart test test/video_stream_test.dart`

Expected: FAIL because the helper stream parser is missing.

- [ ] **Step 3: Implement Swift device discovery.** Copy only the relevant
  discovery logic from `screen_recorder` and keep the `iOS Device` plus
  `Apple Inc.` filter. Add `list` output with machine-readable tab-separated
  `id`, `name`, `model`, and `manufacturer`. Set
  `kCMIOHardwarePropertyAllowScreenCaptureDevices` before discovery. For
  `stream`, accept both `--device-id` and `--device-name`, match capture ID
  first and exact name second, and poll discovery for a bounded interval rather
  than relying on one fixed sleep. Reject duplicate name matches.

- [ ] **Step 4: Implement Swift streaming.** Retain the proven
  `screen_recorder` `AVCaptureSession`, `AVCaptureDeviceInput`, and
  `AVCaptureVideoDataOutput` lifecycle, but replace `AVAssetWriter` with a
  real-time stream. Add `stream --device-id --device-name --max-fps --bit-rate`
  arguments. Configure `AVCaptureSession` and
  `AVCaptureVideoDataOutput` with late-frame discarding. Create a
  `VTCompressionSession`, set realtime/no-reordering/Constrained Baseline
  properties, convert AVCC NAL lengths to Annex B start codes, prepend SPS/PPS
  to IDR frames, and write metadata plus the 13-byte frame envelope to stdout.
  Write diagnostics only to stderr. On SIGTERM stop capture and exit cleanly.

- [ ] **Step 5: Implement Dart discovery, helper startup, and parsing.** Compile
  the Swift file with `swiftc` into a temp executable once. Run helper `list`
  for recordable capture devices and `xcrun xctrace list devices` for connected
  development devices. Resolve the CLI selector without treating an xctrace
  UDID as an AVFoundation capture ID, then launch `stream` with the selected ID
  and name. Parse metadata and frame bytes, expose
  `Stream<VideoFrameEnvelope>`, and terminate the process on cancellation.
  Translate missing executable, permission, busy device, discovery mismatch,
  and non-zero helper exit into stable error codes with both discovery outputs
  retained as diagnostics.

- [ ] **Step 6: Run parser tests and a compile-only native check.**

Run: `cd ios_screen_mvp/server && dart test test/video_stream_test.dart`

Expected: PASS.

Run: `swiftc -parse-as-library ios_screen_mvp/native/ios_capture.swift -o /tmp/ios_screen_mvp_capture`

Expected: successful compilation on macOS with Xcode command-line tools.

- [ ] **Step 7: Commit the capture slice.**

Run: `git add ios_screen_mvp/native ios_screen_mvp/server && git commit -m "feat: stream ios capture frames"`

### Task 4: Implement the local WebSocket server

**Files:**
- Create: `ios_screen_mvp/server/lib/mvp_server.dart`
- Create: `ios_screen_mvp/server/bin/server.dart`
- Modify: `ios_screen_mvp/server/lib/video_stream.dart`
- Modify: `ios_screen_mvp/server/lib/flutter_runtime_control.dart`
- Create: `ios_screen_mvp/server/test/mvp_server_test.dart`

- [ ] **Step 1: Write server contract tests.** Assert one WebSocket client
  receives `ready`, then binary frame messages; pointer JSON is validated and
  forwarded; a second client receives `controller_busy`; disconnect sends a
  pointer cancel and closes both helper and VM Service fakes.

- [ ] **Step 2: Run tests and verify RED.**

Run: `cd ios_screen_mvp/server && dart test test/mvp_server_test.dart`

Expected: FAIL because the server does not exist.

- [ ] **Step 3: Implement the server.** Serve the built web directory, expose
  `/session` through `shelf_web_socket`, enforce one controller, start the video
  stream and runtime control on the first connection, send ready metadata and
  framed binary messages, and close all resources in a `finally` path. Accept
  `--vm-service-uri`, `--device-id`, `--web-root`, and `--port` CLI flags.

- [ ] **Step 4: Run server tests and commit.**

Run: `cd ios_screen_mvp/server && dart test test/mvp_server_test.dart`

Expected: PASS.

Run: `git add ios_screen_mvp/server && git commit -m "feat: add ios mvp websocket server"`

### Task 5: Implement the browser video and geometry path

**Files:**
- Create: `ios_screen_mvp/web/src/video/h264AnnexB.ts`
- Create: `ios_screen_mvp/web/src/video/deviceVideoPipeline.ts`
- Create: `ios_screen_mvp/web/src/geometry/deviceViewGeometry.ts`
- Create: `ios_screen_mvp/web/src/IosScreenDemo.tsx`
- Create: `ios_screen_mvp/web/src/IosScreenDemo.css`
- Modify: `ios_screen_mvp/web/src/main.tsx`
- Create: `ios_screen_mvp/web/src/video/deviceVideoPipeline.test.ts`
- Create: `ios_screen_mvp/web/src/geometry/deviceViewGeometry.test.ts`

- [ ] **Step 1: Write browser tests.** Test Annex B NAL splitting and access
  unit assembly, keyframe/configuration detection, fitted phone rectangle
  calculation, and rejection of pointer coordinates outside that rectangle.

- [ ] **Step 2: Run tests and verify RED.**

Run: `cd ios_screen_mvp/web && npm test -- --run`

Expected: FAIL because the modules do not exist.

- [ ] **Step 3: Implement the parser and WebCodecs pipeline.** Reuse the proven
  Ask UI Annex B parsing behavior as an independent copy. Configure
  `VideoDecoder` on SPS/PPS codec changes, drop stale delta frames when the
  decode queue grows, close decoded frames after canvas rendering, and show a
  clear unsupported-browser state when WebCodecs is unavailable.

- [ ] **Step 4: Implement geometry and page composition.** Fit the video into a
  stable phone viewport using metadata aspect ratio, map `clientX/clientY` to
  normalized coordinates, render connection/error/FPS status, and keep the
  canvas non-resizable while metadata changes.

- [ ] **Step 5: Run browser tests and build.**

Run: `cd ios_screen_mvp/web && npm test -- --run`

Expected: PASS.

Run: `cd ios_screen_mvp/web && npm run build`

Expected: production bundle created under `web/dist`.

- [ ] **Step 6: Commit the browser video slice.**

Run: `git add ios_screen_mvp/web && git commit -m "feat: render ios h264 stream in web"`

### Task 6: Add pointer gesture transport

**Files:**
- Create: `ios_screen_mvp/web/src/gestures/pointerGestureState.ts`
- Modify: `ios_screen_mvp/web/src/IosScreenDemo.tsx`
- Create: `ios_screen_mvp/web/src/gestures/pointerGestureState.test.ts`
- Modify: `ios_screen_mvp/web/src/IosScreenDemo.css`

- [ ] **Step 1: Write gesture tests.** Assert one pointer produces down/move/up;
  a pointer held for 600 ms remains down until up; movement beyond the cancel
  threshold prevents accidental tap feedback; a browser `pointercancel` emits
  cancel; a second pointer is ignored.

- [ ] **Step 2: Run tests and verify RED.**

Run: `cd ios_screen_mvp/web && npm test -- --run src/gestures/pointerGestureState.test.ts`

Expected: FAIL because the state machine is missing.

- [ ] **Step 3: Implement the state machine.** Capture the pointer on down,
  throttle move messages to 30 FPS, never drop down/up/cancel, use a 12 CSS-pixel
  movement threshold and 600 ms long-press timer, and reset state on socket
  close. Send only normalized protocol messages.

- [ ] **Step 4: Connect it to the canvas and verify.** Render long-press and
  connection indicators without changing canvas dimensions; run the gesture
  tests and production build.

- [ ] **Step 5: Commit the interaction slice.**

Run: `git add ios_screen_mvp/web && git commit -m "feat: send ios mvp pointer gestures"`

### Task 7: Integrate and perform the real-device smoke test

**Files:**
- Modify: `ios_screen_mvp/README.md`
- Modify: `ios_screen_mvp/server/bin/server.dart`
- Modify: `ios_screen_mvp/web/package.json`

- [ ] **Step 1: Add reproducible commands.** Document Xcode command-line tools,
  USB trust, camera permission, Flutter demo launch with VM Service, web build,
  server startup, and expected device discovery output. Document that QuickTime
  or other capture clients must be closed.

- [ ] **Step 2: Run all automated tests.**

Run: `cd ios_screen_mvp/server && dart test`

Expected: PASS.

Run: `cd ios_screen_mvp/web && npm test -- --run && npm run build`

Expected: PASS and a production bundle in `web/dist`.

Run: `cd ios_screen_mvp/flutter_demo && flutter analyze`

Expected: no analyzer errors.

- [ ] **Step 3: Run the manual device flow.** Connect and trust an iPhone,
  launch the Flutter demo in debug mode, start the server with its VM Service
  URI and capture device id, open the local page, and verify ready metadata,
  moving video, button click, long press, and scroll. Record actual FPS, first
  frame latency, and pointer alignment in the README.

- [ ] **Step 4: Exercise failure paths.** Lock the phone, revoke camera
  permission, start QuickTime, disconnect USB, and close the browser. Confirm
  each produces the documented error and that no Swift helper or server child
  process remains.

- [ ] **Step 5: Commit the verified MVP.**

Run: `git add ios_screen_mvp && git commit -m "feat: verify ios screen web mvp"`

## Self-Review

- The plan covers capture, H.264 framing, WebCodecs rendering, coordinate
  mapping, all four pointer actions, VM Service control, cleanup, diagnostics,
  and the documented Bluetooth HID replacement boundary.
- The plan does not modify Ask UI applications or the runtime package.
- No task depends on Bluetooth HID, WDA, iPhone Mirroring, or ReplayKit.
- All tests exercise public parser, state-machine, server, and adapter
  interfaces; real capture remains a manual hardware check.
- The plan contains no unresolved TODO/TBD placeholders.
