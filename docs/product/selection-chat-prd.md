# Selection Chat PRD

## Problem Statement

Ask UI helps Flutter developers give coding agents precise UI change context, but the current right panel is still shaped like a placeholder notes area rather than a real conversation with the Agent Session. A developer can inspect the app, select widgets, and view widget context, but they still need a reliable way to stage selected-widget comments, attach visual context, send that context to the launching Codex or Claude Code session, and see the agent's replies in the same workbench.

Without Selection Chat, the developer has to translate UI observations into prose outside Ask UI. That loses the connection between the selected Flutter widget, source location, visual state, and coding-agent conversation.

## Solution

Build the right panel as Chat. The developer selects Flutter UI targets from the Live App Surface or Widget Context Panel, adds Selection Comments from the selected widget card, sees those comments staged as Attachment Tokens in the composer, and sends them to the launching Agent Session. The Bridge Session delivers the current Chat message to exactly one active Agent Session poller. The Agent Session modifies code with its normal tools, writes a plain text reply or system message back into Chat History, and then waits for the next message.

Selection Comments capture explicit screenshot or Snapshot context at Add comment time, store snapshots as local Bridge Session files, and send local file paths to the Agent Session. The Live App Surface overlay remains temporary review UI: selection outlines and markers are shown only while Select Widget mode is active and targets are locatable; overlay geometry and marker positions are not part of the Agent Session payload.

## User Stories

