import assert from 'node:assert/strict';
import test from 'node:test';

import { getWorkbenchReadOnlyState } from './workbenchReadOnlyState.ts';

test('uses bridge session read-only while Chat is still loading', () => {
  assert.equal(
    getWorkbenchReadOnlyState(
      {
        status: 'ready',
        sessionId: 'session-1',
        targetDeviceId: 'device-1',
        clientId: 'client-1',
        readOnly: true,
      },
      {
        status: 'loading',
      },
    ),
    true,
  );
});

test('keeps ready Chat read-only state authoritative after load', () => {
  assert.equal(
    getWorkbenchReadOnlyState(
      {
        status: 'ready',
        sessionId: 'session-1',
        targetDeviceId: 'device-1',
        clientId: 'client-1',
        readOnly: true,
      },
      {
        status: 'ready',
        agentStatus: 'agent_ready',
        readOnly: false,
        connectionWarning: null,
        messages: [],
      },
    ),
    false,
  );
});
