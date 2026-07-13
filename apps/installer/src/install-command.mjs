import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { delimiter, join } from 'node:path';
import { spawn } from 'node:child_process';

const ASK_UI_SKILL_URL =
  'https://github.com/drown0315/ask_ui/tree/main/skills/ask-ui';
const ASK_UI_VERSION_MANIFEST = {
  latest: '0.0.5',
  minimumSupported: '0.0.5',
  packages: {
    installer: '0.0.5',
    bridge: '0.0.5',
    runtime: '0.0.5',
    skill: '0.0.5',
  },
};
const ASK_UI_VERSION_SET = {
  version: ASK_UI_VERSION_MANIFEST.latest,
  bridge: ASK_UI_VERSION_MANIFEST.packages.bridge,
  runtime: ASK_UI_VERSION_MANIFEST.packages.runtime,
  skill: ASK_UI_VERSION_MANIFEST.packages.skill,
};

/**
 * Runs the Ask UI npm installer command.
 *
 * The installer validates the target project and local tools, can print an
 * explicit dry-run plan, and otherwise performs the local Ask UI bootstrap.
 */
export async function runAskUiInstaller({
  args,
  cwd,
  env = process.env,
  tools = new NodeInstallerTools(env),
}) {
  let options;
  try {
    options = parseInstallOptions(args);
  } catch {
    return invalidArgumentsResult(args.includes('--json'));
  }

  if (options.command !== 'install' && options.command !== 'update') {
    return invalidArgumentsResult(options.json);
  }
  if (options.command === 'update' && options.dryRun) {
    return invalidArgumentsResult(options.json);
  }

  const projectRoot = options.projectRoot ?? cwd;
  const checks = [
    await commandCheck(tools, 'dart', 'Install Dart and ensure dart is on PATH.'),
    await commandCheck(
      tools,
      'flutter',
      'Install Flutter and ensure flutter is on PATH.',
    ),
    await projectCheck(tools, projectRoot),
  ];
  const hasMissingPrerequisites = checks.some(
    (check) => check.status !== 'ok',
  );

  if (hasMissingPrerequisites) {
    return installerResult({
      exitCode: 1,
      json: options.json,
      payload: {
        status: 'error',
        error: 'missing_prerequisites',
        projectRoot,
        checks,
      },
      text: formatMissingPrerequisites({ projectRoot, checks }),
    });
  }

  if (options.command === 'update') {
    return runUpdateCommand({ tools, projectRoot, json: options.json });
  }

  if (options.dryRun) {
    return installerResult({
      exitCode: 0,
      json: options.json,
      payload: {
        status: 'plan',
        command: 'install',
        projectRoot,
        dryRun: true,
        checks,
        actions: installActions({ projectRoot }),
        nextStep: 'Run npx ask-ui install to apply this plan.',
      },
      text: formatInstallPlan({
        projectRoot,
        checks,
        actions: installActions({ projectRoot }),
      }),
    });
  }

  const steps = [];
  const bridgeStep = await runInstallStep(tools, {
    name: 'install_bridge',
    command: 'dart',
    args: ['pub', 'global', 'activate', 'ask_ui_bridge'],
  });
  steps.push(bridgeStep);
  if (bridgeStep.status === 'failed') {
    return installFailure({
      json: options.json,
      projectRoot,
      failedStep: bridgeStep.name,
      steps,
    });
  }

  const skillStep = await runInstallStep(tools, {
    name: 'install_skill',
    command: 'npx',
    args: ['skills', 'add', ASK_UI_SKILL_URL],
  });
  steps.push(skillStep);
  if (skillStep.status === 'failed') {
    return installFailure({
      json: options.json,
      projectRoot,
      failedStep: skillStep.name,
      steps,
    });
  }

  const metadataPath = join(projectRoot, '.ask-ui', 'config.json');
  const metadataStep = await writeMetadataStep(tools, {
    path: metadataPath,
    directory: join(projectRoot, '.ask-ui'),
  });
  steps.push(metadataStep);
  if (metadataStep.status === 'failed') {
    return installFailure({
      json: options.json,
      projectRoot,
      failedStep: metadataStep.name,
      steps,
    });
  }

  const diagnosticsStep = await runInstallStep(tools, {
    name: 'run_diagnostics',
    command: 'ask_ui_bridge',
    args: ['doctor', '--project', projectRoot],
  });
  steps.push(diagnosticsStep);
  if (diagnosticsStep.status === 'failed') {
    return installFailure({
      json: options.json,
      projectRoot,
      failedStep: diagnosticsStep.name,
      steps,
    });
  }

  const payload = {
    status: 'installed',
    command: 'install',
    projectRoot,
    dryRun: false,
    checks,
    steps,
    metadataPath,
    launchCommand: `ask_ui_bridge launch --project-root ${projectRoot}`,
  };
  return installerResult({
    exitCode: 0,
    json: options.json,
    payload,
    text: formatInstalled(payload),
  });
}

