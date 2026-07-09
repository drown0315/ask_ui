import assert from 'node:assert/strict';
import test from 'node:test';

import {
  calculateDeviceViewFit,
  getSelectionMarkerPlacement,
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

test('places selection markers inside widget bounds in the rendered Device View frame', () => {
  const fit = calculateDeviceViewFit({
    screenWidth: 1080,
    screenHeight: 2400,
    maxWidth: 540,
    maxHeight: 540,
  });

  assert.deepEqual(
    getSelectionMarkerPlacement({
      bounds: {
        x: 100,
        y: 400,
        width: 600,
        height: 120,
      },
      fit,
      markerIndexForWidget: 0,
      markerSize: 26,
      padding: 4,
    }),
    {
      left: 128,
      top: 91,
    },
  );
});

test('clamps selection markers inside small widget bounds', () => {
  const fit = calculateDeviceViewFit({
    screenWidth: 100,
    screenHeight: 100,
    maxWidth: 100,
    maxHeight: 100,
  });

  assert.deepEqual(
    getSelectionMarkerPlacement({
      bounds: {
        x: 8,
        y: 12,
        width: 12,
        height: 10,
      },
      fit,
      markerIndexForWidget: 0,
      markerSize: 26,
      padding: 4,
    }),
    {
      left: 1,
      top: 4,
    },
  );
});
