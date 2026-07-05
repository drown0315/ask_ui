import { useCallback, useEffect, useRef, useState } from 'react';
import type { DeviceControlMessage } from './deviceControlProtocol';
import { getDeviceWebSocketUrl } from '../services/askUiBridgeClient';
import {
  getInitialLiveAppSurfaceState,
  reduceLiveAppSurfaceFirstFrameRendered,
  reduceLiveAppSurfaceMessage,
  type LiveAppSurfaceState,
} from './liveAppSurfaceState';
import {
  createDeviceVideoPipeline,
  type DeviceVideoPipeline,
  type WebCodecsLike,
} from './deviceVideoPipeline';

/**
 * Open and manage the Live App Surface Device WebSocket for a bridge session.
 *
 * Args:
 * - `sessionId`: Ready bridge session id. `null` means the Surface should stay
 *   idle and must not open a WebSocket.
 *
 * Returns:
 * The visible Surface state and a retry function that reopens the WebSocket for
 * the same bridge session.
 *
 * Example:
 * When `sessionId` becomes `session-1`, this hook opens
 * `/api/sessions/session-1/device`, waits for bridge metadata, and
 * shows `Waiting for video` until a later video frame path is implemented.
 */
export function useLiveAppSurface(sessionId: string | null): {
  surfaceState: LiveAppSurfaceState;
  retryLiveAppSurface: () => void;
  sendDeviceControlMessage: (message: DeviceControlMessage) => void;
} {
  const [retryToken, setRetryToken] = useState(0);
  const socketRef = useRef<WebSocket | null>(null);
  const [surfaceState, setSurfaceState] = useState<LiveAppSurfaceState>(() =>
    getInitialLiveAppSurfaceState(sessionId),
  );
  const sendDeviceControlMessage = useCallback(
    (message: DeviceControlMessage) => {
      const socket = socketRef.current;
      if (socket?.readyState !== WebSocket.OPEN) {
        return;
      }
      socket.send(JSON.stringify(message));
    },
    [],
  );

  useEffect(() => {
    if (sessionId === null) {
      setSurfaceState({
        status: 'idle',
      });
      return;
    }

    let intentionalClose = false;
    let didReceiveFailure = false;
    let disposed = false;
    const videoPipeline = createDeviceVideoPipeline({
      webCodecs: getBrowserWebCodecs(),
      onError: (error) => {
        didReceiveFailure = true;
        console.error('Device video decode failed', error);
        setSurfaceState({
          status: 'failed',
          error: 'video_decode_failed',
          message: 'Device video failed to decode.',
        });
      },
      onFrame: (videoFrame) => {
        setSurfaceState((state) =>
          reduceLiveAppSurfaceFirstFrameRendered(state, videoFrame),
        );
      },
      onFirstFrameRendered: () => {},
    });
    if (videoPipeline.status.type === 'unsupported') {
      setSurfaceState({
        status: 'failed',
        error: 'webcodecs_unavailable',
        message: videoPipeline.status.message,
      });
      return () => videoPipeline.close();
    }
    const readyVideoPipeline = requireReadyDeviceVideoPipeline(videoPipeline);

    const socket = new WebSocket(
      getDeviceWebSocketUrl(sessionId, undefined, getDeviceDebugOptions()),
    );
    socket.binaryType = 'arraybuffer';
    socketRef.current = socket;

    setSurfaceState({
      status: 'connecting',
    });

    socket.addEventListener('message', (event) => {
      if (disposed) {
        return;
      }

      if (event.data instanceof ArrayBuffer) {
        readyVideoPipeline.push(new Uint8Array(event.data));
        return;
      }

      if (event.data instanceof Blob) {
        void event.data.arrayBuffer().then((buffer) => {
          if (disposed) {
            return;
          }

          readyVideoPipeline.push(new Uint8Array(buffer));
        });
        return;
      }

      const rawMessage =
        typeof event.data === 'string' ? event.data : String(event.data);
      didReceiveFailure = rawMessage.includes('"type":"error"');
      setSurfaceState((state) =>
        reduceLiveAppSurfaceMessage(state, rawMessage),
      );
    });

    socket.addEventListener('error', () => {
      didReceiveFailure = true;
      setSurfaceState({
        status: 'failed',
        error: 'device_start_failed',
        message: 'Device failed to start.',
      });
    });

    socket.addEventListener('close', () => {
      if (intentionalClose || didReceiveFailure) {
        return;
      }

      setSurfaceState({
        status: 'failed',
        error: 'device_failed',
        message: 'Device disconnected.',
      });
    });

    return () => {
      intentionalClose = true;
      disposed = true;
      if (socketRef.current === socket) {
        socketRef.current = null;
      }
      readyVideoPipeline.close();
      socket.close();
    };
  }, [retryToken, sessionId]);

  return {
    surfaceState,
    retryLiveAppSurface() {
      setRetryToken((current) => current + 1);
    },
    sendDeviceControlMessage,
  };
}

function getBrowserWebCodecs(): WebCodecsLike {
  if (typeof window === 'undefined') {
    return {};
  }

  return {
    EncodedVideoChunk: window.EncodedVideoChunk,
    VideoDecoder: window.VideoDecoder,
  } as WebCodecsLike;
}

function getDeviceDebugOptions(): { debugVideo?: 'fixture' } {
  if (typeof window === 'undefined') {
    return {};
  }

  const debugVideo = new URLSearchParams(window.location.search).get(
    'debugVideo',
  );
  if (debugVideo === 'fixture') {
    return {
      debugVideo,
    };
  }

  return {};
}

function requireReadyDeviceVideoPipeline(
  pipeline: DeviceVideoPipeline,
): Extract<DeviceVideoPipeline, { status: { type: 'ready' } }> {
  if (pipeline.status.type !== 'ready') {
    throw new Error('Device video pipeline is not ready.');
  }

  return pipeline as Extract<DeviceVideoPipeline, { status: { type: 'ready' } }>;
}
