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
- Select Widget mode integration.
- Right-side Chat panel with Selection Comment staging, Chat History, composer
  Attachment Tokens, and plain text Agent Session handoff.
- Mock data and shared UI types.

Out of scope:

- Persistence.
- Sending Selection Comments as Chat attachments.
- Snapshot capture for Selection Comments.

## Overall Slice Progress

| Slice | Name | Status | Detailed Tracker | Notes |
| --- | --- | --- | --- | --- |
| 1 | App Shell And Layout | Completed | [001 progress](001-app-shell-and-layout-progress.md) | Initial Vite + React + TypeScript shell is implemented. |
| 2 | Top Bar | Completed | TBD | Static session toolbar controls are implemented. |
| 3 | Widget Tree Panel | Completed | TBD | Mock full Flutter tree, selected-node highlight, search UI, refresh action, and resizable left panel are implemented. |
| 4 | Live App Surface | Completed through 0.0.2 slices | [0.0.2 issues](../../issues/0.0.2-live-app-surface.md) | Replaced the plain center placeholder with a Target Device surface, Device View, Surface Controls, WebSocket lifecycle, WebCodecs video path, and scrcpy-backed bridge stream. |
| 5 | Selection Overlay Layer | Completed through 0.0.3 slices | [0.0.3 issues](../../issues/0.0.3-selection-chat.md) | Selection Comment markers appear while Select Widget mode is on and the target is currently locatable. |
| 6 | Chat Panel Shell | Completed through 0.0.3 slices | [0.0.3 issues](../../issues/0.0.3-selection-chat.md) | Right panel is now Chat, with Agent Status, selected widget card, Chat History, and composer. |
| 7 | Current Selection Card | Completed through 0.0.3 slices | [0.0.3 issues](../../issues/0.0.3-selection-chat.md) | Shows selected widget metadata and staged Selection Comments for the active target. |
| 8 | Selection Comment Editor | Completed through 0.0.3 slices | [0.0.3 issues](../../issues/0.0.3-selection-chat.md) | Supports staging, editing, deleting, validation, per-widget drafts, and batch limits. |
| 9 | Attachment Tokens | Completed through 0.0.3 slices | [0.0.3 issues](../../issues/0.0.3-selection-chat.md) | Composer tokens show compact staged Selection Comment references. |
| 10 | Agent Composer | Completed for plain text | [0.0.3 issues](../../issues/0.0.3-selection-chat.md) | Plain text messages send to the active Agent Session poller; Selection Comment attachment send remains later work. |
| 11 | Mock Data And Types | Not started | TBD | Centralize mock data and shared types. |

## Recommended Implementation Order

- [x] 1. App shell and layout.
- [x] 2. Top bar.
- [x] 3. Widget tree panel.
- [x] 4. Live App Surface.
- [x] 5. Chat panel shell.
- [x] 6. Current selection card.
- [x] 7. Selection comment editor.
- [x] 8. Attachment Tokens.
- [x] 9. Plain text Agent composer.
- [x] 10. Selection marker overlay state.
- [ ] 11. Mock data and shared types cleanup.

## Acceptance Tracking

- [x] The app has a stable three-column workbench shell.
- [x] The top toolbar communicates session state and static actions.
- [x] The left panel can display a nested widget tree from mock data.
- [x] The Live App Surface has a stable Device View.
- [x] The Live App Surface reserves an overlay layer for selection markers.
- [x] The right panel clearly communicates staged Selection Comments before agent handoff.
- [x] The current selection summary is easy to scan.
- [x] The Selection Comment editor is visually distinct from the Chat composer.
- [x] Staged Selection Comments are scannable through current-target comments and composer Attachment Tokens.
- [x] The final composer sends plain text to the waiting agent.
- [ ] Mock data and shared types are centralized instead of scattered.

## Work Log

- Slice 1 completed through Issue 001.
- The current App Shell has also received a Vue-green visual polish pass.
- Slice 2 completed with static device status, Select Widget, and Hot Reload/Hot Restart actions.
- Slice 3 completed with a mock full Flutter Widget Tree, selected-node-only highlight, app/framework visual weight differences, search field, refresh button, and draggable left-panel resizing.
- The Widget Tree and TopBar were later connected to the Dart bridge.
- The Live App Surface was later connected to a bridge-owned Device WebSocket,
  WebCodecs rendering path, and official scrcpy server stream.
- Selection Chat 0.0.3 later replaced the Selection Notes placeholder with a
  Chat panel, Bridge Session Chat History, Agent Status, long-poll Agent
  Session handoff, Selection Comment staging, Attachment Tokens, and locatable
  overlay markers.

## Next Candidate Slice

Selection Comment attachment send remains the next Chat workflow candidate.

Expected next work:

- Add snapshot capture for staged Selection Comments.
- Send Selection Comments as Chat attachments.
- Render sent attachment summaries in Chat History.
