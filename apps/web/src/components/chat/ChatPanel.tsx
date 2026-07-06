import { getInitialChatPanelState } from './chatPanelContent';
import {
  getAgentStatusLabel,
  type ChatSessionState,
} from '../../chat/chatSessionState';

export function ChatPanel({
  chatSessionState,
}: {
  chatSessionState: ChatSessionState;
}) {
  const content = getInitialChatPanelState();
  const agentStatusValue =
    chatSessionState.status === 'ready'
      ? getAgentStatusLabel(chatSessionState.agentStatus)
      : content.agentStatusValue;
  const composerDisabledReason =
    chatSessionState.status === 'ready' && chatSessionState.readOnly
      ? 'Read-only browser tabs cannot send Chat messages.'
      : content.composerDisabledReason;

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
        chatSessionState.messages.length > 0 ? (
          <ol className="chat-history-list">
            {chatSessionState.messages.map((message) => (
              <li className="chat-history-message" key={message.id}>
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

      <form className="chat-composer" aria-label="Chat composer">
        <textarea
          aria-label="Message"
          className="chat-composer-input"
          disabled
          placeholder={content.composerPlaceholder}
          rows={3}
        />
        <div className="chat-composer-footer">
          <span className="chat-composer-disabled-reason">
            {composerDisabledReason}
          </span>
          <button className="chat-send-button" disabled type="submit">
            Send
          </button>
        </div>
      </form>
    </aside>
  );
}
