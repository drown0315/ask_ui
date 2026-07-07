import assert from 'node:assert/strict';
import test from 'node:test';

import {
  addSelectionComment,
  deleteSelectionComment,
  getInitialSelectionCommentState,
  getSelectionCommentById,
  type SelectionCommentSnapshot,
  type SelectionCommentState,
} from './selectionCommentState.ts';
import {
  startSelectionCommentSnapshotCapture,
  waitForSelectionCommentSnapshots,
  type PendingSelectionCommentSnapshots,
} from './selectionCommentSnapshots.ts';

const target = {
  id: 'widget-1',
  displayLabel: 'PrimaryButton',
};

test('starts Selection Comment snapshot capture in the background', async () => {
  let state = addSelectionComment(
    getInitialSelectionCommentState(),
    target,
    'Capture this',
  );
  const calls: Array<{ sessionId: string; commentId: string }> = [];
  const pendingSnapshots: PendingSelectionCommentSnapshots = new Map();

  startSelectionCommentSnapshotCapture({
    captureSnapshot: async (sessionId, commentId) => {
      calls.push({ sessionId, commentId });
      return {
        status: 'available',
        path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
        mimeType: 'image/png',
        sizeBytes: 120_000,
      };
    },
    commentId: 'selection-comment-1',
    pendingSnapshots,
    sessionId: 'session-1',
    updateState(update) {
      state = update(state);
    },
  });

  assert.equal(
    getSelectionCommentById(state, 'selection-comment-1')?.snapshot.status,
    'capturing',
  );

  await pendingSnapshots.get('selection-comment-1');

  assert.deepEqual(calls, [
    {
      sessionId: 'session-1',
      commentId: 'selection-comment-1',
    },
  ]);
  assert.deepEqual(
    getSelectionCommentById(state, 'selection-comment-1')?.snapshot,
    {
      status: 'available',
      path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
      mimeType: 'image/png',
      sizeBytes: 120_000,
    },
  );
});

test('degrades failed Selection Comment snapshot capture to unavailable', async () => {
  let state = addSelectionComment(
    getInitialSelectionCommentState(),
    target,
    'Capture this',
  );
  const pendingSnapshots: PendingSelectionCommentSnapshots = new Map();

  startSelectionCommentSnapshotCapture({
    captureSnapshot: async () => {
      throw new Error('device screenshot unavailable');
    },
    commentId: 'selection-comment-1',
    pendingSnapshots,
    sessionId: 'session-1',
    updateState(update) {
      state = update(state);
    },
  });

  await pendingSnapshots.get('selection-comment-1');

  assert.deepEqual(
    getSelectionCommentById(state, 'selection-comment-1')?.snapshot,
    {
      status: 'unavailable',
    },
  );
});

test('discarding a staged Selection Comment ignores later snapshot results', async () => {
  let resolveCapture:
    | ((snapshot: SelectionCommentSnapshot) => void)
    | undefined;
  let state = addSelectionComment(
    getInitialSelectionCommentState(),
    target,
    'Delete before capture returns',
  );
  const pendingSnapshots: PendingSelectionCommentSnapshots = new Map();

  startSelectionCommentSnapshotCapture({
    captureSnapshot: () =>
      new Promise<SelectionCommentSnapshot>((resolve) => {
        resolveCapture = resolve;
      }),
    commentId: 'selection-comment-1',
    pendingSnapshots,
    sessionId: 'session-1',
    updateState(update) {
      state = update(state);
    },
  });
  state = deleteSelectionComment(state, 'selection-comment-1');

  resolveCapture?.({
    status: 'available',
    path: '/tmp/ask-ui/session-1/snapshots/deleted.png',
    mimeType: 'image/png',
    sizeBytes: 120_000,
  });
  await pendingSnapshots.get('selection-comment-1');

  assert.equal(getSelectionCommentById(state, 'selection-comment-1'), null);
});

test('waits for in-progress snapshots before Send and times out incomplete captures', async () => {
  let resolveCapture:
    | ((snapshot: SelectionCommentSnapshot) => void)
    | undefined;
  let state: SelectionCommentState = addSelectionComment(
    getInitialSelectionCommentState(),
    target,
    'Wait for this',
  );
  const pendingSnapshots: PendingSelectionCommentSnapshots = new Map();

  startSelectionCommentSnapshotCapture({
    captureSnapshot: () =>
      new Promise<SelectionCommentSnapshot>((resolve) => {
        resolveCapture = resolve;
      }),
    commentId: 'selection-comment-1',
    pendingSnapshots,
    sessionId: 'session-1',
    updateState(update) {
      state = update(state);
    },
  });

  await waitForSelectionCommentSnapshots({
    getState: () => state,
    pendingSnapshots,
    timeoutMs: 1,
    updateState(update) {
      state = update(state);
    },
  });

  assert.deepEqual(
    getSelectionCommentById(state, 'selection-comment-1')?.snapshot,
    {
      status: 'unavailable',
    },
  );

  resolveCapture?.({
    status: 'available',
    path: '/tmp/ask-ui/session-1/snapshots/late.png',
    mimeType: 'image/png',
    sizeBytes: 120_000,
  });
  await pendingSnapshots.get('selection-comment-1');

  assert.deepEqual(
    getSelectionCommentById(state, 'selection-comment-1')?.snapshot,
    {
      status: 'unavailable',
    },
  );
});
