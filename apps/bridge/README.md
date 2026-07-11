# Ask UI Bridge

`ask_ui_bridge` is the local launcher and bridge server for Ask UI. It starts a
Flutter app, creates the Bridge Session used by the Ask UI workbench, serves the
packaged Web workbench, and exposes the Agent Session Command used by coding
agents.

## Installed Usage

Globally activate the bridge CLI:

```sh
dart pub global activate ask_ui_bridge
```

Start Ask UI from a Flutter project that has registered `ask_ui_runtime`:

```sh
ask_ui_bridge launch
```

Pass Flutter launch options when needed:

```sh
ask_ui_bridge launch \
  --device <device-id> \
  --flavor <flavor> \
  --target lib/main_dev.dart \
  --dart-define API_BASE_URL=http://localhost:3000 \
  --project-root /path/to/flutter_app
```

Use `--no-open` when the command should print the workbench URL without opening
a browser.

## Coding-Agent Skill

The Ask UI repository includes launch workflow skills at `../../skills/ask-ui`
and `../../skills/ask-ui-dev`. Install `ask-ui` for normal Flutter projects, or
`ask-ui-dev` when developing this repository. The skills let Codex, Claude Code,
or a similar agent run the appropriate launch command, handle device selection,
run the returned Agent Session Command, and continue polling for Ask UI Chat
messages.

This version does not include an automatic skill installer command.

## Release Validation

Maintainers should build the Web workbench into the bridge package before
publishing:

```sh
cd apps/web
npm run build:bridge

cd ../bridge
dart run tool/validate_release_layout.dart
dart test
dart pub publish --dry-run
```

The published package must include `web/index.html` and the generated Web
assets under `web/assets`.

The repository publish workflow runs the same release validation for
`ask_ui_bridge-v<version>` tags, verifies the packaged Web files are committed,
and publishes to pub.dev after `dart pub publish --dry-run` succeeds.
