import assert from 'node:assert/strict';
import test from 'node:test';

import {
  CHAT_COMPOSER_TEXT_LIMIT,
  getChatComposerState,
  getChatComposerTextareaInputPolicy,
  getComposerTextAfterSendResult,
  shouldSubmitChatComposerKey,
} from './chatComposerState.ts';
import {
  getInitialChatSessionState,
  reduceChatSessionDisconnected,
} from './chatSessionState.ts';

test('enables Chat send only while the Agent is ready with text or attachments', () => {
  const state = getInitialChatSessionState({
    status: 'ok',
    agentStatus: 'agent_ready',
    readOnly: false,
    messages: [],
  });

  assert.deepEqual(getChatComposerState(state, 'Make it primary.'), {
    canSend: true,
    disabledReason: null,
    isTooLong: false,
  });
  assert.deepEqual(getChatComposerState(state, ' \n\t ', false, 1), {
    canSend: true,
    disabledReason: null,
    isTooLong: false,
  });
});

test('treats whitespace-only composer text as no typed message', () => {
  const state = getInitialChatSessionState({
    status: 'ok',
    agentStatus: 'agent_ready',
    readOnly: false,
    messages: [],
  });

  assert.deepEqual(getChatComposerState(state, ' \n\t '), {
    canSend: false,
    disabledReason: 'Type a message to send.',
    isTooLong: false,
  });
});

test('disables Chat send when Agent Status is not ready', () => {
  const state = getInitialChatSessionState({
    status: 'ok',
    agentStatus: 'agent_working',
    readOnly: false,
    messages: [],
  });

  assert.deepEqual(getChatComposerState(state, 'Make it primary.'), {
    canSend: false,
    disabledReason: 'Agent Status is Agent working.',
    isTooLong: false,
  });
});

test('disables Chat send after session events disconnect', () => {
  const state = reduceChatSessionDisconnected(
    getInitialChatSessionState({
      status: 'ok',
      agentStatus: 'agent_ready',
      readOnly: false,
      messages: [],
    }),
  );

  assert.deepEqual(getChatComposerState(state, 'Make it primary.'), {
    canSend: false,
    disabledReason: 'Agent Status is Waiting for agent.',
    isTooLong: false,
  });
});

test('enables prepared composer text after Agent ready recovery without clearing it', () => {
  const disconnected = reduceChatSessionDisconnected(
    getInitialChatSessionState({
      status: 'ok',
      agentStatus: 'agent_working',
      readOnly: false,
      messages: [],
    }),
  );
  const preparedText = 'Make it primary.';

  assert.deepEqual(getChatComposerState(disconnected, preparedText), {
    canSend: false,
    disabledReason: 'Agent Status is Waiting for agent.',
    isTooLong: false,
  });

  const recovered = getInitialChatSessionState({
    status: 'ok',
    agentStatus: 'agent_ready',
    readOnly: false,
    messages: [],
  });

  assert.deepEqual(getChatComposerState(recovered, preparedText), {
    canSend: true,
    disabledReason: null,
    isTooLong: false,
  });
  assert.equal(
    getComposerTextAfterSendResult(preparedText, false),
    preparedText,
  );
});

test('limits typed composer text to 4000 characters', () => {
  const state = getInitialChatSessionState({
    status: 'ok',
    agentStatus: 'agent_ready',
    readOnly: false,
    messages: [],
  });

  assert.deepEqual(getChatComposerState(state, 'x'.repeat(4001)), {
    canSend: false,
    disabledReason: `Message must be ${CHAT_COMPOSER_TEXT_LIMIT} characters or fewer.`,
    isTooLong: true,
  });
});

test('lets typed composer text exceed the limit so inline validation can explain it', () => {
  assert.deepEqual(getChatComposerTextareaInputPolicy(), {
    maxLength: undefined,
  });
});

test('Enter submits the Chat composer while Shift+Enter inserts a newline', () => {
  assert.equal(shouldSubmitChatComposerKey('Enter', false), true);
  assert.equal(shouldSubmitChatComposerKey('Enter', true), false);
  assert.equal(shouldSubmitChatComposerKey('a', false), false);
});

test('clears composer text only after successful send', () => {
  assert.equal(
    getComposerTextAfterSendResult('Make it primary.', true),
    '',
  );
  assert.equal(
    getComposerTextAfterSendResult('Make it primary.', false),
    'Make it primary.',
  );
});

test('preserves composer text edited while a send is in flight', () => {
  assert.equal(
    getComposerTextAfterSendResult(
      'Make it primary and add contrast.',
      true,
      'Make it primary.',
    ),
    'Make it primary and add contrast.',
  );
});
