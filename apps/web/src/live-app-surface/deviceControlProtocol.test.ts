import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildSystemKeyMessage,
  buildTouchMessage,
  deviceSystemKeys,
  deviceTouchActions,
} from './deviceControlProtocol.ts';

test('builds touch messages with centralized action values', () => {
  assert.deepEqual(deviceTouchActions, ['down', 'move', 'up', 'cancel']);
  assert.deepEqual(
    buildTouchMessage({
      action: 'down',
      pointerId: 1,
      x: 540,
      y: 1200,
      screenWidth: 1080,
      screenHeight: 2400,
    }),
    {
      type: 'touch',
      action: 'down',
      pointerId: 1,
      x: 540,
      y: 1200,
      screenWidth: 1080,
      screenHeight: 2400,
    },
  );
});

test('rejects touch pointer ids outside the protocol range', () => {
  assert.throws(
    () =>
      buildTouchMessage({
        action: 'down',
        pointerId: 4294967296,
        x: 540,
        y: 1200,
        screenWidth: 1080,
        screenHeight: 2400,
      }),
    /pointerId must be an integer from 0 to 4294967295/,
  );
});

test('builds system key messages with centralized key values', () => {
  assert.deepEqual(deviceSystemKeys, ['back', 'home', 'recents']);
  assert.deepEqual(buildSystemKeyMessage('recents'), {
    type: 'systemKey',
    key: 'recents',
  });
});
