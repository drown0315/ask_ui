import assert from 'node:assert/strict';
import test from 'node:test';

import {
  bindDeviceVideoCanvas,
  createDeviceVideoFrameRenderer,
  drawDeviceVideoFrame,
} from './deviceVideoFrameRenderer.ts';

test('closes a decoded video frame after drawing it', () => {
  let didDraw = false;
  let didClose = false;
  const frame = {
    close() {
      didClose = true;
    },
  };
  const canvas = {
    width: 0,
    height: 0,
    getContext() {
      return {
        drawImage(image: unknown, dx: number, dy: number, dw: number, dh: number) {
          assert.equal(image, frame);
          assert.deepEqual([dx, dy, dw, dh], [0, 0, 1080, 2400]);
          didDraw = true;
        },
      };
    },
  };

  assert.equal(
    drawDeviceVideoFrame({
      canvas,
      screenWidth: 1080,
      screenHeight: 2400,
      videoFrame: frame as CanvasImageSource & { close: () => void },
    }),
    true,
  );

  assert.equal(canvas.width, 1080);
  assert.equal(canvas.height, 2400);
  assert.equal(didDraw, true);
  assert.equal(didClose, true);
});

test('closes a decoded video frame when drawing fails', () => {
  let didClose = false;
  const frame = {
    close() {
      didClose = true;
    },
  };
  const canvas = {
    width: 0,
    height: 0,
    getContext() {
      return {
        drawImage() {
          throw new Error('draw failed');
        },
      };
    },
  };

  assert.throws(() => {
    drawDeviceVideoFrame({
      canvas,
      screenWidth: 1080,
      screenHeight: 2400,
      videoFrame: frame as CanvasImageSource & { close: () => void },
    });
  }, /draw failed/);
  assert.equal(didClose, true);
});

test('closes a pending frame when a newer frame replaces it', () => {
  const closedFrames: string[] = [];
  const drawnFrames: string[] = [];
  let animationFrameCallback: (() => void) | null = null;
  const canvas = buildCanvas(drawnFrames);
  const renderer = createDeviceVideoFrameRenderer({
    canvas,
    requestAnimationFrame(callback) {
      animationFrameCallback = callback;
      return 1;
    },
    cancelAnimationFrame() {},
  });

  renderer.resize({
    screenWidth: 1080,
    screenHeight: 2400,
  });
  renderer.render(buildFrame('old-frame', closedFrames));
  renderer.render(buildFrame('new-frame', closedFrames));
  animationFrameCallback?.();

  assert.deepEqual(drawnFrames, ['new-frame']);
  assert.deepEqual(closedFrames, ['old-frame', 'new-frame']);
});

test('closes the pending frame and cancels animation on renderer close', () => {
  const closedFrames: string[] = [];
  let didCancelAnimationFrame = false;
  const renderer = createDeviceVideoFrameRenderer({
    canvas: buildCanvas([]),
    requestAnimationFrame() {
      return 7;
    },
    cancelAnimationFrame(handle) {
      assert.equal(handle, 7);
      didCancelAnimationFrame = true;
    },
  });

  renderer.render(buildFrame('pending-frame', closedFrames));
  renderer.close();

  assert.equal(didCancelAnimationFrame, true);
  assert.deepEqual(closedFrames, ['pending-frame']);
});

test('closes a pending frame when no canvas context is available', () => {
  const closedFrames: string[] = [];
  let animationFrameCallback: (() => void) | null = null;
  const renderer = createDeviceVideoFrameRenderer({
    canvas: {
      width: 0,
      height: 0,
      getContext() {
        return null;
      },
    },
    requestAnimationFrame(callback) {
      animationFrameCallback = callback;
      return 1;
    },
    cancelAnimationFrame() {},
  });

  renderer.render(buildFrame('frame-without-context', closedFrames));
  animationFrameCallback?.();

  assert.deepEqual(closedFrames, ['frame-without-context']);
});

test('binds a renderer when the canvas appears after the Device shell mounts', () => {
  const rendererChanges: unknown[] = [];
  const binding = bindDeviceVideoCanvas({
    requestAnimationFrame() {
      return 1;
    },
    cancelAnimationFrame() {},
    onRendererChange(renderer) {
      rendererChanges.push(renderer);
    },
  });

  binding.setCanvas(null);
  binding.setCanvas(buildCanvas([]));

  assert.equal(rendererChanges.length, 1);
  assert.notEqual(rendererChanges[0], null);
});

test('closes and unregisters the renderer when the canvas unmounts', () => {
  const rendererChanges: unknown[] = [];
  const binding = bindDeviceVideoCanvas({
    requestAnimationFrame() {
      return 1;
    },
    cancelAnimationFrame() {},
    onRendererChange(renderer) {
      rendererChanges.push(renderer);
    },
  });

  binding.setCanvas(buildCanvas([]));
  const renderer = rendererChanges[0] as {
    render: (frame: CanvasImageSource) => void;
  };
  renderer.render(buildFrame('pending-frame', []));
  binding.setCanvas(null);

  assert.deepEqual(
    rendererChanges.map((renderer) => renderer === null),
    [false, true],
  );
});

function buildCanvas(drawnFrames: string[]) {
  return {
    width: 0,
    height: 0,
    getContext() {
      return {
        drawImage(image: { id: string }) {
          drawnFrames.push(image.id);
        },
      };
    },
  };
}

function buildFrame(id: string, closedFrames: string[]) {
  return {
    id,
    close() {
      closedFrames.push(id);
    },
  } as CanvasImageSource & { id: string; close: () => void };
}
