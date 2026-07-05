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

type DeviceVideoFrameRendererClock = {
  requestAnimationFrame(callback: () => void): number;
  cancelAnimationFrame(handle: number): void;
};

export type DeviceVideoFrameRenderer = {
  close: () => void;
  render: (videoFrame: ClosableVideoFrame) => void;
  resize: (size: { screenWidth: number; screenHeight: number }) => void;
};

export type DeviceVideoCanvasBinding = {
  close: () => void;
  getRenderer: () => DeviceVideoFrameRenderer | null;
  resize: (size: { screenWidth: number; screenHeight: number }) => void;
  setCanvas: (canvas: DeviceVideoCanvas | null) => void;
};

/**
 * Bind a Device video renderer to the current canvas element.
 *
 * React may render the Device shell before the fitted canvas exists. This
 * binding is driven by the canvas ref callback, so the renderer is created
 * exactly when the canvas mounts and closed exactly when it unmounts.
 */
export function bindDeviceVideoCanvas({
  cancelAnimationFrame,
  onRendererChange,
  requestAnimationFrame,
}: {
  cancelAnimationFrame?: DeviceVideoFrameRendererClock['cancelAnimationFrame'];
  onRendererChange: (renderer: DeviceVideoFrameRenderer | null) => void;
  requestAnimationFrame?: DeviceVideoFrameRendererClock['requestAnimationFrame'];
}): DeviceVideoCanvasBinding {
  let currentCanvas: DeviceVideoCanvas | null = null;
  let currentRenderer: DeviceVideoFrameRenderer | null = null;
  let currentSize: { screenWidth: number; screenHeight: number } | null = null;

  const closeCurrentRenderer = () => {
    if (!currentRenderer) {
      return;
    }

    const renderer = currentRenderer;
    currentRenderer = null;
    currentCanvas = null;
    onRendererChange(null);
    renderer.close();
  };

  return {
    close() {
      closeCurrentRenderer();
    },
    getRenderer() {
      return currentRenderer;
    },
    resize(size: { screenWidth: number; screenHeight: number }) {
      currentSize = size;
      currentRenderer?.resize(size);
    },
    setCanvas(canvas: DeviceVideoCanvas | null) {
      if (canvas === currentCanvas) {
        return;
      }

      closeCurrentRenderer();
      currentCanvas = canvas;
      if (!canvas) {
        return;
      }

      currentRenderer = createDeviceVideoFrameRenderer({
        canvas,
        cancelAnimationFrame,
        requestAnimationFrame,
      });
      if (currentSize) {
        currentRenderer.resize(currentSize);
      }
      onRendererChange(currentRenderer);
    },
  };
}

/**
 * Create a renderer that owns decoded Device video frames until they are drawn.
 *
 * The renderer keeps only the newest pending frame. When a newer frame arrives
 * before the next animation frame, the old pending frame is closed immediately
 * so WebCodecs memory cannot leak through React batching or skipped renders.
 */
export function createDeviceVideoFrameRenderer({
  canvas,
  cancelAnimationFrame,
  requestAnimationFrame,
}: {
  canvas: DeviceVideoCanvas;
  cancelAnimationFrame?: DeviceVideoFrameRendererClock['cancelAnimationFrame'];
  requestAnimationFrame?: DeviceVideoFrameRendererClock['requestAnimationFrame'];
}): DeviceVideoFrameRenderer {
  const scheduleFrame =
    requestAnimationFrame ?? globalThis.requestAnimationFrame.bind(globalThis);
  const cancelFrame =
    cancelAnimationFrame ?? globalThis.cancelAnimationFrame.bind(globalThis);
  let screenWidth = canvas.width;
  let screenHeight = canvas.height;
  let pendingFrame: ClosableVideoFrame | null = null;
  let animationFrameHandle: number | null = null;

  const drawPendingFrame = () => {
    animationFrameHandle = null;
    const frame = pendingFrame;
    pendingFrame = null;
    if (!frame) {
      return;
    }

    drawDeviceVideoFrame({
      canvas,
      screenHeight,
      screenWidth,
      videoFrame: frame,
    });
  };

  return {
    close() {
      if (animationFrameHandle !== null) {
        cancelFrame(animationFrameHandle);
        animationFrameHandle = null;
      }

      pendingFrame?.close?.();
      pendingFrame = null;
    },
    render(videoFrame: ClosableVideoFrame) {
      pendingFrame?.close?.();
      pendingFrame = videoFrame;
      if (animationFrameHandle === null) {
        animationFrameHandle = scheduleFrame(drawPendingFrame);
      }
    },
    resize(size: { screenWidth: number; screenHeight: number }) {
      screenWidth = size.screenWidth;
      screenHeight = size.screenHeight;
    },
  };
}

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
