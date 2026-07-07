import {
  type Dispatch,
  type FormEvent,
  type KeyboardEvent,
  type RefObject,
  type SetStateAction,
  useRef,
  useState,
} from 'react';
import {
  getChatComposerState,
  getComposerTextAfterSendResult,
  shouldSubmitChatComposerKey,
} from '../../chat/chatComposerState';
import type { ChatSessionState } from '../../chat/chatSessionState';
import {
  type SelectionComment,
  type SelectionCommentState,
} from '../../selection-comments/selectionCommentState';
import { useChatSendFlow } from './useChatSendFlow';

type UseChatComposerFlowOptions = {
  chatSessionState: ChatSessionState;
  defaultDisabledReason: string;
  getSelectionCommentDraftWidgetIdsForSend: () => string[];
  getSelectionCommentsForSend: () => SelectionComment[];
  hasCapturingSnapshots: () => boolean;
  onSelectionCommentStateChange: Dispatch<SetStateAction<SelectionCommentState>>;
  projectRoot: string | null;
  sessionId: string | null;
  snapshotWaitMs: number;
  waitForPendingSnapshots: (timeoutMs: number) => Promise<void>;
};

export function useChatComposerFlow({
  chatSessionState,
  defaultDisabledReason,
  getSelectionCommentDraftWidgetIdsForSend,
  getSelectionCommentsForSend,
  hasCapturingSnapshots,
  onSelectionCommentStateChange,
  projectRoot,
  sessionId,
  snapshotWaitMs,
  waitForPendingSnapshots,
}: UseChatComposerFlowOptions) {
  const [composerText, setComposerText] = useState('');
  const composerInputRef = useRef<HTMLTextAreaElement>(null);
  const sendFlow = useChatSendFlow({
    getSelectionCommentDraftWidgetIdsForSend,
    getSelectionCommentsForSend,
    hasCapturingSnapshots,
    onComposerTextAfterSend(succeeded) {
      setComposerText((currentText) =>
        getComposerTextAfterSendResult(currentText, succeeded),
      );
    },
    onSelectionCommentStateChange,
    projectRoot,
    sessionId,
    snapshotWaitMs,
    waitForPendingSnapshots,
  });
  const composerState = getChatComposerState(
    chatSessionState,
    composerText,
    sendFlow.isSending,
    getSelectionCommentsForSend().length,
  );
  const composerDisabledReason =
    sendFlow.isFinishingSnapshots
      ? 'Finishing snapshots...'
      : composerState.disabledReason ?? defaultDisabledReason;

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!composerState.canSend || sessionId === null || projectRoot === null) {
      return;
    }

    await sendFlow.send({
      composerInputRef,
      text: composerText,
    });
  }

  function handleComposerTextChange(nextText: string) {
    setComposerText(nextText);
    sendFlow.clearSendError();
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
    composerInputRef: composerInputRef as RefObject<HTMLTextAreaElement>,
    composerState,
    composerText,
    handleComposerKeyDown,
    handleComposerTextChange,
    handleSubmit,
    sendError: sendFlow.sendError,
  };
}
