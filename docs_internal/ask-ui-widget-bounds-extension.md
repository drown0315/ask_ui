# Ask UI Runtime Widget Bounds Extension

Ask UI widget marker placement needs real Flutter render bounds, not Flutter
Inspector tree JSON. Inspector JSON exposes widget ids and sizes in some layout
views, but it does not expose each widget's global screen origin.

Flutter apps should install `ask_ui_runtime` and register it before `runApp`.
The runtime registers debug-only VM Service extensions used by the local Ask UI
Bridge.

## Install

For local development, add a path dependency to the target Flutter app:

```yaml
dependencies:
  ask_ui_runtime:
    path: /path/to/ask_ui/packages/ask_ui_runtime
```

## Register

```dart
import 'package:ask_ui_runtime/ask_ui_runtime.dart';

void main() {
  registerAskUiRuntime();
  runApp(const SmokeApp());
}
```

`registerAskUiRuntime()` is wrapped in Dart assertions, so it registers only in
debug builds and is tree-shaken from release builds.

## Bridge Contract

Bridge calls:

```text
ext.ask_ui.widgetBounds
  id: inspector-11
  groupName: ask_ui_widget_tree
```

The extension returns Flutter logical pixels plus `devicePixelRatio`. Bridge
converts the rectangle to device-screen pixels before sending it to the web app.

## Probe Command

```bash
cd apps/bridge
dart run tool/inspect_widget_bounds.dart \
  --vm-service-uri 'ws://127.0.0.1:52051/rIfSxeErFAs=/ws' \
  --project-root '/Users/drown/flutter_project/flutter_pilot/examples/smoke_app' \
  --group-name ask_ui_widget_tree \
  --widget-id inspector-11
```
