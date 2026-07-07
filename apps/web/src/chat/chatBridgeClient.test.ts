import assert from 'node:assert/strict';
import test from 'node:test';

import { BridgeRequestError } from '../services/bridgeHttp.ts';
import { getChatSession, sendPlainTextChatMessage } from './chatBridgeClient.ts';

test('loads Chat History and Agent Status for a bridge session', async () => {
  const requestedUrls: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    requestedUrls.push(String(input));
    return new Response(
      JSON.stringify({
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
    );
  };

  try {
    const result = await getChatSession('session-1', 'browser-2');

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/chat?clientId=browser-2',
    ]);
    assert.deepEqual(result, {
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
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('sends a plain text Chat message to the bridge session', async () => {
  const requestedUrls: string[] = [];
  const requestedBodies: unknown[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    requestedUrls.push(String(input));
    requestedBodies.push(JSON.parse(String(init?.body)));
    return new Response(
      JSON.stringify({
        status: 'ok',
        message: {
          id: 'message-1',
          role: 'user',
          text: 'Make this button primary.',
        },
      }),
    );
  };

  try {
    const result = await sendPlainTextChatMessage(
      'session-1',
      'Make this button primary.',
    );

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/chat/messages',
    ]);
    assert.deepEqual(requestedBodies, [
      {
        text: 'Make this button primary.',
      },
    ]);
    assert.deepEqual(result, {
      status: 'ok',
      message: {
        id: 'message-1',
        role: 'user',
        text: 'Make this button primary.',
      },
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('reports Chat send bridge errors with code and message', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        error: 'agent_not_ready',
      }),
      {
        status: 409,
      },
    );

  try {
    await assert.rejects(
      sendPlainTextChatMessage('session-1', 'Make this button primary.'),
      (error) => {
        assert.ok(error instanceof BridgeRequestError);
        assert.equal(error.code, 'agent_not_ready');
        assert.equal(error.message, 'agent_not_ready');
        return true;
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
