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
  Attachment Tokens, plain text Agent Session handoff, and Selection Comment
  attachment handoff.
- Mock data and shared UI types.

Out of scope:

- Persistence.
- Production-backed snapshot capture for Selection Comments.

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
| 10 | Agent Composer | Completed through Issue 8 | [0.0.3 Issue 8](../../issues/0.0.3-selection-chat.md#issue-8-send-selection-comments-to-agent-session) | Plain text messages and staged Selection Comments send to the active Agent Session poller. Attachment payloads preserve attachments-before-text order, include message-level project root context, and clear local staged state after successful send. |
| 11 | Selection Comment Snapshots | Partially completed | [0.0.3 Issue 7](../../issues/0.0.3-selection-chat.md#issue-7-add-snapshot-capture-for-selection-comments) | Web state, background capture orchestration, Bridge snapshot API contract, JPEG/full-device request validation, unavailable fallback, send wait/timeout behavior, and fake-capture tests exist. Production bridge still defaults to `UnavailableSnapshotCapture`; a real explicit screenshot/Snapshot adapter and session file cleanup are still needed. |
| 12 | Mock Data And Types | Not started | TBD | Centralize mock data and shared types. |

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
- [x] 11. Send Selection Comments to Agent Session.
- [ ] 12. Partial: Selection Comment snapshot capture pipeline exists, but
  production capture is not connected.
- [ ] 13. Mock data and shared types cleanup.

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
- [x] The final composer sends staged Selection Comments to the waiting agent,
  with attachments before optional typed text.
- [x] Selection Comment attachment payloads include message-level project root,
  project-relative source locations, internal message and attachment IDs,
  widget identity/display labels, optional widget context, and snapshot
  available/unavailable state.
- [x] Successful Selection Comment send clears local staged comments,
  Attachment Tokens, overlay markers, typed composer text, and selected-widget
  drafts; failed send preserves them.
- [ ] Partial: Selection Comment snapshot capture state, Bridge API contract,
  and send-time wait/timeout behavior are implemented with fake capture
  dependencies.
- [ ] Selection Comment snapshots are backed by a production explicit screenshot/Snapshot implementation.
- [ ] Selection Comment snapshot files are cleaned up with Bridge Session lifecycle.
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
- Issue 7 is partially implemented: commit `f03d00c` added the web snapshot
  state machine, background capture orchestration, Bridge snapshot endpoint,
  unavailable fallback, send-time wait/timeout handling, and fake-capture tests.
  It does not yet provide a production `SnapshotCapture` implementation; the
  bridge defaults to `UnavailableSnapshotCapture`.
- Issue 8 is implemented: the web composer builds Selection Comment attachment
  payloads with message-level project root context, project-relative source
  locations, snapshot path/unavailable state, and ordered `parts`; the bridge
  accepts that payload on `/api/sessions/:sessionId/chat/messages` and delivers
  the current Chat message to the active Agent Session poller. Successful send
  clears the local staged batch and composer state; failed send preserves the
  unsent state for retry.
- Issue 8 web send boundaries were tightened after implementation:
  `chatMessagePayload.ts` now owns payload assembly, `useChatSendFlow.ts` owns
  the send transaction and success/failure cleanup, and `useChatComposerFlow.ts`
  stays focused on composer input state and submit handling.

## Next Candidate Slice

Rendering sent attachment summaries in Chat History is the next Chat workflow
candidate.

Expected next work:

- Add a production explicit screenshot/Snapshot implementation for staged
  Selection Comments, including session-scoped file cleanup.
- Render sent attachment summaries in Chat History.
