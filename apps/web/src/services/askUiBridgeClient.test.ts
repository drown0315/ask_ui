import assert from 'node:assert/strict';
import test from 'node:test';

import {
  BridgeRequestError,
  captureSelectionCommentSnapshot,
  createBridgeSession,
  getChatSession,
  getDeviceWebSocketUrl,
  getSelectWidgetModeStatus,
  getWidgetTree,
  hotReloadSession,
  hotRestartSession,
  parseBridgeJsonResponse,
  resolveBridgeOrigin,
  sendPlainTextChatMessage,
  setSelectWidgetMode,
  subscribeToBridgeSessionEvents,
} from './askUiBridgeClient.ts';

test('keeps the legacy Ask UI bridge client entrypoint exporting public APIs', () => {
  assert.equal(typeof BridgeRequestError, 'function');
  assert.equal(typeof captureSelectionCommentSnapshot, 'function');
  assert.equal(typeof createBridgeSession, 'function');
  assert.equal(typeof getChatSession, 'function');
  assert.equal(typeof getDeviceWebSocketUrl, 'function');
  assert.equal(typeof getSelectWidgetModeStatus, 'function');
  assert.equal(typeof getWidgetTree, 'function');
  assert.equal(typeof hotReloadSession, 'function');
  assert.equal(typeof hotRestartSession, 'function');
  assert.equal(typeof parseBridgeJsonResponse, 'function');
  assert.equal(typeof resolveBridgeOrigin, 'function');
  assert.equal(typeof sendPlainTextChatMessage, 'function');
  assert.equal(typeof setSelectWidgetMode, 'function');
  assert.equal(typeof subscribeToBridgeSessionEvents, 'function');
});
