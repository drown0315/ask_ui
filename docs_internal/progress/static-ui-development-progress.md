# Progress: Static UI Development Slices

Status: in progress.

Related planning document:

- [Static UI Development Slices](../static-ui-development-slices.md)

Related detailed progress files:

- [Issue 001: App Shell And Layout Progress](001-app-shell-and-layout-progress.md)

## Goal

Track the overall implementation progress for the static Ask UI Workbench interface.

This progress file follows the slice breakdown in `docs_internal/static-ui-development-slices.md`. It is a high-level tracker. Each implementation round can still have its own detailed issue/progress file when the slice needs more detail.

## Current Phase Boundary

The current phase is static UI only.

In scope:

- Three-column DevTools-style workbench.
- Static top toolbar.
- Mock widget tree.
- Device stage placeholder.
- Static selection overlay demo.
- Right-side selection notes and final agent handoff UI.
- Mock data and shared UI types.

Out of scope:

- Flutter VM Service integration.
- Real target-device screen streaming.
- Real widget selection.
- Real hot reload/hot restart execution.
- Agent communication.
- Persistence.

## Overall Slice Progress

| Slice | Name | Status | Detailed Tracker | Notes |
| --- | --- | --- | --- | --- |
| 1 | App Shell And Layout | Completed | [001 progress](001-app-shell-and-layout-progress.md) | Initial Vite + React + TypeScript shell is implemented. |
| 2 | Top Bar | Completed | TBD | Static session toolbar controls are implemented. |
| 3 | Widget Tree Panel | Not started | TBD | Add mock hierarchical widget tree. |
| 4 | Device Stage With Placeholder | Not started | TBD | Replace plain center placeholder with stage, metadata, and viewport frame. |
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
- [ ] 3. Widget tree panel.
- [ ] 4. Device stage placeholder.
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
- [ ] The left panel can display a nested widget tree from mock data.
- [ ] The center stage has a stable device viewport placeholder.
- [ ] The center stage reserves an overlay layer for future widget bounds.
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

## Next Candidate Slice

Slice 3: Widget Tree Panel.

Expected next work:

- Add mock hierarchical widget tree data.
- Render nested widget rows with indentation.
- Highlight the selected widget and handle long widget names.
