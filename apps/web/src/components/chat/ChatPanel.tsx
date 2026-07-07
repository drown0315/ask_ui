import {
  type Dispatch,
  useRef,
  type SetStateAction,
  useMemo,
  useState,
  type FormEvent,
  type KeyboardEvent,
} from 'react';
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
import {
  addSelectionComment,
  deleteSelectionComment,
  getDraftForSelectedWidget,
  getSelectionCommentById,
  getSelectionCommentPanelTarget,
  getNumberedSelectionComments,
  getSelectionCommentInputState,
  SELECTION_COMMENT_TEXT_LIMIT,
  updateSelectionCommentSnapshot,
  updateSelectionCommentDraft,
  updateSelectionCommentText,
  type SelectionCommentAttachmentToken,
  type SelectionCommentState,
  type SelectedWidgetTarget,
} from '../../selection-comments/selectionCommentState';
import {
  captureSelectionCommentSnapshot,
  sendPlainTextChatMessage,
} from '../../services/askUiBridgeClient';
import {
  startSelectionCommentSnapshotCapture,
  waitForSelectionCommentSnapshots,
  type PendingSelectionCommentSnapshots,
} from '../../selection-comments/selectionCommentSnapshots';

const SNAPSHOT_SEND_WAIT_MS = 5000;

