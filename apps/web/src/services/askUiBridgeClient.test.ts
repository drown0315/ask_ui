import assert from 'node:assert/strict';
import test from 'node:test';

import {
  BridgeRequestError,
  createBridgeSession,
  getDeviceSurfaceWebSocketUrl,
  getSelectWidgetModeStatus,
  hotReloadSession,
  hotRestartSession,
  parseBridgeJsonResponse,
  resolveBridgeOrigin,
  setSelectWidgetMode,
  selectWidgetById,
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

test('builds the session-scoped device surface WebSocket URL', () => {
  assert.equal(
    getDeviceSurfaceWebSocketUrl(
      'session/with space',
      'http://127.0.0.1:9000/',
    ),
    'ws://127.0.0.1:9000/api/sessions/session%2Fwith%20space/device-surface',
  );
  assert.equal(
    getDeviceSurfaceWebSocketUrl('session-1', 'https://ask-ui.example'),
    'wss://ask-ui.example/api/sessions/session-1/device-surface',
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

test('creates bridge session with target device id', async () => {
  const requestedBodies: unknown[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_input, init) => {
    requestedBodies.push(JSON.parse(String(init?.body)));
    return new Response(
      JSON.stringify({
        sessionId: 'session-1',
      }),
    );
  };

  try {
    const result = await createBridgeSession({
      vmServiceUri: 'ws://127.0.0.1:12345/ws',
      projectRoot: '/Users/example/app',
      deviceId: '19271FDF6007TY',
    });

    assert.deepEqual(requestedBodies, [
      {
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
      },
    ]);
    assert.deepEqual(result, {
      sessionId: 'session-1',
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('reports Target Device bridge session errors with code and message', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        error: 'target_device_not_found',
        message: 'Target Device device-1 is not listed by Flutter.',
        deviceId: 'device-1',
      }),
      {
        status: 400,
      },
    );

  try {
    await assert.rejects(
      createBridgeSession({
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: 'device-1',
      }),
      (error) => {
        assert.ok(error instanceof BridgeRequestError);
        assert.equal(error.code, 'target_device_not_found');
        assert.equal(
          error.message,
          'Target Device device-1 is not listed by Flutter.',
        );
        return true;
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
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

test('requests Flutter Inspector widget selection for a bridge session', async () => {
  const requestedUrls: string[] = [];
  const requestedBodies: unknown[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    requestedUrls.push(String(input));
    requestedBodies.push(JSON.parse(String(init?.body)));
    return new Response(
      JSON.stringify({
        status: 'ok',
        widgetId: 'inspector-2',
        message: 'Widget selected.',
      }),
    );
  };

  try {
    const result = await selectWidgetById('session-1', 'inspector-2');

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/widget-selection',
    ]);
    assert.deepEqual(requestedBodies, [
      {
        widgetId: 'inspector-2',
      },
    ]);
    assert.deepEqual(result, {
      status: 'ok',
      widgetId: 'inspector-2',
      message: 'Widget selected.',
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
