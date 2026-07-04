export type LiveAppSurfaceMetadata = {
  deviceId: string;
  screenWidth: number;
  screenHeight: number;
  maxFps: number;
  videoCodec: 'h264';
  controlReady: boolean;
};

export type LiveAppSurfaceState =
  | {
      status: 'idle';
    }
  | {
      status: 'connecting';
    }
  | {
      status: 'waitingForVideo';
      metadata: LiveAppSurfaceMetadata;
    }
  | {
      status: 'failed';
      message: string;
      error?: string;
    };

/**
 * Return the first Live App Surface state for the current bridge session.
 *
 * Args:
 * - `sessionId`: Ready bridge session id, or `null` before the bridge session
 *   exists.
 *
 * Returns:
 * `connecting` when a session can open the Device WebSocket, otherwise `idle`.
 */
export function getInitialLiveAppSurfaceState(
  sessionId: string | null,
): LiveAppSurfaceState {
  if (sessionId === null) {
    return {
      status: 'idle',
    };
  }

  return {
    status: 'connecting',
  };
}

/**
 * Apply one text message from the Device WebSocket to the visible state.
 *
 * Args:
 * - `state`: Current Live App Surface state.
 * - `rawMessage`: Text frame received from the bridge Device WebSocket.
 *
 * Returns:
 * The next Live App Surface state. `ready` and `metadata` messages must carry
 * complete metadata because partial metadata diffs are not part of the first
 * version protocol.
 */
export function reduceLiveAppSurfaceMessage(
  state: LiveAppSurfaceState,
  rawMessage: string,
): LiveAppSurfaceState {
  const message = JSON.parse(rawMessage) as Record<string, unknown>;

  if (message.type === 'ready') {
    return {
      status: 'waitingForVideo',
      metadata: parseLiveAppSurfaceMetadata(message),
    };
  }

  if (message.type === 'metadata' && 'metadata' in state) {
    return {
      ...state,
      metadata: parseLiveAppSurfaceMetadata(message),
    };
  }

  if (message.type === 'error') {
    return {
      status: 'failed',
      error: typeof message.error === 'string' ? message.error : undefined,
      message:
        typeof message.message === 'string'
          ? message.message
          : 'Device failed.',
    };
  }

  return state;
}

function parseLiveAppSurfaceMetadata(
  message: Record<string, unknown>,
): LiveAppSurfaceMetadata {
  return {
    deviceId: String(message.deviceId),
    screenWidth: Number(message.screenWidth),
    screenHeight: Number(message.screenHeight),
    maxFps: Number(message.maxFps),
    videoCodec: 'h264',
    controlReady: message.controlReady === true,
  };
}
