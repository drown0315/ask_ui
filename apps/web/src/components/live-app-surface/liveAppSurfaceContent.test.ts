import assert from 'node:assert/strict';
import test from 'node:test';

import { getLiveAppSurfacePhoneStateContent } from './liveAppSurfaceContent.ts';

test('describes connecting as a phone-contained loading state', () => {
  assert.deepEqual(
    getLiveAppSurfacePhoneStateContent(
      {
        status: 'connecting',
      },
      {
        topBarLabel: 'Pixel 6',
        surfaceLabel: '19271FDF6007TY',
        title: 'Pixel 6 (19271FDF6007TY)',
        status: 'ready',
      },
    ),
    {
      label: 'Connecting device',
      detail: 'Preparing Pixel 6 screen stream',
      title: 'Connecting device',
      retryable: false,
    },
  );
});

test('describes failed as a phone-contained retry state', () => {
  assert.deepEqual(
    getLiveAppSurfacePhoneStateContent(
      {
        status: 'failed',
        message: 'Device failed to start.',
      },
      {
        topBarLabel: 'Pixel 6',
        surfaceLabel: '19271FDF6007TY',
        title: 'Pixel 6 (19271FDF6007TY)',
        status: 'ready',
      },
    ),
    {
      label: 'Device failed to start.',
      detail: '19271FDF6007TY',
      title: 'Device failed to start.',
      retryable: true,
    },
  );
});

test('describes waiting for video as a phone-contained loading state', () => {
  assert.deepEqual(
    getLiveAppSurfacePhoneStateContent(
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
      {
        topBarLabel: 'Pixel 6',
        surfaceLabel: '19271FDF6007TY',
        title: 'Pixel 6 (19271FDF6007TY)',
        status: 'ready',
      },
    ),
    {
      label: 'Waiting for video',
      detail: 'Preparing 19271FDF6007TY video stream',
      title: '19271FDF6007TY',
      retryable: false,
    },
  );
});
