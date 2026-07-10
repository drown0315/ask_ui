import assert from 'node:assert/strict';
import test from 'node:test';

import {
  bridgeOrigin,
  parseBridgeJsonResponse,
  resetBridgeOriginOverride,
  resolveBridgeOrigin,
  setBridgeOriginOverride,
} from './bridgeHttp.ts';

test('uses the local Dart bridge as the default bridge origin', () => {
  assert.equal(resolveBridgeOrigin(undefined), 'http://127.0.0.1:8787');
  assert.equal(resolveBridgeOrigin(''), 'http://127.0.0.1:8787');
});

test('normalizes configured bridge origins', () => {
  assert.equal(
    resolveBridgeOrigin(' http://127.0.0.1:9000/ '),
    'http://127.0.0.1:9000',
  );
});

test('allows bridge origin to be overridden at runtime', () => {
  resetBridgeOriginOverride();
  assert.equal(bridgeOrigin, 'http://127.0.0.1:8787');

  setBridgeOriginOverride(' http://127.0.0.1:9000/ ');
  assert.equal(bridgeOrigin, 'http://127.0.0.1:9000');

  resetBridgeOriginOverride();
  assert.equal(bridgeOrigin, 'http://127.0.0.1:8787');
});

test('reports an empty bridge response without surfacing JSON parse internals', async () => {
  const response = new Response('', {
    status: 404,
  });

  await assert.rejects(
    parseBridgeJsonResponse(response, 'Failed to create Ask UI bridge session'),
    /Failed to create Ask UI bridge session: empty response/,
  );
});
