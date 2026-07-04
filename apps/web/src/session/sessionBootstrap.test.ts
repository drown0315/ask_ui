import assert from 'node:assert/strict';
import test from 'node:test';

import { readSessionBootstrap } from './sessionBootstrap.ts';

test('marks bootstrap incomplete when vmServiceUri is missing', () => {
  const result = readSessionBootstrap(
    'http://127.0.0.1:5173/?projectRoot=%2FUsers%2Fexample%2Fapp&deviceId=19271FDF6007TY',
  );

  assert.equal(result.status, 'incomplete');
  assert.deepEqual(result.missing, ['vmServiceUri']);
});

test('marks bootstrap incomplete when projectRoot is missing', () => {
  const result = readSessionBootstrap(
    'http://127.0.0.1:5173/?vmServiceUri=ws%3A%2F%2F127.0.0.1%3A12345%2Fws&deviceId=19271FDF6007TY',
  );

  assert.equal(result.status, 'incomplete');
  assert.deepEqual(result.missing, ['projectRoot']);
});

test('marks bootstrap incomplete when deviceId is missing', () => {
  const result = readSessionBootstrap(
    'http://127.0.0.1:5173/?vmServiceUri=ws%3A%2F%2F127.0.0.1%3A12345%2Fws&projectRoot=%2FUsers%2Fexample%2Fapp',
  );

  assert.equal(result.status, 'incomplete');
  assert.deepEqual(result.missing, ['deviceId']);
});

test('does not accept snake case device_id as the Target Device parameter', () => {
  const result = readSessionBootstrap(
    'http://127.0.0.1:5173/?vmServiceUri=ws%3A%2F%2F127.0.0.1%3A12345%2Fws&projectRoot=%2FUsers%2Fexample%2Fapp&device_id=19271FDF6007TY',
  );

  assert.equal(result.status, 'incomplete');
  assert.deepEqual(result.missing, ['deviceId']);
});

test('returns trimmed bootstrap values when required parameters are present', () => {
  const result = readSessionBootstrap(
    'http://127.0.0.1:5173/?vmServiceUri=++ws%3A%2F%2F127.0.0.1%3A12345%2Fws++&projectRoot=++%2FUsers%2Fexample%2Fapp++&deviceId=++19271FDF6007TY++',
  );

  assert.deepEqual(result, {
    status: 'ready',
    vmServiceUri: 'ws://127.0.0.1:12345/ws',
    projectRoot: '/Users/example/app',
    deviceId: '19271FDF6007TY',
  });
});
