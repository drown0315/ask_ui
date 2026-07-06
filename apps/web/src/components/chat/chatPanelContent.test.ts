import assert from 'node:assert/strict';
import test from 'node:test';

import {
  CHAT_PANEL_SECTIONS,
  getInitialChatPanelState,
} from './chatPanelContent.ts';

test('defines the Chat shell sections and initial Agent Status language', () => {
  assert.deepEqual(
    CHAT_PANEL_SECTIONS.map((section) => section.id),
    ['selectedWidget', 'chatHistory', 'composer'],
  );
  assert.deepEqual(getInitialChatPanelState(), {
    title: 'Chat',
    agentStatusLabel: 'Agent Status',
    agentStatusValue: 'Waiting for agent',
    selectedWidgetTitle: 'Selected widget',
    selectedWidgetEmptyState: 'Select a widget to add Selection Comments.',
    chatHistoryTitle: 'Chat History',
    chatHistoryEmptyState: 'Chat History is empty.',
    composerPlaceholder: 'Message the agent...',
    composerDisabledReason: 'Agent Status is Waiting for agent.',
  });
});
