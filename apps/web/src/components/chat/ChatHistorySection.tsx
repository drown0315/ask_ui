import {
  getChatHistoryMessageContentItems,
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
  const contentItems = getChatHistoryMessageContentItems(message);
  const selectionCommentItems = contentItems.filter(
    (item) => item.type === 'selection_comment',
  );
  const textItem = contentItems.find((item) => item.type === 'text');

  return (
    <>
      {selectionCommentItems.length > 0 ? (
        <ol
          aria-label="Selection Comment attachments"
          className="chat-history-attachment-list"
        >
          {selectionCommentItems.map((item) => (
            <li className="chat-history-attachment" key={item.summary.id}>
              <div className="chat-history-attachment-heading">
                <span className="chat-history-attachment-number">
                  #{item.summary.number}
                </span>
                <span className="chat-history-attachment-widget">
                  {item.summary.widgetLabel}
                </span>
              </div>
              <div className="chat-history-attachment-text">
                {item.summary.text}
              </div>
            </li>
          ))}
        </ol>
      ) : null}
      {textItem ? (
        <div className="chat-history-message-text">{textItem.text}</div>
      ) : null}
    </>
  );
}
