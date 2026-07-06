import { getInitialChatPanelState } from './chatPanelContent';

export function ChatPanel() {
  const content = getInitialChatPanelState();

  return (
    <aside className="workbench-panel chat-panel" aria-label={content.title}>
      <header className="chat-panel-header">
        <div className="chat-panel-title">{content.title}</div>
        <div className="agent-status" aria-label={content.agentStatusLabel}>
          <span className="agent-status-dot" aria-hidden="true" />
          <span className="agent-status-label">{content.agentStatusLabel}</span>
          <span className="agent-status-value">{content.agentStatusValue}</span>
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
        <div className="chat-history-empty">{content.chatHistoryEmptyState}</div>
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
            {content.composerDisabledReason}
          </span>
          <button className="chat-send-button" disabled type="submit">
            Send
          </button>
        </div>
      </form>
    </aside>
  );
}
