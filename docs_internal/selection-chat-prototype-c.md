# Selection Chat Prototype C

Prototype C is the current Selection Chat direction for the 0.0.3 implementation.

## Layout

Ask UI keeps the three-column workbench:

- Widget Context Panel on the left.
- Live App Surface in the center.
- Chat Panel on the right.

The right panel is Chat-first, not a standalone notes drawer. It shows the selected widget, staged Selection Comments for that widget, Chat History, composer Attachment Tokens, and the plain text Chat composer.

## Staging Model

Selection Comments are staged immediately in local web state. Staging does not send data to the Agent Session. Successful Add comment clears and refocuses the comment textarea.

Staged comments are numbered by their order in the current unsent batch. Deleting a comment compacts visible numbers. A batch is limited to 20 staged Selection Comments.

Per-widget unsubmitted drafts remain available while the page stays loaded. Staged comments and drafts are not persisted across browser refresh.

## Attachment Tokens

Every staged Selection Comment creates one composer Attachment Token. A token shows only the visible number and widget label, for example `#2 TextButton`. It does not expose the full comment text in the composer.

Clicking a locatable token selects the stored widget id locally and asks the bridge to synchronize Flutter Inspector selection. Clicking an unavailable token still opens the stored widget metadata in the Chat Panel, but does not call Inspector selection, navigate the app, or restore stale markers.

Unavailable tokens remain visible because they still represent sendable staged context for later attachment-send work.

## Overlay Markers

Markers are automatic and not draggable. The current implementation places them in a lightweight overlay layer rather than using real widget bounds. A marker is shown only when Select Widget mode is on and the staged widget id is present in the current loaded Widget Tree.

Turning Select Widget mode off hides markers and the selection outline without clearing staged comments or Attachment Tokens. Navigating away can make a staged target unavailable and hide its marker while preserving its token.

Prototype C intentionally does not implement automatic marker restoration after navigating back, precise bounds or marker-position payloads, snapshot capture, or send integration for staged Selection Comments.
