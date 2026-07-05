import assert from 'node:assert/strict';
import test from 'node:test';

import {
  calculateDeviceViewFit,
  mapPointToDeviceCoordinates,
} from './deviceViewGeometry.ts';

test('fits metadata screen size inside the available view area', () => {
  assert.deepEqual(
    calculateDeviceViewFit({
      screenWidth: 1080,
      screenHeight: 2400,
      maxWidth: 540,
      maxHeight: 540,
    }),
    {
      width: 243,
      height: 540,
      offsetX: 148.5,
      offsetY: 0,
      scale: 0.225,
    },
  );
});

test('maps view points into metadata coordinates and rejects letterbox hits', () => {
  const fit = calculateDeviceViewFit({
    screenWidth: 1080,
    screenHeight: 2400,
    maxWidth: 540,
    maxHeight: 540,
  });

  assert.equal(mapPointToDeviceCoordinates({ fit, x: 100, y: 20 }), null);
  assert.deepEqual(mapPointToDeviceCoordinates({ fit, x: 148.5, y: 0 }), {
    x: 0,
    y: 0,
  });
  assert.deepEqual(mapPointToDeviceCoordinates({ fit, x: 391.5, y: 540 }), {
    x: 1080,
    y: 2400,
  });
});
