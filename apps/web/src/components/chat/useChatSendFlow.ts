import {
  type Dispatch,
  type RefObject,
  type SetStateAction,
  useState,
} from 'react';
import { buildChatMessagePayload } from '../../chat/chatMessagePayload';
import { sendChatMessage } from '../../services/askUiBridgeClient';
import {
  getSelectionCommentsAfterSnapshotWait,
  getSelectionCommentStateAfterSendResult,
  type SelectionComment,
  type SelectionCommentSnapshot,
  type SelectionCommentState,
} from '../../selection-comments/selectionCommentState';

type UseChatSendFlowOptions = {
  getSelectionCommentDraftsByWidgetIdForSend: () => Record<string, string>;
  getSelectionCommentsForSend: () => SelectionComment[];
  hasCapturingSnapshots: () => boolean;
  onComposerTextAfterSend: (succeeded: boolean, submittedText: string) => void;
  onSelectionCommentStateChange: Dispatch<SetStateAction<SelectionCommentState>>;
  projectRoot: string | null;
  sessionId: string | null;
  snapshotWaitMs: number;
  waitForPendingSnapshots: (
    timeoutMs: number,
  ) => Promise<Record<string, SelectionCommentSnapshot>>;
};

export function useChatSendFlow({
  getSelectionCommentDraftsByWidgetIdForSend,
  getSelectionCommentsForSend,
  hasCapturingSnapshots,
  onComposerTextAfterSend,
  onSelectionCommentStateChange,
  projectRoot,
  sessionId,
  snapshotWaitMs,
  waitForPendingSnapshots,
}: UseChatSendFlowOptions) {
  const [isSending, setIsSending] = useState(false);
  const [isFinishingSnapshots, setIsFinishingSnapshots] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);

  async function send({
    composerInputRef,
    text,
  }: {
    composerInputRef: RefObject<HTMLTextAreaElement | null>;
    text: string;
  }) {
    if (sessionId === null || projectRoot === null) {
      return;
    }

    setIsSending(true);
    setSendError(null);
    const submittedSelectionComments = getSelectionCommentsForSend();
    const submittedSelectionCommentDraftsByWidgetId =
      getSelectionCommentDraftsByWidgetIdForSend();
    try {
      let completedSnapshots: Record<string, SelectionCommentSnapshot> = {};
      if (hasCapturingSnapshots()) {
        setIsFinishingSnapshots(true);
        completedSnapshots = await waitForPendingSnapshots(snapshotWaitMs);
        setIsFinishingSnapshots(false);
      }

      const selectionComments = getSelectionCommentsAfterSnapshotWait(
        submittedSelectionComments,
        getSelectionCommentsForSend(),
        completedSnapshots,
      );

      await sendChatMessage(
        sessionId,
        buildChatMessagePayload({
          projectRoot,
          selectionComments,
          text,
        }),
      );
      onComposerTextAfterSend(true, text);
      onSelectionCommentStateChange((currentState) =>
        getSelectionCommentStateAfterSendResult(
          currentState,
          true,
          selectionComments,
          submittedSelectionCommentDraftsByWidgetId,
        ),
      );
      requestAnimationFrame(() => composerInputRef.current?.focus());
    } catch (error) {
      onComposerTextAfterSend(false, text);
      setSendError(
        error instanceof Error ? error.message : 'Failed to send Chat message.',
      );
    } finally {
      setIsFinishingSnapshots(false);
      setIsSending(false);
    }
  }

  function clearSendError() {
    setSendError(null);
  }

  return {
    clearSendError,
    isFinishingSnapshots,
    isSending,
    send,
    sendError,
  };
}
