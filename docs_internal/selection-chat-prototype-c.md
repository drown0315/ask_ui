# Selection Chat Prototype C

## Prototype Question

How should Chat work when the developer selects Flutter widgets on the Live App
Surface, adds comments to those selected widgets, and sends the collected
context to the Agent Session?

Prototype C answers this with right-panel Chat and right-panel comment staging.
Selection Comments are created from the selected widget card, staged as
Attachment Tokens in the composer, and sent to the launching Agent Session
through the Bridge Session and agent poller loop.

## Selected Direction

Use the right side of the Ask UI workspace as Chat. The center Live App Surface
remains the visual source of truth and normal device-operation area. The Live
App Surface overlay is only for selection outlines and staged comment markers;
it is not the comment editor and does not enter the Agent Session payload.

The right panel uses the `Chat` header. It should not keep the old `Selection
Notes` heading.

The Chat panel order is:

1. Chat header with Agent Status.
2. Selected widget card with `Add comment`.
3. Chat History.
4. Composer with Attachment Tokens, optional typed message, and Send.

The selected widget card remains fixed within the Chat panel. Chat History is
the primary scroll area, and the composer remains fixed at the bottom. The
selected widget card should have a practical maximum height, with its
staged-comment area scrolling internally if needed, so Chat History is not
crowded out.

## Selection And Overlay

The developer enables Select Widget mode from the top toolbar. While this mode
is active, clicking a widget on the Live App Surface selects it and shows the
DevTools-style purple selection outline when that outline can be located.

Select Widget mode off means normal app operation. When Select Widget mode is
off, the overlay hides the selection outline and Selection Comment markers. When
Select Widget mode is turned back on, Ask UI shows the current selection outline
and staged Selection Comment markers that are already locatable in the current
Device View.

Comment markers are placed automatically near the selected widget highlight and
are not draggable in Prototype C. Markers should stay within the Device View
overlay. Multiple comments on the same widget may be slightly offset or stacked
while keeping their visible comment numbers.

The overlay only shows markers for staged Selection Comments whose widgets can
be located on the current Device View. If the app navigates away from a
comment's widget, the Attachment Token remains but the stale marker should not
be drawn. Prototype C does not need automatic marker restoration if the
developer later navigates back to a screen where an earlier staged widget might
be visible again.

Clicking a visible comment marker makes the comment's widget the current
selected widget, updates the Chat panel, and should attempt to synchronize
Flutter Inspector selection to that widget. If Inspector synchronization fails,
Ask UI should still show the comment's stored widget metadata in the Chat panel.

Normal app operation does not need to automatically clear the current selected
widget. Ask UI may keep showing the last selected widget metadata unless the
Bridge Session or Inspector explicitly reports that the selection is invalid.

## Selected Widget Card

The selected widget card contains core widget information:

- widget display name
- semantic node type when available
- visible text when available
- project-relative source location when available, such as
  `lib/features/home/hero_header.dart:42`
- staged Selection Comments for the current selected widget

The selected widget card should not show secondary detail chips or the full
ancestor path. The Widget Context Panel remains responsible for tree context;
the Chat panel stays focused on comments and handoff.

The selected widget card shows only staged Selection Comments for the current
selected widget. The full unsent batch is represented by Attachment Tokens in
the composer.

Selection Comment entry lives in the selected widget card, below widget
metadata and above the staged comments for that widget. Prototype C does not use
an overlay popover for comment entry.

`Add comment` is available only while Select Widget mode is enabled and Ask UI
has a reliable selected widget. If Select Widget mode is off, the selected
widget card may continue showing the current selected widget metadata, but
comment entry is disabled. Existing staged Selection Comments may still be
edited, deleted, or sent.

When there is no reliable selected widget, the selected widget card should not
show an enabled comment textarea. It should show an empty state such as `Select
a widget to add a comment.` The bottom composer remains the place for a plain
text Chat message.

If the current selected widget is marked invalid or unavailable, `Add comment`
remains disabled even when Select Widget mode is enabled. The selected widget
card should show a lightweight state such as `Selection unavailable on current
screen` so the disabled comment entry is understandable.

