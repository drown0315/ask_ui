import {
  SELECTION_COMMENT_BATCH_LIMIT,
  SELECTION_COMMENT_TEXT_LIMIT,
  type SelectedWidgetTarget,
  type SelectionCommentInputState,
} from './selectionCommentTypes.ts';

export type SelectionCommentTextareaInputPolicy = {
  maxLength: number | undefined;
};

export function getSelectionCommentInputState({
  isReadOnly = false,
  isSelectWidgetActive,
  selectedWidget,
  widgetTreeStatus,
  text,
  batchSize,
}: {
  isReadOnly?: boolean;
  isSelectWidgetActive: boolean;
  selectedWidget: SelectedWidgetTarget | null;
  widgetTreeStatus: 'loading' | 'loaded' | 'error';
  text: string;
  batchSize: number;
}): SelectionCommentInputState {
  const isTooLong = text.length > SELECTION_COMMENT_TEXT_LIMIT;

  if (isReadOnly) {
    return {
      canAdd: false,
      disabledReason: 'Read-only browser tabs cannot edit Selection Comments.',
      isTooLong,
    };
  }

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

/**
 * Return DOM input constraints for Selection Comment textareas.
 *
 * The UI keeps over-limit text editable so the existing inline validation can
 * explain why Add comment is disabled.
 */
export function getSelectionCommentTextareaInputPolicy(): SelectionCommentTextareaInputPolicy {
  return {
    maxLength: undefined,
  };
}
