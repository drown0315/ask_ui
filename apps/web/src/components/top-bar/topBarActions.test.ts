import assert from 'node:assert/strict';
import test from 'node:test';

import {
  initialTopBarActionState,
  toggleSelectWidgetMode,
} from './topBarActions.ts';

test('toggles Select Widget mode without changing action statuses', () => {
  const activeState = toggleSelectWidgetMode(initialTopBarActionState);
  const inactiveState = toggleSelectWidgetMode(activeState);

  assert.equal(activeState.isSelectWidgetActive, true);
  assert.deepEqual(activeState.hotReload, { status: 'idle' });
  assert.deepEqual(activeState.hotRestart, { status: 'idle' });
  assert.equal(inactiveState.isSelectWidgetActive, false);
});
