import {
  getChatHistorySelectionCommentSummaries,
  type ChatSessionState,
} from '../../chat/chatSessionState';
import type { ChatMessageResponse } from '../../services/bridgeTypes';

export function ChatHistorySection({
  chatSessionState,
  emptyState,
  title,
  visibleMessages,
}: {
  chatSessionState: ChatSessionState;
  emptyState: string;
  title: string;
  visibleMessages: ChatMessageResponse[];
}) {
  return (
    <section className="chat-history" aria-labelledby="chat-history-title">
      <div id="chat-history-title" className="chat-section-title">
        {title}
      </div>
      {chatSessionState.status === 'ready' &&
      chatSessionState.connectionWarning ? (
        <div className="chat-connection-warning">
          {chatSessionState.connectionWarning}
        </div>
      ) : null}
      {chatSessionState.status === 'ready' && visibleMessages.length > 0 ? (
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
              <ChatHistoryMessageContent message={message} />
            </li>
          ))}
        </ol>
      ) : (
        <div className="chat-history-empty">
          {chatSessionState.status === 'loading'
            ? 'Loading Chat History...'
            : emptyState}
        </div>
      )}
    </section>
  );
}

function ChatHistoryMessageContent({
  message,
}: {
  message: ChatMessageResponse;
}) {
  const selectionCommentSummaries =
    getChatHistorySelectionCommentSummaries(message);

  return (
    <>
      {message.text.trim().length > 0 ? (
        <div className="chat-history-message-text">{message.text}</div>
      ) : null}
      {selectionCommentSummaries.length > 0 ? (
        <ol
          aria-label="Selection Comment attachments"
          className="chat-history-attachment-list"
        >
          {selectionCommentSummaries.map((summary) => (
            <li className="chat-history-attachment" key={summary.id}>
              <div className="chat-history-attachment-heading">
                <span className="chat-history-attachment-number">
                  #{summary.number}
                </span>
                <span className="chat-history-attachment-widget">
                  {summary.widgetLabel}
                </span>
              </div>
              <div className="chat-history-attachment-text">
                {summary.text}
              </div>
            </li>
          ))}
        </ol>
      ) : null}
    </>
  );
}