class NodeInstallerTools {
  constructor(env) {
    this.env = env;
  }

  async commandExists(command) {
    const pathValue = this.env.PATH ?? '';
    for (const directory of pathValue.split(delimiter)) {
      if (directory.length === 0) {
        continue;
      }
      try {
        await access(join(directory, command), constants.X_OK);
        return true;
      } catch {
        // Continue searching PATH.
      }
    }
    return false;
  }

  async isFlutterProject(projectRoot) {
    try {
      await access(join(projectRoot, 'pubspec.yaml'), constants.R_OK);
      return true;
    } catch {
      return false;
    }
  }

  async createDirectory(directory) {
    await mkdir(directory, { recursive: true });
  }

  async writeFile(path, contents) {
    await writeFile(path, contents);
  }

  async readFile(path) {
    return readFile(path, 'utf8');
  }

  async run(command, args, options = {}) {
    return new Promise((resolve) => {
      const child = spawn(command, args, {
        cwd: options.cwd,
        env: this.env,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      let stdout = '';
      let stderr = '';
      child.stdout.on('data', (chunk) => {
        stdout += chunk;
      });
      child.stderr.on('data', (chunk) => {
        stderr += chunk;
      });
      child.on('close', (exitCode) => {
        resolve({ exitCode, stdout, stderr });
      });
      child.on('error', (error) => {
        resolve({ exitCode: 1, stdout: '', stderr: error.message });
      });
    });
  }
}

async function runUpdateCommand({ tools, projectRoot, json }) {
  const metadataPath = join(projectRoot, '.ask-ui', 'config.json');
  const steps = [];
  const metadataStep = await readMetadataStep(tools, metadataPath);
  steps.push(metadataStep);
  if (metadataStep.status === 'failed') {
    return updateFailure({
      json,
      projectRoot,
      failedStep: metadataStep.name,
      steps,
      nextStep: 'Run npx ask-ui install to create local metadata.',
    });
  }

  const current = metadataStep.metadata;
  const target = ASK_UI_VERSION_SET;
  const changes = updateChanges(current, target);

  if (current.bridge !== target.bridge) {
    const bridgeStep = await runInstallStep(tools, {
      name: 'update_bridge',
      command: 'dart',
      args: ['pub', 'global', 'activate', 'ask_ui_bridge'],
    });
    steps.push(bridgeStep);
    if (bridgeStep.status === 'failed') {
      return updateFailure({
        json,
        projectRoot,
        failedStep: bridgeStep.name,
        steps,
        current,
        target,
        changes,
        nextStep:
          'Resolve the bridge update error, then rerun npx ask-ui update.',
      });
    }
  }

  if (current.skill !== target.skill) {
    const skillStep = await runInstallStep(tools, {
      name: 'update_skill',
      command: 'npx',
      args: ['skills', 'add', ASK_UI_SKILL_URL],
    });
    steps.push(skillStep);
    if (skillStep.status === 'failed') {
      return updateFailure({
        json,
        projectRoot,
        failedStep: skillStep.name,
        steps,
        current,
        target,
        changes,
        nextStep: 'Resolve the skill update error, then rerun npx ask-ui update.',
      });
    }
  }

  if (changes.length > 0) {
    const writeStep = await writeMetadataStep(tools, {
      path: metadataPath,
      directory: join(projectRoot, '.ask-ui'),
    });
    steps.push(writeStep);
    if (writeStep.status === 'failed') {
      return updateFailure({
        json,
        projectRoot,
        failedStep: writeStep.name,
        steps,
        current,
        target,
        changes,
        nextStep: 'Fix metadata write access, then rerun npx ask-ui update.',
      });
    }
  }

  const diagnosticsStep = await runInstallStep(tools, {
    name: 'run_diagnostics',
    command: 'ask_ui_bridge',
    args: ['doctor', '--project', projectRoot],
  });
  steps.push(diagnosticsStep);
  if (diagnosticsStep.status === 'failed') {
    return updateFailure({
      json,
      projectRoot,
      failedStep: diagnosticsStep.name,
      steps,
      current,
      target,
      changes,
      nextStep: 'Review diagnostics output before launching Ask UI.',
    });
  }

  const payload = {
    status: changes.length === 0 ? 'current' : 'updated',
    command: 'update',
    projectRoot,
    current,
    target,
    changes,
    steps: steps.map(stripStepMetadata),
    metadataPath,
    launchCommand: `ask_ui_bridge launch --project-root ${projectRoot}`,
  };
  return installerResult({
    exitCode: 0,
    json,
    payload,
    text: formatUpdated(payload),
  });
}

async function readMetadataStep(tools, path) {
  try {
    const source = await tools.readFile(path);
    return {
      name: 'read_metadata',
      status: 'ok',
      path,
      metadata: parseMetadata(source),
    };
  } catch (error) {
    return {
      name: 'read_metadata',
      status: 'failed',
      path,
      message: error instanceof Error ? error.message : String(error),
    };
  }
}

function parseMetadata(source) {
  const decoded = JSON.parse(source);
  if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) {
    throw new Error('metadata must be a JSON object.');
  }
  return {
    version: nonEmptyString(decoded.version, 'version'),
    bridge: nonEmptyString(decoded.bridge, 'bridge'),
    runtime: nonEmptyString(decoded.runtime, 'runtime'),
    skill: nonEmptyString(decoded.skill, 'skill'),
  };
}

function nonEmptyString(value, name) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`${name} must be a non-empty string.`);
  }
  return value;
}