export function ChatPanel({
  activeSelectionCommentId,
  attachmentTokens,
  chatSessionState,
  isSelectWidgetActive,
  onAttachmentTokenClick,
  onSelectionCommentStateChange,
  selectedWidget,
  selectionCommentState,
  sessionId,
  widgetTreeStatus,
}: {
  activeSelectionCommentId: string | null;
  attachmentTokens: SelectionCommentAttachmentToken[];
  chatSessionState: ChatSessionState;
  isSelectWidgetActive: boolean;
  onAttachmentTokenClick: (token: SelectionCommentAttachmentToken) => void;
  onSelectionCommentStateChange: Dispatch<SetStateAction<SelectionCommentState>>;
  selectedWidget: SelectedWidgetTarget | null;
  selectionCommentState: SelectionCommentState;
  sessionId: string | null;
  widgetTreeStatus: 'loading' | 'loaded' | 'error';
}) {
  const content = getInitialChatPanelState();
  const commentInputRef = useRef<HTMLTextAreaElement>(null);
  const pendingSnapshotsRef = useRef<PendingSelectionCommentSnapshots>(
    new Map(),
  );
  const selectionCommentStateRef = useRef(selectionCommentState);
  const [composerText, setComposerText] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [isFinishingSnapshots, setIsFinishingSnapshots] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  selectionCommentStateRef.current = selectionCommentState;
  const activeSelectionComment =
    activeSelectionCommentId === null
      ? null
      : getSelectionCommentById(selectionCommentState, activeSelectionCommentId);
  const panelTarget = useMemo(
    () => getSelectionCommentPanelTarget(selectedWidget, activeSelectionComment),
    [activeSelectionComment, selectedWidget],
  );
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
    isFinishingSnapshots
      ? 'Finishing snapshots...'
      : composerState.disabledReason ?? content.composerDisabledReason;
  const visibleMessages = getVisibleChatHistoryMessages(chatSessionState);
  const selectionCommentText = getDraftForSelectedWidget(
    selectionCommentState,
    panelTarget,
  );
  const selectedWidgetComments = getNumberedSelectionComments(
    selectionCommentState,
    panelTarget,
  );
  const selectionCommentInputState = getSelectionCommentInputState({
    isSelectWidgetActive,
    selectedWidget: panelTarget,
    widgetTreeStatus,
    text: selectionCommentText,
    batchSize: selectionCommentState.comments.length,
  });

  function handleAddSelectionComment() {
    if (!selectionCommentInputState.canAdd || panelTarget === null) {
      return;
    }

    const commentId = `selection-comment-${selectionCommentState.nextCommentId}`;

    onSelectionCommentStateChange((currentState) => {
      const nextState = addSelectionComment(
        currentState,
        panelTarget,
        selectionCommentText,
      );

      return updateSelectionCommentDraft(nextState, panelTarget, '');
    });
    if (sessionId === null) {
      onSelectionCommentStateChange((currentState) =>
        updateSelectionCommentSnapshot(currentState, commentId, {
          status: 'unavailable',
        }),
      );
    } else {
      startSelectionCommentSnapshotCapture({
        captureSnapshot: captureSelectionCommentSnapshot,
        commentId,
        pendingSnapshots: pendingSnapshotsRef.current,
        sessionId,
        updateState: onSelectionCommentStateChange,
      });
    }
    requestAnimationFrame(() => commentInputRef.current?.focus());
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!composerState.canSend || sessionId === null) {
      return;
    }

    setIsSending(true);
    setSendError(null);
    try {
      if (
        selectionCommentStateRef.current.comments.some(
          (comment) => comment.snapshot.status === 'capturing',
        )
      ) {
        setIsFinishingSnapshots(true);
        await waitForSelectionCommentSnapshots({
          getState: () => selectionCommentStateRef.current,
          pendingSnapshots: pendingSnapshotsRef.current,
          timeoutMs: SNAPSHOT_SEND_WAIT_MS,
          updateState: onSelectionCommentStateChange,
        });
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
        {panelTarget === null ? (
          <p className="chat-empty-state">{content.selectedWidgetEmptyState}</p>
        ) : (
          <div className="selected-widget-content">
            <div className="selected-widget-summary">
              <div className="selected-widget-name">
                {panelTarget.displayLabel}
              </div>
              {activeSelectionComment !== null ? (
                <div className="selected-widget-meta">
                  From Attachment Token #
                  {
                    attachmentTokens.find(
                      (token) => token.id === activeSelectionComment.id,
                    )?.number
                  }
                </div>
              ) : null}
              {panelTarget.sourceLocation ? (
                <div className="selected-widget-meta">
                  {panelTarget.sourceLocation}
                </div>
              ) : null}
              {panelTarget.visibleText ? (
                <div className="selected-widget-detail">
                  <span>Text</span>
                  <strong>{panelTarget.visibleText}</strong>
                </div>
              ) : null}
              {panelTarget.semanticInfo ? (
                <div className="selected-widget-detail">
                  <span>Semantic</span>
                  <strong>{panelTarget.semanticInfo}</strong>
                </div>
              ) : null}
            </div>

            <div className="selection-comment-list" aria-label="Selection Comments">
              {selectedWidgetComments.length === 0 ? (
                <div className="selection-comment-empty">No Selection Comments.</div>
              ) : (
                selectedWidgetComments.map((comment) => (
                  <div className="selection-comment-item" key={comment.id}>
                    <div className="selection-comment-number">
                      {comment.number}
                    </div>
                    <textarea
                      aria-label={`Selection Comment ${comment.number}`}
                      className="selection-comment-edit"
                      maxLength={SELECTION_COMMENT_TEXT_LIMIT}
                      onChange={(event) => {
                        const nextText = event.currentTarget.value;

                        onSelectionCommentStateChange((currentState) =>
                          updateSelectionCommentText(
                            currentState,
                            comment.id,
                            nextText,
                          ),
                        );
                      }}
                      rows={2}
                      value={comment.text}
                    />
                    <button
                      aria-label={`Delete Selection Comment ${comment.number}`}
                      className="selection-comment-delete"
                      onClick={() =>
                        onSelectionCommentStateChange((currentState) =>
                          deleteSelectionComment(currentState, comment.id),
                        )
                      }
                      type="button"
                    >
                      Delete
                    </button>
                  </div>
                ))
              )}
            </div>

            <div className="selection-comment-composer">
              <textarea
                aria-label="Selection Comment"
                className="selection-comment-input"
                disabled={panelTarget === null}
                maxLength={SELECTION_COMMENT_TEXT_LIMIT}
                onChange={(event) => {
                  const nextText = event.currentTarget.value;

                  onSelectionCommentStateChange((currentState) =>
                    updateSelectionCommentDraft(
                      currentState,
                      selectedWidget,
                      nextText,
                    ),
                  );
                }}
                placeholder="Comment on this widget..."
                ref={commentInputRef}
                rows={3}
                value={selectionCommentText}
              />
              <div className="selection-comment-footer">
                <span className="selection-comment-disabled-reason">
                  {selectionCommentInputState.disabledReason}
                </span>
                <button
                  className="selection-comment-add"
                  disabled={!selectionCommentInputState.canAdd}
                  onClick={handleAddSelectionComment}
                  type="button"
                >
                  Add comment
                </button>
              </div>
            </div>
          </div>
        )}
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
        {attachmentTokens.length > 0 ? (
          <div className="attachment-token-list" aria-label="Selection Comment attachments">
            {attachmentTokens.map((token) => (
              <button
                aria-label={`Open Selection Comment attachment ${token.number}`}
                className={`attachment-token ${
                  token.isLocatable ? '' : 'attachment-token-unavailable'
                }`}
                key={token.id}
                onClick={() => onAttachmentTokenClick(token)}
                type="button"
              >
                <span className="attachment-token-number">#{token.number}</span>
                <span className="attachment-token-label">{token.widgetLabel}</span>
              </button>
            ))}
          </div>
        ) : null}
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
