import type {
  SelectionCommentAttachmentToken,
  SelectionCommentOverlayMarker,
  SelectionCommentState,
} from './selectionCommentTypes.ts';

export function getSelectionCommentAttachmentTokens(
  state: SelectionCommentState,
  locatableWidgetIds?: ReadonlySet<string>,
): SelectionCommentAttachmentToken[] {
  return state.comments.map((comment, index) => ({
    id: comment.id,
    number: index + 1,
    widgetId: comment.widgetId,
    widgetLabel: comment.widgetLabel,
    isLocatable: locatableWidgetIds?.has(comment.widgetId) ?? true,
  }));
}

export function getSelectionCommentOverlayMarkers({
  isSelectWidgetActive,
  locatableWidgetIds,
  state,
}: {
  isSelectWidgetActive: boolean;
  locatableWidgetIds: ReadonlySet<string>;
  state: SelectionCommentState;
}): SelectionCommentOverlayMarker[] {
  if (!isSelectWidgetActive) {
    return [];
  }

  return state.comments
    .map((comment, index) => ({
      id: comment.id,
      number: index + 1,
      widgetId: comment.widgetId,
      widgetLabel: comment.widgetLabel,
    }))
    .filter((marker) => locatableWidgetIds.has(marker.widgetId));
}