If a Widget Tree refresh no longer contains the current selected widget
identity, Ask UI marks the current selection unavailable instead of deleting
staged Selection Comments. If a Widget Tree refresh no longer contains a staged
Selection Comment's widget identity, Ask UI marks that Attachment Token
unavailable and hides its marker while keeping the comment editable and
sendable.

## Selection Comment Rules

A Selection Comment is a developer-authored comment about a selected Flutter UI
target. A staged Selection Comment has been added to the current Chat composer
but has not been sent to the Agent Session yet.

The minimum metadata for a Selection Comment is a widget identity that can map
back to the Flutter Inspector or Widget Tree plus a display label. Source
location, visible text, and semantic information are strongly preferred but may
be unavailable. Without widget identity, `Add comment` remains unavailable.

Prototype C does not require a custom stable widget path across rebuilds or
browser refreshes. The widget identity only needs to be reliable enough for the
current Bridge Session and current widget tree snapshot.

Source location unavailable, visible text unavailable, or semantic node type
unavailable does not block `Add comment`. The UI and payload should omit the
missing field or mark it unavailable.

Framework widgets such as `Padding`, `Align`, or `Container` may receive
Selection Comments. Ask UI should prefer nearby app/user-code source context
when available, but framework nodes are not disallowed.

If Flutter Inspector selection has multiple plausible widget candidates,
Prototype C does not add a second selection popover. Ask UI uses the current
Inspector selection; the developer can adjust the target through the Widget
Context Panel.

When Select Widget mode is on, a widget chosen from the Widget Context Panel can
also become the target for `Add comment`. If the Live App Surface cannot draw a
selection outline for that Widget Tree selection, `Add comment` may still
proceed as long as widget identity and display label are reliable.

Live App Surface readiness does not block `Add comment`; snapshot capture may be
unavailable. Bridge Session readiness does block Chat and Selection Comment
creation, because Chat state and Agent Status belong to the Bridge Session.

If Widget Tree loading fails, plain text Chat remains available, but new
Selection Comments should not be added. Existing staged Selection Comments may
still be edited or sent. `Add comment` should not force a Widget Tree refresh.

Selection Comment text must be non-empty after trimming and is limited to 1000
characters. Over-limit text should show inline validation and should not be
stageable.

After `Add comment` succeeds, the comment textarea clears and keeps focus so
the developer can add another comment to the same selected widget.

Unsubmitted comment text is kept as a draft for its selected widget while the
page remains loaded. If the developer switches from one widget to another and
then back, the original widget's unsubmitted draft should still be available.
Draft text is not a Chat Attachment until `Add comment` is used. A successful
Send clears all unsubmitted selected-widget comment drafts for the current page.

Before sending, the developer can edit or delete staged Selection Comments.
Editing changes only the comment text. It does not change the comment number,
creation order, selected-widget binding, or captured snapshot. Changing the
target requires deleting the comment and creating a new one.

Prototype C does not support manual reordering. If a staged Selection Comment
is deleted, visible comment numbers compact so the pending batch remains `#1`,
`#2`, `#3`, and so on without gaps.

One Chat message should contain at most 20 Selection Comments. After the
current unsent batch reaches that limit, `Add comment` is disabled until the
batch is sent or comments are deleted.

## Snapshot Capture

When `Add comment` succeeds, Ask UI stages the Selection Comment immediately and
starts snapshot capture in the background. The marker and Attachment Token
appear without waiting for capture to finish; the comment then moves from
capturing to available or unavailable snapshot state.

Each Selection Comment captures its own visual context. Multiple comments on the
same widget do not share a single widget-level snapshot by default, because the
app state may change between comments. Later widget availability changes do not
remove or recapture an existing Selection Comment snapshot.

Captured visual context should represent the underlying app/device state at the
moment the Selection Comment was added. It should not include Ask UI overlays
such as the selection outline or comment markers.

The first version captures the underlying full Device View or app snapshot,
not a widget-bounds crop. Snapshot capture uses the existing explicit
screenshot or Snapshot capture capability provided by the bridge/runtime. It
must not derive snapshots from the Live App Surface decoded video frame.

