import assert from 'node:assert/strict';
import test from 'node:test';

import { BridgeRequestError } from '../services/bridgeHttp.ts';
 import {
  resetBridgeOriginOverride,
  setBridgeOriginOverride,
} from '../services/bridgeHttp.ts';
import { createBridgeSession } from './bridgeSessionClient.ts';
import { getDeviceWebSocketUrl } from './deviceBridgeUrl.ts';

test('builds the session-scoped device WebSocket URL', () => {
  assert.equal(
    getDeviceWebSocketUrl('session-1'),
    'ws://127.0.0.1:8787/api/sessions/session-1/device',
  );
  assert.equal(
    getDeviceWebSocketUrl(
      'session/with space',
      'http://127.0.0.1:9000/',
    ),
    'ws://127.0.0.1:9000/api/sessions/session%2Fwith%20space/device',
  );
  assert.equal(
    getDeviceWebSocketUrl('session-1', 'https://ask-ui.example'),
    'wss://ask-ui.example/api/sessions/session-1/device',
  );
});

test('can request fixture video on the device WebSocket URL', () => {
  assert.equal(
    getDeviceWebSocketUrl('session-1', 'http://127.0.0.1:9000/', {
      debugVideo: 'fixture',
    }),
    'ws://127.0.0.1:9000/api/sessions/session-1/device?debugVideo=fixture',
  );
});

test('creates bridge session with target device id', async () => {
  const requestedBodies: unknown[] = [];
  const requestedUrls: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    requestedUrls.push(String(input));
    requestedBodies.push(JSON.parse(String(init?.body)));
    return new Response(
      JSON.stringify({
        sessionId: 'session-1',
        targetDevice: {
          id: '19271FDF6007TY',
          displayName: 'Pixel 6',
        },
      }),
    );
  };

  try {
    const result = await createBridgeSession({
      vmServiceUri: 'ws://127.0.0.1:12345/ws',
      projectRoot: '/Users/example/app',
      deviceId: '19271FDF6007TY',
    });

    assert.deepEqual(requestedBodies, [
      {
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: '19271FDF6007TY',
      },
    ]);
    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:8787/api/sessions',
    ]);
    assert.deepEqual(result, {
      sessionId: 'session-1',
      targetDevice: {
        id: '19271FDF6007TY',
        displayName: 'Pixel 6',
      },
      readOnly: false,
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('creates bridge session through the runtime bridge origin override', async () => {
  const requestedUrls: string[] = [];
  const originalFetch = globalThis.fetch;
  resetBridgeOriginOverride();
  setBridgeOriginOverride('http://127.0.0.1:9000');
  globalThis.fetch = async (input) => {
    requestedUrls.push(String(input));
    return new Response(
      JSON.stringify({
        sessionId: 'session-1',
      }),
    );
  };

  try {
    await createBridgeSession({
      vmServiceUri: 'ws://127.0.0.1:12345/ws',
      projectRoot: '/Users/example/app',
      deviceId: '19271FDF6007TY',
    });

    assert.deepEqual(requestedUrls, [
      'http://127.0.0.1:9000/api/sessions',
    ]);
  } finally {
    globalThis.fetch = originalFetch;
    resetBridgeOriginOverride();
  }
});

test('reports Target Device bridge session errors with code and message', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () =>
    new Response(
      JSON.stringify({
        error: 'target_device_not_found',
        message: 'Target Device device-1 is not listed by Flutter.',
        deviceId: 'device-1',
      }),
      {
        status: 400,
      },
    );

  try {
    await assert.rejects(
      createBridgeSession({
        vmServiceUri: 'ws://127.0.0.1:12345/ws',
        projectRoot: '/Users/example/app',
        deviceId: 'device-1',
      }),
      (error) => {
        assert.ok(error instanceof BridgeRequestError);
        assert.equal(error.code, 'target_device_not_found');
        assert.equal(
          error.message,
          'Target Device device-1 is not listed by Flutter.',
        );
        return true;
      },
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
