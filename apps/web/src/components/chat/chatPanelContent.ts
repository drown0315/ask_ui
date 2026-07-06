export type ChatPanelSectionId =
  | 'selectedWidget'
  | 'chatHistory'
  | 'composer';

export type ChatPanelSection = {
  id: ChatPanelSectionId;
  title: string;
};

export type InitialChatPanelState = {
  title: string;
  agentStatusLabel: string;
  agentStatusValue: string;
  selectedWidgetTitle: string;
  selectedWidgetEmptyState: string;
  chatHistoryTitle: string;
  chatHistoryEmptyState: string;
  composerPlaceholder: string;
  composerDisabledReason: string;
};

export const CHAT_PANEL_SECTIONS: ChatPanelSection[] = [
  { id: 'selectedWidget', title: 'Selected widget' },
  { id: 'chatHistory', title: 'Chat History' },
  { id: 'composer', title: 'Composer' },
];

export function getInitialChatPanelState(): InitialChatPanelState {
  return {
    title: 'Chat',
    agentStatusLabel: 'Agent Status',
    agentStatusValue: 'Waiting for agent',
    selectedWidgetTitle: 'Selected widget',
    selectedWidgetEmptyState: 'Select a widget to add Selection Comments.',
    chatHistoryTitle: 'Chat History',
    chatHistoryEmptyState: 'Chat History is empty.',
    composerPlaceholder: 'Message the agent...',
    composerDisabledReason: 'Agent Status is Waiting for agent.',
  };
}