If the explicit capture path is unavailable or fails, the snapshot is marked
unavailable. A comment with text and selected-widget metadata remains stageable
and sendable. Ask UI should show a lightweight `Snapshot unavailable` state on
the staged Selection Comment or Attachment Token. The failure should not open a
modal, block `Add comment`, block sending, or require confirmation.

If the developer sends while one or more staged Selection Comments are still
capturing snapshots, Send waits up to 5 seconds for those captures to finish.
Any snapshot still incomplete after that wait is marked unavailable and the
Chat message continues sending. During this wait, the composer disables Send and
shows a lightweight state such as `Finishing snapshots...`.

If snapshot capture later completes for a deleted staged Selection Comment, Ask
UI discards that result. Deleted comments and their snapshots should not appear
in Chat History or Agent Session payloads.

Prototype C does not provide a per-comment snapshot retry action. The developer
can delete and recreate the Selection Comment if a fresh capture is needed.

Each snapshot file should be no larger than 1.2 MB. The Bridge Session may
compress or downscale the captured image to meet that limit while keeping Ask
UI overlays out of the image. Snapshot files should prefer PNG output because
the Android explicit screenshot path already returns PNG bytes. If the captured
image still cannot fit within 1.2 MB after compression or downscaling, the
Selection Comment remains stageable and the snapshot is marked unavailable.

Captured snapshot bytes are stored as local files managed by the Bridge Session.
Chat History and Selection Comment records keep local snapshot file paths and
availability metadata rather than embedding large base64 images directly in
JSON state. The Agent Session payload passes those local file paths to the
launching coding-agent session.

Snapshot files are cleaned up when the Dart Bridge Session is destroyed or
stopped, not when the browser refreshes, a Chat message sends, or overlay
markers are cleared. If a recorded snapshot file path is missing during an
active Bridge Session, Ask UI treats that snapshot as unavailable instead of
failing the whole Chat message or Chat History view.

Prototype C does not add an extra privacy warning for local source locations or
snapshot file paths because Ask UI is launched inside a local developer Agent
Session. Remote agents or shared links would need a separate privacy design.

## Composer And Attachment Tokens

The bottom of the right panel is a message composer, not another notes summary.
It should not show explanatory copy such as "Message agent" or "2 comments will
be attached with selected widget metadata."

Attachment Tokens are composer labels for staged Selection Comments that have
not been sent yet. They should show only the comment number and widget label,
such as `#1 Hero title`, and should not include the full comment text.

Attachment Tokens are clickable navigation within the current unsent batch.
Clicking a token selects that staged Selection Comment and shows its stored
widget metadata in the right panel. If the widget is currently locatable and
Select Widget mode is on, Ask UI should attempt to synchronize Flutter
Inspector selection and Widget Context Panel selection. If the widget is no
longer visible on the current app screen, clicking its Attachment Token only
navigates the right panel to that comment and stored widget metadata. It should
not restore an overlay marker, navigate the app, or force Flutter Inspector
selection.

When Select Widget mode is off, Attachment Tokens may still navigate the right
panel to staged comments for editing or deletion, but should not force Live App
Surface selection or Flutter Inspector synchronization.

Composer tokens for staged comments whose widgets are no longer visible should
remain in the unsent batch and remain sendable. They should use a lightweight
unavailable state, such as muted styling or a tooltip, instead of disappearing.
The developer may edit or delete those existing comments, but cannot add new
Selection Comments to an unavailable stored widget.

Comment numbers are local to the current unsent batch and the Chat message that
batch becomes. After a successful send, the next batch starts numbering again at
`#1`. Prototype C does not need global comment numbers across Chat History.
Repeated `#1` labels are interpreted within their own Chat message.

Below the Attachment Tokens, the developer can type an optional message to the
Agent Session. The typed message is optional. If the composer contains attached
Selection Comments, the developer can send those attachments without adding a
separate summary message. If the composer contains neither typed text nor
attachments, Send remains unavailable.

Typed composer text is trimmed for send eligibility. Whitespace-only text
counts as no typed message. Typed composer text is limited to 4000 characters;
over-limit text shows inline validation and is not sendable.

In the Chat composer, Enter sends and Shift+Enter inserts a newline. In the
selected widget `Add comment` textarea, Enter should not submit by default; the
developer uses the `Add comment` action to stage the Selection Comment.

