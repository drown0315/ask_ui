import type {
  SelectedWidgetTarget,
  SelectionComment,
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

export function getSelectionCommentStateAfterSendResult(
  currentState: SelectionCommentState,
  succeeded: boolean,
  sentComments: SelectionComment[],
  sentDraftsByWidgetId: Record<string, string> = {},
): SelectionCommentState {
  if (!succeeded) {
    return currentState;
  }

  if (sentComments.length === 0) {
    return currentState;
  }

  const sentCommentsById = new Map(
    sentComments.map((comment) => [comment.id, comment]),
  );
  const sentDraftEntries = Object.entries(sentDraftsByWidgetId);

  return {
    ...currentState,
    comments: currentState.comments.filter(
      (comment) =>
        !isSameSelectionComment(comment, sentCommentsById.get(comment.id)),
    ),
    draftsByWidgetId: Object.fromEntries(
      Object.entries(currentState.draftsByWidgetId).filter(([widgetId, text]) =>
        sentDraftEntries.every(
          ([sentWidgetId, sentText]) =>
            sentWidgetId !== widgetId || sentText !== text,
        ),
      ),
    ),
  };
}

function isSameSelectionComment(
  currentComment: SelectionComment,
  sentComment: SelectionComment | undefined,
): boolean {
  return (
    sentComment !== undefined &&
    currentComment.id === sentComment.id &&
    currentComment.widgetId === sentComment.widgetId &&
    currentComment.widgetLabel === sentComment.widgetLabel &&
    currentComment.sourceLocation === sentComment.sourceLocation &&
    currentComment.visibleText === sentComment.visibleText &&
    currentComment.semanticInfo === sentComment.semanticInfo &&
    currentComment.text === sentComment.text &&
    isSameSelectionCommentSnapshot(currentComment.snapshot, sentComment.snapshot)
  );
}

function isSameSelectionCommentSnapshot(
  currentSnapshot: SelectionCommentSnapshot,
  sentSnapshot: SelectionCommentSnapshot,
): boolean {
  if (currentSnapshot.status !== sentSnapshot.status) {
    return false;
  }

  if (currentSnapshot.status === 'available') {
    return (
      sentSnapshot.status === 'available' &&
      currentSnapshot.path === sentSnapshot.path &&
      currentSnapshot.mimeType === sentSnapshot.mimeType &&
      currentSnapshot.sizeBytes === sentSnapshot.sizeBytes
    );
  }

  return true;
}

export function getSelectionCommentsAfterSnapshotWait(
  submittedComments: SelectionComment[],
  currentComments: SelectionComment[],
  completedSnapshots: Record<string, SelectionCommentSnapshot> = {},
): SelectionComment[] {
  const currentCommentsById = new Map(
    currentComments.map((comment) => [comment.id, comment]),
  );

  return submittedComments.map((submittedComment) => {
    const currentComment = currentCommentsById.get(submittedComment.id);

    return {
      ...submittedComment,
      snapshot:
        completedSnapshots[submittedComment.id] ??
        currentComment?.snapshot ??
        submittedComment.snapshot,
    };
  });
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
