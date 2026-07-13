import { access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { delimiter, join } from 'node:path';
import { spawn } from 'node:child_process';

/**
 * Runs the Ask UI npm installer command.
 *
 * The first installer slice is intentionally dry-run only. It validates the
 * target project and local tools, then prints the setup actions that a later
 * slice will execute.
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
    return jsonFailure('invalid_arguments');
  }

  if (options.command !== 'install') {
    return jsonFailure('invalid_arguments');
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
    return {
      exitCode: 1,
      stdout: `${JSON.stringify({
        status: 'error',
        error: 'missing_prerequisites',
        projectRoot,
        checks,
      })}\n`,
      stderr: '',
    };
  }

  return {
    exitCode: 0,
    stdout: `${JSON.stringify({
      status: 'plan',
      command: 'install',
      projectRoot,
      agent: options.agent,
      approved: options.approved,
      dryRun: true,
      checks,
      actions: installActions({ projectRoot, agent: options.agent }),
      nextStep: options.approved
        ? 'Dry-run only for this release; no setup commands were executed.'
        : 'Re-run with --yes when you are ready to apply this plan.',
    })}\n`,
    stderr: '',
  };
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

function parseInstallOptions(args) {
  if (args.length === 0) {
    throw new Error('missing command');
  }
  const [command, ...rest] = args;
  let projectRoot = null;
  let agent = 'codex';
  let approved = false;

  for (let index = 0; index < rest.length; ) {
    const argument = rest[index];
    if (argument === '--project' || argument === '--project-root') {
      if (index + 1 >= rest.length) {
        throw new Error('missing project');
      }
      projectRoot = rest[index + 1];
      index += 2;
    } else if (argument === '--agent') {
      if (index + 1 >= rest.length) {
        throw new Error('missing agent');
      }
      agent = rest[index + 1];
      index += 2;
    } else if (argument === '--yes' || argument === '-y') {
      approved = true;
      index += 1;
    } else {
      throw new Error(`unsupported argument ${argument}`);
    }
  }

  return { command, projectRoot, agent, approved };
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

function installActions({ projectRoot, agent }) {
  return [
    {
      name: 'install_bridge',
      command: 'dart pub global activate ask_ui_bridge',
      mutates: 'global-dart',
      willRun: false,
    },
    {
      name: 'add_runtime',
      command: 'flutter pub add ask_ui_runtime',
      cwd: projectRoot,
      mutates: 'flutter-project',
      willRun: false,
    },
    {
      name: 'install_skill',
      command: `npx skills add ask-ui --agent ${agent}`,
      mutates: 'agent-skills',
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

function jsonFailure(error) {
  return {
    exitCode: 1,
    stdout: '',
    stderr: `${JSON.stringify({
      status: 'error',
      error,
    })}\n`,
  };
}
