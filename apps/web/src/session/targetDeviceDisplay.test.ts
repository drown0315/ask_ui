import assert from 'node:assert/strict';
import test from 'node:test';

import { getTargetDeviceDisplay } from './targetDeviceDisplay.ts';
import type { BridgeSessionState } from '../types/bridgeSession.ts';

test('describes incomplete Target Device startup state', () => {
  const state: BridgeSessionState = {
    status: 'incomplete',
    missing: ['deviceId'],
  };

  assert.deepEqual(getTargetDeviceDisplay(state), {
    topBarLabel: 'Device required',
    surfaceLabel: 'Device required',
    title: 'Device required',
    status: 'incomplete',
  });
});

test('describes Target Device session creation state', () => {
  assert.deepEqual(getTargetDeviceDisplay({ status: 'creating' }), {
    topBarLabel: 'Connecting device',
    surfaceLabel: 'Connecting device',
    title: 'Connecting device',
    status: 'creating',
  });
});

test('describes Target Device error state', () => {
  assert.deepEqual(
    getTargetDeviceDisplay({
      status: 'error',
      message: 'Target Device device-1 is not available.',
    }),
    {
      topBarLabel: 'Device unavailable',
      surfaceLabel: 'Device unavailable',
      title: 'Target Device device-1 is not available.',
      status: 'error',
    },
  );
});

test('describes ready Target Device state with the real device id', () => {
  assert.deepEqual(
    getTargetDeviceDisplay({
      status: 'ready',
      sessionId: 'session-1',
      targetDeviceId: '19271FDF6007TY',
      widgetTree: {
        status: 'loading',
      },
    }),
    {
      topBarLabel: 'Device 19271FDF6007TY',
      surfaceLabel: '19271FDF6007TY',
      title: '19271FDF6007TY',
      status: 'ready',
    },
  );
});