Send is enabled only when the Bridge Session is ready, Chat History has loaded,
Agent Status is `Agent ready`, and the composer has either typed text or
Attachment Tokens. Agent Status initially unknown is treated as
`Waiting for agent`.

When Send is disabled because of Agent Status, the composer should show the
reason near the send control. For example, `Agent is not connected.` for
`Waiting for agent`, and `Agent is working on the previous message.` for
`Agent working`. An empty composer can simply leave Send disabled without an
error.

If the Bridge Session is ready but Widget Tree loading fails, pure text Chat
messages remain available. If Chat History initial load fails, the Chat composer
is disabled and should show a retry path; Live App Surface and selection can
continue independently.

## Send Behavior

Sending the composer sends, in order:

- all attached Selection Comments and their selected-widget context
- local snapshot file paths or snapshot unavailable states already captured for
  each attached Selection Comment
- the typed message, if present

The Agent Session payload follows the same order: attachments first, then typed
message. The payload does not include the full Flutter Widget Tree by default.
It includes selected widget context for each Selection Comment, plus nearby path
or ancestor context when already available.

Project root belongs to the message-level Bridge Session context and is not
repeated inside every Selection Comment. Selection Comment source locations in
the Agent Session payload are project-relative; the message-level project root
provides resolution context.

The Agent Session poller receives the current Chat message payload by default,
not the full Chat History. Full Chat History can be exposed separately if a
future agent workflow needs it.

Chat message and attachment payloads include internal IDs for bridge logs,
correlation, and debugging. These IDs are not the user-visible `#1`, `#2`
comment numbers.

Web Send success means the Bridge Session accepted and delivered the message to
the active Agent Session poller. Send does not wait for agent processing. If no
active poller is ready, the bridge API rejects Send; Prototype C does not use an
offline message queue. If the active poller disconnects during handoff before
delivery succeeds, Send fails and the UI preserves the unsent content.

After a successful send, the sent Selection Comments are cleared from the
canvas overlay and from the composer Attachment Token row. Chat History keeps
the sent message and its Attachment Summaries, but the Live App Surface should
no longer show those comment markers. Successful send also clears all
unsubmitted selected-widget comment drafts for the current page, and focus
returns to the Chat composer.

If sending fails, Ask UI preserves the typed message, staged Selection Comments,
overlay markers, Attachment Tokens, and unsubmitted selected-widget drafts so
the developer can retry without losing feedback.

Sending a Chat message does not change Select Widget mode. Hot Reload and Hot
Restart should not clear Chat History or unsent staged Selection Comments.
Overlay markers remain visible only when their widgets can still be confidently
located after the app updates.

Once a Chat message has been accepted by the Bridge Session and taken by the
Agent Session poller, Ask UI does not automatically resend it. If the Agent
Session disconnects while working, Chat History keeps the already sent message
and shows an appropriate message/status rather than creating a duplicate send.
Prototype C does not provide a `Resend` action for already delivered Chat
messages.

## Chat History

Chat History is the sent and received message list in Chat. It uses three
message roles:

- `user`: Web developer messages.
- `agent`: plain text replies posted by the Codex, Claude Code, or similar
  Agent Session through the Ask UI command/API.
- `system`: workflow/system messages inserted by Ask UI commands or the Bridge
  Session, such as command-level agent errors.

Agent Status is independent state and is not a Chat History message role.

A pure text Chat message with no Selection Comments appears as a normal user
message without an empty attachment area. Its Agent Session payload does not
include placeholder selection context.

When a user Chat message includes both Selection Comments and typed text, Chat
History shows Attachment Summaries first and the typed message after them.
Attachment Summaries include the Selection Comment text so the developer can
review what was sent. When available, they also show the project-relative source
location. Attachment Summaries are read-only history; they do not restore old
overlay markers or reactivate widget selection.

Chat History does not show captured Snapshot thumbnails in Prototype C.
Attachment Summaries may indicate whether snapshot context was available, but
Chat History should stay focused on messages and selected-widget summaries.

