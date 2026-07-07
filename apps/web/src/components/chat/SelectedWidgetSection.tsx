import { SELECTION_COMMENT_TEXT_LIMIT } from '../../selection-comments/selectionCommentState';
import type { useSelectionCommentPanelFlow } from './useSelectionCommentPanelFlow';

type SelectionCommentPanelFlow = ReturnType<
  typeof useSelectionCommentPanelFlow
>;

export function SelectedWidgetSection({
  emptyState,
  selectionComments,
  title,
}: {
  emptyState: string;
  selectionComments: SelectionCommentPanelFlow;
  title: string;
}) {
  const panelTarget = selectionComments.panelTarget;

  return (
    <section className="selected-widget-card" aria-labelledby="selected-widget-title">
      <div id="selected-widget-title" className="chat-section-title">
        {title}
      </div>
      {panelTarget === null ? (
        <p className="chat-empty-state">{emptyState}</p>
      ) : (
        <div className="selected-widget-content">
          <div className="selected-widget-summary">
            <div className="selected-widget-name">{panelTarget.displayLabel}</div>
            {selectionComments.activeSelectionComment !== null ? (
              <div className="selected-widget-meta">
                From Attachment Token #{selectionComments.activeAttachmentNumber}
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
            {selectionComments.selectedWidgetComments.length === 0 ? (
              <div className="selection-comment-empty">No Selection Comments.</div>
            ) : (
              selectionComments.selectedWidgetComments.map((comment) => (
                <div className="selection-comment-item" key={comment.id}>
                  <div className="selection-comment-number">{comment.number}</div>
                  <textarea
                    aria-label={`Selection Comment ${comment.number}`}
                    className="selection-comment-edit"
                    maxLength={SELECTION_COMMENT_TEXT_LIMIT}
                    onChange={(event) => {
                      selectionComments.handleSelectionCommentTextChange(
                        comment.id,
                        event.currentTarget.value,
                      );
                    }}
                    rows={2}
                    value={comment.text}
                  />
                  <button
                    aria-label={`Delete Selection Comment ${comment.number}`}
                    className="selection-comment-delete"
                    onClick={() =>
                      selectionComments.handleDeleteSelectionComment(comment.id)
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
                selectionComments.handleSelectionCommentDraftChange(
                  event.currentTarget.value,
                );
              }}
              placeholder="Comment on this widget..."
              ref={selectionComments.commentInputRef}
              rows={3}
              value={selectionComments.selectionCommentText}
            />
            <div className="selection-comment-footer">
              <span className="selection-comment-disabled-reason">
                {selectionComments.selectionCommentInputState.disabledReason}
              </span>
              <button
                className="selection-comment-add"
                disabled={!selectionComments.selectionCommentInputState.canAdd}
                onClick={selectionComments.handleAddSelectionComment}
                type="button"
              >
                Add comment
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
