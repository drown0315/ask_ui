import assert from 'node:assert/strict';
import test from 'node:test';

import {
  parseBridgeSessionEvent,
  subscribeToBridgeSessionEvents,
} from './bridgeSessionEvents.ts';

test('subscribes to bridge session events with EventSource', () => {
  const listeners = new Map<string, (message: MessageEvent) => void>();
  let closed = false;
  let requestedUrl = '';

  const subscription = subscribeToBridgeSessionEvents(
    'session-1',
    (event) => {
      assert.deepEqual(event, {
        type: 'select_widget_mode_changed',
        sessionId: 'session-1',
        payload: {
          enabled: true,
        },
      });
    },
    {
      createEventSource(url) {
        requestedUrl = url;
        return {
          addEventListener(type, listener) {
            listeners.set(type, listener as (message: MessageEvent) => void);
          },
          close() {
            closed = true;
          },
        };
      },
    },
  );

  assert.equal(
    requestedUrl,
    'http://127.0.0.1:8787/api/sessions/session-1/events',
  );
  listeners.get('bridge_session_event')?.(
    new MessageEvent('bridge_session_event', {
      data: JSON.stringify({
        type: 'select_widget_mode_changed',
        sessionId: 'session-1',
        payload: {
          enabled: true,
        },
      }),
    }),
  );

  subscription.close();
  assert.equal(closed, true);
});

test('parses Chat bridge session events from EventSource', () => {
  assert.deepEqual(
    parseBridgeSessionEvent(
      JSON.stringify({
        type: 'chat_snapshot',
        sessionId: 'session-1',
        payload: {
          agentStatus: 'agent_ready',
          messages: [
            {
              id: 'message-1',
              role: 'agent',
              text: 'Ready.',
            },
          ],
        },
      }),
    ),
    {
      type: 'chat_snapshot',
      sessionId: 'session-1',
      payload: {
        agentStatus: 'agent_ready',
        messages: [
          {
            id: 'message-1',
            role: 'agent',
            text: 'Ready.',
          },
        ],
      },
    },
  );
});

test('parses Widget Selection bridge session events from EventSource', () => {
  assert.deepEqual(
    parseBridgeSessionEvent(
      JSON.stringify({
        type: 'widget_selection_changed',
        sessionId: 'session-1',
        payload: {
          widgetId: 'inspector-2',
        },
      }),
    ),
    {
      type: 'widget_selection_changed',
      sessionId: 'session-1',
      payload: {
        widgetId: 'inspector-2',
      },
    },
  );
});

test('reports invalid bridge session events without dispatching them', () => {
  const invalidEvents: string[] = [];

  subscribeToBridgeSessionEvents(
    'session-1',
    () => {
      throw new Error('Invalid events should not dispatch.');
    },
    {
      createEventSource() {
        return {
          addEventListener(type, listener) {
            if (type === 'bridge_session_event') {
              listener(
                new MessageEvent('bridge_session_event', {
                  data: JSON.stringify({
                    type: 'chat_snapshot',
                    sessionId: 'session-1',
                    payload: {
                      messages: [],
                    },
                  }),
                }),
              );
            }
          },
          close() {},
        };
      },
      onInvalidEvent(error) {
        invalidEvents.push(error.message);
      },
    },
  );

  assert.deepEqual(invalidEvents, [
    'Chat event did not include Agent Status',
  ]);
});
