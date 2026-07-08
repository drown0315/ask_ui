import {
  type Dispatch,
  type FormEvent,
  type KeyboardEvent,
  type RefObject,
  type SetStateAction,
  useEffect,
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
  type SelectionCommentSnapshot,
  type SelectionCommentState,
} from '../../selection-comments/selectionCommentState';
import { shouldWarnBeforeChatUnload } from '../../chat/chatUnloadWarning';
import { useChatSendFlow } from './useChatSendFlow';

type UseChatComposerFlowOptions = {
  chatSessionState: ChatSessionState;
  defaultDisabledReason: string;
  getSelectionCommentDraftsByWidgetIdForSend: () => Record<string, string>;
  getSelectionCommentsForSend: () => SelectionComment[];
  hasCapturingSnapshots: () => boolean;
  onSelectionCommentStateChange: Dispatch<SetStateAction<SelectionCommentState>>;
  projectRoot: string | null;
  sessionId: string | null;
  snapshotWaitMs: number;
  waitForPendingSnapshots: (
    timeoutMs: number,
  ) => Promise<Record<string, SelectionCommentSnapshot>>;
};

export function useChatComposerFlow({
  chatSessionState,
  defaultDisabledReason,
  getSelectionCommentDraftsByWidgetIdForSend,
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
    getSelectionCommentDraftsByWidgetIdForSend,
    getSelectionCommentsForSend,
    hasCapturingSnapshots,
    onComposerTextAfterSend(succeeded, submittedText) {
      setComposerText((currentText) =>
        getComposerTextAfterSendResult(currentText, succeeded, submittedText),
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
  const selectionCommentDraftsByWidgetId =
    getSelectionCommentDraftsByWidgetIdForSend();
  const shouldWarnOnUnload = shouldWarnBeforeChatUnload({
    composerText,
    selectionCommentCount: getSelectionCommentsForSend().length,
    selectionCommentDraftsByWidgetId,
  });

  useEffect(() => {
    if (!shouldWarnOnUnload) {
      return;
    }

    function handleBeforeUnload(event: BeforeUnloadEvent) {
      event.preventDefault();
      event.returnValue = '';
    }

    window.addEventListener('beforeunload', handleBeforeUnload);

    return () => {
      window.removeEventListener('beforeunload', handleBeforeUnload);
    };
  }, [shouldWarnOnUnload]);

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
