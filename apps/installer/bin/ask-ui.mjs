#!/usr/bin/env node

import { runAskUiInstaller } from '../src/install-command.mjs';

const result = await runAskUiInstaller({
  args: process.argv.slice(2),
  cwd: process.cwd(),
  env: process.env,
});

process.stdout.write(result.stdout);
process.stderr.write(result.stderr);
process.exitCode = result.exitCode;
