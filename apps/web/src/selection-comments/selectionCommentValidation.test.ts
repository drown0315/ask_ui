import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getSelectionCommentInputState,
  SELECTION_COMMENT_BATCH_LIMIT,
  SELECTION_COMMENT_TEXT_LIMIT,
  type SelectedWidgetTarget,
} from './selectionCommentState.ts';

const target: SelectedWidgetTarget = {
  id: 'widget-1',
  displayLabel: 'PrimaryButton',
};

test('enables Add comment only with Select Widget mode and reliable selected widget identity', () => {
  assert.deepEqual(
    getSelectionCommentInputState({
      isSelectWidgetActive: true,
      selectedWidget: target,
      widgetTreeStatus: 'loaded',
      text: 'Make this primary.',
      batchSize: 0,
    }),
    {
      canAdd: true,
      disabledReason: null,
      isTooLong: false,
    },
  );

  assert.equal(
    getSelectionCommentInputState({
      isSelectWidgetActive: false,
      selectedWidget: target,
      widgetTreeStatus: 'loaded',
      text: 'Make this primary.',
      batchSize: 0,
    }).disabledReason,
    'Select Widget mode is required.',
  );

  assert.equal(
    getSelectionCommentInputState({
      isSelectWidgetActive: true,
      selectedWidget: {
        id: 'widget-1',
        displayLabel: '   ',
      },
      widgetTreeStatus: 'loaded',
      text: 'Make this primary.',
      batchSize: 0,
    }).disabledReason,
    'Select a widget with a reliable label.',
  );
});

test('validates Selection Comment text, batch limit, and Widget Tree failure', () => {
  assert.deepEqual(
    getSelectionCommentInputState({
      isSelectWidgetActive: true,
      selectedWidget: target,
      widgetTreeStatus: 'loaded',
      text: ' \n\t ',
      batchSize: 0,
    }),
    {
      canAdd: false,
      disabledReason: 'Type a Selection Comment.',
      isTooLong: false,
    },
  );

  assert.deepEqual(
    getSelectionCommentInputState({
      isSelectWidgetActive: true,
      selectedWidget: target,
      widgetTreeStatus: 'loaded',
      text: 'x'.repeat(SELECTION_COMMENT_TEXT_LIMIT + 1),
      batchSize: 0,
    }),
    {
      canAdd: false,
      disabledReason: `Selection Comment must be ${SELECTION_COMMENT_TEXT_LIMIT} characters or fewer.`,
      isTooLong: true,
    },
  );

  assert.equal(
    getSelectionCommentInputState({
      isSelectWidgetActive: true,
      selectedWidget: target,
      widgetTreeStatus: 'loaded',
      text: 'Make this primary.',
      batchSize: SELECTION_COMMENT_BATCH_LIMIT,
    }).disabledReason,
    `One batch can include ${SELECTION_COMMENT_BATCH_LIMIT} Selection Comments.`,
  );

  assert.equal(
    getSelectionCommentInputState({
      isSelectWidgetActive: true,
      selectedWidget: target,
      widgetTreeStatus: 'error',
      text: 'Make this primary.',
      batchSize: 0,
    }).disabledReason,
    'Widget Tree is unavailable.',
  );
});
