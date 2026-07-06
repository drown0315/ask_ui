# Ask UI Workbench Product Draft

Status: Draft, not final.

This document captures the current preferred product direction after reviewing the prototype variants. It is intentionally high level and user-facing. Technical payload details, VM Service integration, widget metadata shape, and agent protocol design are out of scope for this draft.

## Product Intent

Ask UI helps Flutter developers give coding agents precise UI change context.

The current problem is that developers often send screenshots to an agent and describe the area that needs to change. A screenshot helps visually, but it does not tell the coding agent which Flutter widget, widget tree position, or source location should be modified. The agent still has to infer the target from pixels and code search.

Ask UI changes that interaction. The developer runs the Flutter app, opens Ask UI in a browser or desktop surface, selects UI directly from the live app view using a DevTools-like interaction, writes comments on the selected areas, and sends those collected Selection Comments to the waiting coding agent.

The product should feel like a professional Flutter debugging workbench, not a generic chatbot with an image attached.

## Target User

The primary user is a Flutter developer using a coding agent such as Codex, Claude Code, or similar tools.

This user can run the app locally or on a target device, inspect UI behavior, and review code changes. They want to shorten the loop between noticing a UI issue and giving the agent enough context to fix it.

Non-developer collaborators may eventually benefit from the selection/comment model, but the first version should optimize for developers.

## Winning Prototype Direction

The preferred direction is Variant A: DevTools Workbench.

This direction uses a three-column layout:

- Left: widget/context panel.
- Center: live Flutter app surface.
- Right: Chat panel with selected-widget context, staged Selection Comments, Chat History, and final agent handoff.

This layout won because it keeps the important parts visible at the same time: the app, the selected UI target, the contextual Flutter structure, and the Selection Comments that will be sent to the agent.

## Core User Flow

1. The developer asks the coding agent to start a Flutter session with Ask UI.
2. The agent runs the Flutter app on a target device or simulator.
3. The agent opens the Ask UI product page and waits for the user's feedback.
4. The developer uses the live app surface to navigate to the screen that needs changes.
5. The developer switches to Select Widget mode.
6. The developer clicks a UI area in the live app.
7. Ask UI highlights the selected area and shows that it has identified the target.
8. The developer writes a comment for that selected area.
9. The comment is saved as a staged Selection Comment, but it is not sent to the agent yet.
10. The developer can continue selecting more UI areas and writing more Selection Comments.
11. When ready, the developer writes a final instruction in the chat/composer area.
12. The developer sends the full set of Selection Comments plus the final instruction to the waiting agent.
13. The agent modifies the code.
14. The developer uses Hot Reload or Hot Restart from Ask UI to refresh the app.
15. The developer verifies the result and can repeat the loop if needed.

## Main Screen Layout

### Top Bar

The top bar contains session-level controls and status.

Expected elements:

- Product/session identity.
- Target device or simulator status.
- Select Widget mode.
- Hot Reload.
- Hot Restart.

The top bar should feel like a development tool toolbar. It should be compact and always available.

### Center: Live App Surface

The center is the primary workspace. It displays the running Flutter app.

The developer should be able to:

- Operate the app normally by clicking the live app surface.
- Switch into selection mode.
- Click UI areas to select them.
- See a clear highlight around the selected area.
- See numbered markers for already staged Selection Comments while Select Widget mode is on and their targets are locatable.

The live app surface should dominate the page. Ask UI should not feel like the app is a small attachment to a chat window.

### Left: Widget Context Panel

The left panel provides Flutter-specific context for the selected area.

Expected content:

- Widget tree or selected widget path.
- Current selected widget in the tree.
- Nearby parent/child context at a readable level.

This panel is supporting context, not the primary interaction surface. It helps the developer confirm that the right widget was selected and helps reinforce that the agent will receive precise context.

### Right: Chat Panel

The right panel is where the user's Chat with the waiting agent and staged selected comments accumulate before being sent.

It should contain:

- Current selection summary.
- Comment box for the current selection.
- Staged Selection Comments for the current selection.
- Attachment Tokens for the unsent Selection Comment batch.
- Agent status.
- Chat History.
- Final instruction composer.
- Send to Agent action.

The right panel should make one thing very clear: selecting and commenting does not immediately send anything to the agent. The user is collecting context first. The agent receives the request only when the user explicitly sends it.

## Selection Comments

A Selection Comment is a user-authored comment attached to a selected UI target.

From the user's perspective, each comment should show:

- A number or marker matching the live app surface.
- A short target label, such as widget name or screen area.
- The user's comment.
- Enough context to trust that the correct area was selected.

The user should be able to collect multiple Selection Comments before sending.

Before send, each staged Selection Comment also appears as a compact Attachment Token in the Chat composer. The token shows only `#n` and the widget label, never the full comment text. Clicking a locatable token may resynchronize the Widget Context Panel and Flutter Inspector selection; clicking an unavailable token shows the stored widget metadata in the Chat Panel without navigating the app or restoring stale overlay markers.

Example Selection Comments:

- "This Open button is too small. Increase height and horizontal padding."
- "The title in this card feels too far left."
- "The spacing between these rows is too tight."

## Final Agent Handoff

The final agent handoff happens from the right-side chat/composer.

The developer can write an overall instruction, such as:

> Fix these three UI issues together. Keep the existing visual style and do not change business logic.

When the developer sends, Ask UI sends the collected Selection Comments and the final instruction to the waiting coding agent.

The UI should present the send action as a deliberate handoff, not as a normal chat message that fires on every note.

## Interaction Principles

- The app surface is the main workspace.
- Selection is precise and visible.
- Comments are staged before sending.
- The user controls when the agent starts working.
- Flutter context is visible enough to build trust, but not so dominant that it overwhelms the UI.
- Hot reload and restart are part of the same review loop.
- The product should feel like a development tool, with some of the ease of Figma-style comments.

## MVP Boundaries

In scope for the first product direction:

- Live app viewing and operation.
- Select Widget mode.
- Single target selection at a time.
- Multiple staged Selection Comments.
- Attachment Tokens for staged Selection Comments.
- Live App Surface markers for currently locatable staged Selection Comments.
- Final send to waiting agent.
- Hot Reload and Hot Restart controls.
- Widget/context panel.

Out of scope for this draft:

- Full bug reproduction recording.
- Video capture.
- Complex issue tracking.
- Multi-user collaboration.
- Detailed agent payload schema.
- Low-level Flutter VM Service implementation details.
- Persistent project history.

## Open Questions

- Should the left widget context panel always be visible, or collapsible by default?
- Should saved Selection Comments support editing, deleting, and reordering in the first version?
- Should the final composer look more like chat, a task brief, or a command bar?
- Should the product support selecting non-widget regions when the exact widget target is ambiguous?
- How much code location detail should be visible to the user before sending?
- Should Hot Reload be triggered by the user only, or can the agent request it after edits?
