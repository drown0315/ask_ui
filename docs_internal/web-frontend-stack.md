# Web Frontend Stack

Status: decided for the initial static UI phase.

## Decision

Use Vite + React + TypeScript for the Ask UI web workbench.

## Why

The Ask UI page is a development-tool workbench, not a content site. The first version needs fast iteration on a static UI, and later versions will need:

- WebSocket communication with a local bridge.
- Target device preview rendering.
- DOM overlay positioning for selected widgets.
- Selection note state management.
- Agent handoff state.
- Potential desktop wrapping after the web UI stabilizes.

React and TypeScript are a good fit for stateful panel UI, complex component composition, and typed product data. Vite keeps the development setup small and fast.

## Initial App Location

Use:

```text
apps/
  web/
```

Suggested initial structure:

```text
apps/
  web/
    src/
      app/
        AskUiWorkbench.tsx
      components/
        top-bar/
        widget-tree/
        device-stage/
        selection-notes/
      data/
        mockWorkbenchData.ts
      types/
        workbench.ts
    package.json
    vite.config.ts
```

This leaves room for future apps and packages:

```text
apps/
  web/
  bridge/
  desktop/
packages/
  protocol/
  inspector/
```

These future folders should not be created until needed.

## Runtime Packaging Principle

The user should not have to run the frontend project directly.

Vite is the development stack, not the end-user runtime contract. During normal use, the web UI should already be built into static assets and served by the local Ask UI tool or bridge process.

Target user experience:

```text
agent skill starts Ask UI
  -> user selects or confirms target Flutter device
  -> tool runs Flutter app on the target device
  -> tool starts local bridge/server
  -> bridge serves the prebuilt web UI
  -> browser opens automatically
  -> agent waits for user feedback
```

The user should not need to run:

```bash
npm install
npm run dev
vite
```

Those commands are for Ask UI development only.

This follows the comfortable startup shape of `lavish-axi`: a capable agent runs a packaged local tool, the tool starts a local server, opens the browser, and the agent waits for user feedback. Ask UI should borrow that runtime experience, while using a different technical bridge because Ask UI must connect to Flutter VM Service and target devices.

Expected production shape:

```text
apps/web
  Vite + React + TypeScript source
  build output: static dist

apps/bridge
  Dart local bridge/server
  serves the prebuilt web dist
  connects to Flutter VM Service
  exposes localhost HTTP/WebSocket APIs to the web UI
```

This means the web stack choice should remain lightweight and easy to bundle as static files.

## Runtime Connection Boundary

The browser URL should include the target Flutter VM Service URI and Flutter project root as session bootstrap parameters.

Example:

```text
http://127.0.0.1:<ask-ui-port>/?vmServiceUri=<encoded-vm-service-ws-uri>&projectRoot=<encoded-local-path>
```

Both `vmServiceUri` and `projectRoot` are required for the first real Widget Tree integration.

The React web UI should not connect to Flutter VM Service directly. It should pass the VM Service URI and project root to the local Dart bridge/server, and the bridge should own the VM Service connection.

Reasoning:

- Dart can use the official `vm_service` package instead of reimplementing VM Service JSON-RPC in the browser.
- The bridge can normalize Flutter Inspector responses before the UI renders them.
- The bridge can call Flutter Inspector with the project root configured, so project-code classification and source-location context remain meaningful.
- Future actions such as widget selection, selected bounds, hot reload, hot restart, and agent handoff can share one local session boundary.
- The web UI remains static, lightweight, and easy to bundle.

For the first real Widget Tree integration, the intended scope is:

- Read `vmServiceUri` from the page URL.
- Read `projectRoot` from the page URL.
- Create a local bridge session from those parameters.
- Configure Flutter Inspector pub root directories during session creation.
- Fetch the Flutter Inspector summary widget tree through that bridge session.
- Render connection, loading, error, and tree states in the Widget Context Panel.
- Treat missing `vmServiceUri` or missing `projectRoot` as an incomplete session state, and do not fetch the real tree.
- Do not implement target-device streaming, selected widget bounds, comments, hot reload, hot restart, or agent handoff in this slice.

Minimal bridge API shape:

```text
POST /api/sessions
body: { "vmServiceUri": "...", "projectRoot": "..." }
response: { "sessionId": "..." }

GET /api/sessions/:sessionId/widget-tree
response: { "root": ... }
```

The web page should create one session per opened Ask UI page. The Widget Tree refresh action should reuse the existing `sessionId` and fetch a fresh tree snapshot from that session.

The first real Widget Tree integration should fetch the Flutter Inspector summary tree only. The bridge should call `ext.flutter.inspector.getRootWidgetTree` with `isSummaryTree=true`, `withPreviews=true`, and `fullDetails=false`. Do not add a full-tree or "show implementation widgets" toggle in this slice.

The bridge should return a normalized Ask UI Widget Tree payload instead of raw Flutter Diagnostics JSON. The web UI should not need to understand VM Service response envelopes, JSON-string `result` values, Flutter Inspector object groups, or `creationLocation` URI parsing.

Minimal normalized node shape:

```ts
type WidgetTreeNode = {
  id: string; // Flutter Inspector valueId
  label: string; // Flutter description
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
- Keep raw Flutter Diagnostics data only as an escape hatch for debugging or future fields, not as the primary UI contract.

Widget Tree refresh behavior:

- Treat each Widget Tree response as a fresh snapshot.
- Do not assume node ids remain valid across refreshes or Flutter rebuilds.
- Clear any local tree selection after a refresh in this slice.
- Do not implement best-effort selection restoration in the first real Widget Tree integration.
- Do not call `setSelectionById`, read selected widget bounds, or create comment targets in this slice.

## Styling

Start with plain CSS or CSS Modules.

Do not add a large UI component framework in the static UI phase. The workbench needs custom layout, device viewport sizing, and overlay positioning, so direct CSS control is more useful than a generic component kit.

## State Management

Start with local React state and props.

Use `useState` or `useReducer` for the static UI. Do not add a global state library until real session, device, inspector, or agent state makes it necessary.

Potential future option:

- Zustand, if state becomes shared across many independent panels.

## Explicit Non-Decisions

Do not use Next.js for the first version. The product does not need SSR, SEO, file-based routing, or a server-rendered app shell.

Do not start with Electron or Tauri. Build the browser web UI first. Desktop packaging can be evaluated after the core interaction is validated.

Do not implement Flutter VM Service, device streaming, or agent communication as part of the static UI stack decision.
