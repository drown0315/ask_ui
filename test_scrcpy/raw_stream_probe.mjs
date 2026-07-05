import net from 'node:net';
import { spawn } from 'node:child_process';
import { writeFile, rm } from 'node:fs/promises';

const config = {
  adb: process.env.ADB || 'adb',
  deviceId: process.env.DEVICE_ID || '',
  serverPath:
    process.env.SCRCPY_SERVER ||
    '/opt/homebrew/Cellar/scrcpy/4.0/share/scrcpy/scrcpy-server',
  localPort: Number(process.env.PORT || 27183),
  scid: process.env.SCID || '1a2b3c4d',
  tunnelMode: process.env.TUNNEL_MODE || 'reverse',
  maxSize: Number(process.env.MAX_SIZE || 1080),
  videoBitRate: Number(process.env.VIDEO_BIT_RATE || 4_000_000),
  captureMs: Number(process.env.CAPTURE_MS || 5000),
  outputPath: process.env.OUTPUT || '/private/tmp/ask-ui-scrcpy-raw-probe.h264',
};

let serverProcess;

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      ...options,
    });
    let stdout = '';
    let stderr = '';

    child.stdout?.on('data', (chunk) => {
      stdout += chunk;
    });
    child.stderr?.on('data', (chunk) => {
      stderr += chunk;
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
        return;
      }

      reject(new Error(`${command} ${args.join(' ')} failed (${code})\n${stderr || stdout}`));
    });
  });
}

function adbArgs(...args) {
  return config.deviceId ? ['-s', config.deviceId, ...args] : args;
}

async function chooseDeviceId() {
  if (config.deviceId) {
    return config.deviceId;
  }

  const { stdout } = await run(config.adb, ['devices']);
  const devices = stdout
    .split('\n')
    .map((line) => line.trim().split(/\s+/))
    .filter(([serial, status]) => serial && status === 'device')
    .map(([serial]) => serial);

  if (devices.length !== 1) {
    throw new Error(`Set DEVICE_ID. Found ${devices.length} authorized devices.`);
  }

  return devices[0];
}

function findStartCodes(buffer) {
  const offsets = [];
  for (let i = 0; i < buffer.length - 3; i += 1) {
    if (buffer[i] === 0 && buffer[i + 1] === 0) {
      if (buffer[i + 2] === 1) {
        offsets.push({ offset: i, length: 3 });
        i += 2;
      } else if (buffer[i + 2] === 0 && buffer[i + 3] === 1) {
        offsets.push({ offset: i, length: 4 });
        i += 3;
      }
    }
  }
  return offsets;
}

function summarizeH264(buffer) {
  const startCodes = findStartCodes(buffer);
  const nalTypes = new Map();

  for (const startCode of startCodes) {
    const nalOffset = startCode.offset + startCode.length;
    if (nalOffset >= buffer.length) {
      continue;
    }

    const nalType = buffer[nalOffset] & 0x1f;
    nalTypes.set(nalType, (nalTypes.get(nalType) || 0) + 1);
  }

  return {
    bytes: buffer.length,
    startCodeCount: startCodes.length,
    nalTypes: Object.fromEntries([...nalTypes.entries()].sort(([a], [b]) => a - b)),
    hasSps: nalTypes.has(7),
    hasPps: nalTypes.has(8),
    hasIdr: nalTypes.has(5),
  };
}

async function sleep(ms) {
  await new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function cleanup(deviceId) {
  if (serverProcess && !serverProcess.killed) {
    serverProcess.kill('SIGTERM');
  }

  await Promise.allSettled([
    run(config.adb, ['-s', deviceId, 'forward', '--remove', `tcp:${config.localPort}`]),
    run(config.adb, ['-s', deviceId, 'reverse', '--remove', `localabstract:scrcpy_${config.scid}`]),
    rm(config.outputPath, { force: true }),
  ]);
}

function captureFromForwardTunnel() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    const socket = net.connect(config.localPort, '127.0.0.1');

    socket.on('data', (chunk) => {
      chunks.push(chunk);
    });

    socket.once('error', reject);
    socket.once('connect', () => {
      setTimeout(() => {
        socket.destroy();
        resolve(Buffer.concat(chunks));
      }, config.captureMs);
    });
  });
}

