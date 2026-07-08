/**
 * Return whether the browser should warn before leaving a Chat with unsent work.
 *
 * Args:
 *   composerText: Current text in the Chat composer. Whitespace-only text does
 *     not count as unsent work.
 *   selectionCommentCount: Number of staged Selection Comments that have not
 *     been sent to the Agent Session.
 *   selectionCommentDraftsByWidgetId: Unadded selected-widget comment drafts,
 *     keyed by widget id. Whitespace-only drafts do not count as unsent work.
 *
 * Returns:
 *   `true` when any typed composer text, staged Selection Comment, or non-empty
 *   selected-widget draft would be lost on browser unload; otherwise `false`.
 *
 * Example:
 *   Composer text `""`, one staged Selection Comment, and no drafts returns
 *   `true` because the staged comment exists only in the current browser page.
 */
export function shouldWarnBeforeChatUnload({
  composerText,
  selectionCommentCount,
  selectionCommentDraftsByWidgetId,
}: {
  composerText: string;
  selectionCommentCount: number;
  selectionCommentDraftsByWidgetId: Record<string, string>;
}): boolean {
  return (
    composerText.trim().length > 0 ||
    selectionCommentCount > 0 ||
    Object.values(selectionCommentDraftsByWidgetId).some(
      (draft) => draft.trim().length > 0,
    )
  );
}
