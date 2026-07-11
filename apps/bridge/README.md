# Ask UI Bridge

`ask_ui_bridge` is the local launcher and bridge server for Ask UI. It starts a
Flutter app, creates the Bridge Session used by the Ask UI workbench, serves the
packaged Web workbench, and exposes the Agent Session Command used by coding
agents.

## Installed Usage

Add the package as a dev dependency in a Flutter project:

```yaml
dev_dependencies:
  ask_ui_bridge: ^0.0.4
```

Start Ask UI from the Flutter project:

```sh
dart run ask_ui_bridge launch
```

Pass Flutter launch options when needed:

```sh
dart run ask_ui_bridge launch \
  --device <device-id> \
  --flavor <flavor> \
  --target lib/main_dev.dart \
  --dart-define API_BASE_URL=http://localhost:3000
```

Use `--no-open` when the command should print the workbench URL without opening
a browser.

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
