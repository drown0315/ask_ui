import assert from 'node:assert/strict';
import test from 'node:test';

import {
  addSelectionComment,
  deleteSelectionComment,
  getDraftForSelectedWidget,
  getInitialSelectionCommentState,
  getSelectionCommentById,
  getSelectionCommentsAfterSnapshotWait,
  getSelectionCommentStateAfterSendResult,
  getSelectionCommentsForSelectedWidget,
  updateSelectionCommentDraft,
  updateSelectionCommentSnapshot,
  updateSelectionCommentText,
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
      snapshot: capturingSnapshot,
    },
  ]);
  assert.deepEqual(getSelectionCommentsForSelectedWidget(state, otherTarget), [
    {
      id: 'selection-comment-2',
      widgetId: 'widget-2',
      widgetLabel: 'SecondaryButton',
      text: 'Move this lower',
      snapshot: capturingSnapshot,
    },
  ]);
  assert.equal(getDraftForSelectedWidget(state, target), 'Make this primary');
  assert.equal(getDraftForSelectedWidget(state, otherTarget), 'Move this lower');
});

test('stages comments immediately with per-comment snapshot capture state', () => {
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'Capture this moment');

  assert.deepEqual(getSelectionCommentById(state, 'selection-comment-1'), {
    id: 'selection-comment-1',
    widgetId: 'widget-1',
    widgetLabel: 'PrimaryButton',
    text: 'Capture this moment',
    snapshot: capturingSnapshot,
  });
});

test('edits comment text and deletes comments without mutating other comments', () => {
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'First');
  state = addSelectionComment(state, target, 'Second');
  state = updateSelectionCommentText(
    state,
    'selection-comment-2',
    'Second revised',
  );
  state = deleteSelectionComment(state, 'selection-comment-1');

  assert.deepEqual(getSelectionCommentsForSelectedWidget(state, target), [
    {
      id: 'selection-comment-2',
      widgetId: 'widget-1',
      widgetLabel: 'PrimaryButton',
      text: 'Second revised',
      snapshot: capturingSnapshot,
    },
  ]);
});

test('updates snapshot capture results without recapturing edited text', () => {
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'Before edit');
  state = updateSelectionCommentSnapshot(state, 'selection-comment-1', {
    status: 'available',
    path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
    mimeType: 'image/png',
    sizeBytes: 120_000,
  });
  state = updateSelectionCommentText(state, 'selection-comment-1', 'After edit');

  assert.deepEqual(getSelectionCommentById(state, 'selection-comment-1'), {
    id: 'selection-comment-1',
    widgetId: 'widget-1',
    widgetLabel: 'PrimaryButton',
    text: 'After edit',
    snapshot: {
      status: 'available',
      path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
      mimeType: 'image/png',
      sizeBytes: 120_000,
    },
  });
});

test('marks failed and late deleted snapshot captures unavailable without blocking comments', () => {
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, target, 'Unavailable is sendable');
  state = addSelectionComment(state, target, 'Delete before capture returns');
  state = deleteSelectionComment(state, 'selection-comment-2');
  state = updateSelectionCommentSnapshot(state, 'selection-comment-1', {
    status: 'unavailable',
  });
  state = updateSelectionCommentSnapshot(state, 'selection-comment-2', {
    status: 'available',
    path: '/tmp/ask-ui/session-1/snapshots/deleted.png',
    mimeType: 'image/png',
    sizeBytes: 120_000,
  });

  assert.deepEqual(getSelectionCommentsForSelectedWidget(state, target), [
    {
      id: 'selection-comment-1',
      widgetId: 'widget-1',
      widgetLabel: 'PrimaryButton',
      text: 'Unavailable is sendable',
      snapshot: {
        status: 'unavailable',
      },
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
      snapshot: capturingSnapshot,
    },
  ]);
});

test('stores selected widget metadata with staged comments for later token navigation', () => {
  const metadataTarget: SelectedWidgetTarget = {
    id: 'widget-1',
    displayLabel: 'PrimaryButton',
    sourceLocation: 'lib/home.dart:12',
    visibleText: 'Save',
    semanticInfo: 'button',
  };
  let state: SelectionCommentState = {
    comments: [],
    draftsByWidgetId: {},
    nextCommentId: 1,
  };

  state = addSelectionComment(state, metadataTarget, 'Make it clearer');

  assert.deepEqual(getSelectionCommentById(state, 'selection-comment-1'), {
    id: 'selection-comment-1',
    widgetId: 'widget-1',
    widgetLabel: 'PrimaryButton',
    sourceLocation: 'lib/home.dart:12',
    visibleText: 'Save',
    semanticInfo: 'button',
    text: 'Make it clearer',
    snapshot: capturingSnapshot,
  });
});

