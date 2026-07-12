# iOS Screen Web MVP

This standalone macOS proof of concept streams a trusted USB iPhone to a local
browser and forwards pointer input to the included Flutter debug application.
It does not modify Ask UI applications or `packages/ask_ui_runtime`.

## Prerequisites

- macOS with Xcode Command Line Tools (`xcode-select --install`)
- Flutter and Dart on `PATH`
- Node.js 20 or newer
- Chrome or another browser with WebCodecs H.264 support
- an unlocked USB iPhone that trusts this Mac
- Camera permission for the terminal application running the helper

Close QuickTime Player, OBS, and other applications that may own the iPhone
capture device. In System Settings, enable the terminal under **Privacy &
Security > Camera** if macOS requests access.

## Install And Verify

From the repository root:

```sh
cd ios_screen_mvp/server
dart pub get
dart test

cd ../web
npm install
npm run verify

cd ../flutter_demo
flutter pub get
flutter analyze
```

Compile the native helper and list recordable devices:

```sh
cd /path/to/ask_ui
swiftc -parse-as-library ios_screen_mvp/native/ios_capture.swift \
  -o /tmp/ios_screen_mvp_capture
/tmp/ios_screen_mvp_capture list
```

Expected output has a header and one row per trusted iPhone:

```text
id	name	model	manufacturer
<device-id>	<phone-name>	iOS Device	Apple Inc.
```

An empty list means AVFoundation does not currently expose a trusted physical
iOS screen capture device. Unlock the phone, confirm USB trust, reconnect it,
and check Camera permission before retrying.

## Run

Build the browser client, then start capture before launching Flutter:

```sh
cd ios_screen_mvp/web
npm run build

cd ../server
dart run bin/server.dart \
  --device-id '<capture-id, Flutter UDID, device name, or name prefix>' \
  --web-root ../web/dist \
  --port 8765
```

Open `http://127.0.0.1:8765` and confirm that video is live. The first capture
activation can terminate an already-running Flutter debug app, which is why
capture starts first and remains owned by the server.

Launch the included Flutter app on the iPhone in another terminal:

```sh
cd ios_screen_mvp/flutter_demo
flutter devices
flutter run -d '<flutter-device-id>'
```

Keep `flutter run` active, copy its VM Service URI, and attach control without
restarting capture or the browser:

```sh
curl -X PUT http://127.0.0.1:8765/control \
  -H 'content-type: application/json' \
  -d '{"vmServiceUri":"http://127.0.0.1:<port>/<token>=/"}'
```

Both the printed HTTP URI and its `ws://.../ws` form are accepted. The page
reports video and control states separately, capture dimensions, and rendered
FPS. One browser controller is supported at a time.

The server runs helper `list` and `xcrun xctrace list devices` before starting
the stream. It resolves the selector to an AVFoundation capture device by
capture ID first and exact device name second; an Xcode development UDID is not
assumed to equal `AVCaptureDevice.uniqueID`.

## Troubleshooting

| Error code | Action |
| --- | --- |
| `capture_dependency_missing` | Run `xcode-select --install` and verify `swiftc --version`. |
| `capture_permission_denied` | Enable Camera access for the terminal, then restart it. |
| `capture_device_not_found` | Unlock and trust the USB iPhone, reconnect it, and rerun `list`. |
| `capture_device_busy` | Close QuickTime, OBS, and other capture clients. |
| `capture_start_failed` | Read server stderr, reconnect USB, and rerun device discovery. |
| `video_encode_failed` | Restart capture and check that the phone remains unlocked. |
| `vm_service_unavailable` | Keep `flutter run` active and PUT its current service URI to `/control`. |
| `runtime_control_unavailable` | Confirm the standalone demo is a debug build. |
| `invalid_control_message` | Reload the bundled web client so protocol versions match. |

Closing the browser cancels any active pointer but keeps video capture and VM
control alive. Reopen the browser to resume the same capture session. A Flutter
restart only requires another `PUT /control` with the new URI. Use
`DELETE /control` to detach control without stopping video. Press `Ctrl+C` in
the server terminal to disconnect VM Service, stop the helper, and release the
capture device.

## Manual Acceptance Record

Hardware validation is intentionally not mocked. Record results from the actual
phone used for acceptance:

| Check | Result |
| --- | --- |
| Device / iOS version | Pass: 钟惠彬的 iPhone, iOS 15.8.8 |
| Ready metadata and moving video | Pass: 750x1334 capture, 375x667 logical, DPR 2; consecutive H.264 binary frames received |
| First keyframe latency (target <= 1 s) | Pending measurement |
| Sustained rendered FPS | Pending measurement |
| Button click | Pass: WebSocket down/up changed `_clicks` from 0 to 1 |
| 600 ms long press | Pass: 700 ms pointer hold changed `_longPresses` from 0 to 1 |
| Single-finger list scroll | Pass: upward pointer sequence changed scroll pixels from 0.0 to 266.8 |
| Pointer alignment after video fitting | Pass for button and long-press target using normalized fitted coordinates |
| Browser reconnect preserves helper | Pending persistent-helper PID verification |
| Flutter restart replaces control | Pending replacement with a second VM Service URI |
| Lock / permission / busy / USB failure paths | Partial: controller busy and missing capture device verified; lock, permission revocation, and USB removal pending |

Bluetooth HID, WDA, ReplayKit, iPhone Mirroring, audio, multitouch, keyboard,
and arbitrary native-app control are outside this phase.
