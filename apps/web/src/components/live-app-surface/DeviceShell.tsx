import { useEffect, useMemo, useRef, useState } from 'react';
import type { PointerEvent } from 'react';
import type { LiveAppSurfaceState } from '../../live-app-surface/liveAppSurfaceState';
import {
  buildSystemKeyMessage,
  buildTouchMessage,
  type DeviceControlMessage,
  type DeviceSystemKey,
} from '../../live-app-surface/deviceControlProtocol';
import {
  calculateDeviceViewFit,
  mapPointToDeviceCoordinates,
  type DeviceViewFit,
} from '../../live-app-surface/deviceViewGeometry';

type DeviceShellProps = {
  onDeviceControlMessage: (message: DeviceControlMessage) => void;
  surfaceState: Extract<
    LiveAppSurfaceState,
    { status: 'waitingForVideo' | 'renderingVideo' }
  >;
};

/**
 * Renders the interactive Device View shell before real video frames arrive.
 *
 * Pointer events are mapped from the visible view back into bridge metadata
 * coordinates, and Back/Home/Recents are sent over the same Device WebSocket.
 */
export function DeviceShell({
  onDeviceControlMessage,
  surfaceState,
}: DeviceShellProps) {
  const areaRef = useRef<HTMLDivElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const activePointerRef = useRef<{
    pointerId: number;
    screenWidth: number;
    screenHeight: number;
    x: number;
    y: number;
  } | null>(null);
  const lastMoveSentAtRef = useRef(0);
  const [areaSize, setAreaSize] = useState({ width: 0, height: 0 });
  const metadata = surfaceState.metadata;
  const metadataKey = `${metadata.deviceId}:${metadata.screenWidth}:${metadata.screenHeight}`;

  useEffect(() => {
    const area = areaRef.current;
    if (!area) {
      return;
    }

    const updateAreaSize = () => {
      const rect = area.getBoundingClientRect();
      setAreaSize({
        width: rect.width,
        height: rect.height,
      });
    };

    updateAreaSize();
    const observer = new ResizeObserver(updateAreaSize);
    observer.observe(area);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const activePointer = activePointerRef.current;
    if (!activePointer) {
      return;
    }

    onDeviceControlMessage(
      buildTouchMessage({
        action: 'cancel',
        pointerId: activePointer.pointerId,
        x: activePointer.x,
        y: activePointer.y,
        screenWidth: activePointer.screenWidth,
        screenHeight: activePointer.screenHeight,
      }),
    );
    activePointerRef.current = null;
  }, [metadataKey, onDeviceControlMessage]);

  const fit = useMemo<DeviceViewFit | null>(() => {
    if (areaSize.width <= 0 || areaSize.height <= 0) {
      return null;
    }

    return calculateDeviceViewFit({
      screenWidth: metadata.screenWidth,
      screenHeight: metadata.screenHeight,
      maxWidth: areaSize.width,
      maxHeight: areaSize.height,
    });
  }, [
    areaSize.height,
    areaSize.width,
    metadata.screenHeight,
    metadata.screenWidth,
  ]);

  useEffect(() => {
    if (surfaceState.status !== 'renderingVideo') {
      return;
    }

    const canvas = canvasRef.current;
    const context = canvas?.getContext('2d');
    if (!canvas || !context) {
      return;
    }

    canvas.width = metadata.screenWidth;
    canvas.height = metadata.screenHeight;
    context.drawImage(surfaceState.videoFrame as CanvasImageSource, 0, 0);

    return () => {
      const maybeClosableFrame = surfaceState.videoFrame as {
        close?: () => void;
      };
      maybeClosableFrame.close?.();
    };
  }, [metadata.screenHeight, metadata.screenWidth, surfaceState]);

  const sendPointerMessage = (
    action: 'down' | 'move' | 'up' | 'cancel',
    event: PointerEvent<HTMLDivElement>,
  ) => {
    if (!fit || !metadata.controlReady) {
      return;
    }

    if (action === 'move') {
      const now = performance.now();
      if (now - lastMoveSentAtRef.current < 16) {
        return;
      }
      lastMoveSentAtRef.current = now;
    }

    const rect = event.currentTarget.getBoundingClientRect();
    const point = mapPointToDeviceCoordinates({
      fit,
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    });
    if (!point) {
      return;
    }

    const pointerId = event.pointerId;
    const message = buildTouchMessage({
      action,
      pointerId,
      x: point.x,
      y: point.y,
      screenWidth: metadata.screenWidth,
      screenHeight: metadata.screenHeight,
    });

    onDeviceControlMessage(message);

    if (action === 'down') {
      activePointerRef.current = {
        pointerId,
        x: point.x,
        y: point.y,
        screenWidth: metadata.screenWidth,
        screenHeight: metadata.screenHeight,
      };
      event.currentTarget.setPointerCapture(pointerId);
    } else if (action === 'up' || action === 'cancel') {
      activePointerRef.current = null;
      if (event.currentTarget.hasPointerCapture(pointerId)) {
        event.currentTarget.releasePointerCapture(pointerId);
      }
    } else if (activePointerRef.current?.pointerId === pointerId) {
      activePointerRef.current = {
        pointerId,
        x: point.x,
        y: point.y,
        screenWidth: metadata.screenWidth,
        screenHeight: metadata.screenHeight,
      };
    }
  };

  const sendSystemKey = (key: DeviceSystemKey) => {
    onDeviceControlMessage(buildSystemKeyMessage(key));
  };

  return (
    <div className="device-shell">
      <div
        className="device-view-area"
        onPointerCancel={(event) => sendPointerMessage('cancel', event)}
        onPointerDown={(event) => sendPointerMessage('down', event)}
        onPointerMove={(event) => sendPointerMessage('move', event)}
        onPointerUp={(event) => sendPointerMessage('up', event)}
        ref={areaRef}
      >
        {fit ? (
          <div
            className="device-view-frame"
            style={{
              height: `${fit.height}px`,
              transform: `translate(${fit.offsetX}px, ${fit.offsetY}px)`,
              width: `${fit.width}px`,
            }}
            title={metadata.deviceId}
          >
            {surfaceState.status === 'renderingVideo' ? (
              <canvas
                aria-label="Device video"
                className="device-view-canvas"
                ref={canvasRef}
              />
            ) : (
              <>
                <div className="device-view-status">Waiting for video</div>
                <div className="device-view-device-id">{metadata.deviceId}</div>
              </>
            )}
          </div>
        ) : null}
      </div>
      <div className="surface-controls">
        <button
          disabled={!metadata.controlReady}
          onClick={() => sendSystemKey('back')}
          type="button"
        >
          Back
        </button>
        <button
          disabled={!metadata.controlReady}
          onClick={() => sendSystemKey('home')}
          type="button"
        >
          Home
        </button>
        <button
          disabled={!metadata.controlReady}
          onClick={() => sendSystemKey('recents')}
          type="button"
        >
          Recents
        </button>
      </div>
    </div>
  );
}
