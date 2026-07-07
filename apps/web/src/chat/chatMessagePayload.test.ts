import assert from 'node:assert/strict';
import test from 'node:test';

import {
  sendChatMessage,
} from './chatBridgeClient.ts';
import { buildChatMessagePayload } from './chatMessagePayload.ts';

test('builds Selection Comment attachments before optional typed text', () => {
  const request = buildChatMessagePayload({
    projectRoot: '/Users/example/app',
    selectionComments: [
      {
        id: 'selection-comment-1',
        widgetId: 'widget-1',
        widgetLabel: 'PrimaryButton',
        sourceLocation: '/Users/example/app/lib/home.dart:12:4',
        visibleText: 'Save',
        semanticInfo: 'button',
        text: 'Make this the primary action.',
        snapshot: {
          status: 'available',
          path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
          mimeType: 'image/png',
          sizeBytes: 1200,
        },
      },
      {
        id: 'selection-comment-2',
        widgetId: 'widget-2',
        widgetLabel: 'Subtitle',
        text: 'Use less muted copy.',
        snapshot: {
          status: 'unavailable',
        },
      },
    ],
    text: 'Please update this screen.',
  });

  assert.deepEqual(request, {
    context: {
      projectRoot: '/Users/example/app',
    },
    parts: [
      {
        type: 'selection_comment',
        attachment: {
          id: 'selection-comment-1',
          commentText: 'Make this the primary action.',
          selectedWidget: {
            id: 'widget-1',
            displayLabel: 'PrimaryButton',
            sourceLocation: 'lib/home.dart:12:4',
            visibleText: 'Save',
            semanticInfo: 'button',
          },
          snapshot: {
            status: 'available',
            path: '/tmp/ask-ui/session-1/snapshots/selection-comment-1.png',
          },
        },
      },
      {
        type: 'selection_comment',
        attachment: {
          id: 'selection-comment-2',
          commentText: 'Use less muted copy.',
          selectedWidget: {
            id: 'widget-2',
            displayLabel: 'Subtitle',
          },
          snapshot: {
            status: 'unavailable',
          },
        },
      },
      {
        type: 'text',
        text: 'Please update this screen.',
      },
    ],
  });
});

test('sends the current Chat message payload to the bridge session', async () => {
  const requestedBodies: unknown[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_input, init) => {
    requestedBodies.push(JSON.parse(String(init?.body)));
    return new Response(
      JSON.stringify({
        status: 'ok',
        message: {
          id: 'message-1',
          role: 'user',
          text: '',
        },
      }),
    );
  };

  try {
    await sendChatMessage('session-1', {
      context: {
        projectRoot: '/Users/example/app',
      },
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
      ],
    });

    assert.deepEqual(requestedBodies, [
      {
        context: {
          projectRoot: '/Users/example/app',
        },
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
        ],
      },
    ]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
