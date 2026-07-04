# Issue 004: Real Flutter Widget Tree Snapshot

Status: ready for implementation.

## Goal

Replace the mock Widget Tree with a real Flutter Inspector summary tree snapshot for a running Flutter debug session.

This issue is the first real Flutter integration slice. It should prove that Ask UI can read session parameters from the browser URL, create a local bridge session, fetch the real Widget Tree through Flutter VM Service, and render it in the existing Widget Context Panel.

## User-Facing Result

Opening Ask UI with a valid Flutter session URL should show the running app's real Widget Tree in the left panel.

Expected URL shape:

```text
http://127.0.0.1:<ask-ui-port>/?vmServiceUri=<encoded-vm-service-ws-uri>&projectRoot=<encoded-local-path>
```

Future Android device work extends this URL with a required target device parameter:

```text
http://127.0.0.1:<ask-ui-port>/?vmServiceUri=<encoded-vm-service-ws-uri>&projectRoot=<encoded-local-path>&deviceId=<encoded-android-device-id>
```

The user should see:

- Missing-parameter state when `vmServiceUri` or `projectRoot` is absent.
- Connecting/loading state while the bridge creates the session and fetches the tree.
- Error state when the VM Service session or tree fetch fails.
- Real Flutter Widget Tree rows when the fetch succeeds.
- Refresh action that fetches a fresh tree snapshot from the existing bridge session.

## Scope

Implement:

- A local Dart bridge/server under `apps/bridge`.
- Bridge session creation from `vmServiceUri` and `projectRoot`.
- Flutter VM Service connection ownership in the bridge, not in the browser.
- Flutter Inspector pub root configuration during session creation.
- Summary Widget Tree fetch through `ext.flutter.inspector.getRootWidgetTree`.
- Normalized Widget Tree response for the web UI.
- Web URL bootstrap parsing for `vmServiceUri` and `projectRoot`.
- Web loading, missing-parameter, error, and success states for the Widget Tree panel.
- Refresh button behavior that reuses the existing bridge `sessionId`.

## Runtime Contract

The React web UI must not connect to Flutter VM Service directly.

Minimal bridge API:

```text
POST /api/sessions
body: { "vmServiceUri": "...", "projectRoot": "..." }
response: { "sessionId": "..." }

GET /api/sessions/:sessionId/widget-tree
response: { "root": WidgetTreeNode }
```

The web page should create one bridge session per opened Ask UI page.

## Widget Tree Fetch Contract

The bridge should call Flutter Inspector with:

```text
ext.flutter.inspector.getRootWidgetTree
groupName=<ask-ui-session-object-group>
isSummaryTree=true
withPreviews=true
fullDetails=false
```

This issue only fetches the Flutter Inspector summary tree. Do not add a full-tree or "show implementation widgets" toggle.

## Normalized Node Shape

The bridge should return normalized Ask UI nodes instead of raw Flutter Diagnostics JSON:

```ts
type WidgetTreeNode = {
  id: string;
  label: string;
  widgetRuntimeType?: string;
  kind: 'app' | 'framework' | 'unknown';
  source?: {
    file: string;
    line?: number;
    column?: number;
    name?: string;
  };
  children: WidgetTreeNode[];
  raw?: unknown;
};
```

Normalization rules:

- Use Flutter Inspector `valueId` as `id`.
- Use Flutter Inspector `description` as `label`.
- Map `createdByLocalProject` and source path information into `kind`.
- Normalize `creationLocation.file` from `file:///...` into a local file path when possible.
- Always return `children` as an array.
- Keep raw Flutter Diagnostics data only as a debug escape hatch.

## Refresh Behavior

Treat every Widget Tree response as a fresh snapshot.

Refreshing the tree should:

- Reuse the existing bridge `sessionId`.
- Fetch a new summary tree snapshot.
- Clear any local tree selection for this slice.
- Avoid assuming node ids are stable across refreshes or Flutter rebuilds.

## Out Of Scope

Do not implement:

- Browser-side direct VM Service connection.
- Target-device screen streaming.
- App operation/click forwarding.
- Select Widget mode.
- Tree node selection behavior.
- `setSelectionById`.
- Selected widget bounds.
- Comment popovers.
- Selection notes or agent handoff integration.
- Hot reload or hot restart execution.
- Full Widget Tree / implementation-widget toggle.
- Best-effort selection restoration after refresh.
- Automatic VM Service discovery.
- Multi-device or multi-isolate selection UI.

## Suggested Files

```text
apps/
  bridge/
    pubspec.yaml
    bin/
      ask_ui_bridge.dart
    lib/
      server/
      sessions/
      inspector/
      protocol/
  web/
    src/
      app/
      components/
        widget-tree/
      services/
        askUiBridgeClient.ts
      types/
        widgetTree.ts
```

The exact bridge file structure can change during implementation, but the bridge/web boundary should stay stable.

## Acceptance Criteria

- Ask UI requires both `vmServiceUri` and `projectRoot` for real Widget Tree mode.
- Missing either parameter renders a clear incomplete-session state.
- The web UI creates one bridge session using both parameters.
- The bridge owns the VM Service connection.
- The bridge configures Flutter Inspector pub root directories using `projectRoot`.
- The bridge fetches `getRootWidgetTree` with `isSummaryTree=true`.
- The bridge returns normalized Widget Tree nodes.
- The existing Widget Context Panel renders the real tree instead of mock data when the session succeeds.
- Refresh fetches a new tree snapshot through the existing session.
- Refresh does not preserve local selection state.
- The mock Widget Tree remains available only as a development fallback if the implementation needs it.
- `apps/web` build still passes.

## Notes

This issue intentionally stops at real tree display. Selection, bounds, comments, and agent handoff should be implemented as later slices after the session and tree contract is proven.
