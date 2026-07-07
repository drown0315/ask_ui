import type {
  SelectedWidgetTarget,
  SelectionCommentSnapshot,
  SelectionCommentState,
} from './selectionCommentTypes.ts';

export * from './selectedWidgetTarget.ts';
export * from './selectionCommentAttachments.ts';
export * from './selectionCommentSelectors.ts';
export * from './selectionCommentTypes.ts';
export * from './selectionCommentValidation.ts';

export function getInitialSelectionCommentState(): SelectionCommentState {
  return {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };
}

export function getDraftForSelectedWidget(
  state: SelectionCommentState,
  selectedWidget: SelectedWidgetTarget | null,
): string {
  if (selectedWidget === null) {
    return '';
  }

  return state.draftsByWidgetId[selectedWidget.id] ?? '';
}

export function updateSelectionCommentDraft(
  state: SelectionCommentState,
  selectedWidget: SelectedWidgetTarget | null,
  text: string,
): SelectionCommentState {
  if (selectedWidget === null) {
    return state;
  }

  return {
    ...state,
    draftsByWidgetId: {
      ...state.draftsByWidgetId,
      [selectedWidget.id]: text,
    },
  };
}

export function addSelectionComment(
  state: SelectionCommentState,
  selectedWidget: SelectedWidgetTarget,
  text: string,
): SelectionCommentState {
  return {
    ...state,
    comments: [
      ...state.comments,
      {
        id: `selection-comment-${state.nextCommentId}`,
        widgetId: selectedWidget.id,
        widgetLabel: selectedWidget.displayLabel,
        ...(selectedWidget.sourceLocation
          ? { sourceLocation: selectedWidget.sourceLocation }
          : {}),
        ...(selectedWidget.visibleText
          ? { visibleText: selectedWidget.visibleText }
          : {}),
        ...(selectedWidget.semanticInfo
          ? { semanticInfo: selectedWidget.semanticInfo }
          : {}),
        text: text.trim(),
        snapshot: {
          status: 'capturing',
        },
      },
    ],
    nextCommentId: state.nextCommentId + 1,
  };
}

export function updateSelectionCommentText(
  state: SelectionCommentState,
  commentId: string,
  text: string,
): SelectionCommentState {
  const trimmedText = text.trim();

  if (trimmedText.length === 0) {
    return state;
  }

  return {
    ...state,
    comments: state.comments.map((comment) =>
      comment.id === commentId
        ? {
            ...comment,
            text: trimmedText,
          }
        : comment,
    ),
  };
}

export function updateSelectionCommentSnapshot(
  state: SelectionCommentState,
  commentId: string,
  snapshot: SelectionCommentSnapshot,
): SelectionCommentState {
  if (!state.comments.some((comment) => comment.id === commentId)) {
    return state;
  }

  return {
    ...state,
    comments: state.comments.map((comment) =>
      comment.id === commentId
        ? {
            ...comment,
            snapshot,
          }
        : comment,
    ),
  };
}

export function deleteSelectionComment(
  state: SelectionCommentState,
  commentId: string,
): SelectionCommentState {
  return {
    ...state,
    comments: state.comments.filter((comment) => comment.id !== commentId),
  };
}
