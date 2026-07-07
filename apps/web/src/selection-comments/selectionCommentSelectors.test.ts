import assert from 'node:assert/strict';
import test from 'node:test';

import {
  addSelectionComment,
  deleteSelectionComment,
  getNumberedSelectionComments,
  getSelectionCommentById,
  getSelectionCommentPanelTarget,
  type SelectedWidgetTarget,
  type SelectionCommentState,
} from './selectionCommentState.ts';

const target: SelectedWidgetTarget = {
  id: 'widget-1',
  displayLabel: 'PrimaryButton',
};
const capturingSnapshot = {
  status: 'capturing',
} as const;

test('numbers Selection Comments compactly after deletion', () => {
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'First');
  state = addSelectionComment(state, target, 'Second');
  state = addSelectionComment(state, target, 'Third');
  state = deleteSelectionComment(state, 'selection-comment-1');

  assert.deepEqual(getNumberedSelectionComments(state, target), [
    {
      number: 1,
      id: 'selection-comment-2',
      widgetId: 'widget-1',
      widgetLabel: 'PrimaryButton',
      text: 'Second',
      snapshot: capturingSnapshot,
    },
    {
      number: 2,
      id: 'selection-comment-3',
      widgetId: 'widget-1',
      widgetLabel: 'PrimaryButton',
      text: 'Third',
      snapshot: capturingSnapshot,
    },
  ]);
});

test('uses active Attachment Token metadata as the panel target', () => {
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'Still here');

  const activeComment = getSelectionCommentById(state, 'selection-comment-1');

  assert.deepEqual(
    getSelectionCommentPanelTarget(
      {
        id: 'widget-2',
        displayLabel: 'SecondaryButton',
      },
      activeComment,
    ),
    {
      id: 'widget-1',
      displayLabel: 'PrimaryButton',
    },
  );
});