Sent user messages and Agent Session replies in Chat History are read-only.
Corrections should be sent as new Chat messages rather than editing history.
Prototype C does not need dedicated copy buttons for Chat History messages or
Attachment Summaries; normal text selection and copy is sufficient.

When new Chat History content arrives, Ask UI auto-scrolls only if the developer
is already near the bottom of Chat History. If the developer is reviewing older
messages, Ask UI should avoid forcing scroll and should show a new-message
indicator instead.

Chat History is stored in Bridge Session memory so it survives browser refreshes
and surface reconnects during the same Dart Bridge Session. It belongs to the
Bridge Session, not to an individual browser tab or browser-local storage entry.
Different Flutter app sessions or project roots do not share Chat History.

Chat History is not restored after bridge backend restart or Bridge Session
destruction. Prototype C does not implement crash recovery.

Unsent staged Selection Comments, overlay markers, Attachment Tokens, typed
composer text, and selected-widget drafts do not survive browser refreshes in
Prototype C. If unsent content exists, Ask UI should use the browser's native
unload warning before refresh or close. A custom modal is not required.

The web app loads Chat History from the Bridge Session and receives Chat History
or Agent Status updates through bridge session events/SSE. Prototype C does not
need a separate Chat WebSocket; the Device WebSocket remains dedicated to the
Live App Surface.

If session events/SSE disconnects, Ask UI maps the visible state to
`Waiting for agent`, disables Send, and shows a connection warning rather than
introducing a fourth Agent Status. Reconnect keeps local unsent state and does
not auto-send prepared content. Chat History updates received over SSE do not
affect local unsent composer, staged comments, or drafts.

Prototype C does not support multiple active Chat clients for the same Bridge
Session. A second browser tab should prefer read-only mode over a blank
rejection. It may show Chat History, session status, and SSE updates, but should
disable Live App Surface input, selection, Selection Comment editing, composer
editing, and Send.

Prototype C does not include Chat History search, clear-history, or export UI.
UI copy is English to match the current app.

## Agent Status And Poller Loop

Agent Status tells the developer whether the launching Agent Session can receive
Chat messages. It has three first-version states:

- `Waiting for agent`: no Agent Session poller is currently waiting for Chat
  messages.
- `Agent ready`: an Agent Session poller is currently waiting for the next Chat
  message, so the composer can send.
- `Agent working`: the previous Chat message has been taken by the Agent
  Session poller and the Agent Session is working on it.

Agent Status is driven by the Agent Session poller state. An agent reply
arriving in Chat History does not by itself mean the Agent Session is ready for
another message; Ask UI should show `Agent ready` only after the Agent Session
starts waiting again.

`Agent Session poller` is implementation terminology and should not appear in
the product UI. The UI exposes only Agent Status.

The skill that launches Ask UI should automatically enter the Agent Session
polling loop after starting the bridge, running the Flutter app, and opening the
workbench URL. The developer should not need to run a second manual command to
make Chat become ready.

The normal loop is poll, process, reply, and poll again until the Bridge Session
ends or the Agent Session cannot continue. After processing a Chat message, the
Agent Session posts a plain text reply to Chat History and automatically waits
for the next Chat message again.

Prototype C does not add an `End session` control inside the Chat panel.
Workbench and Agent Session lifecycle controls belong outside the Chat composer.

Agent Status changes do not clear typed composer text, staged Selection
Comments, Attachment Tokens, overlay markers, or selected-widget drafts. If
Agent Status changes from `Waiting for agent` to `Agent ready` while the
developer has prepared content, Ask UI enables Send but does not automatically
send the prepared content.

While Agent Status is `Agent working`, the composer Send action is disabled.
The developer may continue selecting widgets and staging the next set of
Selection Comments, but that next batch cannot be sent until Agent Status is
`Agent ready`.

After a Chat message is sent and Agent Status becomes `Agent working`, Chat may
show a temporary `Agent working...` placeholder. The placeholder is not a
permanent Chat History message and should be removed when the plain text agent
reply or system message arrives.

Agent replies are plain text `agent` messages in Prototype C. They do not carry
a separate task-status schema and do not automatically parse or link `#n`
references to Attachment Summaries.

Agent replies are stored with the user Chat message ID they respond to so the
Bridge Session can correlate logs and replace the correct working placeholder.
The message ID does not need to be visible in the UI.

