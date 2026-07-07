import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getChatHistoryMessageContentItems,
  getChatHistorySelectionCommentSummaries,
  getVisibleChatHistoryMessages,
  getInitialChatSessionStateWithQueuedEvents,
  getInitialChatSessionState,
  reduceChatSessionBridgeEvent,
  reduceChatSessionDisconnected,
} from './chatSessionState.ts';

test('loads Chat History and Agent Status from the bridge snapshot', () => {
  assert.deepEqual(
    getInitialChatSessionState({
      status: 'ok',
      agentStatus: 'agent_ready',
      readOnly: true,
      messages: [
        {
          id: 'message-1',
          role: 'agent',
          text: 'Ready.',
        },
      ],
    }),
    {
      status: 'ready',
      agentStatus: 'agent_ready',
      readOnly: true,
      connectionWarning: null,
      messages: [
        {
          id: 'message-1',
          role: 'agent',
          text: 'Ready.',
        },
      ],
    },
  );
});

test('applies Chat History and Agent Status bridge events', () => {
  const initial = getInitialChatSessionState({
    status: 'ok',
    agentStatus: 'waiting_for_agent',
    readOnly: false,
    messages: [],
  });

  const withStatus = reduceChatSessionBridgeEvent(initial, {
    type: 'agent_status_changed',
    sessionId: 'session-1',
    payload: {
      agentStatus: 'agent_working',
    },
  });
  const withHistory = reduceChatSessionBridgeEvent(withStatus, {
    type: 'chat_history_changed',
    sessionId: 'session-1',
    payload: {
      messages: [
        {
          id: 'message-1',
          role: 'system',
          text: 'Agent command failed.',
        },
      ],
    },
  });

  assert.equal(withHistory.agentStatus, 'agent_working');
  assert.deepEqual(withHistory.messages, [
    {
      id: 'message-1',
      role: 'system',
      text: 'Agent command failed.',
    },
  ]);
});

test('replays queued bridge events after loading the initial Chat snapshot', () => {
  assert.deepEqual(
    getInitialChatSessionStateWithQueuedEvents(
      {
        status: 'ok',
        agentStatus: 'waiting_for_agent',
        readOnly: false,
        messages: [
          {
            id: 'message-1',
            role: 'agent',
            text: 'Older snapshot.',
          },
        ],
      },
      [
        {
          type: 'agent_status_changed',
          sessionId: 'session-1',
          payload: {
            agentStatus: 'agent_working',
          },
        },
        {
          type: 'chat_history_changed',
          sessionId: 'session-1',
          payload: {
            messages: [
              {
                id: 'message-2',
                role: 'user',
                text: 'Newer live update.',
              },
            ],
          },
        },
      ],
    ),
    {
      status: 'ready',
      agentStatus: 'agent_working',
      readOnly: false,
      connectionWarning: null,
      messages: [
        {
          id: 'message-2',
          role: 'user',
          text: 'Newer live update.',
        },
      ],
    },
  );
});

test('maps session event disconnect to Waiting for agent with a warning', () => {
  const state = getInitialChatSessionState({
    status: 'ok',
    agentStatus: 'agent_working',
    readOnly: false,
    messages: [],
  });

  assert.deepEqual(reduceChatSessionDisconnected(state), {
    status: 'ready',
    agentStatus: 'waiting_for_agent',
    readOnly: false,
    connectionWarning: 'Bridge session events disconnected.',
    messages: [],
  });
});

test('adds a temporary Agent working placeholder to visible Chat History', () => {
  const state = getInitialChatSessionState({
    status: 'ok',
    agentStatus: 'agent_working',
    readOnly: false,
    messages: [
      {
        id: 'message-1',
        role: 'user',
        text: 'Make it primary.',
      },
    ],
  });

  assert.deepEqual(getVisibleChatHistoryMessages(state), [
    {
      id: 'message-1',
      role: 'user',
      text: 'Make it primary.',
    },
    {
      id: 'agent-working-placeholder',
      role: 'agent',
      text: 'Agent working...',
    },
  ]);
});

test('summarizes Selection Comment attachments for Chat History rows', () => {
  assert.deepEqual(
    getChatHistorySelectionCommentSummaries({
      id: 'message-1',
      role: 'user',
      text: '',
      parts: [
        {
          type: 'selection_comment',
          attachment: {
            id: 'selection-comment-1',
            commentText: 'Make this primary.',
            selectedWidget: {
              id: 'widget-1',
              displayLabel: 'PrimaryButton',
            },
            snapshot: {
              status: 'unavailable',
            },
          },
        },
        {
          type: 'text',
          text: 'Also update spacing.',
        },
        {
          type: 'selection_comment',
          attachment: {
            id: 'selection-comment-2',
            commentText: 'Use friendlier copy.',
            selectedWidget: {
              id: 'widget-2',
              displayLabel: 'Subtitle',
            },
            snapshot: {
              status: 'available',
              path: '/tmp/selection-comment-2.png',
            },
          },
        },
      ],
    }),
    [
      {
        id: 'selection-comment-1',
        number: 1,
        widgetLabel: 'PrimaryButton',
        text: 'Make this primary.',
      },
      {
        id: 'selection-comment-2',
        number: 2,
        widgetLabel: 'Subtitle',
        text: 'Use friendlier copy.',
      },
    ],
  );
});

test('orders Chat History attachments before typed text', () => {
  assert.deepEqual(
    getChatHistoryMessageContentItems({
      id: 'message-1',
      role: 'user',
      text: 'Also update spacing.',
      parts: [
        {
          type: 'selection_comment',
          attachment: {
            id: 'selection-comment-1',
            commentText: 'Make this primary.',
            selectedWidget: {
              id: 'widget-1',
              displayLabel: 'PrimaryButton',
            },
            snapshot: {
              status: 'unavailable',
            },
          },
        },
        {
          type: 'text',
          text: 'Also update spacing.',
        },
      ],
    }),
    [
      {
        type: 'selection_comment',
        summary: {
          id: 'selection-comment-1',
          number: 1,
          widgetLabel: 'PrimaryButton',
          text: 'Make this primary.',
        },
      },
      {
        type: 'text',
        text: 'Also update spacing.',
      },
    ],
  );
});
