import {
  updateSelectionCommentSnapshot,
  type SelectionCommentSnapshot,
  type SelectionCommentState,
} from './selectionCommentState.ts';

export type PendingSelectionCommentSnapshots = Map<string, Promise<void>>;

export type CaptureSelectionCommentSnapshot = (
  sessionId: string,
  commentId: string,
) => Promise<SelectionCommentSnapshot>;

export function startSelectionCommentSnapshotCapture({
  captureSnapshot,
  commentId,
  pendingSnapshots,
  sessionId,
  updateState,
}: {
  captureSnapshot: CaptureSelectionCommentSnapshot;
  commentId: string;
  pendingSnapshots: PendingSelectionCommentSnapshots;
  sessionId: string;
  updateState: (
    update: (state: SelectionCommentState) => SelectionCommentState,
  ) => void;
}) {
  const capture = captureSnapshot(sessionId, commentId)
    .catch<SelectionCommentSnapshot>(() => ({
      status: 'unavailable',
    }))
    .then((snapshot) => {
      updateState((state) => {
        const comment = state.comments.find(
          (candidate) => candidate.id === commentId,
        );

        if (comment?.snapshot.status !== 'capturing') {
          return state;
        }

        return updateSelectionCommentSnapshot(state, commentId, snapshot);
      });
    })
    .finally(() => {
      pendingSnapshots.delete(commentId);
    });

  pendingSnapshots.set(commentId, capture);
}

export async function waitForSelectionCommentSnapshots({
  getState,
  pendingSnapshots,
  timeoutMs,
  updateState,
}: {
  getState: () => SelectionCommentState;
  pendingSnapshots: PendingSelectionCommentSnapshots;
  timeoutMs: number;
  updateState: (
    update: (state: SelectionCommentState) => SelectionCommentState,
  ) => void;
}) {
  const pendingForCurrentComments = getState().comments
    .filter((comment) => comment.snapshot.status === 'capturing')
    .map((comment) => pendingSnapshots.get(comment.id))
    .filter((capture): capture is Promise<void> => capture !== undefined);

  if (pendingForCurrentComments.length === 0) {
    return;
  }

  let timedOut = false;
  await Promise.race([
    Promise.allSettled(pendingForCurrentComments),
    new Promise<void>((resolve) => {
      setTimeout(() => {
        timedOut = true;
        resolve();
      }, timeoutMs);
    }),
  ]);

  if (!timedOut) {
    return;
  }

  updateState((state) => ({
    ...state,
    comments: state.comments.map((comment) =>
      comment.snapshot.status === 'capturing'
        ? {
            ...comment,
            snapshot: {
              status: 'unavailable',
            },
          }
        : comment,
    ),
  }));
}