Codex, Claude Code, or similar agents write back through Ask UI commands. A
normal reply uses the agent reply path and creates an `agent` message. A command
or workflow-level failure uses the agent error path and creates a separate
`system` message in Chat History. If the agent can normally explain that it did
not complete a task, that explanation should be an `agent` reply rather than a
`system` error.

If an agent reply is written successfully but continuing the poll loop fails,
Chat History keeps the agent reply and Agent Status becomes `Waiting for
agent`; Ask UI does not automatically add a system message. If writing an agent
reply or agent error message fails, the command should not continue polling and
should return an error so the Agent Session can retry.

The standard skill-facing command can use a combined form such as
`poll --agent-reply "..."`: first write the agent reply, then continue waiting
for the next Chat message. A corresponding agent-error command/API should write
a `system` message; by default it should then continue polling unless explicitly
stopped or unable to continue.

Each Bridge Session allows only one active Agent Session poller. If a poller is
already active, a second poller request is rejected rather than replacing the
first. Polling is an indefinite long-poll by default, with optional timeout only
for tests or debugging. If a waiting poller disconnects before receiving a
message, Agent Status becomes `Waiting for agent`.

The poller output should include the current message payload and a next-step
instruction telling the Agent Session to process the message, write back a
reply or error, and continue polling. The poller receives the current message
only; it does not receive full Chat History by default.

## Implementation Shape

The web implementation should rename the old `SelectionNotesPanel` concept to
`ChatPanel`. Component code should live under `apps/web/src/components/chat/`.
Chat-specific hooks, types, and API helpers should live under `apps/web/src/chat/`
while reusing existing bridge origin/error utilities where practical.

The bridge implementation should add chat-oriented modules inside the existing
bridge package, such as `apps/bridge/lib/chat/`. This is not a new pub package.
Chat models, store, and service logic should not all be folded into the server
file.

Chat History first-version storage is in Bridge Session memory. Snapshot files
are local files owned by the Bridge Session. Bridge restart or session
destruction ends the session; Prototype C does not recover old Chat History or
snapshot files after restart.

## Testing Notes

Implementation should include focused tests for:

- Bridge chat send, poll, reply, error, and Agent Status transitions.
- Single active poller enforcement.
- Rejection of Send when no active poller is ready.
- Handoff failure preserving Web unsent state.
- Chat History in Bridge Session memory.
- Web composer disabled rules.
- Attachment Token behavior and unavailable states.
- Send success/failure clearing rules.
- Chat History rendering, read-only Attachment Summaries, and system messages.
- Session events/SSE updates with a fake Bridge Session where practical.

Prototype C does not require first-version end-to-end tests against a real
Flutter device and real snapshot capture.

## Removed From Prototype C

Prototype C intentionally removes these elements from the right panel:

- the old `Selection Notes` header
- overlay popover comment entry
- a separate scrollable notes list for all comments
- an Agent packet preview section
- raw file-location lists in Attachment Tokens
- selected-widget detail chips
- full ancestor path in the selected widget card
- captured Snapshot thumbnails in Chat History
- Chat History search, clear, or export controls
- a `Resend` action for already delivered messages

## Product Notes

The first-version workflow is:

1. The launching skill starts the Bridge Session, Flutter app, Ask UI URL, and
   Agent Session polling loop.
2. The developer enables Select Widget mode.
3. The developer selects a widget from the Live App Surface or Widget Context
   Panel.
4. The developer adds one or more Selection Comments from the right-side
   selected widget card.
5. Ask UI stages those comments as Attachment Tokens, captures per-comment
   snapshots in the background, and shows overlay markers only while Select
   Widget mode is on and the targets are locatable.
6. The developer optionally types a Chat message and sends the attachments.
7. The Bridge Session delivers the current message to the active Agent Session
   poller.
8. The Agent Session modifies code with its normal tools, writes a plain text
   reply or system error back to Chat History, and polls again.

This keeps the workflow close to chat while preserving precise Flutter context.
The device screen stays clean: purple outlines and numbered comment markers are
review overlays, not app UI, not the comment editor, and not part of the Agent
Session payload.
