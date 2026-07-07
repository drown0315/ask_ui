import { type Dispatch, type SetStateAction } from 'react';
import { ChatComposer } from './ChatComposer';
import { ChatHistorySection } from './ChatHistorySection';
import { ChatPanelHeader } from './ChatPanelHeader';
import { SelectedWidgetSection } from './SelectedWidgetSection';
import { getInitialChatPanelState } from './chatPanelContent';
import {
  getAgentStatusLabel,
  getVisibleChatHistoryMessages,
  type ChatSessionState,
} from '../../chat/chatSessionState';
import {
  type SelectionCommentAttachmentToken,
  type SelectionCommentState,
  type SelectedWidgetTarget,
} from '../../selection-comments/selectionCommentState';
import { useChatComposerFlow } from './useChatComposerFlow';
import { useSelectionCommentPanelFlow } from './useSelectionCommentPanelFlow';
import './ChatPanel.css';

const SNAPSHOT_SEND_WAIT_MS = 5000;

export function ChatPanel({
  activeSelectionCommentId,
  attachmentTokens,
  chatSessionState,
  isSelectWidgetActive,
  onAttachmentTokenClick,
  onSelectionCommentStateChange,
  projectRoot,
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
  projectRoot: string | null;
  widgetTreeStatus: 'loading' | 'loaded' | 'error';
}) {
  const content = getInitialChatPanelState();
  const selectionComments = useSelectionCommentPanelFlow({
    activeSelectionCommentId,
    attachmentTokens,
    isSelectWidgetActive,
    onSelectionCommentStateChange,
    selectedWidget,
    selectionCommentState,
    sessionId,
    widgetTreeStatus,
  });
  const composer = useChatComposerFlow({
    chatSessionState,
    defaultDisabledReason: content.composerDisabledReason,
    getSelectionCommentDraftWidgetIdsForSend:
      selectionComments.getSelectionCommentDraftWidgetIdsForSend,
    getSelectionCommentsForSend: selectionComments.getSelectionCommentsForSend,
    hasCapturingSnapshots: selectionComments.hasCapturingSnapshots,
    onSelectionCommentStateChange,
    projectRoot,
    sessionId,
    snapshotWaitMs: SNAPSHOT_SEND_WAIT_MS,
    waitForPendingSnapshots: selectionComments.waitForPendingSnapshots,
  });
  const agentStatusValue =
    chatSessionState.status === 'ready'
      ? getAgentStatusLabel(chatSessionState.agentStatus)
      : content.agentStatusValue;
  const visibleMessages = getVisibleChatHistoryMessages(chatSessionState);

  return (
    <aside className="workbench-panel chat-panel" aria-label={content.title}>
      <ChatPanelHeader
        agentStatusLabel={content.agentStatusLabel}
        agentStatusValue={agentStatusValue}
        title={content.title}
      />
      <SelectedWidgetSection
        emptyState={content.selectedWidgetEmptyState}
        selectionComments={selectionComments}
        title={content.selectedWidgetTitle}
      />
      <ChatHistorySection
        chatSessionState={chatSessionState}
        emptyState={content.chatHistoryEmptyState}
        title={content.chatHistoryTitle}
        visibleMessages={visibleMessages}
      />
      <ChatComposer
        attachmentTokens={attachmentTokens}
        chatSessionState={chatSessionState}
        composer={composer}
        onAttachmentTokenClick={onAttachmentTokenClick}
        placeholder={content.composerPlaceholder}
        sessionId={sessionId}
      />
    </aside>
  );
}
