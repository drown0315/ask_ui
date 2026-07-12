import { describe, expect, it } from 'vitest'

import {
  initialSessionState,
  reduceSessionMessage,
  type ReadyMetadata,
} from './sessionState'

const readyMetadata: ReadyMetadata = {
  type: 'ready',
  deviceId: 'ios-1',
  screenWidth: 750,
  screenHeight: 1334,
  logicalWidth: 375,
  logicalHeight: 667,
  devicePixelRatio: 2,
  videoCodec: 'h264',
  controlBackend: 'flutterRuntime',
}

describe('reduceSessionMessage', () => {
  it('tracks control availability independently from connecting video', () => {
    expect(reduceSessionMessage(initialSessionState, {
      type: 'control',
      state: 'unavailable',
    })).toMatchObject({
      videoState: 'connecting',
      controlState: 'unavailable',
    })
  })

  it('marks video live without changing control availability', () => {
    expect(reduceSessionMessage(initialSessionState, readyMetadata)).toMatchObject({
      videoState: 'live',
      controlState: 'unavailable',
      metadata: readyMetadata,
    })
  })

  it('keeps live video while control becomes ready', () => {
    const liveState = reduceSessionMessage(initialSessionState, readyMetadata)

    expect(reduceSessionMessage(liveState, {
      type: 'control',
      state: 'ready',
    })).toMatchObject({
      videoState: 'live',
      controlState: 'ready',
    })
  })
})
