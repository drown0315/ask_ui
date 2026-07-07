import { CHAT_COMPOSER_TEXT_LIMIT } from '../../chat/chatComposerState';
import type { ChatSessionState } from '../../chat/chatSessionState';
import type { SelectionCommentAttachmentToken } from '../../selection-comments/selectionCommentState';
import type { useChatComposerFlow } from './useChatComposerFlow';

type ChatComposerFlow = ReturnType<typeof useChatComposerFlow>;

export function ChatComposer({
  attachmentTokens,
  chatSessionState,
  composer,
  onAttachmentTokenClick,
  placeholder,
  sessionId,
}: {
  attachmentTokens: SelectionCommentAttachmentToken[];
  chatSessionState: ChatSessionState;
  composer: ChatComposerFlow;
  onAttachmentTokenClick: (token: SelectionCommentAttachmentToken) => void;
  placeholder: string;
  sessionId: string | null;
}) {
  return (
    <form
      className="chat-composer"
      aria-label="Chat composer"
      onSubmit={composer.handleSubmit}
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
          composer.handleComposerTextChange(event.target.value);
        }}
        onKeyDown={composer.handleComposerKeyDown}
        placeholder={placeholder}
        ref={composer.composerInputRef}
        rows={3}
        value={composer.composerText}
      />
      <div className="chat-composer-footer">
        <span className="chat-composer-disabled-reason">
          {composer.sendError ?? composer.composerDisabledReason}
        </span>
        <button
          className="chat-send-button"
          disabled={!composer.composerState.canSend || sessionId === null}
          type="submit"
        >
          Send
        </button>
      </div>
    </form>
  );
}
