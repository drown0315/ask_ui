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
  type SelectionCommentState,
} from '../../selection-comments/selectionCommentState';

type UseChatSendFlowOptions = {
  getSelectionCommentsForSend: () => SelectionComment[];
  hasCapturingSnapshots: () => boolean;
  onComposerTextAfterSend: (succeeded: boolean) => void;
  onSelectionCommentStateChange: Dispatch<SetStateAction<SelectionCommentState>>;
  projectRoot: string | null;
  sessionId: string | null;
  snapshotWaitMs: number;
  waitForPendingSnapshots: (timeoutMs: number) => Promise<void>;
};

export function useChatSendFlow({
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
    const submittedSelectionCommentIds = submittedSelectionComments.map(
      (comment) => comment.id,
    );
    try {
      if (hasCapturingSnapshots()) {
        setIsFinishingSnapshots(true);
        await waitForPendingSnapshots(snapshotWaitMs);
        setIsFinishingSnapshots(false);
      }

      const selectionComments = getSelectionCommentsAfterSnapshotWait(
        submittedSelectionComments,
        getSelectionCommentsForSend(),
      );

      await sendChatMessage(
        sessionId,
        buildChatMessagePayload({
          projectRoot,
          selectionComments,
          text,
        }),
      );
      onComposerTextAfterSend(true);
      onSelectionCommentStateChange((currentState) =>
        getSelectionCommentStateAfterSendResult(
          currentState,
          true,
          submittedSelectionCommentIds,
        ),
      );
      requestAnimationFrame(() => composerInputRef.current?.focus());
    } catch (error) {
      onComposerTextAfterSend(false);
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
