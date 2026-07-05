# Context Glossary

## Widget Context Panel

The left-side workbench panel that helps the developer confirm which Flutter UI target is selected.

It contains the Flutter Widget Tree as its primary view.

## Flutter Widget Tree

The full widget hierarchy for the running Flutter app session.

Ask UI shows the full tree and highlights the currently selected widget within that tree.

Framework nodes and app/user-code nodes both remain visible. App/user-code nodes should carry stronger visual weight, while framework nodes can use quieter styling so the full structure stays accurate without overwhelming the target context.

Only the currently selected widget receives selection highlighting. Ancestor rows stay visually neutral.

## Target Device

The Android device or emulator that runs the Flutter app being inspected through Ask UI.

Ask UI binds a workbench session to one Target Device from the page URL at startup.

The startup parameter is `deviceId`, the stable Android device serial used directly for ADB and scrcpy targeting.

Without a Target Device, the workbench session is not established.

One `vmServiceUri` belongs to exactly one Target Device for the lifetime of the workbench session.

The `deviceId` startup parameter must identify that same Target Device.

## Live App Surface

The center workbench surface where the developer views and operates the Flutter app running on the Target Device.

It is the primary place for normal app interaction, widget selection, selected-area highlighting, and note markers.

Pointer input on the Live App Surface is always sent to the Target Device. When Select Widget is enabled, Flutter Inspector decides whether that input selects a widget.
_Avoid_: Device Stage, Operate Mode

## Device View

The video area inside the Live App Surface that shows the Target Device screen and receives pointer input mapped to device coordinates.

It does not include the Surface Controls.

## Surface Controls

The device-control area inside the Live App Surface for Android system actions such as Back, Home, and Recents.

Surface Controls operate the Target Device but are not part of the Device View coordinate space.
