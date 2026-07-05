# Ask UI

Ask UI is a Flutter developer workbench for selecting precise UI targets, collecting comments, and handing that context to a coding agent.

## Project Structure

- `apps/web` - Vite, React, and TypeScript web frontend.
- `apps/bridge` - Dart local bridge for Flutter Inspector, app actions, and Android device streaming.
- `docs` - Product and user-facing documentation.
- `docs_internal` - Internal implementation notes, issue plans, and progress notes.
- `issues` - Issue tracking artifacts.

## Bridge

Run commands from `apps/bridge`:

```sh
dart pub get
dart run bin/ask_ui_bridge.dart --host 127.0.0.1 --port 8787
```

Workbench sessions require `vmServiceUri`, `projectRoot`, and `deviceId` query
parameters. `deviceId` must be the Android device or emulator serial used by
Flutter, ADB, and scrcpy.

The bridge defaults to `adb` from `PATH` and the calibrated Homebrew scrcpy 4.0
server path. Override those when needed:

```sh
ADB=/path/to/adb SCRCPY_SERVER=/path/to/scrcpy-server dart run bin/ask_ui_bridge.dart
```

## Web App

Run commands from `apps/web`:

```sh
npm install
npm run dev
```

Build the web app:

```sh
npm run build
```

Preview a production build:

```sh
npm run preview
```
