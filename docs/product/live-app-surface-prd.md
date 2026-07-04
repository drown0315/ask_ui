# Live App Surface PRD

## Problem Statement

Ask UI currently has a workbench shell and bridge-backed Flutter Inspector session, but the center surface is not yet a real interactive Target Device. A developer needs to see the Android device or emulator that is running the inspected Flutter app, interact with it directly, and use that live context while selecting widgets and writing notes for an agent.

Without a real Live App Surface, Ask UI cannot close the loop between observing a UI issue, selecting the exact widget target, and handing useful visual/device context to the coding agent.

## Solution

Build the Live App Surface as a bridge-owned Android device stream under the existing bridge session. The web app opens a Device WebSocket for the ready bridge session, receives metadata and raw H.264 video from the bridge, decodes and renders the stream with WebCodecs, and sends touch/system-control events back over the same WebSocket.

The bridge owns Flutter device availability checks, Target Device binding consistency, scrcpy server lifecycle, ADB reverse/forward state, video/control sockets, and cleanup. The web app owns layout, Device View scaling, pointer coordinate mapping, WebCodecs decoding, user-visible state, and retry controls.

The first implementation should proceed through a Device WebSocket shell before connecting the real scrcpy/WebCodecs path. This fixes the protocol, UI states, metadata handling, and coordinate mapping before introducing the full video/control lifecycle.

## User Stories

1. As a Flutter developer, I want Ask UI to require a `deviceId` URL parameter, so that the workbench is bound to a concrete Target Device.
2. As a Flutter developer, I want the bridge to reject missing `deviceId`, so that I know the startup URL is incomplete.
3. As a Flutter developer, I want the bridge to check `flutter devices --machine`, so that Ask UI only starts for Android devices visible to Flutter.
4. As a Flutter developer, I want non-Android Flutter targets such as Chrome or macOS rejected, so that the Android/scrcpy Live App Surface does not fail later.
5. As a Flutter developer, I want unsupported Android devices rejected, so that I get an immediate Target Device error.
6. As a Flutter developer, I want device check failures separated from device-not-found failures, so that I can distinguish Flutter tooling problems from missing devices.
7. As a Flutter developer, I want bridge logs to include the device check command, error, and stack trace, so that I can diagnose local Flutter tooling failures.
8. As a Flutter developer, I want the same bridge session to remain bound to one Target Device, so that tabs or refreshes cannot silently switch devices.
9. As a Flutter developer, I want the TopBar to show device connection state and the real `deviceId`, so that I know which Target Device I am operating.
10. As a Flutter developer, I want the Live App Surface to show device connection states, so that I understand whether it is connecting, waiting for video, ready, or failed.
11. As a Flutter developer, I want Ask UI to automatically start the Live App Surface when the bridge session is ready, so that I do not need an extra start step.
12. As a Flutter developer, I want Surface retry to reuse the existing bridge session, so that a video/control failure does not reset the whole workbench.
13. As a Flutter developer, I want Device startup failures to show a retry path, so that I can recover after fixing local device state.
14. As a Flutter developer, I want runtime Surface disconnects to show a retry path, so that I can recover from transient device or socket failures.
15. As a Flutter developer, I want a clear WebCodecs unavailable error, so that I know the browser cannot run the first-version video path.
16. As a Flutter developer, I want the Device View to show the Target Device screen, so that I can inspect the app visually inside Ask UI.
17. As a Flutter developer, I want the Device View to scale the device screen to fit the available center surface, so that the whole app remains visible.
18. As a Flutter developer, I want small device views to be allowed to scale up, so that the app is easier to inspect and operate.
19. As a Flutter developer, I want letterboxed or empty areas ignored for touch input, so that accidental clicks outside the Device View do not reach the device.
20. As a Flutter developer, I want pointer coordinates mapped back to the device/video coordinate space, so that touches land where I clicked.
21. As a Flutter developer, I want device orientation or screen-size changes reflected in the Device View, so that coordinates remain correct after rotation.
22. As a Flutter developer, I want in-progress pointer gestures cancelled when metadata changes, so that stale coordinates do not produce incorrect touches.
23. As a Flutter developer, I want normal app interaction through pointer down/move/up/cancel events, so that taps, long presses, swipes, and drags feel natural.
24. As a Flutter developer, I want pointer move throttled to a practical rate, so that the device receives smooth input without overwhelming the connection.
25. As a Flutter developer, I want Back, Home, and Recents controls near the Device View, so that I can operate Android navigation without leaving Ask UI.
26. As a Flutter developer, I want Surface Controls disabled until device control is ready, so that unavailable commands cannot be clicked.
27. As a Flutter developer, I want Surface Controls to remain available during Select Widget mode, so that I can navigate the device while selecting UI targets.
28. As a Flutter developer, I want Select Widget mode to keep sending Device View pointer input to the Target Device, so that Flutter Inspector can select widgets through the running app.
29. As a Flutter developer, I do not want Back/Home/Recents to automatically exit Select Widget mode, so that navigation does not unexpectedly change my workbench tool mode.
30. As a Flutter developer, I want invalid control messages to return control errors without tearing down video, so that protocol mistakes do not unnecessarily kill the Surface.
31. As a Flutter developer, I want startup and runtime Surface errors to have stable error codes, so that the web app can display consistent failure states.
32. As a Flutter developer, I want detailed server logs available for debugging but not rendered as high-frequency UI, so that diagnostics do not harm video latency.
33. As a Flutter developer, I want low-latency video behavior that prioritizes the latest frame, so that interacting with the device feels responsive.
34. As a Flutter developer, I want the Device implementation to clean up scrcpy and ADB resources immediately on close, so that future connections do not get stuck behind stale sessions.
35. As a Flutter developer, I want only one active Device connection per bridge session in the first version, so that scrcpy lifecycle ownership is clear.
36. As a Flutter developer, I want a tested H.264 parser module, so that video decoding does not depend on one device's TCP chunk shape.

