type DeviceVideoCanvas = {
  height: number;
  width: number;
  getContext(contextId: '2d'): DeviceVideoCanvasContext | null;
};

type DeviceVideoCanvasContext = {
  drawImage(
    image: CanvasImageSource,
    dx: number,
    dy: number,
    dw: number,
    dh: number,
  ): void;
};

type ClosableVideoFrame = CanvasImageSource & {
  close?: () => void;
};

/**
 * Draw one decoded Device video frame and release its WebCodecs resource.
 *
 * Args:
 * - `canvas`: Target canvas sized in bridge screen coordinates.
 * - `videoFrame`: Decoded WebCodecs frame. It is closed after the draw attempt,
 *   including failed draws, because `VideoFrame` owns browser decoder memory.
 * - `screenWidth`: Device screen width from bridge metadata.
 * - `screenHeight`: Device screen height from bridge metadata.
 *
 * Returns:
 * `true` when the frame was drawn, otherwise `false` when no 2D canvas context
 * was available.
 */
export function drawDeviceVideoFrame({
  canvas,
  screenHeight,
  screenWidth,
  videoFrame,
}: {
  canvas: DeviceVideoCanvas;
  screenHeight: number;
  screenWidth: number;
  videoFrame: ClosableVideoFrame;
}): boolean {
  const context = canvas.getContext('2d');
  if (!context) {
    videoFrame.close?.();
    return false;
  }

  canvas.width = screenWidth;
  canvas.height = screenHeight;
  try {
    context.drawImage(videoFrame, 0, 0, screenWidth, screenHeight);
    return true;
  } finally {
    videoFrame.close?.();
  }
}
