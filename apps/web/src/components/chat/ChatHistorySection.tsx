import { useEffect, useRef, useState } from 'react';
import {
  getChatHistoryMessageContentItems,
  type ChatSessionState,
} from '../../chat/chatSessionState';
import {
  getChatHistoryViewportAfterMessageChange,
  getChatHistoryViewportAfterScroll,
  isChatHistoryNearBottom,
} from '../../chat/chatHistoryViewport';
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
  const historyRef = useRef<HTMLElement>(null);
  const previousMessageCountRef = useRef(visibleMessages.length);
  const isNearBottomRef = useRef(true);
  const [showNewMessageIndicator, setShowNewMessageIndicator] =
    useState(false);

  useEffect(() => {
    const messageCountChanged =
      previousMessageCountRef.current !== visibleMessages.length;
    const viewport = getChatHistoryViewportAfterMessageChange({
      isNearBottom: isNearBottomRef.current,
      messageCountChanged,
    });
    previousMessageCountRef.current = visibleMessages.length;

    if (viewport.shouldScrollToBottom) {
      requestAnimationFrame(() => {
        const history = historyRef.current;
        if (history === null) {
          return;
        }

        history.scrollTop = history.scrollHeight;
      });
    }

    if (viewport.showNewMessageIndicator) {
      setShowNewMessageIndicator(true);
    } else if (viewport.shouldScrollToBottom || !messageCountChanged) {
      setShowNewMessageIndicator(false);
    }
  }, [visibleMessages.length]);

  function handleHistoryScroll() {
    const history = historyRef.current;
    if (history === null) {
      return;
    }

    isNearBottomRef.current = isChatHistoryNearBottom({
      clientHeight: history.clientHeight,
      scrollHeight: history.scrollHeight,
      scrollTop: history.scrollTop,
    });
    setShowNewMessageIndicator(
      getChatHistoryViewportAfterScroll({
        isNearBottom: isNearBottomRef.current,
        showNewMessageIndicator,
      }).showNewMessageIndicator,
    );
  }

  function scrollToLatestMessage() {
    const history = historyRef.current;
    if (history === null) {
      return;
    }

    history.scrollTop = history.scrollHeight;
    isNearBottomRef.current = true;
    setShowNewMessageIndicator(false);
  }

  return (
    <section
      className="chat-history"
      aria-labelledby="chat-history-title"
      onScroll={handleHistoryScroll}
      ref={historyRef}
    >
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
              {message.id === 'agent-working-placeholder' ? (
                <AgentWorkingMessage text={message.text} />
              ) : (
                <ChatHistoryMessageContent message={message} />
              )}
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
      {showNewMessageIndicator ? (
        <button
          className="chat-history-new-message"
          onClick={scrollToLatestMessage}
          type="button"
        >
          New messages
        </button>
      ) : null}
    </section>
  );
}

function AgentWorkingMessage({ text }: { text: string }) {
  return (
    <div className="chat-history-message-text chat-history-working-text">
      <span>{text}</span>
      <span aria-hidden="true" className="chat-history-working-dots">
        <span />
        <span />
        <span />
      </span>
    </div>
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
              <div className="chat-history-attachment-meta">
                {item.summary.sourceLocation ? (
                  <span>{item.summary.sourceLocation}</span>
                ) : null}
                <span>{item.summary.snapshotLabel}</span>
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
