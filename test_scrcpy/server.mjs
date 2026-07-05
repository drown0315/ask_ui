import { createServer } from 'node:http';
import crypto from 'node:crypto';
import net from 'node:net';
import { readFile, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));

const config = {
  adb: process.env.ADB || 'adb',
  scrcpy: process.env.SCRCPY || 'scrcpy',
  deviceId: process.env.DEVICE_ID || '',
  httpPort: Number(process.env.PORT || 3010),
  maxSize: Number(process.env.MAX_SIZE || 1080),
  maxFps: Number(process.env.MAX_FPS || 60),
  videoBitRate: Number(process.env.VIDEO_BIT_RATE || 8_000_000),
  segmentSeconds: Number(process.env.SEGMENT_SECONDS || 3),
  scrcpyServer:
    process.env.SCRCPY_SERVER ||
    '/opt/homebrew/Cellar/scrcpy/4.0/share/scrcpy/scrcpy-server',
  rawPort: Number(process.env.RAW_PORT || 27184),
  scid: process.env.SCID || '2b3c4d5e',
};

let state = {
  deviceId: '',
  displaySize: null,
  started: false,
};
let rawSession = null;

const SCRCPY_CONTROL_TYPE_TOUCH = 2;
const SCRCPY_TOUCH_ACTION_DOWN = 0;
const SCRCPY_TOUCH_ACTION_UP = 1;
const SCRCPY_TOUCH_ACTION_MOVE = 2;
const SCRCPY_MAX_PRESSURE = 0xffff;

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
  return state.deviceId ? ['-s', state.deviceId, ...args] : args;
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

async function readDisplaySize() {
  const { stdout } = await run(config.adb, adbArgs('shell', 'wm', 'size'));
  const match = stdout.match(/Physical size:\s*(\d+)x(\d+)/);

  if (!match) {
    throw new Error(`Could not parse display size from: ${stdout}`);
  }

  return {
    width: Number(match[1]),
    height: Number(match[2]),
  };
}

async function startScrcpyServer() {
  if (state.started) {
    return state;
  }

  state.deviceId = await chooseDeviceId();
  state.displaySize = await readDisplaySize();
  state.started = true;
  return state;
}

function writeJson(response, statusCode, body) {
  response.writeHead(statusCode, {
    'content-type': 'application/json',
    'cache-control': 'no-store',
  });
  response.end(JSON.stringify(body));
}

async function readJson(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }

  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}

async function handleStream(request, response) {
  await startScrcpyServer();

  const stamp = `${process.pid}-${Date.now()}`;
  const videoPath = `/private/tmp/ask-ui-scrcpy-${stamp}.mkv`;
  const framePath = `/private/tmp/ask-ui-scrcpy-${stamp}.jpg`;

  try {
    await run(config.scrcpy, [
      '-s',
      state.deviceId,
      '--no-video-playback',
      '--no-audio',
      `--record=${videoPath}`,
      '--record-format=mkv',
      `--max-size=${config.maxSize}`,
      `--max-fps=${config.maxFps}`,
      `--video-bit-rate=${config.videoBitRate}`,
      `--time-limit=${config.segmentSeconds}`,
      '--verbosity=error',
    ]);

    await run('ffmpeg', [
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-i',
      videoPath,
      '-frames:v',
      '1',
      '-q:v',
      '3',
      framePath,
    ]);

    const frame = await readFile(framePath);
    response.writeHead(200, {
      'content-type': 'image/jpeg',
      'content-length': frame.length,
      'cache-control': 'no-store',
    });
    response.end(frame);
  } finally {
    await Promise.allSettled([rm(videoPath, { force: true }), rm(framePath, { force: true })]);
  }
}

function createWebSocketAccept(key) {
  return crypto
    .createHash('sha1')
    .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
    .digest('base64');
}