## Implementation Decisions

- Use the existing domain language: Target Device, Live App Surface, Device View, and Surface Controls.
- The URL startup contract requires `vmServiceUri`, `projectRoot`, and `deviceId`.
- `deviceId` is camelCase and no alternate query parameter names are supported.
- The bridge records `deviceId` on the bridge session and rejects repeated requests for the same Flutter app session with a different `deviceId`.
- Target Device availability is checked with `flutter devices --machine` for every session creation request.
- The availability check accepts only exact `deviceId` matches whose `targetPlatform` is Android.
- `deviceId` matching is case-sensitive after trimming leading and trailing whitespace.
- `targetPlatform` matching is case-insensitive against the `android` prefix.
- `isSupported == false` marks the Target Device unavailable.
- Missing `isSupported` means the Target Device is treated as available.
- Empty machine output lists use `target_device_not_found`.
- Flutter command failure, malformed JSON, or unexpected machine output uses `target_device_check_failed`.
- Device check failures log the command, `deviceId`, error, and stack trace, but HTTP responses do not expose stdout, stderr, environment variables, or the command.
- First-version Flutter executable selection uses `flutter` from the bridge process `PATH`; user-facing executable configuration is out of scope.
- TopBar device label states are `Device required`, `Connecting device`, `Device unavailable`, and `Device <deviceId>`.
- Live App Surface states use the same language, with ready Surface showing raw `<deviceId>` in the Device View context.
- Long device ids should truncate visually with the complete id available through tooltip/title behavior.
- The Live App Surface is the center workbench area and includes both Device View and Surface Controls.
- Device View is the video area that receives mapped pointer input.
- Surface Controls are the Back, Home, and Recents controls and are outside the Device View coordinate space.
- Back, Home, and Recents live below the Device View, not as an overlay on the video.
- Surface Controls remain available during Select Widget mode once control is ready.
- Back/Home/Recents do not automatically exit Select Widget mode.
- The Device WebSocket is under the existing bridge session and does not accept a separate `deviceId`.
- One bridge session allows one active Device WebSocket in the first version.
- A second active Device connection fails with `device_already_active`.
- One WebSocket carries both binary H.264 frames and text JSON protocol messages.
- Binary frames are raw H.264 Annex B chunks from scrcpy.
- Text JSON frames carry ready/metadata, control messages, logs, and errors.
- The bridge sends `ready` only after both video and control paths are ready.
- Ready metadata includes `deviceId`, `screenWidth`, `screenHeight`, `maxFps`, `videoCodec`, and `controlReady: true`.
- Later screen-size or orientation changes use a complete `metadata` message, not a partial diff.
- `screenWidth` and `screenHeight` come from bridge/device/video metadata, not canvas backing size or CSS layout.
- The web app computes Device View fit inside available space, maps pointer coordinates back to the `screenWidth/screenHeight` coordinate space, and ignores pointer events outside the visible Device View.
- Device orientation or metadata changes cancel in-progress pointer gestures.
- Touch control messages use string actions: `down`, `move`, `up`, and `cancel`.
- Web and bridge should define protocol action types centrally rather than scattering string literals.
- Bridge maps `cancel` to the same release behavior as `up`.
- Long press and swipe are not separate protocol events; they are expressed through the pointer stream.
- Pointer move is throttled around 16ms.
- Pointer id range is `0..0xffffffff`.
- Touch coordinates are valid in the inclusive ranges `0..screenWidth` and `0..screenHeight`.
- Out-of-range touch coordinates return `control-error`, not clamped input.
- Invalid `screenWidth/screenHeight` returns `control-error`.
- System key messages use `systemKey` with `back`, `home`, and `recents`.
- Bridge maps `recents` to the Android app-switch key behavior internally.
- Invalid control messages return `control-error` and do not close the Device WebSocket.
- Underlying video or control socket failures fail the whole Device session.
- Device startup failures use `device_start_failed`.
- Device runtime failures use `device_failed`.
- Device WebSocket close or startup cancellation triggers immediate scrcpy server, socket, ADB reverse/forward, parser, buffer, and Device state cleanup.
- The bridge uses a project-controlled official scrcpy server jar, not a desktop scrcpy CLI window.
- Scrcpy server version is logged by bridge but not included in Surface ready metadata.
- WebCodecs is the only first-version decode path; no MSE/fMP4 fallback is included.
- Web owns Annex B parsing and access-unit assembly in a media module rather than inside a React component.
- Low-latency decoding prioritizes the latest frame and may drop delta access units when decode queue pressure grows.
- Device implementation should start with a WebSocket shell that sends fake metadata and validates control messages, then connect the real scrcpy/WebCodecs stream.