1. As a Flutter developer, I want the right panel to be Chat, so that I can talk to the Agent Session without leaving Ask UI.
2. As a Flutter developer, I want Chat to be bound to the Agent Session that launched the workbench, so that my comments return to the coding agent that can edit the project.
3. As a Flutter developer, I want the Chat panel to show Agent Status, so that I know whether the Agent Session can receive a message.
4. As a Flutter developer, I want `Agent ready` to mean an Agent Session poller is waiting, so that Send is only enabled when the agent can receive my message.
5. As a Flutter developer, I want `Agent working` to mean my previous message has been taken by the Agent Session, so that I do not send conflicting follow-up work too early.
6. As a Flutter developer, I want `Waiting for agent` to mean no poller is connected, so that I understand why Send is disabled.
7. As a Flutter developer, I want the selected widget card to stay visible in Chat, so that I can see the current target while writing comments.
8. As a Flutter developer, I want the selected widget card to show widget name, source location, visible text, and semantic information when available, so that I can trust the target.
9. As a Flutter developer, I want the selected widget card to avoid full ancestor paths and secondary detail chips, so that it stays focused on comment creation.
10. As a Flutter developer, I want to add a Selection Comment from the selected widget card, so that comments are clearly attached to the current Flutter UI target.
11. As a Flutter developer, I do not want comment entry in an overlay popover, so that the Live App Surface remains a clean device-operation area.
12. As a Flutter developer, I want Add comment to require Select Widget mode, so that comment creation stays part of the selection workflow.
13. As a Flutter developer, I want Select Widget mode off to hide selection outlines and comment markers, so that the Live App Surface behaves like normal app operation.
14. As a Flutter developer, I want Select Widget mode on again to restore locatable selection overlays, so that I can continue staging comments.
15. As a Flutter developer, I want Add comment disabled when no reliable selected widget exists, so that I do not create unattached comments.
16. As a Flutter developer, I want Add comment disabled for invalid or unavailable selections, so that I do not create new comments for stale targets.
17. As a Flutter developer, I want the selected widget card to explain unavailable selections, so that disabled comment entry is understandable.
18. As a Flutter developer, I want source location, visible text, and semantic info to be optional, so that I can still comment when the core widget identity is reliable.
19. As a Flutter developer, I want framework widgets to be valid comment targets, so that layout issues on Padding, Align, Container, and similar widgets can be described.
20. As a Flutter developer, I want the Widget Context Panel to let me refine the selected widget, so that I can choose a more precise target without a center-screen candidate popup.
21. As a Flutter developer, I want Widget Tree selections to be comment targets when Select Widget mode is on, so that I can target widgets from the tree as well as the Live App Surface.
22. As a Flutter developer, I want Add comment to work even when a visual selection outline cannot be drawn, so that reliable widget identity remains enough.
23. As a Flutter developer, I want Live App Surface readiness not to block comment creation, so that widget metadata can still be sent when visual capture is unavailable.
24. As a Flutter developer, I want Widget Tree load failure to block new Selection Comments but not plain text Chat, so that I can still communicate with the agent.
25. As a Flutter developer, I want Add comment to stage immediately, so that marker and token feedback appears without waiting for snapshot capture.
26. As a Flutter developer, I want each Selection Comment to capture its own visual context, so that each comment carries evidence from its creation moment.
27. As a Flutter developer, I want captured visual context to exclude Ask UI overlays, so that screenshots represent the underlying app.
28. As a Flutter developer, I want snapshots captured from an explicit screenshot or Snapshot capability, so that they are not derived from decoded video frames.
29. As a Flutter developer, I want snapshot capture failure to be non-blocking, so that selected-widget comments can still be sent.
30. As a Flutter developer, I want snapshot unavailable state to be visible but lightweight, so that I know when a comment lacks visual context.
31. As a Flutter developer, I want Send to wait briefly for in-progress snapshots, so that available snapshots are included without making Chat hang indefinitely.
32. As a Flutter developer, I want snapshots stored as local files, so that the Agent Session can receive file paths instead of large base64 payloads.
33. As a Flutter developer, I want snapshot files cleaned up when the Dart Bridge Session is destroyed or stopped, so that local temporary files do not outlive the session.
34. As a Flutter developer, I want a missing snapshot path to degrade to snapshot unavailable, so that Chat History still renders.
35. As a Flutter developer, I want Attachment Tokens in the composer, so that I can see which Selection Comments are staged before sending.
36. As a Flutter developer, I want Attachment Tokens to show only comment number and widget label, so that the composer stays compact.
37. As a Flutter developer, I want Attachment Tokens to be clickable, so that I can navigate to staged comments for editing or deletion.
38. As a Flutter developer, I want Attachment Tokens for unavailable widgets to remain sendable, so that navigation changes do not destroy my staged batch.
39. As a Flutter developer, I want unavailable Attachment Tokens to avoid forcing Inspector selection or overlay restoration, so that Ask UI does not pretend stale targets are on the current screen.
40. As a Flutter developer, I want staged Selection Comments editable before send, so that I can correct text without recreating the target.
41. As a Flutter developer, I want staged Selection Comments deletable before send, so that mistaken comments can be removed.
42. As a Flutter developer, I want deletion to compact visible comment numbers, so that the pending batch remains easy to read.
43. As a Flutter developer, I want comment numbers local to the current Chat message, so that each sent message has a compact attachment list.
44. As a Flutter developer, I want up to 20 Selection Comments per Chat message, so that one batch can cover a screen without overwhelming the agent.
45. As a Flutter developer, I want Selection Comment text to require non-empty content and practical length limits, so that attachments remain meaningful.
46. As a Flutter developer, I want the typed composer message to be optional, so that Selection Comments alone can be sent.
47. As a Flutter developer, I want pure text Chat messages to work without attachments, so that I can communicate with the agent even without selecting widgets.
48. As a Flutter developer, I want Enter to send in the Chat composer and Shift+Enter to insert a newline, so that Chat behaves predictably.
49. As a Flutter developer, I want Add comment to keep focus in the comment textarea, so that I can add several comments to the same widget quickly.
50. As a Flutter developer, I want successful Send to clear staged comments, Attachment Tokens, overlay markers, typed message, and selected-widget drafts, so that the current batch is closed.
51. As a Flutter developer, I want failed Send to preserve everything unsent, so that I can retry without losing work.
52. As a Flutter developer, I want Send not to change Select Widget mode, so that I control the selection workflow.
53. As a Flutter developer, I want Hot Reload and Hot Restart not to clear Chat History or unsent comments, so that verification does not lose my feedback.
54. As a Flutter developer, I want Chat History to show sent Attachment Summaries before the typed message, so that selected-widget context is visible first.
55. As a Flutter developer, I want Attachment Summaries to include comment text and source location when available, so that I can review what was sent.
56. As a Flutter developer, I do not want Snapshot thumbnails in Chat History, so that the right panel stays focused and compact.
57. As a Flutter developer, I want Chat History messages to be read-only, so that the record of what the agent saw does not change after sending.
58. As a Flutter developer, I want Chat History to survive browser refreshes during the same Bridge Session, so that I do not lose the conversation.
59. As a Flutter developer, I accept unsent staged comments and drafts not surviving refresh, so that the first version avoids complex recovery semantics.
60. As a Flutter developer, I want a browser unload warning when unsent content exists, so that I do not accidentally lose a prepared batch.
61. As a Flutter developer, I want Chat History and Agent Status updates over Bridge Session events, so that Chat does not need a separate WebSocket.
62. As a Flutter developer, I want a second browser tab to be read-only, so that it does not create competing composers or device controls.
63. As a Flutter developer, I want no Chat History search, clear, or export controls in the first version, so that the MVP remains focused.
64. As a Flutter developer, I want the launching skill to automatically enter the polling loop, so that Chat becomes ready without another manual command.
65. As a Flutter developer, I want the Agent Session to reply and poll again, so that Chat feels continuous.
66. As a Flutter developer, I want no Chat-panel End Session control, so that lifecycle stays outside the composer.
67. As a Flutter developer, I want Agent replies to be plain text Chat messages, so that replies stay readable.
68. As a Flutter developer, I want command-level agent errors to appear as separate system messages, so that workflow failures are visible in Chat History.
69. As a Flutter developer, I want Agent Status changes not to clear prepared content, so that connection changes do not lose comments.
70. As a Flutter developer, I want no automatic resend, so that the agent does not process the same UI request twice.
71. As a Flutter developer, I want Send rejected when no active poller is ready, so that Ask UI does not become an offline queue.
72. As a Flutter developer, I want a single active poller per Bridge Session, so that only the launching Agent Session receives work.
73. As a Flutter developer, I want poller output to include the current message and a next-step instruction, so that the agent loop remains reliable.

