import { useEffect, useState } from 'react';
import { getDeviceWebSocketUrl } from '../services/askUiBridgeClient';
import {
  getInitialLiveAppSurfaceState,
  reduceLiveAppSurfaceMessage,
  type LiveAppSurfaceState,
} from './liveAppSurfaceState';

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
} {
  const [retryToken, setRetryToken] = useState(0);
  const [surfaceState, setSurfaceState] = useState<LiveAppSurfaceState>(() =>
    getInitialLiveAppSurfaceState(sessionId),
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
    const socket = new WebSocket(getDeviceWebSocketUrl(sessionId));

    setSurfaceState({
      status: 'connecting',
    });

    socket.addEventListener('message', (event) => {
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
      socket.close();
    };
  }, [retryToken, sessionId]);

  return {
    surfaceState,
    retryLiveAppSurface() {
      setRetryToken((current) => current + 1);
    },
  };
}
