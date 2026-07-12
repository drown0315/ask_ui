import { type PointerEvent as ReactPointerEvent, useEffect, useRef, useState } from 'react'

import { fitVideoRect, normalizePoint } from './geometry/deviceViewGeometry'
import { PointerGestureState, type PointerSample } from './gestures/pointerGestureState'
import {
  initialSessionState,
  reduceSessionMessage,
  type SessionMessage,
} from './session/sessionState'
import { DeviceVideoPipeline } from './video/deviceVideoPipeline'
import './IosScreenDemo.css'

export function IosScreenDemo() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const socketRef = useRef<WebSocket>(null)
  const gestureRef = useRef<PointerGestureState>(null)
  const [session, setSession] = useState(initialSessionState)
  const [fps, setFps] = useState(0)
  const [longPressActive, setLongPressActive] = useState(false)

  useEffect(() => {
    gestureRef.current?.socketClosed()
    gestureRef.current = null
    if (session.controlState !== 'ready') return
    gestureRef.current = new PointerGestureState((message) => {
      const socket = socketRef.current
      if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message))
    }, setLongPressActive)
  }, [session.controlState])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    let pipeline: DeviceVideoPipeline
    try {
      pipeline = new DeviceVideoPipeline(canvas)
    } catch (caught) {
      setSession((state) => reduceSessionMessage(state, {
        type: 'error', code: 'webcodecs_unavailable', message: String(caught),
      }))
      return
    }
    const scheme = location.protocol === 'https:' ? 'wss' : 'ws'
    const socket = new WebSocket(`${scheme}://${location.host}/session`)
    socketRef.current = socket
    socket.binaryType = 'arraybuffer'
    let frameCount = 0
    let fpsStartedAt = performance.now()
    socket.onmessage = (event) => {
      if (typeof event.data === 'string') {
        const message = JSON.parse(event.data) as SessionMessage
        setSession((state) => reduceSessionMessage(state, message))
        return
      }
      const bytes = new Uint8Array(event.data as ArrayBuffer)
      if (bytes.length < 13) return
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
      const length = view.getUint32(0)
      if (bytes.length !== 13 + length) return
      const flags = view.getUint8(4)
      const timestamp = Number(view.getBigUint64(5))
      pipeline.push(bytes.subarray(13), timestamp, (flags & 1) !== 0)
      frameCount += 1
      const now = performance.now()
      if (now - fpsStartedAt >= 1000) {
        setFps(Math.round(frameCount * 1000 / (now - fpsStartedAt)))
        frameCount = 0
        fpsStartedAt = now
      }
    }
    socket.onerror = () => setSession((state) => reduceSessionMessage(state, {
      type: 'error', code: 'connection_failed', message: 'Unable to connect to the local session.',
    }))
    socket.onclose = () => {
      gestureRef.current?.socketClosed()
      setSession((state) => ({
        ...state,
        videoState: state.videoState === 'error' ? 'error' : 'disconnected',
        controlState: 'unavailable',
      }))
    }
    return () => {
      gestureRef.current?.socketClosed()
      gestureRef.current = null
      socketRef.current = null
      socket.close()
      pipeline.close()
    }
  }, [])

  const { metadata, error } = session
  const aspectRatio = metadata ? `${metadata.screenWidth} / ${metadata.screenHeight}` : '390 / 844'

  function pointerSample(event: ReactPointerEvent<HTMLCanvasElement>): PointerSample | null {
    if (!metadata) return null
    const bounds = event.currentTarget.getBoundingClientRect()
    const fitted = fitVideoRect(bounds.width, bounds.height, metadata.screenWidth, metadata.screenHeight)
    const point = normalizePoint(event.clientX, event.clientY, {
      ...fitted,
      x: fitted.x + bounds.left,
      y: fitted.y + bounds.top,
    })
    return point && {
      pointerId: event.pointerId,
      clientX: event.clientX,
      clientY: event.clientY,
      ...point,
    }
  }

  return (
    <main className="workbench">
      <header className="toolbar">
        <div>
          <h1>iOS Screen</h1>
          <p>{metadata?.deviceId ?? 'No device metadata'}</p>
        </div>
        <div className="telemetry" aria-live="polite">
          <span data-state={session.videoState}>Video: {session.videoState}</span>
          <span data-state={session.controlState}>Control: {session.controlState}</span>
          <span>{fps} FPS</span>
          {metadata && <span>{metadata.screenWidth} x {metadata.screenHeight}</span>}
        </div>
      </header>
      <section className="stage">
        <div className="device" style={{ aspectRatio }}>
          <canvas
            ref={canvasRef}
            aria-label="Live iPhone screen"
            data-control={session.controlState}
            onPointerDown={(event) => {
              const sample = pointerSample(event)
              if (sample && gestureRef.current?.pointerDown(sample)) {
                event.currentTarget.setPointerCapture(event.pointerId)
              }
            }}
            onPointerMove={(event) => {
              const sample = pointerSample(event)
              if (sample) gestureRef.current?.pointerMove(sample)
            }}
            onPointerUp={(event) => {
              const sample = pointerSample(event)
              if (sample) gestureRef.current?.pointerUp(sample)
            }}
            onPointerCancel={(event) => {
              const sample = pointerSample(event)
              if (sample) gestureRef.current?.pointerCancel(sample)
            }}
          />
          {longPressActive && <div className="long-press" aria-hidden="true" />}
          {session.videoState === 'error' && error && <div className="error"><strong>{error.code}</strong><span>{error.message}</span></div>}
        </div>
      </section>
    </main>
  )
}
