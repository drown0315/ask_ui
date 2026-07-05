import assert from 'node:assert/strict';
import test from 'node:test';

import { getWidgetTreeErrorMessage } from './useWidgetTree.ts';

test('normalizes Widget Tree refresh errors for visible error state', () => {
  assert.equal(
    getWidgetTreeErrorMessage(new Error('Bridge unavailable')),
    'Bridge unavailable',
  );
  assert.equal(
    getWidgetTreeErrorMessage('failed'),
    'Failed to fetch Flutter Widget Tree',
  );
});
