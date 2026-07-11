import { useEffect, useRef, useState } from 'react'

import { DeviceVideoPipeline } from './video/deviceVideoPipeline'
import './IosScreenDemo.css'

interface ReadyMetadata {
  type: 'ready'
  deviceId: string
  screenWidth: number
  screenHeight: number
  logicalWidth: number
  logicalHeight: number
  devicePixelRatio: number
  controlBackend: string
}

interface ErrorMessage {
  type: 'error'
  code: string
  message: string
}

export function IosScreenDemo() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [metadata, setMetadata] = useState<ReadyMetadata>()
  const [status, setStatus] = useState('Connecting')
  const [error, setError] = useState<ErrorMessage>()
  const [fps, setFps] = useState(0)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    let pipeline: DeviceVideoPipeline
    try {
      pipeline = new DeviceVideoPipeline(canvas)
    } catch (caught) {
      setError({ type: 'error', code: 'webcodecs_unavailable', message: String(caught) })
      setStatus('Unsupported')
      return
    }
    const scheme = location.protocol === 'https:' ? 'wss' : 'ws'
    const socket = new WebSocket(`${scheme}://${location.host}/session`)
    socket.binaryType = 'arraybuffer'
    let frameCount = 0
    let fpsStartedAt = performance.now()
    socket.onopen = () => setStatus('Waiting for device')
    socket.onmessage = (event) => {
      if (typeof event.data === 'string') {
        const message = JSON.parse(event.data) as ReadyMetadata | ErrorMessage
        if (message.type === 'ready') {
          setMetadata(message)
          setError(undefined)
          setStatus('Live')
        } else {
          setError(message)
          setStatus('Error')
        }
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
    socket.onerror = () => setError({ type: 'error', code: 'connection_failed', message: 'Unable to connect to the local session.' })
    socket.onclose = () => setStatus((current) => current === 'Error' ? current : 'Disconnected')
    return () => {
      socket.close()
      pipeline.close()
    }
  }, [])

  const aspectRatio = metadata ? `${metadata.screenWidth} / ${metadata.screenHeight}` : '390 / 844'
  return (
    <main className="workbench">
      <header className="toolbar">
        <div>
          <h1>iOS Screen</h1>
          <p>{metadata?.deviceId ?? 'No device metadata'}</p>
        </div>
        <div className="telemetry" aria-live="polite">
          <span data-state={status.toLowerCase()}>{status}</span>
          <span>{fps} FPS</span>
          {metadata && <span>{metadata.screenWidth} x {metadata.screenHeight}</span>}
        </div>
      </header>
      <section className="stage">
        <div className="device" style={{ aspectRatio }}>
          <canvas ref={canvasRef} aria-label="Live iPhone screen" />
          {error && <div className="error"><strong>{error.code}</strong><span>{error.message}</span></div>}
        </div>
      </section>
    </main>
  )
}
