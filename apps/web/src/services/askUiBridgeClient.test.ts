import assert from 'node:assert/strict';
import test from 'node:test';

import {
  BridgeRequestError,
  getSelectWidgetModeStatus,
  hotReloadSession,
  hotRestartSession,
  parseBridgeJsonResponse,
  resolveBridgeOrigin,
  setSelectWidgetMode,
  subscribeToBridgeSessionEvents,
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

test('requests Select Widget mode for a bridge session', async () => {
  const requestedUrls: string[] = [];
  const requestedBodies: unknown[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    requestedUrls.push(String(input));
    requestedBodies.push(JSON.parse(String(init?.body)));
    return new Response(
      JSON.stringify({
        status: 'ok',
        enabled: true,
        message: 'Select Widget mode enabled.',
      }),
    );
  };

  try {
    const result = await setSelectWidgetMode('session-1', true);

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/select-widget-mode',
    ]);
    assert.deepEqual(requestedBodies, [
      {
        enabled: true,
      },
    ]);
    assert.deepEqual(result, {
      status: 'ok',
      enabled: true,
      message: 'Select Widget mode enabled.',
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('requests Select Widget mode status for a bridge session', async () => {
  const requestedUrls: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    requestedUrls.push(String(input));
    return new Response(
      JSON.stringify({
        status: 'ok',
        known: true,
        enabled: false,
      }),
    );
  };

  try {
    const result = await getSelectWidgetModeStatus('session-1');

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/select-widget-mode',
    ]);
    assert.deepEqual(result, {
      status: 'ok',
      known: true,
      enabled: false,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('subscribes to bridge session events with EventSource', () => {
  const openedUrls: string[] = [];
  const listeners = new Map<string, (event: MessageEvent) => void>();
  const closed: boolean[] = [];

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
        openedUrls.push(url);
        return {
          addEventListener(eventName, listener) {
            listeners.set(eventName, listener as (event: MessageEvent) => void);
          },
          close() {
            closed.push(true);
          },
        };
      },
    },
  );

  listeners.get('bridge_session_event')?.({
    data: JSON.stringify({
      type: 'select_widget_mode_changed',
      sessionId: 'session-1',
      payload: {
        enabled: true,
      },
    }),
  } as MessageEvent);
  subscription.close();

  assert.deepEqual(openedUrls, [
    'http://127.0.0.1:8787/api/sessions/session-1/events',
  ]);
  assert.deepEqual(closed, [true]);
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