function updateChanges(current, target) {
  const changes = [];
  if (current.bridge !== target.bridge) {
    changes.push({ name: 'bridge', from: current.bridge, to: target.bridge });
  }
  if (current.skill !== target.skill) {
    changes.push({ name: 'skill', from: current.skill, to: target.skill });
  }
  if (current.version !== target.version || current.runtime !== target.runtime) {
    changes.push({
      name: 'metadata',
      from: current.version,
      to: target.version,
    });
  }
  return changes;
}

function stripStepMetadata(step) {
  const { metadata, ...publicStep } = step;
  return publicStep;
}

function parseInstallOptions(args) {
  if (args.length === 0) {
    throw new Error('missing command');
  }
  const [command, ...rest] = args;
  let projectRoot = null;
  let dryRun = false;
  let json = false;

  for (let index = 0; index < rest.length; ) {
    const argument = rest[index];
    if (argument === '--project' || argument === '--project-root') {
      if (index + 1 >= rest.length || rest[index + 1].startsWith('-')) {
        throw new Error('missing project');
      }
      projectRoot = rest[index + 1];
      index += 2;
    } else if (argument === '--dry-run') {
      dryRun = true;
      index += 1;
    } else if (argument === '--json') {
      json = true;
      index += 1;
    } else {
      throw new Error(`unsupported argument ${argument}`);
    }
  }

  return { command, projectRoot, dryRun, json };
}

async function commandCheck(tools, command, missingMessage) {
  if (await tools.commandExists(command)) {
    return {
      name: command,
      status: 'ok',
      message: `${command} is available.`,
    };
  }
  return {
    name: command,
    status: 'missing',
    message: missingMessage,
  };
}

async function projectCheck(tools, projectRoot) {
  if (await tools.isFlutterProject(projectRoot)) {
    return {
      name: 'project',
      status: 'ok',
      message: 'Flutter project found.',
    };
  }
  return {
    name: 'project',
    status: 'missing',
    message: 'Run from a Flutter project or pass --project <path>.',
  };
}

function installActions({ projectRoot }) {
  return [
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
      command: `write ${join(projectRoot, '.ask-ui', 'config.json')}`,
      mutates: 'flutter-project',
      willRun: false,
    },
    {
      name: 'run_diagnostics',
      command: `ask_ui_bridge doctor --project ${projectRoot}`,
      mutates: 'none',
      willRun: false,
    },
  ];
}

async function writeMetadataStep(tools, { directory, path }) {
  try {
    await tools.createDirectory(directory);
    await tools.writeFile(
      path,
      `${JSON.stringify(ASK_UI_VERSION_SET, null, 2)}\n`,
    );
    return {
      name: 'write_metadata',
      status: 'ok',
      path,
    };
  } catch (error) {
    return {
      name: 'write_metadata',
      status: 'failed',
      path,
      message: error instanceof Error ? error.message : String(error),
    };
  }
}

async function runInstallStep(tools, { name, command, args }) {
  const result = await tools.run(command, args);
  const step = {
    name,
    status: result.exitCode === 0 ? 'ok' : 'failed',
    command: [command, ...args].join(' '),
    exitCode: result.exitCode,
  };
  if (result.stdout) {
    step.stdout = result.stdout;
  }
  if (result.stderr) {
    step.stderr = result.stderr;
  }
  return step;
}