function sendWebSocketFrame(socket, data, opcode = 0x2) {
  const payload = Buffer.isBuffer(data) ? data : Buffer.from(data);
  const length = payload.length;
  let header;

  if (length < 126) {
    header = Buffer.from([0x80 | opcode, length]);
  } else if (length <= 0xffff) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(length), 2);
  }

  socket.write(Buffer.concat([header, payload]));
}

function sendWebSocketText(socket, body) {
  sendWebSocketFrame(socket, Buffer.from(body), 0x1);
}

function parseClientWebSocketFrames(session, chunk) {
  session.clientFrameBuffer = Buffer.concat([session.clientFrameBuffer || Buffer.alloc(0), chunk]);

  while (session.clientFrameBuffer.length >= 2) {
    const first = session.clientFrameBuffer[0];
    const second = session.clientFrameBuffer[1];
    const opcode = first & 0x0f;
    const masked = (second & 0x80) !== 0;
    let length = second & 0x7f;
    let offset = 2;

    if (length === 126) {
      if (session.clientFrameBuffer.length < offset + 2) {
        return;
      }
      length = session.clientFrameBuffer.readUInt16BE(offset);
      offset += 2;
    } else if (length === 127) {
      if (session.clientFrameBuffer.length < offset + 8) {
        return;
      }
      length = Number(session.clientFrameBuffer.readBigUInt64BE(offset));
      offset += 8;
    }

    const maskLength = masked ? 4 : 0;
    if (session.clientFrameBuffer.length < offset + maskLength + length) {
      return;
    }

    let payload = session.clientFrameBuffer.slice(offset + maskLength, offset + maskLength + length);
    if (masked) {
      const mask = session.clientFrameBuffer.slice(offset, offset + 4);
      payload = Buffer.from(payload.map((byte, index) => byte ^ mask[index % 4]));
    }
    session.clientFrameBuffer = session.clientFrameBuffer.slice(offset + maskLength + length);

    if (opcode === 0x8) {
      session.webSocket.end();
      return;
    }
    if (opcode === 0x1) {
      handleClientControlMessage(session, payload.toString('utf8'));
    }
  }
}

function numberInRange(value, min, max, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return fallback;
  }
  return Math.max(min, Math.min(max, number));
}

function buildScrcpyTouchMessage({ action, pointerId, x, y, screenWidth, screenHeight, pressure }) {
  const buffer = Buffer.alloc(32);
  let offset = 0;
  offset = buffer.writeUInt8(SCRCPY_CONTROL_TYPE_TOUCH, offset);
  offset = buffer.writeUInt8(action, offset);
  offset = buffer.writeBigUInt64BE(BigInt(pointerId), offset);
  offset = buffer.writeInt32BE(Math.round(x), offset);
  offset = buffer.writeInt32BE(Math.round(y), offset);
  offset = buffer.writeUInt16BE(Math.round(screenWidth), offset);
  offset = buffer.writeUInt16BE(Math.round(screenHeight), offset);
  offset = buffer.writeUInt16BE(Math.round(pressure * SCRCPY_MAX_PRESSURE), offset);
  offset = buffer.writeUInt32BE(0, offset); // action_button, unused for touch input
  buffer.writeUInt32BE(0, offset); // buttons, unused for touch input
  return buffer;
}

function writeScrcpyTouch(session, body) {
  if (!session?.controlSocket || session.controlSocket.destroyed) {
    return { ok: false, error: 'scrcpy control socket is not connected yet' };
  }

  const action = numberInRange(body.action, SCRCPY_TOUCH_ACTION_DOWN, SCRCPY_TOUCH_ACTION_MOVE, NaN);
  const screenWidth = numberInRange(body.screenWidth, 1, 0xffff, NaN);
  const screenHeight = numberInRange(body.screenHeight, 1, 0xffff, NaN);
  const x = numberInRange(body.x, 0, screenWidth, NaN);
  const y = numberInRange(body.y, 0, screenHeight, NaN);
  const pointerId = numberInRange(body.pointerId, 0, 0xffffffff, 0);

  if (![action, screenWidth, screenHeight, x, y, pointerId].every(Number.isFinite)) {
    return { ok: false, error: 'invalid scrcpy touch payload' };
  }

  const pressure = action === SCRCPY_TOUCH_ACTION_UP ? 0 : 1;
  const message = buildScrcpyTouchMessage({
    action,
    pointerId,
    x,
    y,
    screenWidth,
    screenHeight,
    pressure,
  });

  session.controlSocket.write(message);
  session.controlEvents += 1;
  return { ok: true };
}

