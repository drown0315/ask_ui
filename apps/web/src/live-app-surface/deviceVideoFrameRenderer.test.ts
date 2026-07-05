import assert from 'node:assert/strict';
import test from 'node:test';

import { drawDeviceVideoFrame } from './deviceVideoFrameRenderer.ts';

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
