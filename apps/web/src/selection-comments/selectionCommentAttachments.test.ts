import assert from 'node:assert/strict';
import test from 'node:test';

import {
  addSelectionComment,
  deleteSelectionComment,
  getSelectionCommentAttachmentTokens,
  getSelectionCommentOverlayMarkers,
  type SelectedWidgetTarget,
  type SelectionCommentState,
} from './selectionCommentState.ts';

const target: SelectedWidgetTarget = {
  id: 'widget-1',
  displayLabel: 'PrimaryButton',
};

test('renders Attachment Tokens with compact numbers and widget labels only', () => {
  const otherTarget: SelectedWidgetTarget = {
    id: 'widget-2',
    displayLabel: 'SecondaryButton',
  };
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'Do not show full text');
  state = addSelectionComment(state, otherTarget, 'Also hidden');
  state = deleteSelectionComment(state, 'selection-comment-1');

  assert.deepEqual(getSelectionCommentAttachmentTokens(state), [
    {
      id: 'selection-comment-2',
      number: 1,
      widgetId: 'widget-2',
      widgetLabel: 'SecondaryButton',
      isLocatable: true,
    },
  ]);
});

test('keeps unavailable Attachment Tokens sendable while hiding stale overlay markers', () => {
  const otherTarget: SelectedWidgetTarget = {
    id: 'widget-2',
    displayLabel: 'SecondaryButton',
  };
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'Still here');
  state = addSelectionComment(state, otherTarget, 'No stale marker');

  assert.deepEqual(
    getSelectionCommentAttachmentTokens(state, new Set(['widget-1'])),
    [
      {
        id: 'selection-comment-1',
        number: 1,
        widgetId: 'widget-1',
        widgetLabel: 'PrimaryButton',
        isLocatable: true,
      },
      {
        id: 'selection-comment-2',
        number: 2,
        widgetId: 'widget-2',
        widgetLabel: 'SecondaryButton',
        isLocatable: false,
      },
    ],
  );
  assert.deepEqual(
    getSelectionCommentOverlayMarkers({
      isSelectWidgetActive: true,
      locatableWidgetIds: new Set(['widget-1']),
      state,
    }),
    [
      {
        id: 'selection-comment-1',
        number: 1,
        widgetId: 'widget-1',
        widgetLabel: 'PrimaryButton',
      },
    ],
  );
});

test('hides overlay markers while Select Widget mode is off without clearing staged comments', () => {
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'Keep token');

  assert.deepEqual(
    getSelectionCommentOverlayMarkers({
      isSelectWidgetActive: false,
      locatableWidgetIds: new Set(['widget-1']),
      state,
    }),
    [],
  );
  assert.deepEqual(getSelectionCommentAttachmentTokens(state), [
    {
      id: 'selection-comment-1',
      number: 1,
      widgetId: 'widget-1',
      widgetLabel: 'PrimaryButton',
      isLocatable: true,
    },
  ]);
});
