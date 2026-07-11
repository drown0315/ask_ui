# ask_ui_runtime

Debug runtime service extensions for Ask UI Flutter app integration.

## Usage

Add the package to your Flutter app:

```yaml
dependencies:
  ask_ui_runtime: ^0.0.1
```

Register the runtime before `runApp`:

```dart
import 'package:ask_ui_runtime/ask_ui_runtime.dart';

void main() {
  registerAskUiRuntime();
  runApp(const MyApp());
}
```

`registerAskUiRuntime` currently registers `ext.ask_ui.widgetBounds`, which Ask
UI Bridge uses to query real `RenderBox.localToGlobal` bounds for Flutter
Inspector widget ids. Registration is debug-only and is removed from release
builds by Dart assertions.
