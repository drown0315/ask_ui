import type {
  NumberedSelectionComment,
  SelectedWidgetTarget,
  SelectionComment,
  SelectionCommentState,
} from './selectionCommentTypes.ts';

export function getSelectionCommentById(
  state: SelectionCommentState,
  commentId: string,
): SelectionComment | null {
  return state.comments.find((comment) => comment.id === commentId) ?? null;
}

export function getSelectionCommentPanelTarget(
  selectedWidget: SelectedWidgetTarget | null,
  activeSelectionComment: SelectionComment | null,
): SelectedWidgetTarget | null {
  if (activeSelectionComment === null) {
    return selectedWidget;
  }

  return {
    id: activeSelectionComment.widgetId,
    displayLabel: activeSelectionComment.widgetLabel,
    ...(activeSelectionComment.sourceLocation
      ? { sourceLocation: activeSelectionComment.sourceLocation }
      : {}),
    ...(activeSelectionComment.visibleText
      ? { visibleText: activeSelectionComment.visibleText }
      : {}),
    ...(activeSelectionComment.semanticInfo
      ? { semanticInfo: activeSelectionComment.semanticInfo }
      : {}),
  };
}

export function getSelectionCommentsForSelectedWidget(
  state: SelectionCommentState,
  selectedWidget: SelectedWidgetTarget | null,
): SelectionComment[] {
  if (selectedWidget === null) {
    return [];
  }

  return state.comments.filter(
    (comment) => comment.widgetId === selectedWidget.id,
  );
}

export function getNumberedSelectionComments(
  state: SelectionCommentState,
  selectedWidget: SelectedWidgetTarget | null,
): NumberedSelectionComment[] {
  return getSelectionCommentsForSelectedWidget(state, selectedWidget).map(
    (comment, index) => ({
      number: index + 1,
      ...comment,
    }),
  );
}
