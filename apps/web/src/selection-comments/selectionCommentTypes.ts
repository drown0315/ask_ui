export const SELECTION_COMMENT_TEXT_LIMIT = 1000;
export const SELECTION_COMMENT_BATCH_LIMIT = 20;

/**
 * Widget target that can receive a staged Selection Comment.
 *
 * It contains the stable widget identity used for drafts, tokens, and markers,
 * plus the display metadata shown in the Chat Panel. Optional fields stay
 * absent when the Widget Tree does not provide that context.
 *
 * Example:
 * A selected Flutter button can be represented as widget id `inspector-2`,
 * display label `PrimaryButton`, source location `lib/home.dart:12`, visible
 * text `Save`, and semantic info `button`.
 */
export type SelectedWidgetTarget = {
  /** Stable Widget Tree node id used to bind drafts and staged comments. */
  id: string;

  /** User-visible widget label shown in the selected widget card and tokens. */
  displayLabel: string;

  /** Project-relative source location when Flutter Inspector provides it. */
  sourceLocation?: string;

  /** Text currently visible in or near the selected widget, when available. */
  visibleText?: string;

  /** Semantic role or accessibility summary for the selected widget. */
  semanticInfo?: string;
};

/**
 * Snapshot state stored on one staged Selection Comment.
 *
 * `capturing` means background capture is still running. `available` carries a
 * Bridge Session local JPEG file path and size. `unavailable` means capture,
 * compression, timeout, or file lookup could not provide a sendable snapshot.
 *
 * Example:
 * A comment starts as `capturing`, may become `available` with a local
 * `/tmp/ask-ui/.../selection-comment-1.jpg` path, or may become `unavailable`
 * without blocking Send.
 */
export type SelectionCommentSnapshot =
  | {
      /** Background snapshot capture is still running for this comment. */
      status: 'capturing';
    }
  | {
      /** Snapshot capture produced a local Bridge Session file. */
      status: 'available';

      /** Local file path passed later to the Agent Session payload. */
      path: string;

      /** Snapshot file type. Prototype C stores sendable snapshots as JPEG. */
      mimeType: 'image/jpeg';

      /** Snapshot file size in bytes after bridge compression or downscaling. */
      sizeBytes: number;
    }
  | {
      /** Snapshot context is not available, but the comment remains sendable. */
      status: 'unavailable';
    };

/**
 * Staged user comment attached to one selected widget target.
 *
 * It stores the comment text, the selected widget metadata copied at Add
 * comment time, and the per-comment snapshot state. Later Widget Tree changes
 * do not mutate this record's target metadata.
 *
 * Example:
 * Comment `selection-comment-1` can attach text `Make this primary` to widget
 * id `inspector-2` with widget label `PrimaryButton` and a still-capturing
 * snapshot.
 */
export type SelectionComment = {
  /** Stable local id for one staged comment in the current browser page. */
  id: string;

  /** Widget target id copied from `SelectedWidgetTarget.id` at Add comment. */
  widgetId: string;

  /** Widget label copied from `SelectedWidgetTarget.displayLabel`. */
  widgetLabel: string;

  /** Source location copied at Add comment, when available. */
  sourceLocation?: string;

  /** Visible text copied at Add comment, when available. */
  visibleText?: string;

  /** Semantic info copied at Add comment, when available. */
  semanticInfo?: string;

  /** User-authored Selection Comment text after trimming. */
  text: string;

  /** Per-comment snapshot capture state and optional local file reference. */
  snapshot: SelectionCommentSnapshot;
};

/**
 * Selection Comment with the current visible number for a selected widget.
 *
 * The number is derived for display and can change after comments are deleted;
 * it is not the stable comment identity.
 *
 * Example:
 * If comment `selection-comment-1` is deleted, `selection-comment-2` can become
 * visible number `1` in the selected widget card.
 */
export type NumberedSelectionComment = SelectionComment & {
  /** Current one-based display number for the selected widget's comments. */
  number: number;
};

/**
 * Compact Chat composer token for one staged Selection Comment.
 *
 * It carries only the stable comment id, current visible number, widget label,
 * and whether the current Widget Tree can still locate the widget target.
 *
 * Example:
 * Token `#1 PrimaryButton` points back to comment `selection-comment-1`; when
 * `isLocatable` is false it remains visible and sendable but does not restore
 * stale selection or markers.
 */
export type SelectionCommentAttachmentToken = {
  /** Stable id of the staged Selection Comment represented by this token. */
  id: string;

  /** Current one-based token number shown as `#n` in the composer. */
  number: number;

  /** Widget target id used when token navigation can synchronize selection. */
  widgetId: string;

  /** Widget label shown next to the token number. */
  widgetLabel: string;

  /** Whether the current Widget Tree still contains this token's widget id. */
  isLocatable: boolean;
};

/**
 * Numbered marker shown on the Live App Surface for a locatable comment.
 *
 * Markers are derived from staged comments while Select Widget mode is active.
 * They do not store geometry because placement belongs to the Live App Surface.
 *
 * Example:
 * A marker with number `2` and widget label `PrimaryButton` is shown only while
 * Select Widget mode is active and the current Widget Tree can locate that
 * widget id.
 */
export type SelectionCommentOverlayMarker = {
  /** Stable id of the staged Selection Comment represented by this marker. */
  id: string;

  /** Current one-based marker number shown on the Live App Surface. */
  number: number;

  /** Widget target id used by the Live App Surface to place the marker. */
  widgetId: string;

  /** Widget label available for marker accessibility or debugging. */
  widgetLabel: string;
};

/**
 * Local browser state for the unsent Selection Comment batch.
 *
 * `comments` are staged comments that can become Chat attachments later.
 * `draftsByWidgetId` stores one unsent textarea draft per widget id.
 * `nextCommentId` provides stable local ids for newly staged comments.
 *
 * Example:
 * Before Send, this state may contain two staged comments plus drafts such as
 * `{ "inspector-2": "Make this primary" }` for widgets the developer edited
 * but has not added as comments yet.
 */
export type SelectionCommentState = {
  /** Current unsent Selection Comments in creation order. */
  comments: SelectionComment[];

  /** Unadded textarea draft text keyed by `SelectedWidgetTarget.id`. */
  draftsByWidgetId: Record<string, string>;

  /** Next integer suffix used for ids such as `selection-comment-3`. */
  nextCommentId: number;
};

/**
 * Add comment enablement derived for the selected widget card.
 *
 * `disabledReason` is user-visible when adding is blocked. `isTooLong` lets the
 * UI style length validation separately from other disabled states.
 *
 * Example:
 * Whitespace-only text returns `canAdd: false`, disabled reason
 * `Type a Selection Comment.`, and `isTooLong: false`.
 */
export type SelectionCommentInputState = {
  /** Whether the Add comment button should be enabled. */
  canAdd: boolean;

  /** User-visible reason when `canAdd` is false, otherwise null. */
  disabledReason: string | null;

  /** Whether the raw textarea text exceeds `SELECTION_COMMENT_TEXT_LIMIT`. */
  isTooLong: boolean;
};
