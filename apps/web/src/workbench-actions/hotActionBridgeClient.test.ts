import assert from 'node:assert/strict';
import test from 'node:test';

import {
  hotReloadSession,
  hotRestartSession,
} from './hotActionBridgeClient.ts';

test('requests hot reload for a bridge session', async () => {
  const requestedUrls: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    requestedUrls.push(String(input));
    return new Response(
      JSON.stringify({
        status: 'ok',
        reloadReport: {
          notices: [],
        },
      }),
    );
  };

  try {
    const result = await hotReloadSession('session-1');

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/hot-reload',
    ]);
    assert.deepEqual(result, {
      status: 'ok',
      reloadReport: {
        notices: [],
      },
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('reports unsupported hot restart responses from the bridge', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        error: 'hot_restart_unsupported',
        message: 'Hot restart is not available for this bridge session.',
      }),
      {
        status: 409,
      },
    );

  try {
    await assert.rejects(
      hotRestartSession('session-1'),
      /Hot restart is not available for this bridge session/,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
