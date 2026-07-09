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

export type DeviceBounds = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type SelectionMarkerPlacementInput = {
  bounds: DeviceBounds;
  fit: DeviceViewFit;
  markerIndexForWidget: number;
  markerSize: number;
  padding: number;
};

export type SelectionMarkerPlacement = {
  left: number;
  top: number;
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

export function getSelectionMarkerPlacement({
  bounds,
  fit,
  markerIndexForWidget,
  markerSize,
  padding,
}: SelectionMarkerPlacementInput): SelectionMarkerPlacement {
  const rect = {
    left: bounds.x * fit.scale,
    top: bounds.y * fit.scale,
    width: bounds.width * fit.scale,
    height: bounds.height * fit.scale,
  };
  const rectRight = rect.left + rect.width;
  const rectBottom = rect.top + rect.height;
  const markerOffset = markerIndexForWidget * (markerSize + padding);

  const preferredLeft = rectRight - markerSize - padding - markerOffset;
  const preferredTop = rect.top + padding;
  const centeredLeft = rect.left + (rect.width - markerSize) / 2;
  const centeredTop = rect.top + (rect.height - markerSize) / 2;

  return {
    left: Math.round(
      clamp(
        rect.width >= markerSize + padding * 2 ? preferredLeft : centeredLeft,
        rect.left,
        rectRight - markerSize,
      ),
    ),
    top: Math.round(
      clamp(
        rect.height >= markerSize + padding * 2 ? preferredTop : centeredTop,
        rect.top,
        rectBottom - markerSize,
      ),
    ),
  };
}

function clamp(value: number, min: number, max: number): number {
  if (min > max) {
    return (min + max) / 2;
  }

  return Math.min(Math.max(value, min), max);
}