## Testing Decisions

- Tests should verify externally observable behavior: HTTP/WebSocket responses, protocol messages, rendered states, coordinate mapping outputs, cleanup effects, and error codes. Avoid tests that depend on private helper names or internal state not visible at module boundaries.
- The Target Device availability checker should be tested with machine JSON fixtures covering Android success, non-Android rejection, exact `deviceId` matching, unsupported devices, malformed output, command failure, missing `isSupported`, and case-sensitive id matching.
- Bridge session tests should cover required `deviceId`, trimming, session reuse for the same Target Device, and `device_mismatch_for_session` for conflicting Target Devices.
- Bridge server tests should cover `target_device_not_found`, `target_device_unavailable`, `target_device_check_failed`, and creation success using a fake device checker.
- Device WebSocket shell tests should cover single active connection, ready metadata, metadata update, unsupported control type, invalid JSON, invalid touch fields, invalid system keys, and the fact that `control-error` does not close the socket.
- Surface lifecycle tests should cover startup cancellation, WebSocket close cleanup, startup failure cleanup, runtime failure cleanup, and second connection rejection.
- Web protocol tests should cover parsing ready/metadata messages, Surface state transitions, retry behavior, disconnected behavior, and WebCodecs unavailable behavior.
- Web layout tests should cover Device View fit calculations, allowed upscaling, letterbox hit rejection, long `deviceId` truncation behavior, and metadata-driven remapping.
- Web input tests should cover pointer down/move/up/cancel payload generation, move throttling, coordinate remapping, gesture cancellation on metadata changes, and disabled Surface Controls before `controlReady`.
- Web H.264 media tests should cover Annex B start codes, NAL splitting across chunks, SPS/PPS handling, IDR access-unit assembly, queue pressure/drop behavior, and malformed stream handling.
- Prior art exists in bridge session/server tests for HTTP API behavior, web session bootstrap tests for URL parsing, and widget-tree tests for focused transformation modules.
- H.264 parser tests should prefer saved real `.h264` samples from the calibration work; if samples are not available, byte fixtures should cover the critical parsing behavior.
- Playwright/browser verification should be used before claiming the Live App Surface UI works visually, especially for scaled Device View layout and non-overlapping Surface Controls.

## Out of Scope

- Strict proof that `vmServiceUri` came from the same Android device as `deviceId`.
- Automatic Surface reconnect.
- Device startup timeout policy for `flutter devices --machine`.
- User-facing configuration for Flutter executable path.
- Multiple simultaneous Device WebSocket clients or fan-out.
- MSE/fMP4, WebRTC, Broadway, or TinyH264 fallback paths.
- Multi-touch, keyboard text input, mouse wheel, power button, menu button, and additional Android system controls beyond Back/Home/Recents.
- Desktop, web, iOS, or non-Android Target Devices.
- Rendering high-frequency performance diagnostics in the primary UI.
- Agent handoff, note persistence, selected bounds overlays, and comment workflow changes beyond preserving compatibility with the Live App Surface.
- Full production packaging of the scrcpy server jar if a narrower tracer bullet only proves the protocol shell.

## Further Notes

- The current calibration documents support the WebCodecs + official scrcpy server route and warn against treating TCP chunks as video frames.
- The first-version availability check is intentionally less strict than a true VM Service/device binding verification.
- The implementation should preserve bridge ownership of ADB and scrcpy lifecycle. The web app should never directly run ADB or encode scrcpy binary control messages.
- The PRD respects the accepted ADRs for bridge-owned Android device and the Live App Surface Device WebSocket protocol.