function installFailure({ json, projectRoot, failedStep, steps }) {
  return installerResult({
    exitCode: 1,
    json,
    payload: {
      status: 'error',
      error: 'install_failed',
      failedStep,
      projectRoot,
      steps,
    },
    text: formatInstallFailure({ projectRoot, failedStep, steps }),
  });
}

function updateFailure({
  json,
  projectRoot,
  failedStep,
  steps,
  current,
  target,
  changes = [],
  nextStep,
}) {
  return installerResult({
    exitCode: 1,
    json,
    payload: {
      status: 'error',
      error: 'update_failed',
      failedStep,
      projectRoot,
      ...(current ? { current } : {}),
      ...(target ? { target } : {}),
      changes,
      steps: steps.map(stripStepMetadata),
      nextStep,
    },
    text: formatUpdateFailure({
      projectRoot,
      failedStep,
      steps: steps.map(stripStepMetadata),
      nextStep,
    }),
  });
}

function invalidArgumentsResult(json) {
  if (json) {
    return {
      exitCode: 1,
      stdout: '',
      stderr: `${JSON.stringify({
        status: 'error',
        error: 'invalid_arguments',
      })}\n`,
    };
  }
  return {
    exitCode: 1,
    stdout: '',
    stderr: 'Invalid ask-ui installer arguments.\n',
  };
}

function installerResult({ exitCode, json, payload, text }) {
  return {
    exitCode,
    stdout: json ? `${JSON.stringify(payload)}\n` : text,
    stderr: '',
  };
}

function formatInstallPlan({ projectRoot, checks, actions }) {
  return [
    'Ask UI install plan',
    `Project: ${projectRoot}`,
    '',
    'Checks:',
    ...checks.map(formatCheck),
    '',
    'Actions:',
    ...actions.map((action) => `- ${action.command}`),
    '',
    'Run npx ask-ui install to apply this plan.',
    '',
  ].join('\n');
}

function formatInstalled({ projectRoot, steps, launchCommand }) {
  return [
    'Ask UI installed',
    `Project: ${projectRoot}`,
    '',
    'Completed:',
    ...steps.map(formatStep),
    '',
    'Next:',
    launchCommand,
    '',
  ].join('\n');
}

function formatUpdated({ status, projectRoot, changes, steps, launchCommand }) {
  return [
    status === 'current' ? 'Ask UI is current' : 'Ask UI updated',
    `Project: ${projectRoot}`,
    '',
    'Changes:',
    ...(changes.length === 0
      ? ['- none']
      : changes.map(
          (change) => `- ${change.name}: ${change.from} -> ${change.to}`,
        )),
    '',
    'Completed:',
    ...steps.map(formatStep),
    '',
    'Next:',
    launchCommand,
    '',
  ].join('\n');
}

function formatMissingPrerequisites({ projectRoot, checks }) {
  return [
    'Ask UI install prerequisites failed',
    `Project: ${projectRoot}`,
    '',
    'Checks:',
    ...checks.map(formatCheck),
    '',
  ].join('\n');
}

function formatInstallFailure({ projectRoot, failedStep, steps }) {
  return [
    'Ask UI install failed',
    `Project: ${projectRoot}`,
    `Failed step: ${failedStep}`,
    '',
    'Steps:',
    ...steps.flatMap(formatStepWithDetails),
    '',
  ].join('\n');
}

function formatUpdateFailure({ projectRoot, failedStep, steps, nextStep }) {
  return [
    'Ask UI update failed',
    `Project: ${projectRoot}`,
    `Failed step: ${failedStep}`,
    '',
    'Steps:',
    ...steps.flatMap(formatStepWithDetails),
    '',
    'Next:',
    nextStep,
    '',
  ].join('\n');
}

function formatCheck(check) {
  return `- ${check.status.toUpperCase()} ${check.name}: ${check.message}`;
}

function formatStep(step) {
  const detail = step.command ?? step.path;
  return `- ${step.status.toUpperCase()} ${step.name}: ${detail}`;
}

function formatStepWithDetails(step) {
  const lines = [formatStep(step)];
  if (step.stdout) {
    lines.push(`  stdout: ${step.stdout}`);
  }
  if (step.stderr) {
    lines.push(`  stderr: ${step.stderr}`);
  }
  if (step.message) {
    lines.push(`  message: ${step.message}`);
  }
  return lines;
}
