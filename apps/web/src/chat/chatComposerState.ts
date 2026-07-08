import {
  getAgentStatusLabel,
  type ChatSessionState,
} from './chatSessionState.ts';

export const CHAT_COMPOSER_TEXT_LIMIT = 4000;

export type ChatComposerState = {
  canSend: boolean;
  disabledReason: string | null;
  isTooLong: boolean;
};

/**
 * Derive Chat composer sendability from Chat session state and attachments.
 *
 * The function keeps UI components small and makes the product rules around
 * Agent Status, read-only browser tabs, empty sends, and text length directly
 * testable.
 */
export function getChatComposerState(
  chatSessionState: ChatSessionState,
  text: string,
  isSending = false,
  attachmentCount = 0,
): ChatComposerState {
  const isTooLong = text.length > CHAT_COMPOSER_TEXT_LIMIT;

  if (chatSessionState.status !== 'ready') {
    return {
      canSend: false,
      disabledReason: 'Chat is not connected.',
      isTooLong,
    };
  }

  if (chatSessionState.readOnly) {
    return {
      canSend: false,
      disabledReason: 'Read-only browser tabs cannot send Chat messages.',
      isTooLong,
    };
  }

  if (chatSessionState.agentStatus !== 'agent_ready') {
    return {
      canSend: false,
      disabledReason: `Agent Status is ${getAgentStatusLabel(
        chatSessionState.agentStatus,
      )}.`,
      isTooLong,
    };
  }

  if (isSending) {
    return {
      canSend: false,
      disabledReason: 'Sending...',
      isTooLong,
    };
  }

  if (text.trim().length === 0 && attachmentCount === 0) {
    return {
      canSend: false,
      disabledReason: 'Type a message to send.',
      isTooLong,
    };
  }

  if (isTooLong) {
    return {
      canSend: false,
      disabledReason: `Message must be ${CHAT_COMPOSER_TEXT_LIMIT} characters or fewer.`,
      isTooLong,
    };
  }

  return {
    canSend: true,
    disabledReason: null,
    isTooLong,
  };
}

/**
 * Return whether a textarea key press should submit Chat.
 *
 * Plain Enter sends the composer. Shift+Enter stays with native textarea
 * behavior and inserts a newline.
 */
export function shouldSubmitChatComposerKey(
  key: string,
  shiftKey: boolean,
): boolean {
  return key === 'Enter' && !shiftKey;
}

/**
 * Return the composer text after a send attempt resolves.
 *
 * Successful sends clear the local draft. Failed sends keep the draft so the
 * developer can retry manually after the Agent Session is ready again.
 */
export function getComposerTextAfterSendResult(
  currentText: string,
  succeeded: boolean,
  submittedText = currentText,
): string {
  return succeeded && currentText === submittedText ? '' : currentText;
}
