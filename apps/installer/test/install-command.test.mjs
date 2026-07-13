import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { runAskUiInstaller } from '../src/install-command.mjs';

describe('ask-ui install dry-run command', () => {
  it('prints a dry-run setup plan for the current Flutter project', async () => {
    const tools = new FakeTools({
      availableCommands: new Set(['dart', 'flutter']),
      flutterProjects: new Set(['/workspace/flutter_app']),
    });

    const result = await runAskUiInstaller({
      args: ['install'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    assert.equal(result.stderr, '');
    assert.deepEqual(JSON.parse(result.stdout), {
      status: 'plan',
      command: 'install',
      projectRoot: '/workspace/flutter_app',
      agent: 'codex',
      approved: false,
      dryRun: true,
      checks: [
        {
          name: 'dart',
          status: 'ok',
          message: 'dart is available.',
        },
        {
          name: 'flutter',
          status: 'ok',
          message: 'flutter is available.',
        },
        {
          name: 'project',
          status: 'ok',
          message: 'Flutter project found.',
        },
      ],
      actions: [
        {
          name: 'install_bridge',
          command: 'dart pub global activate ask_ui_bridge',
          mutates: 'global-dart',
          willRun: false,
        },
        {
          name: 'install_skill',
          command: 'npx skills add ask-ui --agent codex',
          mutates: 'agent-skills',
          willRun: false,
        },
        {
          name: 'run_diagnostics',
          command: 'ask_ui_bridge doctor --project /workspace/flutter_app',
          mutates: 'none',
          willRun: false,
        },
      ],
      nextStep: 'Re-run with --yes when you are ready to apply this plan.',
    });
    assert.deepEqual(tools.executedCommands, []);
  });

  it('accepts an explicit project and non-interactive approval', async () => {
    const tools = new FakeTools({
      availableCommands: new Set(['dart', 'flutter']),
      flutterProjects: new Set(['/workspace/other_app']),
    });

    const result = await runAskUiInstaller({
      args: [
        'install',
        '--project',
        '/workspace/other_app',
        '--agent',
        'codex',
        '--yes',
      ],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    const output = JSON.parse(result.stdout);
    assert.equal(output.projectRoot, '/workspace/other_app');
    assert.equal(output.approved, true);
    assert.equal(output.dryRun, true);
    assert.equal(
      output.nextStep,
      'Dry-run only for this release; no setup commands were executed.',
    );
    assert.deepEqual(
      output.actions.map((action) => action.willRun),
      [false, false, false],
    );
    assert.deepEqual(tools.executedCommands, []);
  });

  it('fails before planning when required tools are missing', async () => {
    const tools = new FakeTools({
      availableCommands: new Set(['dart']),
      flutterProjects: new Set(['/workspace/flutter_app']),
    });

    const result = await runAskUiInstaller({
      args: ['install'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 1);
    assert.equal(result.stderr, '');
    assert.deepEqual(JSON.parse(result.stdout), {
      status: 'error',
      error: 'missing_prerequisites',
      projectRoot: '/workspace/flutter_app',
      checks: [
        {
          name: 'dart',
          status: 'ok',
          message: 'dart is available.',
        },
        {
          name: 'flutter',
          status: 'missing',
          message: 'Install Flutter and ensure flutter is on PATH.',
        },
        {
          name: 'project',
          status: 'ok',
          message: 'Flutter project found.',
        },
      ],
    });
    assert.deepEqual(tools.executedCommands, []);
  });

  it('fails with stable stderr JSON for invalid arguments', async () => {
    const result = await runAskUiInstaller({
      args: ['install', '--agent'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools: new FakeTools(),
    });

    assert.equal(result.exitCode, 1);
    assert.equal(result.stdout, '');
    assert.deepEqual(JSON.parse(result.stderr), {
      status: 'error',
      error: 'invalid_arguments',
    });
  });
});

class FakeTools {
  constructor({
    availableCommands = new Set(),
    flutterProjects = new Set(),
  } = {}) {
    this.availableCommands = availableCommands;
    this.flutterProjects = flutterProjects;
    this.executedCommands = [];
  }

  async commandExists(command) {
    return this.availableCommands.has(command);
  }

  async isFlutterProject(projectRoot) {
    return this.flutterProjects.has(projectRoot);
  }

  async run(command, args, options = {}) {
    this.executedCommands.push({ command, args, cwd: options.cwd });
    return { exitCode: 0, stdout: '', stderr: '' };
  }
}