function createReverseCapture() {
  let resolveReady;
  let rejectReady;
  const ready = new Promise((resolve, reject) => {
    resolveReady = resolve;
    rejectReady = reject;
  });

  const captured = new Promise((resolve, reject) => {
    const chunks = [];
    const server = net.createServer((socket) => {
      socket.on('data', (chunk) => {
        chunks.push(chunk);
      });

      setTimeout(() => {
        socket.destroy();
        server.close(() => resolve(Buffer.concat(chunks)));
      }, config.captureMs);
    });

    server.once('error', (error) => {
      rejectReady(error);
      reject(error);
    });
    server.listen(config.localPort, '127.0.0.1', resolveReady);
  });

  return { ready, captured };
}

async function main() {
  const deviceId = await chooseDeviceId();
  const socketName = `scrcpy_${config.scid}`;
  const deviceServerPath = '/data/local/tmp/scrcpy-server.jar';

  await cleanup(deviceId);
  await run(config.adb, ['-s', deviceId, 'push', config.serverPath, deviceServerPath]);

  if (config.tunnelMode === 'reverse') {
    await run(config.adb, [
      '-s',
      deviceId,
      'reverse',
      `localabstract:${socketName}`,
      `tcp:${config.localPort}`,
    ]);
  } else if (config.tunnelMode === 'forward') {
    await run(config.adb, [
      '-s',
      deviceId,
      'forward',
      `tcp:${config.localPort}`,
      `localabstract:${socketName}`,
    ]);
  } else {
    throw new Error(`Unsupported TUNNEL_MODE: ${config.tunnelMode}`);
  }

  const serverArgs = [
    '-s',
    deviceId,
    'shell',
    `CLASSPATH=${deviceServerPath}`,
    'app_process',
    '/',
    'com.genymobile.scrcpy.Server',
    '4.0',
    `scid=${config.scid}`,
    'log_level=debug',
    'audio=false',
    'control=false',
    'raw_stream=true',
    `max_size=${config.maxSize}`,
    `video_bit_rate=${config.videoBitRate}`,
    'cleanup=false',
    'power_on=false',
  ];

  if (config.tunnelMode === 'forward') {
    serverArgs.push('tunnel_forward=true');
  }

  const reverseCapture =
    config.tunnelMode === 'reverse' ? createReverseCapture() : undefined;

  if (reverseCapture) {
    await reverseCapture.ready;
  }

  serverProcess = spawn(config.adb, serverArgs, {
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let serverStdout = '';
  let serverStderr = '';
  serverProcess.stdout.on('data', (chunk) => {
    serverStdout += chunk;
  });
  serverProcess.stderr.on('data', (chunk) => {
    serverStderr += chunk;
  });

  await sleep(500);

  const buffer =
    config.tunnelMode === 'reverse' ? await reverseCapture.captured : await captureFromForwardTunnel();

  if (serverProcess && !serverProcess.killed) {
    serverProcess.kill('SIGTERM');
  }

  await writeFile(config.outputPath, buffer);
  const summary = summarizeH264(buffer);

  console.log(JSON.stringify(
    {
      deviceId,
      socketName,
      localPort: config.localPort,
      tunnelMode: config.tunnelMode,
      outputPath: config.outputPath,
      summary,
      serverLogTail: (serverStderr || serverStdout).split('\n').slice(-20).join('\n'),
    },
    null,
    2,
  ));

  await Promise.allSettled([
    run(config.adb, ['-s', deviceId, 'forward', '--remove', `tcp:${config.localPort}`]),
    run(config.adb, ['-s', deviceId, 'reverse', '--remove', `localabstract:${socketName}`]),
  ]);

  if (!summary.hasSps || !summary.hasPps || !summary.hasIdr) {
    process.exitCode = 2;
  }
}

main().catch(async (error) => {
  console.error(error instanceof Error ? error.stack || error.message : String(error));
  if (config.deviceId) {
    await cleanup(config.deviceId);
  }
  process.exitCode = 1;
});
