import assert from 'node:assert/strict';
import test from 'node:test';

import { captureSelectionCommentSnapshot } from './snapshotBridgeClient.ts';

test('captures a session-scoped PNG snapshot for a Selection Comment', async () => {
  const requestedUrls: string[] = [];
  const requestedBodies: unknown[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    requestedUrls.push(String(input));
    requestedBodies.push(JSON.parse(String(init?.body)));
    return new Response(
      JSON.stringify({
        status: 'ok',
        snapshot: {
          path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
          mimeType: 'image/png',
          sizeBytes: 120000,
        },
      }),
    );
  };

  try {
    const result = await captureSelectionCommentSnapshot(
      'session-1',
      'selection-comment-1',
    );

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions/session-1/snapshots',
    ]);
    assert.deepEqual(requestedBodies, [
      {
        commentId: 'selection-comment-1',
        format: 'png',
        maxSizeBytes: 1258291,
        scope: 'full_device',
      },
    ]);
    assert.deepEqual(result, {
      status: 'available',
      path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
      mimeType: 'image/png',
      sizeBytes: 120000,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('degrades failed Selection Comment snapshot capture to unavailable', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        error: 'snapshot_unavailable',
      }),
      {
        status: 503,
      },
    );

  try {
    assert.deepEqual(
      await captureSelectionCommentSnapshot('session-1', 'selection-comment-1'),
      {
        status: 'unavailable',
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
