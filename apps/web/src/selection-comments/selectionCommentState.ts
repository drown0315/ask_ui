import type { WidgetTreeNode } from '../types/bridgeSession.ts';

export const SELECTION_COMMENT_TEXT_LIMIT = 1000;
export const SELECTION_COMMENT_BATCH_LIMIT = 20;

export type SelectedWidgetTarget = {
  id: string;
  displayLabel: string;
  sourceLocation?: string;
  visibleText?: string;
  semanticInfo?: string;
};

export type SelectionComment = {
  id: string;
  widgetId: string;
  widgetLabel: string;
  sourceLocation?: string;
  visibleText?: string;
  semanticInfo?: string;
  text: string;
};

export type NumberedSelectionComment = SelectionComment & {
  number: number;
};

export type SelectionCommentAttachmentToken = {
  id: string;
  number: number;
  widgetId: string;
  widgetLabel: string;
  isLocatable: boolean;
};

export type SelectionCommentOverlayMarker = {
  id: string;
  number: number;
  widgetId: string;
  widgetLabel: string;
};

export type SelectionCommentState = {
  comments: SelectionComment[];
  draftsByWidgetId: Record<string, string>;
  nextCommentId: number;
};

export type SelectionCommentInputState = {
  canAdd: boolean;
  disabledReason: string | null;
  isTooLong: boolean;
};

export function getInitialSelectionCommentState(): SelectionCommentState {
  return {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };
}

export function getSelectedWidgetTarget(
  root: WidgetTreeNode,
  selectedWidgetId: string | null,
): SelectedWidgetTarget | null {
  if (selectedWidgetId === null) {
    return null;
  }

  const node = findWidgetTreeNode(root, selectedWidgetId);

  if (node === null) {
    return null;
  }

  return {
    id: stringifyWidgetContextValue(node.id) ?? '',
    displayLabel: stringifyWidgetContextValue(node.label) ?? '',
    sourceLocation: stringifyWidgetContextValue(node.sourceLocation),
    visibleText: stringifyWidgetContextValue(node.visibleText),
    semanticInfo: stringifyWidgetContextValue(node.semanticInfo),
  };
}

export function getLocatableWidgetIds(root: WidgetTreeNode): Set<string> {
  const locatableWidgetIds = new Set<string>();

  collectLocatableWidgetIds(root, locatableWidgetIds);

  return locatableWidgetIds;
}

function collectLocatableWidgetIds(
  node: WidgetTreeNode,
  locatableWidgetIds: Set<string>,
) {
  locatableWidgetIds.add(node.id);

  const children = Array.isArray(node.children) ? node.children : [];

  for (const child of children) {
    collectLocatableWidgetIds(child, locatableWidgetIds);
  }
}

function stringifyWidgetContextValue(value: unknown): string | undefined {
  if (value === null || value === undefined) {
    return undefined;
  }

  if (typeof value === 'string') {
    return value;
  }

  if (
    typeof value === 'number' ||
    typeof value === 'boolean' ||
    typeof value === 'bigint'
  ) {
    return String(value);
  }

  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function findWidgetTreeNode(
  node: WidgetTreeNode,
  selectedWidgetId: string,
): WidgetTreeNode | null {
  if (node.id === selectedWidgetId) {
    return node;
  }

  const children = Array.isArray(node.children) ? node.children : [];

  for (const child of children) {
    const found = findWidgetTreeNode(child, selectedWidgetId);

    if (found !== null) {
      return found;
    }
  }

  return null;
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
      },
    ],
    nextCommentId: state.nextCommentId + 1,
  };
}

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

export function deleteSelectionComment(
  state: SelectionCommentState,
  commentId: string,
): SelectionCommentState {
  return {
    ...state,
    comments: state.comments.filter((comment) => comment.id !== commentId),
  };
}

export function getSelectionCommentInputState({
  isSelectWidgetActive,
  selectedWidget,
  widgetTreeStatus,
  text,
  batchSize,
}: {
  isSelectWidgetActive: boolean;
  selectedWidget: SelectedWidgetTarget | null;
  widgetTreeStatus: 'loading' | 'loaded' | 'error';
  text: string;
  batchSize: number;
}): SelectionCommentInputState {
  const isTooLong = text.length > SELECTION_COMMENT_TEXT_LIMIT;

  if (!isSelectWidgetActive) {
    return {
      canAdd: false,
      disabledReason: 'Select Widget mode is required.',
      isTooLong,
    };
  }

  if (widgetTreeStatus === 'error') {
    return {
      canAdd: false,
      disabledReason: 'Widget Tree is unavailable.',
      isTooLong,
    };
  }

  if (
    selectedWidget === null ||
    selectedWidget.id.trim().length === 0 ||
    selectedWidget.displayLabel.trim().length === 0
  ) {
    return {
      canAdd: false,
      disabledReason: 'Select a widget with a reliable label.',
      isTooLong,
    };
  }

  if (text.trim().length === 0) {
    return {
      canAdd: false,
      disabledReason: 'Type a Selection Comment.',
      isTooLong,
    };
  }

  if (isTooLong) {
    return {
      canAdd: false,
      disabledReason: `Selection Comment must be ${SELECTION_COMMENT_TEXT_LIMIT} characters or fewer.`,
      isTooLong,
    };
  }

  if (batchSize >= SELECTION_COMMENT_BATCH_LIMIT) {
    return {
      canAdd: false,
      disabledReason: `One batch can include ${SELECTION_COMMENT_BATCH_LIMIT} Selection Comments.`,
      isTooLong,
    };
  }

  return {
    canAdd: true,
    disabledReason: null,
    isTooLong,
  };
}
