# Progress: Issue 004 Real Flutter Widget Tree Snapshot

Status: in progress.

Related issue:

- [Issue 004: Real Flutter Widget Tree Snapshot](../issues/004-real-widget-tree-integration.md)
- [Issues 0.0.1: Real Widget Tree Snapshot](../../issues/0.0.1-real-widget-tree-snapshot.md)

## Current Goal

Render a real Flutter Inspector summary Widget Tree snapshot in the existing Ask UI Widget Context Panel.

This round is the first bridge-backed Flutter integration. The browser page reads `vmServiceUri` and `projectRoot` from the URL, creates a local bridge session, and fetches a normalized Widget Tree snapshot from that session.

## 0.0.1 Slice Progress

| Slice | Name | Status | Commit | Notes |
| --- | --- | --- | --- | --- |
| 1 | Bootstrap Bridge Session From URL | Completed | `aed554f` | Bridge session API, URL bootstrap parsing, Widget Tree panel session states, and singleton session reuse are implemented. |
| 2 | Render Real Flutter Widget Tree Snapshot | Completed | TBD | Bridge owns VM Service access, configures pub roots, fetches Inspector summary tree, normalizes nodes, and web renders the real tree snapshot. |
| 3 | Refresh Tree Snapshot And Error Recovery | Not started | TBD | Depends on Slice 2. Reuse existing session and fetch fresh tree snapshots. |

## Progress Checklist

- [x] Create `apps/bridge` Dart bridge/server scaffold.
- [x] Add bridge endpoint for `POST /api/sessions`.
- [x] Store singleton bridge session state keyed by `vmServiceUri` and `projectRoot`.
- [x] Configure Flutter Inspector pub root directories during Widget Tree fetch.
- [x] Add bridge endpoint for `GET /api/sessions/:sessionId/widget-tree`.
- [x] Fetch Flutter Inspector summary tree with `isSummaryTree=true`.
- [x] Normalize Flutter Diagnostics nodes into Ask UI `WidgetTreeNode`.
- [x] Add web bridge client for session creation.
- [x] Parse `vmServiceUri` and `projectRoot` from the page URL.
- [x] Add Widget Tree missing-parameter state.
- [x] Add Widget Tree session-creation/loading state.
- [x] Add Widget Tree error state.
- [x] Render real Widget Tree data in the existing panel.
- [ ] Wire refresh button to fetch a new snapshot through the existing session.
- [ ] Clear local tree selection on refresh.
- [x] Verify `apps/web` build passes.
- [ ] Verify bridge can fetch a real tree from a debug Flutter app.
- [ ] Update this progress file with final status.

## Out Of Scope For This Round

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

## Acceptance Tracking

- [x] Ask UI requires both `vmServiceUri` and `projectRoot` for real Widget Tree mode.
- [x] Missing either parameter renders a clear incomplete-session state.
- [x] The web UI creates one bridge session using both parameters.
- [x] Repeated session creation for the same `vmServiceUri` and `projectRoot` returns the same `sessionId`.
- [x] The bridge owns the VM Service connection.
- [x] The bridge configures Flutter Inspector pub root directories using `projectRoot`.
- [x] The bridge fetches `getRootWidgetTree` with `isSummaryTree=true`.
- [x] The bridge returns normalized Widget Tree nodes.
- [x] The existing Widget Context Panel renders the real tree instead of mock data when the session succeeds.
- [ ] Refresh fetches a new tree snapshot through the existing session.
- [ ] Refresh does not preserve local selection state.
- [ ] The mock Widget Tree remains available only as a development fallback if needed.
- [ ] `apps/web` build still passes.

## Notes

Keep this file updated during implementation. This progress file tracks only the real Widget Tree snapshot slice, not later selection, bounds, comment, or agent handoff work.

## Work Log

- Created the issue and progress tracker after confirming the session and Widget Tree contracts.
- Implemented the first AFK slice, `Bootstrap Bridge Session From URL`.
- Added a Dart bridge scaffold with `POST /api/sessions`.
- Added bridge tests for missing parameters, successful session creation, and singleton reuse for repeated target parameters.
- Added web URL bootstrap parsing, bridge session client, and Widget Tree panel states for incomplete, creating, ready, and error.
- Verified `dart test`, the web bootstrap Node test, and `npm run build`.
- Committed the completed first slice as `aed554f feat: add bridge session bootstrap`.
- Implemented the second AFK slice, `Render Real Flutter Widget Tree Snapshot`.
- Added `GET /api/sessions/:sessionId/widget-tree` on the bridge.
- Added a `vm_service` backed Flutter Inspector client that configures pub roots and calls `getRootWidgetTree` with summary-tree parameters.
- Added normalization from Flutter Diagnostics nodes to Ask UI `WidgetTreeNode` payloads.
- Updated the web bridge client and Widget Tree panel to fetch and render the real tree after session bootstrap.
- Verified `dart test`, `dart analyze`, and `npm run build`.
