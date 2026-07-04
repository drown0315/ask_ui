import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getInitialLiveAppSurfaceState,
  reduceLiveAppSurfaceMessage,
} from './liveAppSurfaceState.ts';

test('starts connecting when a bridge session is ready', () => {
  assert.deepEqual(getInitialLiveAppSurfaceState('session-1'), {
    status: 'connecting',
  });
});

test('stays idle before a bridge session is ready', () => {
  assert.deepEqual(getInitialLiveAppSurfaceState(null), {
    status: 'idle',
  });
});

test('moves to Waiting for video after ready metadata arrives', () => {
  const state = reduceLiveAppSurfaceMessage(
    {
      status: 'connecting',
    },
    JSON.stringify({
      type: 'ready',
      deviceId: '19271FDF6007TY',
      screenWidth: 1080,
      screenHeight: 2400,
      maxFps: 60,
      videoCodec: 'h264',
      controlReady: true,
    }),
  );

  assert.deepEqual(state, {
    status: 'waitingForVideo',
    metadata: {
      deviceId: '19271FDF6007TY',
      screenWidth: 1080,
      screenHeight: 2400,
      maxFps: 60,
      videoCodec: 'h264',
      controlReady: true,
    },
  });
});

test('applies complete metadata updates without changing waiting state', () => {
  const state = reduceLiveAppSurfaceMessage(
    {
      status: 'waitingForVideo',
      metadata: {
        deviceId: '19271FDF6007TY',
        screenWidth: 1080,
        screenHeight: 2400,
        maxFps: 60,
        videoCodec: 'h264',
        controlReady: true,
      },
    },
    JSON.stringify({
      type: 'metadata',
      deviceId: '19271FDF6007TY',
      screenWidth: 2400,
      screenHeight: 1080,
      maxFps: 60,
      videoCodec: 'h264',
      controlReady: true,
    }),
  );

  assert.deepEqual(state, {
    status: 'waitingForVideo',
    metadata: {
      deviceId: '19271FDF6007TY',
      screenWidth: 2400,
      screenHeight: 1080,
      maxFps: 60,
      videoCodec: 'h264',
      controlReady: true,
    },
  });
});
