import assert from 'node:assert/strict';
import test from 'node:test';

import { shouldWarnBeforeChatUnload } from './chatUnloadWarning.ts';

test('warns before unload when Chat has unsent content', () => {
  assert.equal(
    shouldWarnBeforeChatUnload({
      composerText: 'Please update this copy.',
      selectionCommentCount: 0,
      selectionCommentDraftsByWidgetId: {},
    }),
    true,
  );
  assert.equal(
    shouldWarnBeforeChatUnload({
      composerText: '   ',
      selectionCommentCount: 1,
      selectionCommentDraftsByWidgetId: {},
    }),
    true,
  );
  assert.equal(
    shouldWarnBeforeChatUnload({
      composerText: '',
      selectionCommentCount: 0,
      selectionCommentDraftsByWidgetId: {
        'widget-1': 'Make this more prominent.',
      },
    }),
    true,
  );
});

test('does not warn before unload when Chat has no unsent content', () => {
  assert.equal(
    shouldWarnBeforeChatUnload({
      composerText: '   ',
      selectionCommentCount: 0,
      selectionCommentDraftsByWidgetId: {
        'widget-1': '   ',
      },
    }),
    false,
  );
});
