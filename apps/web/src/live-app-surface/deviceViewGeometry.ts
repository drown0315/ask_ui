export type DeviceViewFitInput = {
  screenWidth: number;
  screenHeight: number;
  maxWidth: number;
  maxHeight: number;
};

export type DeviceViewFit = {
  width: number;
  height: number;
  offsetX: number;
  offsetY: number;
  scale: number;
};

export type DeviceViewPointInput = {
  fit: DeviceViewFit;
  x: number;
  y: number;
};

export type DeviceCoordinates = {
  x: number;
  y: number;
};

/**
 * Fit bridge-reported device metadata inside the available UI area.
 *
 * The returned `scale` maps metadata coordinates into rendered Device View
 * pixels. Small devices are allowed to scale up because the shell should use
 * the available center surface instead of pinning the view to native pixels.
 */
export function calculateDeviceViewFit({
  screenWidth,
  screenHeight,
  maxWidth,
  maxHeight,
}: DeviceViewFitInput): DeviceViewFit {
  const scale = Math.min(maxWidth / screenWidth, maxHeight / screenHeight);
  const width = screenWidth * scale;
  const height = screenHeight * scale;

  return {
    width,
    height,
    offsetX: (maxWidth - width) / 2,
    offsetY: (maxHeight - height) / 2,
    scale,
  };
}

/**
 * Map a point in the available view area back into device metadata space.
 *
 * Returns `null` for letterboxed or empty areas outside the rendered Device
 * View. Points on the visible Device View edge are accepted, so the returned
 * coordinates can include `screenWidth` or `screenHeight`.
 */
export function mapPointToDeviceCoordinates({
  fit,
  x,
  y,
}: DeviceViewPointInput): DeviceCoordinates | null {
  const localX = x - fit.offsetX;
  const localY = y - fit.offsetY;

  if (localX < 0 || localY < 0 || localX > fit.width || localY > fit.height) {
    return null;
  }

  return {
    x: localX / fit.scale,
    y: localY / fit.scale,
  };
}
