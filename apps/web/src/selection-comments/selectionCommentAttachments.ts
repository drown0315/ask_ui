import type {
  SelectionCommentAttachmentToken,
  SelectionCommentOverlayMarker,
  SelectionCommentState,
} from './selectionCommentTypes.ts';
import type { WidgetBounds } from '../types/bridgeSession.ts';

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
  locatableWidgetBoundsById,
  state,
}: {
  isSelectWidgetActive: boolean;
  locatableWidgetBoundsById: ReadonlyMap<string, WidgetBounds>;
  state: SelectionCommentState;
}): SelectionCommentOverlayMarker[] {
  if (!isSelectWidgetActive) {
    return [];
  }

  return state.comments
    .map((comment, index) => {
      const bounds = locatableWidgetBoundsById.get(comment.widgetId);
      if (bounds === undefined) {
        return null;
      }

      return {
        id: comment.id,
        number: index + 1,
        widgetId: comment.widgetId,
        widgetLabel: comment.widgetLabel,
        bounds,
      };
    })
    .filter((marker) => marker !== null);
}
