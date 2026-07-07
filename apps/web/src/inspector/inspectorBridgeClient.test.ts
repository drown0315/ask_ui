import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getSelectWidgetModeStatus,
  selectWidgetById,
  setSelectWidgetMode,
} from './inspectorBridgeClient.ts';

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
      }),
    );
  };

  try {
    const result = await setSelectWidgetMode('session-1', true);

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/select-widget-mode',
    ]);
    assert.deepEqual(requestedBodies, [{ enabled: true }]);
    assert.deepEqual(result, {
      status: 'ok',
      enabled: true,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('requests Select Widget mode status for a bridge session', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        status: 'ok',
        known: true,
        enabled: false,
      }),
    );

  try {
    assert.deepEqual(await getSelectWidgetModeStatus('session-1'), {
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
      }),
    );
  };

  try {
    const result = await selectWidgetById('session-1', 'inspector-2');

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/widget-selection',
    ]);
    assert.deepEqual(requestedBodies, [{ widgetId: 'inspector-2' }]);
    assert.deepEqual(result, {
      status: 'ok',
      widgetId: 'inspector-2',
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
