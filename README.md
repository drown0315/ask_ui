# Ask UI

Ask UI is a Flutter developer workbench for selecting precise UI targets, collecting comments, and handing that context to a coding agent.

## Project Structure

- `apps/web` - Vite, React, and TypeScript web frontend.
- `apps/bridge` - Dart local bridge for Flutter Inspector, app actions, and Android device streaming.
- `docs` - Product and user-facing documentation.
- `docs_internal` - Internal implementation notes, issue plans, and progress notes.
- `issues` - Issue tracking artifacts.
- `skills` - Coding-agent workflows for Ask UI.

## Bridge

Run commands from `apps/bridge`:

```sh
dart pub get
dart run bin/ask_ui_bridge.dart --host 127.0.0.1 --port 8787
```

Installed Flutter projects should add `ask_ui_runtime`, register the runtime
before `runApp`, and start Ask UI through the globally activated bridge CLI:

```yaml
dependencies:
  ask_ui_runtime: ^0.0.1
```

```dart
import 'package:ask_ui_runtime/ask_ui_runtime.dart';

void main() {
  registerAskUiRuntime();
  runApp(const MyApp());
}
```

```sh
dart pub global activate ask_ui_bridge
ask_ui_bridge launch
```

## Coding-Agent Skill

Ask UI includes two launch workflow skills:

- `skills/ask-ui/SKILL.md` for normal Flutter projects using the installed
  `ask_ui_bridge` CLI.
- `skills/ask-ui-dev/SKILL.md` for Ask UI maintainers working from this source
  checkout.

The skills are intentionally installed manually in this version. They tell the
agent to start Ask UI, handle device selection, and write Ask UI Chat replies
through the returned `agent poll` command.

Ask UI maintainers prepare the bridge package for release by building the Web
workbench into the bridge package before running pub validation:

```sh
cd apps/web
npm run build:bridge

cd ../bridge
dart run tool/validate_release_layout.dart
dart pub publish --dry-run
```

Formal bridge package publishing is handled by the
`Publish Bridge Package` GitHub Actions workflow. Configure pub.dev automated
publishing for this repository and the `ask_ui_bridge-v[0-9]+.[0-9]+.[0-9]+`
tag pattern, then publish by pushing a tag that matches the bridge package
version:

```sh
git tag ask_ui_bridge-v0.0.4
git push origin ask_ui_bridge-v0.0.4
```

The publish workflow rebuilds the Web workbench, verifies the generated
`apps/bridge/web` files match the committed package files, runs bridge analysis
and tests, validates the release layout, performs `dart pub publish --dry-run`,
and only then runs `dart pub publish --force`.

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
