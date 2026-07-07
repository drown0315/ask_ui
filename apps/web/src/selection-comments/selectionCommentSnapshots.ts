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

  let timedOut = false;
  const settledSnapshots = await Promise.race([
    Promise.allSettled(
      pendingForCurrentComments.map((pending) => pending.capture),
    ),
    new Promise<void>((resolve) => {
      setTimeout(() => {
        timedOut = true;
        resolve();
      }, timeoutMs);
    }),
  ]);

  if (!timedOut) {
    return Object.fromEntries(
      pendingForCurrentComments.flatMap((pending, index) => {
        const result = settledSnapshots?.[index];
        return result?.status === 'fulfilled'
          ? [[pending.commentId, result.value]]
          : [];
      }),
    );
  }

  const timedOutSnapshots = Object.fromEntries(
    pendingForCurrentComments.map((pending) => [
      pending.commentId,
      { status: 'unavailable' as const },
    ]),
  );
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
  return timedOutSnapshots;
}