test('updates sent Selection Comment snapshots without changing submitted text', () => {
  let state = addSelectionComment(
    getInitialSelectionCommentState(),
    target,
    'Make this primary.',
  );
  const submittedComments = state.comments;

  state = updateSelectionCommentText(
    updateSelectionCommentSnapshot(state, 'selection-comment-1', {
      status: 'available',
      path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
      mimeType: 'image/png',
      sizeBytes: 120_000,
    }),
    'selection-comment-1',
    'Edited after send.',
  );

  assert.deepEqual(
    getSelectionCommentsAfterSnapshotWait(submittedComments, state.comments),
    [
      {
        id: 'selection-comment-1',
        widgetId: 'widget-1',
        widgetLabel: 'PrimaryButton',
        text: 'Make this primary.',
        snapshot: {
          status: 'available',
          path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
          mimeType: 'image/png',
          sizeBytes: 120_000,
        },
      },
    ],
  );
});

test('clears submitted Selection Comments and submit-time drafts after successful Chat send', () => {
  let state = addSelectionComment(
    getInitialSelectionCommentState(),
    target,
    'Make this primary.',
  );
  state = updateSelectionCommentDraft(state, target, 'Submitted draft.');
  const submittedComments = state.comments;
  const submittedDraftsByWidgetId = state.draftsByWidgetId;

  state = updateSelectionCommentDraft(
    addSelectionComment(state, target, 'Added during send.'),
    {
      id: 'widget-2',
      displayLabel: 'SecondaryButton',
    },
    'Draft added during send.',
  );

  assert.deepEqual(
    getSelectionCommentStateAfterSendResult(
      state,
      true,
      submittedComments,
      submittedDraftsByWidgetId,
    ),
    {
      comments: [
        {
          id: 'selection-comment-2',
          widgetId: 'widget-1',
          widgetLabel: 'PrimaryButton',
          text: 'Added during send.',
          snapshot: capturingSnapshot,
        },
      ],
      draftsByWidgetId: {
        'widget-2': 'Draft added during send.',
      },
      nextCommentId: 3,
    },
  );
  assert.deepEqual(
    getSelectionCommentStateAfterSendResult(
      state,
      true,
      state.comments,
      submittedDraftsByWidgetId,
    ),
    {
      comments: [],
      draftsByWidgetId: {
        'widget-2': 'Draft added during send.',
      },
      nextCommentId: 3,
    },
  );
  assert.equal(
    getSelectionCommentStateAfterSendResult(state, false, submittedComments),
    state,
  );
});

test('preserves submitted Selection Comments and drafts edited during Chat send', () => {
  let state = addSelectionComment(
    getInitialSelectionCommentState(),
    target,
    'Make this primary.',
  );
  state = updateSelectionCommentDraft(state, target, 'Submitted draft.');

  const submittedComments = state.comments;
  const submittedDraftsByWidgetId = state.draftsByWidgetId;

  state = updateSelectionCommentText(
    state,
    'selection-comment-1',
    'Edited during send.',
  );
  state = updateSelectionCommentDraft(state, target, 'Draft edited during send.');

  assert.deepEqual(
    getSelectionCommentStateAfterSendResult(
      state,
      true,
      submittedComments,
      submittedDraftsByWidgetId,
    ),
    {
      comments: [
        {
          id: 'selection-comment-1',
          widgetId: 'widget-1',
          widgetLabel: 'PrimaryButton',
          text: 'Edited during send.',
          snapshot: capturingSnapshot,
        },
      ],
      draftsByWidgetId: {
        'widget-1': 'Draft edited during send.',
      },
      nextCommentId: 2,
    },
  );
});

test('preserves drafts after successful Chat send without Selection Comments', () => {
  const state = updateSelectionCommentDraft(
    getInitialSelectionCommentState(),
    target,
    'Keep this for later.',
  );

  assert.equal(
    getSelectionCommentStateAfterSendResult(
      state,
      true,
      [],
      state.draftsByWidgetId,
    ),
    state,
  );
});

test('keeps id allocation stable after clearing all submitted comments', () => {
  const state = addSelectionComment(
    getInitialSelectionCommentState(),
    target,
    'Make this primary.',
  );

  assert.deepEqual(
    getSelectionCommentStateAfterSendResult(state, true, state.comments),
    {
      comments: [],
      draftsByWidgetId: {},
      nextCommentId: 2,
    },
  );
});
