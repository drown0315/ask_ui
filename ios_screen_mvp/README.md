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

Launch the included Flutter app on the iPhone in debug mode:

```sh
cd ios_screen_mvp/flutter_demo
flutter devices
flutter run -d <flutter-device-id>
```

Keep `flutter run` active and copy its VM Service URI. Both the printed HTTP URI
and its `ws://.../ws` form are accepted.

Build the browser client and start the local server in another terminal:

```sh
cd ios_screen_mvp/web
npm run build

cd ../server
dart run bin/server.dart \
  --device-id '<capture-device-id>' \
  --vm-service-uri 'http://127.0.0.1:<port>/<token>=/' \
  --web-root ../web/dist \
  --port 8765
```

Open `http://127.0.0.1:8765`. The page reports capture dimensions, connection
state, and rendered FPS. One browser controller is supported at a time.

## Troubleshooting

| Error code | Action |
| --- | --- |
| `capture_dependency_missing` | Run `xcode-select --install` and verify `swiftc --version`. |
| `capture_permission_denied` | Enable Camera access for the terminal, then restart it. |
| `capture_device_not_found` | Unlock and trust the USB iPhone, reconnect it, and rerun `list`. |
| `capture_device_busy` | Close QuickTime, OBS, and other capture clients. |
| `capture_start_failed` | Read server stderr, reconnect USB, and rerun device discovery. |
| `video_encode_failed` | Restart capture and check that the phone remains unlocked. |
| `vm_service_unavailable` | Keep `flutter run` active and pass its current service URI. |
| `runtime_control_unavailable` | Confirm the standalone demo is a debug build. |
| `invalid_control_message` | Reload the bundled web client so protocol versions match. |

Closing the browser cancels any active pointer, disconnects VM Service, sends
SIGTERM to the helper, and releases the capture device. Reconnection is manual.

## Manual Acceptance Record

Hardware validation is intentionally not mocked. Record results from the actual
phone used for acceptance:

| Check | Result |
| --- | --- |
| Device / iOS version | Pending real-device run |
| Ready metadata and moving video | Pending real-device run |
| First keyframe latency (target <= 1 s) | Pending measurement |
| Sustained rendered FPS | Pending measurement |
| Button click | Pending real-device run |
| 600 ms long press | Pending real-device run |
| Single-finger list scroll | Pending real-device run |
| Pointer alignment after video fitting | Pending real-device run |
| Browser close releases helper | Pending real-device run |
| Lock / permission / busy / USB failure paths | Pending real-device run |

Bluetooth HID, WDA, ReplayKit, iPhone Mirroring, audio, multitouch, keyboard,
and arbitrary native-app control are outside this phase.
