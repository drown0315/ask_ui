export interface VideoRect {
  x: number
  y: number
  width: number
  height: number
}

export interface NormalizedPoint {
  x: number
  y: number
}

export function fitVideoRect(
  containerWidth: number,
  containerHeight: number,
  videoWidth: number,
  videoHeight: number,
): VideoRect {
  if (containerWidth <= 0 || containerHeight <= 0 || videoWidth <= 0 || videoHeight <= 0) {
    return { x: 0, y: 0, width: 0, height: 0 }
  }
  const scale = Math.min(containerWidth / videoWidth, containerHeight / videoHeight)
  const width = videoWidth * scale
  const height = videoHeight * scale
  return {
    x: (containerWidth - width) / 2,
    y: (containerHeight - height) / 2,
    width,
    height,
  }
}

export function normalizePoint(
  clientX: number,
  clientY: number,
  rect: VideoRect,
): NormalizedPoint | null {
  if (
    rect.width <= 0 || rect.height <= 0 ||
    clientX < rect.x || clientX > rect.x + rect.width ||
    clientY < rect.y || clientY > rect.y + rect.height
  ) return null
  return {
    x: (clientX - rect.x) / rect.width,
    y: (clientY - rect.y) / rect.height,
  }
}
