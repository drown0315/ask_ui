import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';

test('renders the live Device shell inside the phone hardware frame', async () => {
  const componentSource = await readFile(
    path.join(import.meta.dirname, 'DeviceShell.tsx'),
    'utf8',
  );

  assert.match(componentSource, /className="device-shell-hardware"/);
  assert.match(componentSource, /className="device-shell-screen"/);
  assert.match(componentSource, /className="device-shell-speaker"/);
});
