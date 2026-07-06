import { useState, type FormEvent, type KeyboardEvent } from 'react';
import { getInitialChatPanelState } from './chatPanelContent';
import {
  CHAT_COMPOSER_TEXT_LIMIT,
  getChatComposerState,
  getComposerTextAfterSendResult,
  shouldSubmitChatComposerKey,
} from '../../chat/chatComposerState';
import {
  getAgentStatusLabel,
  getVisibleChatHistoryMessages,
  type ChatSessionState,
} from '../../chat/chatSessionState';
import { sendPlainTextChatMessage } from '../../services/askUiBridgeClient';

export function ChatPanel({
  chatSessionState,
  sessionId,
}: {
  chatSessionState: ChatSessionState;
  sessionId: string | null;
}) {
  const content = getInitialChatPanelState();
  const [composerText, setComposerText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const agentStatusValue =
    chatSessionState.status === 'ready'
      ? getAgentStatusLabel(chatSessionState.agentStatus)
      : content.agentStatusValue;
  const composerState = getChatComposerState(
    chatSessionState,
    composerText,
    isSending,
  );
  const composerDisabledReason =
    composerState.disabledReason ?? content.composerDisabledReason;
  const visibleMessages = getVisibleChatHistoryMessages(chatSessionState);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!composerState.canSend || sessionId === null) {
      return;
    }

    setIsSending(true);
    setSendError(null);
    try {
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
      setIsSending(false);
    }
  }

  function handleComposerKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (!shouldSubmitChatComposerKey(event.key, event.shiftKey)) {
      return;
    }

    event.preventDefault();
    event.currentTarget.form?.requestSubmit();
  }

  return (
    <aside className="workbench-panel chat-panel" aria-label={content.title}>
      <header className="chat-panel-header">
        <div className="chat-panel-title">{content.title}</div>
        <div className="agent-status" aria-label={content.agentStatusLabel}>
          <span className="agent-status-dot" aria-hidden="true" />
          <span className="agent-status-label">{content.agentStatusLabel}</span>
          <span className="agent-status-value">{agentStatusValue}</span>
        </div>
      </header>

      <section className="selected-widget-card" aria-labelledby="selected-widget-title">
        <div id="selected-widget-title" className="chat-section-title">
          {content.selectedWidgetTitle}
        </div>
        <p className="chat-empty-state">{content.selectedWidgetEmptyState}</p>
      </section>

      <section className="chat-history" aria-labelledby="chat-history-title">
        <div id="chat-history-title" className="chat-section-title">
          {content.chatHistoryTitle}
        </div>
        {chatSessionState.status === 'ready' &&
        chatSessionState.connectionWarning ? (
          <div className="chat-connection-warning">
            {chatSessionState.connectionWarning}
          </div>
        ) : null}
        {chatSessionState.status === 'ready' &&
        visibleMessages.length > 0 ? (
          <ol className="chat-history-list">
            {visibleMessages.map((message) => (
              <li
                className={
                  message.id === 'agent-working-placeholder'
                    ? 'chat-history-message chat-history-message-working'
                    : 'chat-history-message'
                }
                key={message.id}
              >
                <div className="chat-history-message-role">{message.role}</div>
                <div className="chat-history-message-text">{message.text}</div>
              </li>
            ))}
          </ol>
        ) : (
          <div className="chat-history-empty">
            {chatSessionState.status === 'loading'
              ? 'Loading Chat History...'
              : content.chatHistoryEmptyState}
          </div>
        )}
      </section>

      <form
        className="chat-composer"
        aria-label="Chat composer"
        onSubmit={handleSubmit}
      >
        <textarea
          aria-label="Message"
          className="chat-composer-input"
          disabled={chatSessionState.status === 'ready' && chatSessionState.readOnly}
          maxLength={CHAT_COMPOSER_TEXT_LIMIT}
          onChange={(event) => {
            setComposerText(event.target.value);
            setSendError(null);
          }}
          onKeyDown={handleComposerKeyDown}
          placeholder={content.composerPlaceholder}
          rows={3}
          value={composerText}
        />
        <div className="chat-composer-footer">
          <span className="chat-composer-disabled-reason">
            {sendError ?? composerDisabledReason}
          </span>
          <button
            className="chat-send-button"
            disabled={!composerState.canSend || sessionId === null}
            type="submit"
          >
            Send
          </button>
        </div>
      </form>
    </aside>
  );
}
