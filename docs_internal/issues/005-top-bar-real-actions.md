# Issue 005: Top Bar Real Flutter Actions

Status: implemented for the first real-action slice.

## Goal

Connect the Top Bar actions to real Flutter session behavior while keeping the
browser UI lightweight and the Dart bridge responsible for Flutter runtime
operations.

This issue covers the real-action contract for:

- Select Widget
- Hot Reload
- Hot Restart

## Product Behavior

The Top Bar should remain the user's primary control point for switching between
normal app operation and Flutter workbench actions.

`Select Widget` is a toggle, not a submit action. Turning it on puts the device
stage into widget-picking mode. Users may select one or more widgets, add notes
near those selections or in the right panel, and only send the collected context
to the coding agent from the chat composer.

`Hot Reload` runs Flutter hot reload for the current bridge session. The button
should show an in-progress state while the action is running, report failures
clearly, and refresh the Widget Tree snapshot after a successful reload.

`Hot Restart` should use the same UI shape as `Hot Reload`, but its technical
support must be treated separately. Hot restart may require the process that
started `flutter run` or a Flutter tool daemon, not only the VM Service
connection.

## Technical Direction

The web UI must not call Flutter VM Service directly. It should call local bridge
HTTP APIs using the existing `sessionId`.

Initial bridge API shape:

```text
POST /api/sessions/:sessionId/hot-reload
response: { "status": "ok", "message"?: string, "reloadReport"?: object }

POST /api/sessions/:sessionId/hot-restart
response: { "status": "ok", "message"?: string }
```

Widget selection should remain a separate integration slice because it depends
on device-stage coordinates, selected widget hit testing, Flutter Inspector
selection state, selected bounds, code location, and tree selection sync.

Future widget selection API shape:

```text
POST /api/sessions/:sessionId/inspector/select-widget
body: { "x": number, "y": number, "coordinateSpace": "device-stage" }
response: {
  "selectedNodeId": string,
  "widgetType"?: string,
  "label"?: string,
  "bounds"?: object,
  "source"?: object,
  "treePath"?: object[]
}
```

## Web UI Scope

For the first real-action slice:

- Keep `Select Widget` as a controlled toggle in the Top Bar.
- Reflect the active toggle state visually.
- Pass the toggle state down to the device-stage area so later slices can route
  clicks as selection gestures instead of normal app operations.
- Add action states for `Hot Reload` and `Hot Restart`: idle, running, failed,
  and unsupported where needed.
- Reuse the existing bridge session created from `vmServiceUri + projectRoot`.
- After successful hot reload, fetch a fresh Widget Tree snapshot through the
  existing session.
- Treat node ids as snapshot-scoped after reload.
- Clear local widget-tree selection after reload until selection restoration is
  designed.

## Bridge Scope

The bridge should expose action endpoints behind the existing session boundary.

Recommended bridge abstraction:

```dart
abstract class FlutterAppController {
  Future<HotReloadResult> hotReload(BridgeSession session);
  Future<HotRestartResult> hotRestart(BridgeSession session);
}
```

`Hot Reload` should be implemented only after calibrating the exact Flutter/VM
Service operation used by the bridge. The web contract should not expose raw VM
Service details.

`Hot Restart` should return a clear unsupported error until the project has a
proven runner-level implementation.

Suggested unsupported response:

```json
{
  "error": "hot_restart_not_supported_for_session",
  "message": "Hot restart is not available for this bridge session."
}
```

## Capability Matrix

| Product capability | Technical evidence needed | Status | Decision |
| --- | --- | --- | --- |
| Select Widget toggle UI | Internal React state | Supported | Current UI contract |
| Select Widget hit testing | Flutter Inspector selection and coordinate mapping | Unknown | Future slice |
| Hot Reload | Flutter tool uses VM `reloadSources` plus `ext.flutter.reassemble` | Supported by bridge implementation | Real Flutter session smoke test still needed |
| Hot Restart | Flutter tool registers VM Service method `hotRestart` when runner support exists | Partial | Bridge calls the registered service; unsupported when the method is absent |
| Refresh Widget Tree after reload | Existing `GET /api/sessions/:sessionId/widget-tree` | Supported | Current contract after hot reload succeeds |

## Implementation Notes

- `Select Widget` is now a controlled Top Bar toggle and passes its active state
  to the device stage.
- `Hot Reload` calls `POST /api/sessions/:sessionId/hot-reload`.
- The bridge implements hot reload with VM Service `reloadSources` for the main
  isolate, followed by Flutter framework `ext.flutter.reassemble`.
- After successful hot reload, the web UI fetches a fresh Widget Tree snapshot
  through the existing bridge session.
- `Hot Restart` calls `POST /api/sessions/:sessionId/hot-restart`.
- The Dart bridge now routes both hot reload and hot restart through
  `FlutterAppController`.
- Hot restart calls the Flutter tool registered VM Service method `hotRestart`.
  If the running session does not expose that service, the bridge returns
  `hot_restart_not_supported_for_session`.

## Out Of Scope

- Sending comments to the coding agent.
- Device screen streaming.
- Coordinate mapping from browser pixels to device pixels.
- Flutter Inspector `setSelectionById` or hit-test integration.
- Selected widget bounds overlay.
- Best-effort selection restoration after hot reload or restart.
- Multi-device or multi-isolate UI.

## Acceptance Criteria

- `Select Widget` behaves as a visible toggle.
- Toggling `Select Widget` does not send staged comments to the agent.
- `Hot Reload` calls the bridge using the current `sessionId`.
- `Hot Reload` shows running and failed states.
- Successful `Hot Reload` refreshes the Widget Tree through the existing session.
- `Hot Restart` has a defined UI state and bridge contract.
- Unsupported `Hot Restart` failures use a clear error code and message.
- The web UI still works as a static Vite build served by the local tool or
  bridge.