## Implementation Decisions

- Use the project glossary terms: Chat, Chat History, Chat Attachment, Attachment Token, Attachment Summary, Selection Comment, Staged Selection Comment, Agent Session, Bridge Session, and Agent Status.
- Rename the old Selection Notes concept to Chat in product UI and implementation naming.
- Use a right-panel Chat layout: header with Agent Status, selected widget card, Chat History, and composer.
- Keep the selected widget card fixed in the Chat panel, with Chat History as the primary scroll area and the composer fixed at the bottom.
- Keep Selection Comment entry in the selected widget card. Do not use an overlay popover.
- Limit the selected widget card to core metadata and current-widget staged Selection Comments. Keep full tree context in the Widget Context Panel.
- Require Select Widget mode and reliable selected-widget identity for Add comment.
- Allow source location, visible text, and semantic info to be unavailable without blocking Add comment.
- Allow framework widgets to receive Selection Comments.
- Do not add a secondary candidate picker when Inspector selection is ambiguous.
- Allow Widget Context Panel selection to become the comment target when Select Widget mode is on.
- Do not require visual bounds or selection outline availability to create a Selection Comment if widget identity and label are reliable.
- Disable new Selection Comments when Widget Tree loading fails, but allow pure text Chat and existing staged-comment maintenance.
- Stage Selection Comments immediately and start snapshot capture in the background.
- Capture visual context per Selection Comment, not per widget.
- Use the existing explicit screenshot or Snapshot capability. Do not derive snapshots from decoded video frames.
- Capture full app/device visual context rather than widget-bounds crops.
- Exclude Ask UI overlays from snapshots.
- Prefer PNG snapshot files, with a per-file size limit of 1.2 MB.
- If snapshot capture, compression, or file lookup fails, mark snapshot unavailable and continue.
- Store snapshot bytes as local Bridge Session files. Store local paths and availability metadata in Chat state.
- Clean up snapshot files when the Dart Bridge Session is destroyed or stopped.
- Do not add per-comment snapshot retry in the first version.
- Show Attachment Tokens as number plus widget label only.
- Use Attachment Tokens for unsent-batch navigation and editing.
- Keep unavailable Attachment Tokens visible and sendable, but do not force app navigation, overlay restoration, or Inspector selection.
- Keep comment numbers local to the current unsent batch and the Chat message it becomes.
- Do not add global comment numbering.
- Allow multiple widgets and multiple comments per widget in one Chat message.
- Limit one Chat message to 20 Selection Comments.
- Require non-empty Selection Comment text after trimming, with a 1000-character limit.
- Treat whitespace-only typed composer text as absent, with a 4000-character limit.
- Let Selection Comments alone be sendable without a typed message.
- Let plain text messages be sendable without Selection Comments.
- Use Enter to send in the Chat composer and Shift+Enter for newline. Do not submit Add comment with Enter by default.
- On successful Send, clear the sent batch, overlay markers, Attachment Tokens, typed composer text, and selected-widget drafts.
- On failed Send, preserve all unsent state.
- Do not change Select Widget mode on Send.
- Do not automatically resend delivered messages.
- Do not provide a Resend action in the first version.
- Show Attachment Summaries before typed text in Chat History.
- Include Selection Comment text and project-relative source location in Attachment Summaries when available.
- Do not show captured Snapshot thumbnails in Chat History.
- Make sent user messages, agent replies, and Attachment Summaries read-only.
- Persist Chat History in Bridge Session memory. Do not persist unsent staged comments or drafts across browser refreshes.
- Use native browser unload warning when unsent content exists.
- Load Chat History from the Bridge Session and receive Chat History and Agent Status updates through Bridge Session events.
- Do not create a separate Chat WebSocket.
- Treat session events disconnect as Waiting for agent plus a connection warning.
- Make a second browser tab read-only rather than another active composer.
- Do not include Chat History search, clear-history, or export UI in the first version.
- Drive Agent Status from Agent Session poller state, not from agent reply arrival.
- Use `Waiting for agent`, `Agent ready`, and `Agent working` as first-version Agent Status values.
- Keep poller terminology out of product UI.
- Require the launching skill to start the Agent Session polling loop after opening Ask UI.
- Use the loop: poll, process, reply, poll again.
- Do not add End Session control inside Chat.
- Store Chat History message roles as user, agent, and system.
- Store command-level agent errors as system messages. Store normal agent replies as agent messages, even when the reply explains a failure.
- Correlate agent replies with the user message ID they answer.
- Allow a combined poll command with agent reply to write the reply and continue waiting.
- Provide an agent error path that writes a system message and normally continues polling unless stopped or unable to continue.
- Allow only one active Agent Session poller per Bridge Session. Reject additional concurrent pollers.
- Use indefinite long-poll by default, with optional timeout only for tests or debugging.
- Reject Send when no active poller is ready. Do not provide an offline message queue.
- Treat delivery failure during Send handoff as Send failure, preserving Web unsent state.
- Return the current Chat message payload to the poller by default, not full Chat History.
- Include internal message and attachment IDs for bridge logs, correlation, and debugging.
- Put project root in message-level Bridge Session context. Use project-relative source locations in Selection Comment payloads.
- Do not include the full Flutter Widget Tree by default in the Agent Session payload.
- Build web Chat as a deep module around Chat state, composer rules, attachment navigation, Agent Status, and rendering.
- Build bridge Chat as a deep module around Chat History, poller lifecycle, send handoff, reply/error recording, and snapshot references.
- Keep Chat implementation inside the existing bridge package; do not create a separate pub package.
- Use Bridge Session memory for first-version Chat History storage. Do not implement crash recovery.

