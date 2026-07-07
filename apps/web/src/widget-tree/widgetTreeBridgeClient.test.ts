import assert from 'node:assert/strict';
import test from 'node:test';

import { getWidgetTree } from './widgetTreeBridgeClient.ts';

test('loads a Widget Tree snapshot from the bridge session', async () => {
  const requestedUrls: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input) => {
    requestedUrls.push(String(input));
    return new Response(
      JSON.stringify({
        root: {
          id: 'root',
          label: 'MaterialApp',
          children: [],
        },
      }),
    );
  };

  try {
    const result = await getWidgetTree('session-1');

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/widget-tree',
    ]);
    assert.deepEqual(result.root, {
      id: 'root',
      label: 'MaterialApp',
      children: [],
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
