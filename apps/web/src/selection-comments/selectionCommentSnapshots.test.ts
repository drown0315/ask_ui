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

test('snapshot wait timeout only degrades captures pending when wait started', async () => {
  let resolveSecondCapture:
    | ((snapshot: SelectionCommentSnapshot) => void)
    | undefined;
  let state: SelectionCommentState = addSelectionComment(
    getInitialSelectionCommentState(),
    target,
    'Pending before send',
  );
  const pendingSnapshots: PendingSelectionCommentSnapshots = new Map();

  startSelectionCommentSnapshotCapture({
    captureSnapshot: () => new Promise<SelectionCommentSnapshot>(() => {}),
    commentId: 'selection-comment-1',
    pendingSnapshots,
    sessionId: 'session-1',
    updateState(update) {
      state = update(state);
    },
  });

  const waitPromise = waitForSelectionCommentSnapshots({
    getState: () => state,
    pendingSnapshots,
    timeoutMs: 1,
    updateState(update) {
      state = update(state);
    },
  });

  state = addSelectionComment(state, target, 'Added during send wait');
  startSelectionCommentSnapshotCapture({
    captureSnapshot: () =>
      new Promise<SelectionCommentSnapshot>((resolve) => {
        resolveSecondCapture = resolve;
      }),
    commentId: 'selection-comment-2',
    pendingSnapshots,
    sessionId: 'session-1',
    updateState(update) {
      state = update(state);
    },
  });

  await waitPromise;

  assert.deepEqual(
    getSelectionCommentById(state, 'selection-comment-1')?.snapshot,
    {
      status: 'unavailable',
    },
  );
  assert.equal(
    getSelectionCommentById(state, 'selection-comment-2')?.snapshot.status,
    'capturing',
  );

  resolveSecondCapture?.({
    status: 'available',
    path: '/tmp/ask-ui/session-1/snapshots/selection-comment-2.png',
    mimeType: 'image/png',
    sizeBytes: 120_000,
  });
  await pendingSnapshots.get('selection-comment-2');

  assert.deepEqual(
    getSelectionCommentById(state, 'selection-comment-2')?.snapshot,
    {
      status: 'available',
      path: '/tmp/ask-ui/session-1/snapshots/selection-comment-2.png',
      mimeType: 'image/png',
      sizeBytes: 120_000,
    },
  );
});

test('snapshot wait timeout preserves captures completed before timeout', async () => {
  let resolveFirstCapture:
    | ((snapshot: SelectionCommentSnapshot) => void)
    | undefined;
  let state: SelectionCommentState = addSelectionComment(
    addSelectionComment(
      getInitialSelectionCommentState(),
      target,
      'Resolved before timeout',
    ),
    target,
    'Still pending at timeout',
  );
  const pendingSnapshots: PendingSelectionCommentSnapshots = new Map();

  startSelectionCommentSnapshotCapture({
    captureSnapshot: () =>
      new Promise<SelectionCommentSnapshot>((resolve) => {
        resolveFirstCapture = resolve;
      }),
    commentId: 'selection-comment-1',
    pendingSnapshots,
    sessionId: 'session-1',
    updateState(update) {
      state = update(state);
    },
  });
  startSelectionCommentSnapshotCapture({
    captureSnapshot: () => new Promise<SelectionCommentSnapshot>(() => {}),
    commentId: 'selection-comment-2',
    pendingSnapshots,
    sessionId: 'session-1',
    updateState(update) {
      state = update(state);
    },
  });

  const waitPromise = waitForSelectionCommentSnapshots({
    getState: () => state,
    pendingSnapshots,
    timeoutMs: 1,
    updateState(update) {
      state = update(state);
    },
  });

  resolveFirstCapture?.({
    status: 'available',
    path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
    mimeType: 'image/png',
    sizeBytes: 120_000,
  });

  assert.deepEqual(await waitPromise, {
    'selection-comment-1': {
      status: 'available',
      path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
      mimeType: 'image/png',
      sizeBytes: 120_000,
    },
    'selection-comment-2': {
      status: 'unavailable',
    },
  });
  assert.deepEqual(
    getSelectionCommentById(state, 'selection-comment-1')?.snapshot,
    {
      status: 'available',
      path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
      mimeType: 'image/png',
      sizeBytes: 120_000,
    },
  );
  assert.deepEqual(
    getSelectionCommentById(state, 'selection-comment-2')?.snapshot,
    {
      status: 'unavailable',
    },
  );
});

test('returns completed snapshots from Send wait without requiring a state read', async () => {
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
      setTimeout(() => {
        state = update(state);
      }, 0);
    },
  });

  const waitPromise = waitForSelectionCommentSnapshots({
    getState: () => state,
    pendingSnapshots,
    timeoutMs: 100,
    updateState(update) {
      setTimeout(() => {
        state = update(state);
      }, 0);
    },
  });

  resolveCapture?.({
    status: 'available',
    path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
    mimeType: 'image/png',
    sizeBytes: 120_000,
  });

  assert.deepEqual(await waitPromise, {
    'selection-comment-1': {
      status: 'available',
      path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
      mimeType: 'image/png',
      sizeBytes: 120_000,
    },
  });
  assert.equal(
    getSelectionCommentById(state, 'selection-comment-1')?.snapshot.status,
    'capturing',
  );
});
