import {
  updateSelectionCommentSnapshot,
  type SelectionCommentSnapshot,
  type SelectionCommentState,
} from './selectionCommentState.ts';

export type CompletedSelectionCommentSnapshots = Record<
  string,
  SelectionCommentSnapshot
>;

export type PendingSelectionCommentSnapshots = Map<
  string,
  Promise<SelectionCommentSnapshot>
>;

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
      return snapshot;
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
}): Promise<CompletedSelectionCommentSnapshots> {
  const pendingForCurrentComments = getState().comments
    .filter((comment) => comment.snapshot.status === 'capturing')
    .map((comment) => ({
      commentId: comment.id,
      capture: pendingSnapshots.get(comment.id),
    }))
    .filter(
      (
        pending,
      ): pending is {
        commentId: string;
        capture: Promise<SelectionCommentSnapshot>;
      } => pending.capture !== undefined,
    );

  if (pendingForCurrentComments.length === 0) {
    return {};
  }

  const completedSnapshots: CompletedSelectionCommentSnapshots = {};
  let timedOut = false;
  await Promise.race([
    Promise.allSettled(
      pendingForCurrentComments.map((pending) =>
        pending.capture.then((snapshot) => {
          completedSnapshots[pending.commentId] = snapshot;
        }),
      ),
    ),
    new Promise<void>((resolve) => {
      setTimeout(() => {
        timedOut = true;
        resolve();
      }, timeoutMs);
    }),
  ]);

  if (!timedOut) {
    return completedSnapshots;
  }

  const timedOutCommentIds = new Set(
    pendingForCurrentComments
      .filter((pending) => completedSnapshots[pending.commentId] === undefined)
      .map((pending) => pending.commentId),
  );
  const timedOutSnapshots = Object.fromEntries(
    [...timedOutCommentIds].map((commentId) => [
      commentId,
      { status: 'unavailable' as const },
    ]),
  );
  updateState((state) => ({
    ...state,
    comments: state.comments.map((comment) =>
      timedOutCommentIds.has(comment.id) &&
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
  return {
    ...completedSnapshots,
    ...timedOutSnapshots,
  };
}
