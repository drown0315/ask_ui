import assert from 'node:assert/strict';
import test from 'node:test';

import { readSessionBootstrap } from './sessionBootstrap.ts';

test('marks bootstrap incomplete when vmServiceUri is missing', () => {
  const result = readSessionBootstrap(
    'http://127.0.0.1:5173/?projectRoot=%2FUsers%2Fexample%2Fapp',
  );

  assert.equal(result.status, 'incomplete');
  assert.deepEqual(result.missing, ['vmServiceUri']);
});

test('marks bootstrap incomplete when projectRoot is missing', () => {
  const result = readSessionBootstrap(
    'http://127.0.0.1:5173/?vmServiceUri=ws%3A%2F%2F127.0.0.1%3A12345%2Fws',
  );

  assert.equal(result.status, 'incomplete');
  assert.deepEqual(result.missing, ['projectRoot']);
});

test('returns trimmed vmServiceUri and projectRoot when both are present', () => {
  const result = readSessionBootstrap(
    'http://127.0.0.1:5173/?vmServiceUri=++ws%3A%2F%2F127.0.0.1%3A12345%2Fws++&projectRoot=++%2FUsers%2Fexample%2Fapp++',
  );

  assert.deepEqual(result, {
    status: 'ready',
    vmServiceUri: 'ws://127.0.0.1:12345/ws',
    projectRoot: '/Users/example/app',
  });
});