function handleClientControlMessage(session, text) {
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    sendWebSocketText(session.webSocket, JSON.stringify({ type: 'control-error', message: 'invalid JSON' }));
    return;
  }

  if (body.type !== 'touch') {
    sendWebSocketText(session.webSocket, JSON.stringify({ type: 'control-error', message: 'unsupported control type' }));
    return;
  }

  const result = writeScrcpyTouch(session, body);
  if (!result.ok) {
    sendWebSocketText(session.webSocket, JSON.stringify({ type: 'control-error', message: result.error }));
  }
}

async function cleanupRawSession(session) {
  if (!session || session.closed) {
    return;
  }

  session.closed = true;
  session.videoSocket?.destroy();
  session.controlSocket?.destroy();
  session.captureServer?.close();
  if (session.serverProcess && !session.serverProcess.killed) {
    session.serverProcess.kill('SIGTERM');
  }

  await Promise.allSettled([
    run(config.adb, ['-s', state.deviceId, 'reverse', '--remove', `localabstract:scrcpy_${config.scid}`]),
    run(config.adb, ['-s', state.deviceId, 'forward', '--remove', `tcp:${config.rawPort}`]),
  ]);

  if (rawSession === session) {
    rawSession = null;
  }
}

function createReverseRawCapture(webSocket) {
  let resolveReady;
  let rejectReady;
  const ready = new Promise((resolve, reject) => {
    resolveReady = resolve;
    rejectReady = reject;
  });

  const captureServer = net.createServer((videoSocket) => {
    if (!rawSession) {
      videoSocket.destroy();
      return;
    }

    if (rawSession.videoSocket && rawSession.controlSocket) {
      videoSocket.destroy();
      return;
    }

    if (!rawSession.videoSocket) {
      rawSession.videoSocket = videoSocket;
      rawSession.videoBytes = 0;
      sendWebSocketText(webSocket, JSON.stringify({ type: 'video-connected' }));
      console.log('raw h264 video socket connected');

      videoSocket.on('data', (chunk) => {
        rawSession.videoBytes += chunk.length;
        if (rawSession.videoBytes === chunk.length) {
          console.log(`raw h264 first chunk: ${chunk.length} bytes`);
        }
        if (webSocket.destroyed) {
          void cleanupRawSession(rawSession);
          return;
        }
        if (!webSocket.destroyed) {
          sendWebSocketFrame(webSocket, chunk);
        }
      });
      videoSocket.once('close', () => {
        if (!webSocket.destroyed) {
          webSocket.end();
        }
      });
      videoSocket.once('error', () => {
        if (!webSocket.destroyed) {
          webSocket.end();
        }
      });
      return;
    }

    rawSession.controlSocket = videoSocket;
    rawSession.controlEvents = 0;
    sendWebSocketText(webSocket, JSON.stringify({ type: 'control-connected' }));
    console.log('scrcpy control socket connected');
    videoSocket.once('close', () => {
      if (rawSession) {
        rawSession.controlSocket = null;
      }
    });
    videoSocket.once('error', () => {
      if (rawSession) {
        rawSession.controlSocket = null;
      }
    });
  });

  captureServer.once('error', (error) => {
    rejectReady(error);
  });
  captureServer.listen(config.rawPort, '127.0.0.1', resolveReady);

  return { captureServer, ready };
}