## Testing Decisions

- Tests should verify externally observable behavior: rendered Chat states, disabled/enabled composer rules, Bridge Session HTTP responses, session events, poller responses, Chat History records, and payload shape.
- Avoid tests that depend on private helper names or implementation-only state. Test module contracts and user-visible outcomes.
- Web tests should cover ChatPanel layout states, Agent Status display, composer enablement, validation limits, Attachment Token rendering, unavailable token behavior, staged-comment editing and deletion, Send success clearing, Send failure preservation, and Chat History rendering.
- Web tests should cover the distinction between Attachment Tokens and Attachment Summaries.
- Web tests should cover Select Widget mode interactions that enable or disable Add comment.
- Web tests should cover unload-warning eligibility when unsent content exists.
- Bridge tests should cover Chat History storage in Bridge Session memory, single active poller enforcement, Send rejection when no poller is ready, Send delivery to an active poller, delivery failure behavior, agent reply recording, agent error recording, and Agent Status transitions.
- Bridge tests should cover poller disconnect before message delivery and after message delivery.
- Bridge tests should cover message roles and reply-to-message correlation.
- Bridge tests should cover snapshot reference metadata, snapshot unavailable state, and cleanup boundaries at Bridge Session destruction.
- Integration-style tests with fake Bridge Sessions should cover session events/SSE updates for Chat History and Agent Status.
- Existing bridge session/server tests provide prior art for HTTP behavior and fake dependency injection.
- Existing web session bootstrap, widget tree, and live app surface tests provide prior art for focused state modules and rendered-state assertions.
- First-version tests do not need to run against a real Flutter app, real Android device, real screenshot capture path, or real coding-agent CLI.

## Out of Scope

- Overlay popover comment entry.
- Full Widget Tree in every Chat payload.
- Global comment numbering across Chat History.
- Manual comment reordering.
- Resend for already delivered messages.
- Offline message queue when no Agent Session poller is active.
- Multiple active Chat composers for one Bridge Session.
- Multiple active Agent Session pollers for one Bridge Session.
- Snapshot thumbnails in Chat History.
- Snapshot deduplication.
- Widget-bounds snapshot crops.
- Snapshot capture from decoded video frames.
- Per-comment snapshot retry.
- Chat History persistence across bridge backend restart.
- Crash recovery for Bridge Session Chat state.
- Chat History search, clear, or export UI.
- End Session control inside Chat.
- Remote agent or shared-link privacy design.
- Real-device end-to-end coverage as a first-version requirement.

## Further Notes

- This PRD respects the accepted Agent Chat Long-Poll ADR.
- The Prototype C decision is "Chat with right-panel comment staging."
- The right panel is Chat, not Selection Notes.
- The Bridge Session owns Chat History, Agent Status, poller handoff, and snapshot file references.
- The Agent Session owns code editing authority and communicates through the poll/reply loop.
- Snapshot local file paths are intended for local coding-agent sessions on the same machine.
- The `ready-for-agent` triage label should be applied when this PRD is published to the issue tracker.
