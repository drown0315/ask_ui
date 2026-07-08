import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getChatHistoryViewportAfterMessageChange,
  getChatHistoryViewportAfterScroll,
  isChatHistoryNearBottom,
} from './chatHistoryViewport.ts';

test('treats Chat History as near bottom within the scroll threshold', () => {
  assert.equal(
    isChatHistoryNearBottom({
      clientHeight: 240,
      scrollHeight: 640,
      scrollTop: 356,
    }),
    true,
  );
  assert.equal(
    isChatHistoryNearBottom({
      clientHeight: 240,
      scrollHeight: 640,
      scrollTop: 300,
    }),
    false,
  );
});

test('auto-scrolls only when the developer is near the bottom', () => {
  assert.deepEqual(
    getChatHistoryViewportAfterMessageChange({
      isNearBottom: true,
      messageCountChanged: true,
    }),
    {
      shouldScrollToBottom: true,
      showNewMessageIndicator: false,
    },
  );
  assert.deepEqual(
    getChatHistoryViewportAfterMessageChange({
      isNearBottom: false,
      messageCountChanged: true,
    }),
    {
      shouldScrollToBottom: false,
      showNewMessageIndicator: true,
    },
  );
  assert.deepEqual(
    getChatHistoryViewportAfterMessageChange({
      isNearBottom: false,
      messageCountChanged: false,
    }),
    {
      shouldScrollToBottom: false,
      showNewMessageIndicator: false,
    },
  );
});

test('clears the new-message indicator when Chat History returns near bottom', () => {
  assert.deepEqual(
    getChatHistoryViewportAfterScroll({
      isNearBottom: true,
      showNewMessageIndicator: true,
    }),
    {
      showNewMessageIndicator: false,
    },
  );
  assert.deepEqual(
    getChatHistoryViewportAfterScroll({
      isNearBottom: false,
      showNewMessageIndicator: true,
    }),
    {
      showNewMessageIndicator: true,
    },
  );
});