async function startRawH264WebSocket(webSocket) {
  await startScrcpyServer();

  if (rawSession?.webSocket?.destroyed) {
    await cleanupRawSession(rawSession);
  }

  if (rawSession) {
    sendWebSocketText(webSocket, JSON.stringify({ type: 'error', message: 'raw stream already active' }));
    webSocket.end();
    return;
  }

  const session = {
    closed: false,
    webSocket,
    serverProcess: null,
    captureServer: null,
    videoSocket: null,
    controlSocket: null,
    videoBytes: 0,
    controlEvents: 0,
    clientFrameBuffer: Buffer.alloc(0),
  };
  rawSession = session;

  try {
    const socketName = `scrcpy_${config.scid}`;
    const deviceServerPath = '/data/local/tmp/scrcpy-server.jar';

    await Promise.allSettled([
      run(config.adb, ['-s', state.deviceId, 'reverse', '--remove', `localabstract:${socketName}`]),
      run(config.adb, ['-s', state.deviceId, 'forward', '--remove', `tcp:${config.rawPort}`]),
    ]);
    if (webSocket.destroyed || session.closed) {
      throw new Error('websocket closed');
    }

    await run(config.adb, ['-s', state.deviceId, 'push', config.scrcpyServer, deviceServerPath]);
    if (webSocket.destroyed || session.closed) {
      throw new Error('websocket closed');
    }

    const reverseCapture = createReverseRawCapture(webSocket);
    session.captureServer = reverseCapture.captureServer;
    await reverseCapture.ready;
    if (webSocket.destroyed || session.closed) {
      throw new Error('websocket closed');
    }

    await run(config.adb, [
      '-s',
      state.deviceId,
      'reverse',
      `localabstract:${socketName}`,
      `tcp:${config.rawPort}`,
    ]);
    if (webSocket.destroyed || session.closed) {
      throw new Error('websocket closed');
    }

    const serverArgs = [
      '-s',
      state.deviceId,
      'shell',
      `CLASSPATH=${deviceServerPath}`,
      'app_process',
      '/',
      'com.genymobile.scrcpy.Server',
      '4.0',
      `scid=${config.scid}`,
      'log_level=debug',
      'audio=false',
      'control=true',
      'raw_stream=true',
      `max_size=${config.maxSize}`,
      `max_fps=${config.maxFps}`,
      `video_bit_rate=${config.videoBitRate}`,
      'cleanup=false',
      'power_on=false',
    ];

    session.serverProcess = spawn(config.adb, serverArgs, {
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    session.serverProcess.stderr.on('data', (chunk) => {
      const message = chunk.toString('utf8').trim();
      if (message && !webSocket.destroyed) {
        sendWebSocketText(webSocket, JSON.stringify({ type: 'server-log', message }));
      }
      if (message) {
        console.error(message);
      }
    });
    session.serverProcess.once('close', (code) => {
      if (!session.closed && !webSocket.destroyed) {
        sendWebSocketText(webSocket, JSON.stringify({ type: 'server-exit', code }));
        webSocket.end();
      }
    });

    sendWebSocketText(
      webSocket,
      JSON.stringify({
        type: 'ready',
        deviceId: state.deviceId,
        displaySize: state.displaySize,
        maxSize: config.maxSize,
        maxFps: config.maxFps,
        videoBitRate: config.videoBitRate,
        lowLatency: true,
        control: true,
      }),
    );
  } catch (error) {
    if (!webSocket.destroyed) {
      sendWebSocketText(
        webSocket,
        JSON.stringify({ type: 'error', message: error instanceof Error ? error.message : String(error) }),
      );
      webSocket.end();
    }
    await cleanupRawSession(session);
  }
}

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url || '/', `http://${request.headers.host}`);

    if (request.method === 'GET' && url.pathname === '/') {
      const html = await readFile(join(here, 'index.html'), 'utf8');
      response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      response.end(html);
      return;
    }

    if (request.method === 'GET' && url.pathname === '/webcodecs.html') {
      const html = await readFile(join(here, 'webcodecs.html'), 'utf8');
      response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      response.end(html);
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/start') {
      const nextState = await startScrcpyServer();
      writeJson(response, 200, {
        deviceId: nextState.deviceId,
        displaySize: nextState.displaySize,
      });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/tap') {
      const body = await readJson(request);
      const x = Number(body.x);
      const y = Number(body.y);

      if (!Number.isFinite(x) || !Number.isFinite(y)) {
        writeJson(response, 400, { error: 'x and y are required numbers' });
        return;
      }

      await startScrcpyServer();
      await run(config.adb, adbArgs('shell', 'input', 'tap', String(Math.round(x)), String(Math.round(y))));
      writeJson(response, 200, { status: 'ok', x: Math.round(x), y: Math.round(y) });
      return;
    }

    if (request.method === 'POST' && url.pathname === '/api/swipe') {
      const body = await readJson(request);
      const x1 = Number(body.x1);
      const y1 = Number(body.y1);
      const x2 = Number(body.x2);
      const y2 = Number(body.y2);
      const durationMs = Math.max(50, Math.min(1500, Number(body.durationMs) || 250));

      if (![x1, y1, x2, y2].every(Number.isFinite)) {
        writeJson(response, 400, { error: 'x1, y1, x2, and y2 are required numbers' });
        return;
      }

      await startScrcpyServer();
      await run(
        config.adb,
        adbArgs(
          'shell',
          'input',
          'swipe',
          String(Math.round(x1)),
          String(Math.round(y1)),
          String(Math.round(x2)),
          String(Math.round(y2)),
          String(Math.round(durationMs)),
        ),
      );
      writeJson(response, 200, {
        status: 'ok',
        x1: Math.round(x1),
        y1: Math.round(y1),
        x2: Math.round(x2),
        y2: Math.round(y2),
        durationMs: Math.round(durationMs),
      });
      return;
    }

    if (request.method === 'GET' && url.pathname === '/stream.mjpg') {
      await handleStream(request, response);
      return;
    }

    writeJson(response, 404, { error: 'not found' });
  } catch (error) {
    writeJson(response, 500, { error: error instanceof Error ? error.message : String(error) });
  }
});

