import assert from 'node:assert/strict';
import test from 'node:test';

import { createDeviceVideoFrameHandoff } from './useLiveAppSurface.ts';

test('renders a decoded frame that arrives before the renderer is registered', () => {
  let closedFrameCount = 0;
  let renderedFrame: unknown = null;
  let renderedFrameCount = 0;
  const frame = {
    close() {
      closedFrameCount += 1;
    },
  };
  const handoff = createDeviceVideoFrameHandoff({
    onFrameRendered() {
      renderedFrameCount += 1;
    },
  });

  handoff.render(frame);
  handoff.setRenderer({
    render(nextFrame) {
      renderedFrame = nextFrame;
    },
  });

  assert.equal(renderedFrame, frame);
  assert.equal(renderedFrameCount, 1);
  assert.equal(closedFrameCount, 0);
});
