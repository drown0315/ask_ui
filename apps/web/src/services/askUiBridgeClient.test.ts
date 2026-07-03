import assert from 'node:assert/strict';
import test from 'node:test';

import {
  BridgeRequestError,
  hotReloadSession,
  hotRestartSession,
  parseBridgeJsonResponse,
  resolveBridgeOrigin,
} from './askUiBridgeClient.ts';

test('uses the local Dart bridge as the default bridge origin', () => {
  assert.equal(resolveBridgeOrigin(undefined), 'http://127.0.0.1:8787');
  assert.equal(resolveBridgeOrigin(''), 'http://127.0.0.1:8787');
});

test('normalizes configured bridge origins', () => {
  assert.equal(
    resolveBridgeOrigin(' http://127.0.0.1:9000/ '),
    'http://127.0.0.1:9000',
  );
});

test('reports an empty bridge response without surfacing JSON parse internals', async () => {
  const response = new Response('', {
    status: 404,
  });

  await assert.rejects(
    parseBridgeJsonResponse(response, 'Failed to create Ask UI bridge session'),
    /Failed to create Ask UI bridge session: empty response/,
  );
});

test('requests hot reload for a bridge session', async () => {
  const requestedUrls: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    requestedUrls.push(String(input));
    return new Response(
      JSON.stringify({
        status: 'ok',
        message: 'Hot reload completed.',
        reloadReport: {
          success: true,
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
      message: 'Hot reload completed.',
      reloadReport: {
        success: true,
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
        error: 'hot_restart_not_supported_for_session',
        message: 'Hot restart is not available for this bridge session.',
      }),
      {
        status: 501,
      },
    );

  try {
    await assert.rejects(hotRestartSession('session-1'), (error) => {
      assert.ok(error instanceof BridgeRequestError);
      assert.equal(error.code, 'hot_restart_not_supported_for_session');
      assert.equal(
        error.message,
        'Hot restart is not available for this bridge session.',
      );
      return true;
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
