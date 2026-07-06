import assert from 'node:assert/strict';
import test from 'node:test';

import {
  addSelectionComment,
  deleteSelectionComment,
  getDraftForSelectedWidget,
  getNumberedSelectionComments,
  getSelectionCommentsForSelectedWidget,
  getSelectionCommentInputState,
  getSelectedWidgetTarget,
  SELECTION_COMMENT_BATCH_LIMIT,
  SELECTION_COMMENT_TEXT_LIMIT,
  updateSelectionCommentText,
  updateSelectionCommentDraft,
  type SelectionCommentState,
  type SelectedWidgetTarget,
} from './selectionCommentState.ts';
import type { WidgetTreeNode } from '../types/bridgeSession.ts';

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

test('stages comments for the selected widget and preserves per-widget drafts', () => {
  const otherTarget: SelectedWidgetTarget = {
    id: 'widget-2',
    displayLabel: 'SecondaryButton',
  };
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = updateSelectionCommentDraft(state, target, 'Make this primary');
  state = updateSelectionCommentDraft(state, otherTarget, 'Move this lower');
  state = addSelectionComment(state, target, '  Make this primary  ');
  state = addSelectionComment(state, otherTarget, 'Move this lower');

  assert.deepEqual(getSelectionCommentsForSelectedWidget(state, target), [
    {
      id: 'selection-comment-1',
      widgetId: 'widget-1',
      widgetLabel: 'PrimaryButton',
      text: 'Make this primary',
    },
  ]);
  assert.deepEqual(getSelectionCommentsForSelectedWidget(state, otherTarget), [
    {
      id: 'selection-comment-2',
      widgetId: 'widget-2',
      widgetLabel: 'SecondaryButton',
      text: 'Move this lower',
    },
  ]);
  assert.equal(getDraftForSelectedWidget(state, target), 'Make this primary');
  assert.equal(getDraftForSelectedWidget(state, otherTarget), 'Move this lower');
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

test('edits comment text and deletes comments with compact visible numbering', () => {
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'First');
  state = addSelectionComment(state, target, 'Second');
  state = addSelectionComment(state, target, 'Third');
  state = updateSelectionCommentText(
    state,
    'selection-comment-2',
    'Second revised',
  );
  state = deleteSelectionComment(state, 'selection-comment-1');

  assert.deepEqual(getNumberedSelectionComments(state, target), [
    {
      number: 1,
      id: 'selection-comment-2',
      widgetId: 'widget-1',
      widgetLabel: 'PrimaryButton',
      text: 'Second revised',
    },
    {
      number: 2,
      id: 'selection-comment-3',
      widgetId: 'widget-1',
      widgetLabel: 'PrimaryButton',
      text: 'Third',
    },
  ]);
});

test('keeps staged Selection Comments non-empty when editing', () => {
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'Keep this');
  state = updateSelectionCommentText(state, 'selection-comment-1', '   ');

  assert.deepEqual(getSelectionCommentsForSelectedWidget(state, target), [
    {
      id: 'selection-comment-1',
      widgetId: 'widget-1',
      widgetLabel: 'PrimaryButton',
      text: 'Keep this',
    },
  ]);
});

test('builds Add comment targets from Widget Context Panel selections without ancestor path', () => {
  const root: WidgetTreeNode = {
    id: 'root',
    label: 'MaterialApp',
    children: [
      {
        id: 'button',
        label: 'PrimaryButton',
        sourceLocation: 'lib/home.dart:12',
        visibleText: 'Save',
        semanticInfo: 'button',
        children: [],
      },
    ],
  };

  assert.deepEqual(getSelectedWidgetTarget(root, 'button'), {
    id: 'button',
    displayLabel: 'PrimaryButton',
    sourceLocation: 'lib/home.dart:12',
    visibleText: 'Save',
    semanticInfo: 'button',
  });
});

test('normalizes optional widget context fields before rendering', () => {
  const root = {
    id: 'root',
    label: 'MaterialApp',
    children: [
      {
        id: 'button',
        label: 'PrimaryButton',
        sourceLocation: {
          file: '/Users/drown/flutter_project/app/lib/home.dart',
          line: 12,
        },
        visibleText: ['Save', 'now'],
        semanticInfo: {
          role: 'button',
        },
        children: [],
      },
    ],
  } as unknown as WidgetTreeNode;

  assert.deepEqual(getSelectedWidgetTarget(root, 'button'), {
    id: 'button',
    displayLabel: 'PrimaryButton',
    sourceLocation:
      '{"file":"/Users/drown/flutter_project/app/lib/home.dart","line":12}',
    visibleText: '["Save","now"]',
    semanticInfo: '{"role":"button"}',
  });
});

test('treats missing widget children as an empty child list while searching', () => {
  const root = {
    id: 'root',
    label: 'MaterialApp',
  } as unknown as WidgetTreeNode;

  assert.equal(getSelectedWidgetTarget(root, 'missing'), null);
});
