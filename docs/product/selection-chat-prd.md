# Selection Chat PRD

Status: Draft for the 0.0.3 Selection Chat slices.

## Problem

Ask UI needs a precise handoff path from Flutter UI selection to a coding agent. A developer should be able to identify widgets in the live app, stage comments on them, review the staged context, and send a deliberate Chat message only when ready.

## Goals

- Replace the old right-panel Selection Notes placeholder with a Chat panel.
- Keep Chat History and Agent Status scoped to the Bridge Session.
- Let one waiting Agent Session receive user Chat messages through a long-poll loop.
- Support plain text Chat send and agent reply before attachment send exists.
- Let developers stage, edit, delete, and review Selection Comments for selected widgets.
- Surface staged Selection Comments as composer Attachment Tokens and Live App Surface markers.
- Keep unavailable targets usable as stored context without restoring stale app state.

## Current Scope

The implemented 0.0.3 slices cover the Chat shell, Bridge Session Chat baseline, Agent Session polling, plain text Chat send and reply, Selection Comment staging, Attachment Tokens, and overlay marker staging.

Selection Comments are still local web state in this scope. They are visible as Attachment Tokens but are not sent in the Chat payload yet.

## User Experience

The Chat panel contains:

- Agent Status.
- Selected widget card.
- Staged Selection Comments for the current selected widget.
- Chat History.
- Attachment Tokens for the current unsent Selection Comment batch.
- Plain text Chat composer and Send action.

Add comment is available only while Select Widget mode is enabled, the Widget Tree is loaded, the selected widget has reliable id and label, the comment is non-empty, the comment is at most 1000 characters, and the batch has fewer than 20 Selection Comments.

Attachment Tokens show only `#n` and widget label. They never show the full Selection Comment text. Clicking a locatable token may synchronize Flutter Inspector selection and Widget Context Panel selection. Clicking an unavailable token shows the stored widget metadata in the Chat panel without navigating the app, forcing stale Inspector selection, or restoring stale overlay markers.

Overlay markers are automatic and not draggable. They are visible only while Select Widget mode is on and the staged target is currently locatable in the loaded Widget Tree. Turning Select Widget mode off hides markers without clearing staged comments or tokens. Navigating away can make markers disappear while tokens remain.

## Bridge Chat Contract

The Bridge Session owns Chat History and Agent Status in memory. Browser clients load `GET /api/sessions/:sessionId/chat` and receive Chat updates through `/api/sessions/:sessionId/events`.

Agent Status values are:

- `waiting_for_agent`
- `agent_ready`
- `agent_working`

The browser sends plain text with `POST /api/sessions/:sessionId/chat/messages`. The bridge accepts it only when one Agent Session is actively polling. The launching Agent Session waits with `GET /api/sessions/:sessionId/agent/poll`, then writes back with `/agent/reply` or `/agent/error`.

## Read-Only Tabs

The primary browser client is writable. A second browser tab for the same Bridge Session is read-only when it supplies a different `clientId`. Read-only tabs may observe Chat History and Agent Status, but cannot control the Live App Surface, toggle Select Widget mode, edit Selection Comments, edit the composer, or Send.

## Out Of Scope

- Sending Selection Comments as Chat attachments.
- Snapshot capture for Selection Comments.
- Attachment summaries in sent Chat History.
- Persisting Chat History or staged comments across bridge restart.
- Marker positions, selected bounds, or precise overlay coordinate payloads.
- Automatic marker restoration after navigating back to a previously locatable target.
- Resend, clear, search, export, or end-session controls.
