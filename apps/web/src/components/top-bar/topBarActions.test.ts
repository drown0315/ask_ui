import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getTopBarStatusMessage,
  initialTopBarActionState,
  markSessionActionUnavailable,
  toggleSelectWidgetMode,
} from './topBarActions.ts';

test('toggles Select Widget mode without changing action statuses', () => {
  const activeState = toggleSelectWidgetMode(initialTopBarActionState);
  const inactiveState = toggleSelectWidgetMode(activeState);

  assert.equal(activeState.isSelectWidgetActive, true);
  assert.deepEqual(activeState.selectWidget, {
    status: 'idle',
    message: 'Select Widget mode enabled.',
  });
  assert.deepEqual(activeState.hotReload, { status: 'idle' });
  assert.deepEqual(activeState.hotRestart, { status: 'idle' });
  assert.equal(inactiveState.isSelectWidgetActive, false);
  assert.deepEqual(inactiveState.selectWidget, {
    status: 'idle',
    message: 'Select Widget mode disabled.',
  });
});

test('describes Select Widget mode as visible top bar feedback', () => {
  const activeState = toggleSelectWidgetMode(initialTopBarActionState);

  assert.equal(
    getTopBarStatusMessage(activeState),
    'Select Widget mode enabled.',
  );
});

test('describes running and failed hot actions as visible top bar feedback', () => {
  assert.equal(
    getTopBarStatusMessage({
      ...initialTopBarActionState,
      hotReload: {
        status: 'running',
      },
    }),
    'Hot reload running',
  );
  assert.equal(
    getTopBarStatusMessage({
      ...initialTopBarActionState,
      hotRestart: {
        status: 'unsupported',
        message: 'Hot restart is not available for this bridge session.',
      },
    }),
    'Hot restart is not available for this bridge session.',
  );
});

test('marks hot actions unavailable when no bridge session is ready', () => {
  const state = markSessionActionUnavailable(initialTopBarActionState, 'hotReload');

  assert.deepEqual(state.hotReload, {
    status: 'failed',
    message: 'Bridge session required before hot reload.',
  });
  assert.equal(
    getTopBarStatusMessage(state),
    'Bridge session required before hot reload.',
  );
});
