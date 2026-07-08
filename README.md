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

The bridge defaults to `adb` from `PATH` and the project-controlled official
scrcpy 4.0 server artifact at
`apps/bridge/vendor/scrcpy/4.0/scrcpy-server-v4.0`.

```sh
ADB=/path/to/adb dart run bin/ask_ui_bridge.dart
```

The same bridge entrypoint also exposes the Agent Session Command used by a
launching coding agent. Pass the Bridge Session connection with flags or the
matching environment variables:

```sh
dart run bin/ask_ui_bridge.dart agent poll \
  --base-url http://127.0.0.1:8787 \
  --session-id <session-id>

ASK_UI_BRIDGE_URL=http://127.0.0.1:8787 \
ASK_UI_SESSION_ID=<session-id> \
dart run bin/ask_ui_bridge.dart agent poll --once
```

After processing a user Chat message, reply with the returned message ID:

```sh
dart run bin/ask_ui_bridge.dart agent poll \
  --base-url http://127.0.0.1:8787 \
  --session-id <session-id> \
  --reply-to <message-id> \
  --agent-reply "Done."
```

Use `--agent-error` for command-level system errors. `--once` writes or polls
only the current action; without it, reply and error commands continue polling
for the next Chat message.

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
