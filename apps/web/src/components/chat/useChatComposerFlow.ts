import { type FormEvent, type KeyboardEvent, useState } from 'react';
import {
  getChatComposerState,
  getComposerTextAfterSendResult,
  shouldSubmitChatComposerKey,
} from '../../chat/chatComposerState';
import type { ChatSessionState } from '../../chat/chatSessionState';
import { sendPlainTextChatMessage } from '../../services/askUiBridgeClient';

type UseChatComposerFlowOptions = {
  chatSessionState: ChatSessionState;
  defaultDisabledReason: string;
  hasCapturingSnapshots: () => boolean;
  sessionId: string | null;
  snapshotWaitMs: number;
  waitForPendingSnapshots: (timeoutMs: number) => Promise<void>;
};

export function useChatComposerFlow({
  chatSessionState,
  defaultDisabledReason,
  hasCapturingSnapshots,
  sessionId,
  snapshotWaitMs,
  waitForPendingSnapshots,
}: UseChatComposerFlowOptions) {
  const [composerText, setComposerText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [isFinishingSnapshots, setIsFinishingSnapshots] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const composerState = getChatComposerState(
    chatSessionState,
    composerText,
    isSending,
  );
  const composerDisabledReason =
    isFinishingSnapshots
      ? 'Finishing snapshots...'
      : composerState.disabledReason ?? defaultDisabledReason;

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!composerState.canSend || sessionId === null) {
      return;
    }

    setIsSending(true);
    setSendError(null);
    try {
      if (hasCapturingSnapshots()) {
        setIsFinishingSnapshots(true);
        await waitForPendingSnapshots(snapshotWaitMs);
        setIsFinishingSnapshots(false);
      }

      await sendPlainTextChatMessage(sessionId, composerText);
      setComposerText((currentText) =>
        getComposerTextAfterSendResult(currentText, true),
      );
    } catch (error) {
      setComposerText((currentText) =>
        getComposerTextAfterSendResult(currentText, false),
      );
      setSendError(
        error instanceof Error ? error.message : 'Failed to send Chat message.',
      );
    } finally {
      setIsFinishingSnapshots(false);
      setIsSending(false);
    }
  }

  function handleComposerTextChange(nextText: string) {
    setComposerText(nextText);
    setSendError(null);
  }

  function handleComposerKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (!shouldSubmitChatComposerKey(event.key, event.shiftKey)) {
      return;
    }

    event.preventDefault();
    event.currentTarget.form?.requestSubmit();
  }

  return {
    composerDisabledReason,
    composerState,
    composerText,
    handleComposerKeyDown,
    handleComposerTextChange,
    handleSubmit,
    sendError,
  };
}
