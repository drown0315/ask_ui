# Progress: Static UI Development Slices

Status: superseded by bridge-backed workbench integration.

Related planning document:

- [Static UI Development Slices](../static-ui-development-slices.md)

Related detailed progress files:

- [Issue 001: App Shell And Layout Progress](001-app-shell-and-layout-progress.md)

## Goal

Track the overall implementation progress for the static Ask UI Workbench interface.

This progress file follows the slice breakdown in `docs_internal/static-ui-development-slices.md`. It is a high-level tracker. Each implementation round can still have its own detailed issue/progress file when the slice needs more detail.

## Current Phase Boundary

The static UI phase has been superseded. The workbench now has bridge-backed
session bootstrap, a real Flutter Widget Tree, real TopBar actions, and a
bridge-owned Android Live App Surface path.

In scope:

- Three-column DevTools-style workbench.
- Bridge-backed top toolbar.
- Real Flutter Widget Tree.
- Live App Surface with Target Device states, Device View, Surface Controls,
  and scrcpy/WebCodecs streaming path.
- Static selection overlay demo.
- Right-side selection notes and final agent handoff UI.
- Mock data and shared UI types.

Out of scope:

- Agent communication.
- Real widget selection.
- Persistence.

## Overall Slice Progress

| Slice | Name | Status | Detailed Tracker | Notes |
| --- | --- | --- | --- | --- |
| 1 | App Shell And Layout | Completed | [001 progress](001-app-shell-and-layout-progress.md) | Initial Vite + React + TypeScript shell is implemented. |
| 2 | Top Bar | Completed | TBD | Static session toolbar controls are implemented. |
| 3 | Widget Tree Panel | Completed | TBD | Mock full Flutter tree, selected-node highlight, search UI, refresh action, and resizable left panel are implemented. |
| 4 | Live App Surface | Completed through 0.0.2 slices | [0.0.2 issues](../../issues/0.0.2-live-app-surface.md) | Replaced the plain center placeholder with a Target Device surface, Device View, Surface Controls, WebSocket lifecycle, WebCodecs video path, and scrcpy-backed bridge stream. |
| 5 | Selection Overlay Layer | Not started | TBD | Add hidden/demo overlay layer inside the device viewport. |
| 6 | Selection Notes Panel Shell | Not started | TBD | Build right panel sections without detailed child behavior. |
| 7 | Current Selection Card | Not started | TBD | Show selected widget summary and empty state. |
| 8 | Selection Comment Editor | Not started | TBD | Add current-selection comment editor UI. |
| 9 | Selection Notes List | Not started | TBD | Render staged notes with active state. |
| 10 | Agent Composer | Not started | TBD | Add final instruction composer and send action. |
| 11 | Mock Data And Types | Not started | TBD | Centralize mock data and shared types. |

## Recommended Implementation Order

- [x] 1. App shell and layout.
- [x] 2. Top bar.
- [x] 3. Widget tree panel.
- [x] 4. Live App Surface.
- [ ] 5. Selection notes panel shell.
- [ ] 6. Current selection card.
- [ ] 7. Selection comment editor.
- [ ] 8. Selection notes list.
- [ ] 9. Agent composer.
- [ ] 10. Selection overlay demo state.
- [ ] 11. Mock data and shared types cleanup.

## Acceptance Tracking

- [x] The app has a stable three-column workbench shell.
- [x] The top toolbar communicates session state and static actions.
- [x] The left panel can display a nested widget tree from mock data.
- [x] The Live App Surface has a stable Device View.
- [ ] The Live App Surface reserves an overlay layer for future widget bounds.
- [ ] The right panel clearly communicates staged notes before agent handoff.
- [ ] The current selection summary is easy to scan.
- [ ] The selection comment editor is visually distinct from the final composer.
- [ ] The staged notes list is scannable and supports an active note state.
- [ ] The final composer clearly sends all staged context to the agent.
- [ ] Mock data and shared types are centralized instead of scattered.

## Work Log

- Slice 1 completed through Issue 001.
- The current App Shell has also received a Vue-green visual polish pass.
- Slice 2 completed with static device status, Select Widget, and Hot Reload/Hot Restart actions.
- Slice 3 completed with a mock full Flutter Widget Tree, selected-node-only highlight, app/framework visual weight differences, search field, refresh button, and draggable left-panel resizing.
- The Widget Tree and TopBar were later connected to the Dart bridge.
- The Live App Surface was later connected to a bridge-owned Device WebSocket,
  WebCodecs rendering path, and official scrcpy server stream.

## Next Candidate Slice

Selection notes and agent handoff slices remain the next static UI candidates.

Expected next work:

- Build right-panel selection note workflows.
- Add current selection summary and comment editing.
- Preserve compatibility with the bridge-backed Live App Surface.
