export interface ReadyMetadata {
  type: 'ready'
  deviceId: string
  screenWidth: number
  screenHeight: number
  logicalWidth: number
  logicalHeight: number
  devicePixelRatio: number
  videoCodec: string
  controlBackend: string
}

export interface ErrorMessage {
  type: 'error'
  code: string
  message: string
}

export interface ControlMessage {
  type: 'control'
  state: 'unavailable' | 'connecting' | 'ready'
}

export type SessionMessage = ReadyMetadata | ErrorMessage | ControlMessage

export interface SessionState {
  videoState: 'connecting' | 'live' | 'error' | 'disconnected'
  controlState: 'unavailable' | 'connecting' | 'ready'
  metadata?: ReadyMetadata
  error?: ErrorMessage
}

export const initialSessionState: SessionState = {
  videoState: 'connecting',
  controlState: 'unavailable',
}

export function reduceSessionMessage(
  state: SessionState,
  message: SessionMessage,
): SessionState {
  if (message.type === 'ready') {
    return { ...state, videoState: 'live', metadata: message, error: undefined }
  }
  if (message.type === 'control') {
    return { ...state, controlState: message.state }
  }
  if (message.code === 'runtime_control_unavailable') {
    return { ...state, controlState: 'unavailable', error: message }
  }
  return { ...state, videoState: 'error', error: message }
}
