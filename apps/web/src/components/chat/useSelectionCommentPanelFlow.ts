import {
  type Dispatch,
  type RefObject,
  type SetStateAction,
  useCallback,
  useMemo,
  useRef,
} from 'react';
import {
  addSelectionComment,
  deleteSelectionComment,
  getDraftForSelectedWidget,
  getNumberedSelectionComments,
  getSelectionCommentById,
  getSelectionCommentInputState,
  getSelectionCommentPanelTarget,
  updateSelectionCommentDraft,
  updateSelectionCommentSnapshot,
  updateSelectionCommentText,
  type SelectedWidgetTarget,
  type SelectionCommentAttachmentToken,
  type SelectionCommentState,
} from '../../selection-comments/selectionCommentState';
import {
  startSelectionCommentSnapshotCapture,
  waitForSelectionCommentSnapshots,
  type PendingSelectionCommentSnapshots,
} from '../../selection-comments/selectionCommentSnapshots';
import { captureSelectionCommentSnapshot } from '../../services/askUiBridgeClient';

type UseSelectionCommentPanelFlowOptions = {
  activeSelectionCommentId: string | null;
  attachmentTokens: SelectionCommentAttachmentToken[];
  isSelectWidgetActive: boolean;
  onSelectionCommentStateChange: Dispatch<SetStateAction<SelectionCommentState>>;
  selectedWidget: SelectedWidgetTarget | null;
  selectionCommentState: SelectionCommentState;
  sessionId: string | null;
  widgetTreeStatus: 'loading' | 'loaded' | 'error';
};

export function useSelectionCommentPanelFlow({
  activeSelectionCommentId,
  attachmentTokens,
  isSelectWidgetActive,
  onSelectionCommentStateChange,
  selectedWidget,
  selectionCommentState,
  sessionId,
  widgetTreeStatus,
}: UseSelectionCommentPanelFlowOptions) {
  const commentInputRef = useRef<HTMLTextAreaElement>(null);
  const pendingSnapshotsRef = useRef<PendingSelectionCommentSnapshots>(
    new Map(),
  );
  const selectionCommentStateRef = useRef(selectionCommentState);
  selectionCommentStateRef.current = selectionCommentState;

  const activeSelectionComment =
    activeSelectionCommentId === null
      ? null
      : getSelectionCommentById(selectionCommentState, activeSelectionCommentId);
  const panelTarget = useMemo(
    () => getSelectionCommentPanelTarget(selectedWidget, activeSelectionComment),
    [activeSelectionComment, selectedWidget],
  );
  const activeAttachmentNumber =
    activeSelectionComment === null
      ? null
      : attachmentTokens.find((token) => token.id === activeSelectionComment.id)
          ?.number ?? null;
  const selectionCommentText = getDraftForSelectedWidget(
    selectionCommentState,
    panelTarget,
  );
  const selectedWidgetComments = getNumberedSelectionComments(
    selectionCommentState,
    panelTarget,
  );
  const selectionCommentInputState = getSelectionCommentInputState({
    isSelectWidgetActive,
    selectedWidget: panelTarget,
    widgetTreeStatus,
    text: selectionCommentText,
    batchSize: selectionCommentState.comments.length,
  });

  const handleAddSelectionComment = useCallback(() => {
    if (!selectionCommentInputState.canAdd || panelTarget === null) {
      return;
    }

    const commentId = `selection-comment-${selectionCommentState.nextCommentId}`;

    onSelectionCommentStateChange((currentState) => {
      const nextState = addSelectionComment(
        currentState,
        panelTarget,
        selectionCommentText,
      );

      return updateSelectionCommentDraft(nextState, panelTarget, '');
    });

    if (sessionId === null) {
      onSelectionCommentStateChange((currentState) =>
        updateSelectionCommentSnapshot(currentState, commentId, {
          status: 'unavailable',
        }),
      );
    } else {
      startSelectionCommentSnapshotCapture({
        captureSnapshot: captureSelectionCommentSnapshot,
        commentId,
        pendingSnapshots: pendingSnapshotsRef.current,
        sessionId,
        updateState: onSelectionCommentStateChange,
      });
    }

    requestAnimationFrame(() => commentInputRef.current?.focus());
  }, [
    onSelectionCommentStateChange,
    panelTarget,
    selectionCommentInputState.canAdd,
    selectionCommentState.nextCommentId,
    selectionCommentText,
    sessionId,
  ]);

  const handleSelectionCommentTextChange = useCallback(
    (commentId: string, nextText: string) => {
      onSelectionCommentStateChange((currentState) =>
        updateSelectionCommentText(currentState, commentId, nextText),
      );
    },
    [onSelectionCommentStateChange],
  );

  const handleDeleteSelectionComment = useCallback(
    (commentId: string) => {
      onSelectionCommentStateChange((currentState) =>
        deleteSelectionComment(currentState, commentId),
      );
    },
    [onSelectionCommentStateChange],
  );

  const handleSelectionCommentDraftChange = useCallback(
    (nextText: string) => {
      onSelectionCommentStateChange((currentState) =>
        updateSelectionCommentDraft(currentState, selectedWidget, nextText),
      );
    },
    [onSelectionCommentStateChange, selectedWidget],
  );

  const hasCapturingSnapshots = useCallback(
    () =>
      selectionCommentStateRef.current.comments.some(
        (comment) => comment.snapshot.status === 'capturing',
      ),
    [],
  );

  const waitForPendingSnapshots = useCallback(
    (timeoutMs: number) =>
      waitForSelectionCommentSnapshots({
        getState: () => selectionCommentStateRef.current,
        pendingSnapshots: pendingSnapshotsRef.current,
        timeoutMs,
        updateState: onSelectionCommentStateChange,
      }),
    [onSelectionCommentStateChange],
  );

  return {
    activeAttachmentNumber,
    activeSelectionComment,
    commentInputRef: commentInputRef as RefObject<HTMLTextAreaElement>,
    handleAddSelectionComment,
    handleDeleteSelectionComment,
    handleSelectionCommentDraftChange,
    handleSelectionCommentTextChange,
    hasCapturingSnapshots,
    panelTarget,
    selectedWidgetComments,
    selectionCommentInputState,
    selectionCommentText,
    waitForPendingSnapshots,
  };
}