server.on('upgrade', (request, socket) => {
  const url = new URL(request.url || '/', `http://${request.headers.host}`);
  if (url.pathname !== '/raw-h264') {
    socket.destroy();
    return;
  }

  const key = request.headers['sec-websocket-key'];
  if (!key) {
    socket.destroy();
    return;
  }

  socket.write(
    [
      'HTTP/1.1 101 Switching Protocols',
      'Upgrade: websocket',
      'Connection: Upgrade',
      `Sec-WebSocket-Accept: ${createWebSocketAccept(key)}`,
      '',
      '',
    ].join('\r\n'),
  );

  socket.on('data', (chunk) => {
    if (rawSession?.webSocket === socket) {
      parseClientWebSocketFrames(rawSession, chunk);
    }
  });
  const cleanupSocketSession = () => {
    if (rawSession?.webSocket === socket) {
      void cleanupRawSession(rawSession);
    }
  };
  socket.once('end', cleanupSocketSession);
  socket.once('close', cleanupSocketSession);
  socket.once('error', cleanupSocketSession);

  void startRawH264WebSocket(socket);
});

server.listen(config.httpPort, '127.0.0.1', () => {
  console.log(`test_scrcpy demo: http://127.0.0.1:${config.httpPort}`);
  console.log(`webcodecs demo: http://127.0.0.1:${config.httpPort}/webcodecs.html`);
  console.log(`DEVICE_ID=${config.deviceId || '(auto if exactly one device)'}`);
  console.log(`SCRCPY=${config.scrcpy}`);
  console.log(`SCRCPY_SERVER=${config.scrcpyServer}`);
  console.log(`MAX_SIZE=${config.maxSize}`);
  console.log(`MAX_FPS=${config.maxFps}`);
  console.log(`VIDEO_BIT_RATE=${config.videoBitRate}`);
});

function shutdown() {
  void cleanupRawSession(rawSession).finally(() => {
    server.close(() => process.exit(0));
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
