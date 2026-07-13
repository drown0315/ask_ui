import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { runAskUiInstaller } from '../src/install-command.mjs';

const ASK_UI_SKILL_URL =
  'https://github.com/drown0315/ask_ui/tree/main/skills/ask-ui';
const REPO_ROOT = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../..',
);

describe('ask-ui install command', () => {
  it('prints a human-readable dry-run setup plan by default', async () => {
    const tools = readyTools('/workspace/flutter_app');

    const result = await runAskUiInstaller({
      args: ['install', '--dry-run'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    assert.equal(result.stderr, '');
    assert.equal(
      result.stdout,
      [
        'Ask UI install plan',
        'Project: /workspace/flutter_app',
        '',
        'Checks:',
        '- OK dart: dart is available.',
        '- OK flutter: flutter is available.',
        '- OK project: Flutter project found.',
        '',
        'Actions:',
        '- dart pub global activate ask_ui_bridge',
        `- npx skills add ${ASK_UI_SKILL_URL}`,
        '- write /workspace/flutter_app/.ask-ui/config.json',
        '- ask_ui_bridge doctor --project /workspace/flutter_app',
        '',
        'Run npx ask-ui install to apply this plan.',
        '',
      ].join('\n'),
    );
    assert.deepEqual(tools.executedCommands, []);
    assert.deepEqual(tools.writtenFiles, new Map());
  });

  it('prints a JSON dry-run setup plan when --json is provided', async () => {
    const tools = readyTools('/workspace/flutter_app');

    const result = await runAskUiInstaller({
      args: ['install', '--dry-run', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    assert.equal(result.stderr, '');
    assert.deepEqual(JSON.parse(result.stdout), planPayload());
  });

  it('installs bridge and skill, runs diagnostics, writes metadata, and prints human output', async () => {
    const tools = readyTools('/workspace/flutter_app');

    const result = await runAskUiInstaller({
      args: ['install'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    assert.equal(result.stderr, '');
    assert.equal(
      result.stdout,
      [
        'Ask UI installed',
        'Project: /workspace/flutter_app',
        '',
        'Completed:',
        '- OK install_bridge: dart pub global activate ask_ui_bridge',
        `- OK install_skill: npx skills add ${ASK_UI_SKILL_URL}`,
        '- OK write_metadata: /workspace/flutter_app/.ask-ui/config.json',
        '- OK run_diagnostics: ask_ui_bridge doctor --project /workspace/flutter_app',
        '',
        'Next:',
        'ask_ui_bridge launch --project-root /workspace/flutter_app',
        '',
      ].join('\n'),
    );
    assertInstallCommands(tools, '/workspace/flutter_app');
    assertMetadata(tools, '/workspace/flutter_app');
  });

  it('prints JSON install output when --json is provided', async () => {
    const tools = readyTools('/workspace/flutter_app');

    const result = await runAskUiInstaller({
      args: ['install', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    assert.equal(result.stderr, '');
    assert.deepEqual(JSON.parse(result.stdout), installedPayload());
  });

  it('accepts an explicit project path during install', async () => {
    const tools = readyTools('/workspace/other_app');

    const result = await runAskUiInstaller({
      args: ['install', '--project', '/workspace/other_app', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    const output = JSON.parse(result.stdout);
    assert.equal(output.projectRoot, '/workspace/other_app');
    assert.equal(
      output.launchCommand,
      'ask_ui_bridge launch --project-root /workspace/other_app',
    );
    assert.deepEqual(tools.executedCommands.at(-1), {
      command: 'ask_ui_bridge',
      args: ['doctor', '--project', '/workspace/other_app'],
      cwd: undefined,
    });
    assertMetadata(tools, '/workspace/other_app');
  });

  it('can be rerun for the same project and refreshes local metadata', async () => {
    const tools = readyTools('/workspace/flutter_app');

    const first = await runAskUiInstaller({
      args: ['install', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });
    const second = await runAskUiInstaller({
      args: ['install', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(first.exitCode, 0);
    assert.equal(second.exitCode, 0);
    assertMetadata(tools, '/workspace/flutter_app');
    assert.equal(tools.executedCommands.length, 6);
  });

  it('stops after bridge activation failure and reports completed setup results', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      commandResults: new Map([
        [
          'dart pub global activate ask_ui_bridge',
          { exitCode: 69, stdout: '', stderr: 'pub failed' },
        ],
      ]),
    });

    const result = await runAskUiInstaller({
      args: ['install', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 1);
    assert.equal(result.stderr, '');
    assert.deepEqual(JSON.parse(result.stdout), {
      status: 'error',
      error: 'install_failed',
      failedStep: 'install_bridge',
      projectRoot: '/workspace/flutter_app',
      steps: [
        {
          name: 'install_bridge',
          status: 'failed',
          command: 'dart pub global activate ask_ui_bridge',
          exitCode: 69,
          stderr: 'pub failed',
        },
      ],
    });
    assert.deepEqual(tools.executedCommands, [
      {
        command: 'dart',
        args: ['pub', 'global', 'activate', 'ask_ui_bridge'],
        cwd: undefined,
      },
    ]);
    assert.deepEqual(tools.writtenFiles, new Map());
  });

  it('prints human-readable install failure by default', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      commandResults: new Map([
        [
          'dart pub global activate ask_ui_bridge',
          { exitCode: 69, stdout: '', stderr: 'pub failed' },
        ],
      ]),
    });

    const result = await runAskUiInstaller({
      args: ['install'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 1);
    assert.equal(result.stderr, '');
    assert.equal(
      result.stdout,
      [
        'Ask UI install failed',
        'Project: /workspace/flutter_app',
        'Failed step: install_bridge',
        '',
        'Steps:',
        '- FAILED install_bridge: dart pub global activate ask_ui_bridge',
        '  stderr: pub failed',
        '',
      ].join('\n'),
    );
  });

  it('reports skill installation failure without hiding bridge success', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      commandResults: new Map([
        [
          `npx skills add ${ASK_UI_SKILL_URL}`,
          { exitCode: 1, stdout: '', stderr: 'skill failed' },
        ],
      ]),
    });

    const result = await runAskUiInstaller({
      args: ['install', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 1);
    assert.deepEqual(JSON.parse(result.stdout), {
      status: 'error',
      error: 'install_failed',
      failedStep: 'install_skill',
      projectRoot: '/workspace/flutter_app',
      steps: [
        {
          name: 'install_bridge',
          status: 'ok',
          command: 'dart pub global activate ask_ui_bridge',
          exitCode: 0,
        },
        {
          name: 'install_skill',
          status: 'failed',
          command: `npx skills add ${ASK_UI_SKILL_URL}`,
          exitCode: 1,
          stderr: 'skill failed',
        },
      ],
    });
    assert.deepEqual(
      tools.executedCommands.map((command) => command.command),
      ['dart', 'npx'],
    );
    assert.deepEqual(tools.writtenFiles, new Map());
  });

  it('reports diagnostics failure after writing metadata', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      commandResults: new Map([
        [
          'ask_ui_bridge doctor --project /workspace/flutter_app',
          { exitCode: 2, stdout: 'doctor output', stderr: 'doctor failed' },
        ],
      ]),
    });

    const result = await runAskUiInstaller({
      args: ['install', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 1);
    const output = JSON.parse(result.stdout);
    assert.equal(output.failedStep, 'run_diagnostics');
    assert.deepEqual(output.steps.at(-1), {
      name: 'run_diagnostics',
      status: 'failed',
      command: 'ask_ui_bridge doctor --project /workspace/flutter_app',
      exitCode: 2,
      stdout: 'doctor output',
      stderr: 'doctor failed',
    });
    assertMetadata(tools, '/workspace/flutter_app');
  });

  it('reports metadata write failure before running diagnostics', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      writeError: new Error('metadata denied'),
    });

    const result = await runAskUiInstaller({
      args: ['install', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 1);
    assert.deepEqual(JSON.parse(result.stdout), {
      status: 'error',
      error: 'install_failed',
      failedStep: 'write_metadata',
      projectRoot: '/workspace/flutter_app',
      steps: [
        {
          name: 'install_bridge',
          status: 'ok',
          command: 'dart pub global activate ask_ui_bridge',
          exitCode: 0,
        },
        {
          name: 'install_skill',
          status: 'ok',
          command: `npx skills add ${ASK_UI_SKILL_URL}`,
          exitCode: 0,
        },
        {
          name: 'write_metadata',
          status: 'failed',
          path: '/workspace/flutter_app/.ask-ui/config.json',
          message: 'metadata denied',
        },
      ],
    });
    assert.deepEqual(
      tools.executedCommands.map((command) => command.command),
      ['dart', 'npx'],
    );
  });

  it('prints human-readable prerequisite failure by default', async () => {
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
    assert.equal(
      result.stdout,
      [
        'Ask UI install prerequisites failed',
        'Project: /workspace/flutter_app',
        '',
        'Checks:',
        '- OK dart: dart is available.',
        '- MISSING flutter: Install Flutter and ensure flutter is on PATH.',
        '- OK project: Flutter project found.',
        '',
      ].join('\n'),
    );
    assert.deepEqual(tools.executedCommands, []);
  });

  it('prints JSON prerequisite failure when --json is provided', async () => {
    const tools = new FakeTools({
      availableCommands: new Set(['dart']),
      flutterProjects: new Set(['/workspace/flutter_app']),
    });

    const result = await runAskUiInstaller({
      args: ['install', '--json'],
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
  });

  it('rejects removed installer arguments', async () => {
    for (const args of [
      ['install', '--yes'],
      ['install', '-y'],
      ['install', '--agent', 'codex'],
      ['install', '--skill-only'],
    ]) {
      const result = await runAskUiInstaller({
        args,
        cwd: '/workspace/flutter_app',
        env: {},
        tools: new FakeTools(),
      });

      assert.equal(result.exitCode, 1);
      assert.equal(result.stdout, '');
      assert.equal(result.stderr, 'Invalid ask-ui installer arguments.\n');
    }
  });

  it('prints JSON invalid argument errors when --json is provided', async () => {
    const result = await runAskUiInstaller({
      args: ['install', '--project', '--json'],
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

  it('rejects update dry-run instead of silently mutating', async () => {
    const result = await runAskUiInstaller({
      args: ['update', '--dry-run'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools: new FakeTools(),
    });

    assert.equal(result.exitCode, 1);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, 'Invalid ask-ui installer arguments.\n');
  });

  it('keeps public install docs aligned with the installer skill command', async () => {
    const readme = await readFile(resolve(REPO_ROOT, 'README.md'), 'utf8');
    const tools = readyTools('/workspace/flutter_app');

    const result = await runAskUiInstaller({
      args: ['install', '--dry-run', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    const plan = JSON.parse(result.stdout);
    const documentedCommands = commandsInSection(readme, 'Other Install Ways');
    const installerSkillCommand = plan.actions.find(
      (action) => action.name === 'install_skill',
    )?.command;

    assert.match(readme, /^## Recommended Install$/m);
    assert.match(readme, /^## Other Install Ways$/m);
    assert.doesNotMatch(readme, /^## Bridge Only$/m);
    assert.doesNotMatch(readme, /^## Skill Only$/m);
    assert.deepEqual(documentedCommands, [
      'dart pub global activate ask_ui_bridge',
      installerSkillCommand,
    ]);
  });

  it('updates an out-of-date Ask UI setup and refreshes metadata', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      files: metadataFiles('/workspace/flutter_app', {
        version: '0.0.4',
        bridge: '0.0.4',
        runtime: '0.0.4',
        skill: '0.0.4',
      }),
    });

    const result = await runAskUiInstaller({
      args: ['update', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    assert.equal(result.stderr, '');
    assert.deepEqual(JSON.parse(result.stdout), {
      status: 'updated',
      command: 'update',
      projectRoot: '/workspace/flutter_app',
      current: {
        version: '0.0.4',
        bridge: '0.0.4',
        runtime: '0.0.4',
        skill: '0.0.4',
      },
      target: {
        version: '0.0.5',
        bridge: '0.0.5',
        runtime: '0.0.5',
        skill: '0.0.5',
      },
      changes: [
        { name: 'bridge', from: '0.0.4', to: '0.0.5' },
        { name: 'skill', from: '0.0.4', to: '0.0.5' },
        { name: 'metadata', from: '0.0.4', to: '0.0.5' },
      ],
      steps: [
        {
          name: 'read_metadata',
          status: 'ok',
          path: '/workspace/flutter_app/.ask-ui/config.json',
        },
        {
          name: 'update_bridge',
          status: 'ok',
          command: 'dart pub global activate ask_ui_bridge',
          exitCode: 0,
        },
        {
          name: 'update_skill',
          status: 'ok',
          command: `npx skills add ${ASK_UI_SKILL_URL}`,
          exitCode: 0,
        },
        {
          name: 'write_metadata',
          status: 'ok',
          path: '/workspace/flutter_app/.ask-ui/config.json',
        },
        {
          name: 'run_diagnostics',
          status: 'ok',
          command: 'ask_ui_bridge doctor --project /workspace/flutter_app',
          exitCode: 0,
        },
      ],
      metadataPath: '/workspace/flutter_app/.ask-ui/config.json',
      launchCommand: 'ask_ui_bridge launch --project-root /workspace/flutter_app',
    });
    assertInstallCommands(tools, '/workspace/flutter_app');
    assertMetadata(tools, '/workspace/flutter_app');
  });

  it('treats an already-current setup as a successful no-op', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      files: metadataFiles('/workspace/flutter_app', {
        version: '0.0.5',
        bridge: '0.0.5',
        runtime: '0.0.5',
        skill: '0.0.5',
      }),
    });

    const result = await runAskUiInstaller({
      args: ['update'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    assert.equal(result.stderr, '');
    assert.equal(
      result.stdout,
      [
        'Ask UI is current',
        'Project: /workspace/flutter_app',
        '',
        'Changes:',
        '- none',
        '',
        'Completed:',
        '- OK read_metadata: /workspace/flutter_app/.ask-ui/config.json',
        '- OK run_diagnostics: ask_ui_bridge doctor --project /workspace/flutter_app',
        '',
        'Next:',
        'ask_ui_bridge launch --project-root /workspace/flutter_app',
        '',
      ].join('\n'),
    );
    assert.deepEqual(tools.executedCommands, [
      {
        command: 'ask_ui_bridge',
        args: ['doctor', '--project', '/workspace/flutter_app'],
        cwd: undefined,
      },
    ]);
    assert.deepEqual(tools.writtenFiles, new Map());
  });

  it('updates only out-of-date bridge and metadata for mixed-version setup', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      files: metadataFiles('/workspace/flutter_app', {
        version: '0.0.5',
        bridge: '0.0.4',
        runtime: '0.0.5',
        skill: '0.0.5',
      }),
    });

    const result = await runAskUiInstaller({
      args: ['update', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 0);
    const output = JSON.parse(result.stdout);
    assert.deepEqual(output.changes, [
      { name: 'bridge', from: '0.0.4', to: '0.0.5' },
    ]);
    assert.deepEqual(
      tools.executedCommands.map((command) => command.command),
      ['dart', 'ask_ui_bridge'],
    );
    assertMetadata(tools, '/workspace/flutter_app');
  });

  it('reports partial update failure with completed and failed steps', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      files: metadataFiles('/workspace/flutter_app', {
        version: '0.0.4',
        bridge: '0.0.4',
        runtime: '0.0.4',
        skill: '0.0.4',
      }),
      commandResults: new Map([
        [
          `npx skills add ${ASK_UI_SKILL_URL}`,
          { exitCode: 1, stdout: '', stderr: 'skill update failed' },
        ],
      ]),
    });

    const result = await runAskUiInstaller({
      args: ['update', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 1);
    assert.deepEqual(JSON.parse(result.stdout), {
      status: 'error',
      error: 'update_failed',
      failedStep: 'update_skill',
      projectRoot: '/workspace/flutter_app',
      current: {
        version: '0.0.4',
        bridge: '0.0.4',
        runtime: '0.0.4',
        skill: '0.0.4',
      },
      target: {
        version: '0.0.5',
        bridge: '0.0.5',
        runtime: '0.0.5',
        skill: '0.0.5',
      },
      changes: [
        { name: 'bridge', from: '0.0.4', to: '0.0.5' },
        { name: 'skill', from: '0.0.4', to: '0.0.5' },
        { name: 'metadata', from: '0.0.4', to: '0.0.5' },
      ],
      steps: [
        {
          name: 'read_metadata',
          status: 'ok',
          path: '/workspace/flutter_app/.ask-ui/config.json',
        },
        {
          name: 'update_bridge',
          status: 'ok',
          command: 'dart pub global activate ask_ui_bridge',
          exitCode: 0,
        },
        {
          name: 'update_skill',
          status: 'failed',
          command: `npx skills add ${ASK_UI_SKILL_URL}`,
          exitCode: 1,
          stderr: 'skill update failed',
        },
      ],
      nextStep: 'Resolve the skill update error, then rerun npx ask-ui update.',
    });
    assert.deepEqual(tools.writtenFiles, new Map());
  });

  it('reports post-update diagnostics failure after refreshing metadata', async () => {
    const tools = readyTools('/workspace/flutter_app', {
      files: metadataFiles('/workspace/flutter_app', {
        version: '0.0.5',
        bridge: '0.0.5',
        runtime: '0.0.5',
        skill: '0.0.4',
      }),
      commandResults: new Map([
        [
          'ask_ui_bridge doctor --project /workspace/flutter_app',
          { exitCode: 2, stdout: 'doctor output', stderr: 'doctor failed' },
        ],
      ]),
    });

    const result = await runAskUiInstaller({
      args: ['update', '--json'],
      cwd: '/workspace/flutter_app',
      env: {},
      tools,
    });

    assert.equal(result.exitCode, 1);
    const output = JSON.parse(result.stdout);
    assert.equal(output.failedStep, 'run_diagnostics');
    assert.deepEqual(output.steps.at(-1), {
      name: 'run_diagnostics',
      status: 'failed',
      command: 'ask_ui_bridge doctor --project /workspace/flutter_app',
      exitCode: 2,
      stdout: 'doctor output',
      stderr: 'doctor failed',
    });
    assert.equal(
      output.nextStep,
      'Review diagnostics output before launching Ask UI.',
    );
    assertMetadata(tools, '/workspace/flutter_app');
  });
});

function readyTools(projectRoot, options = {}) {
  return new FakeTools({
    availableCommands: new Set(['dart', 'flutter']),
    flutterProjects: new Set([projectRoot]),
    ...options,
  });
}

function metadataFiles(projectRoot, metadata) {
  return new Map([
    [`${projectRoot}/.ask-ui/config.json`, JSON.stringify(metadata)],
  ]);
}

function planPayload() {
  return {
    status: 'plan',
    command: 'install',
    projectRoot: '/workspace/flutter_app',
    dryRun: true,
    checks: checksPayload(),
    actions: [
      {
        name: 'install_bridge',
        command: 'dart pub global activate ask_ui_bridge',
        mutates: 'global-dart',
        willRun: false,
      },
      {
        name: 'install_skill',
        command: `npx skills add ${ASK_UI_SKILL_URL}`,
        mutates: 'agent-skills',
        willRun: false,
      },
      {
        name: 'write_metadata',
        command: 'write /workspace/flutter_app/.ask-ui/config.json',
        mutates: 'flutter-project',
        willRun: false,
      },
      {
        name: 'run_diagnostics',
        command: 'ask_ui_bridge doctor --project /workspace/flutter_app',
        mutates: 'none',
        willRun: false,
      },
    ],
    nextStep: 'Run npx ask-ui install to apply this plan.',
  };
}

function installedPayload() {
  return {
    status: 'installed',
    command: 'install',
    projectRoot: '/workspace/flutter_app',
    dryRun: false,
    checks: checksPayload(),
    steps: [
      {
        name: 'install_bridge',
        status: 'ok',
        command: 'dart pub global activate ask_ui_bridge',
        exitCode: 0,
      },
      {
        name: 'install_skill',
        status: 'ok',
        command: `npx skills add ${ASK_UI_SKILL_URL}`,
        exitCode: 0,
      },
      {
        name: 'write_metadata',
        status: 'ok',
        path: '/workspace/flutter_app/.ask-ui/config.json',
      },
      {
        name: 'run_diagnostics',
        status: 'ok',
        command: 'ask_ui_bridge doctor --project /workspace/flutter_app',
        exitCode: 0,
      },
    ],
    metadataPath: '/workspace/flutter_app/.ask-ui/config.json',
    launchCommand: 'ask_ui_bridge launch --project-root /workspace/flutter_app',
  };
}

function checksPayload() {
  return [
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
  ];
}

function assertInstallCommands(tools, projectRoot) {
  assert.deepEqual(tools.executedCommands, [
    {
      command: 'dart',
      args: ['pub', 'global', 'activate', 'ask_ui_bridge'],
      cwd: undefined,
    },
    {
      command: 'npx',
      args: ['skills', 'add', ASK_UI_SKILL_URL],
      cwd: undefined,
    },
    {
      command: 'ask_ui_bridge',
      args: ['doctor', '--project', projectRoot],
      cwd: undefined,
    },
  ]);
}

function assertMetadata(tools, projectRoot) {
  assert.equal(
    tools.writtenFiles.get(`${projectRoot}/.ask-ui/config.json`),
    `${JSON.stringify(
      {
        version: '0.0.5',
        bridge: '0.0.5',
        runtime: '0.0.5',
        skill: '0.0.5',
      },
      null,
      2,
    )}\n`,
  );
}

function commandsInSection(markdown, heading) {
  const sectionMatch = markdown.match(
    new RegExp(
      `^## ${heading}\\n(?<body>[\\s\\S]*?)(?=^## |$(?![\\s\\S]))`,
      'm',
    ),
  );
  assert.ok(sectionMatch, `Missing README section: ${heading}`);
  return [...sectionMatch.groups.body.matchAll(/^([^`\n#].+)$/gm)]
    .map((match) => match[1].trim())
    .filter(
      (line) =>
        line === 'dart pub global activate ask_ui_bridge' ||
        line.startsWith('npx skills add '),
    );
}

class FakeTools {
  constructor({
    availableCommands = new Set(),
    flutterProjects = new Set(),
    commandResults = new Map(),
    files = new Map(),
    writeError = null,
  } = {}) {
    this.availableCommands = availableCommands;
    this.flutterProjects = flutterProjects;
    this.commandResults = commandResults;
    this.files = files;
    this.writeError = writeError;
    this.executedCommands = [];
    this.createdDirectories = [];
    this.writtenFiles = new Map();
  }

  async commandExists(command) {
    return this.availableCommands.has(command);
  }

  async isFlutterProject(projectRoot) {
    return this.flutterProjects.has(projectRoot);
  }

  async createDirectory(directory) {
    this.createdDirectories.push(directory);
  }

  async readFile(path) {
    if (!this.files.has(path)) {
      throw new Error(`missing file: ${path}`);
    }
    return this.files.get(path);
  }

  async writeFile(path, contents) {
    if (this.writeError) {
      throw this.writeError;
    }
    this.writtenFiles.set(path, contents);
  }

  async run(command, args, options = {}) {
    this.executedCommands.push({ command, args, cwd: options.cwd });
    const key = [command, ...args].join(' ');
    return (
      this.commandResults.get(key) ?? { exitCode: 0, stdout: '', stderr: '' }
    );
  }
}
