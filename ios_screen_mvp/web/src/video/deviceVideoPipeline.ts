import { inspectAnnexBAccessUnit } from './h264AnnexB'

export class DeviceVideoPipeline {
  private readonly decoder: VideoDecoder
  private codec?: string

  constructor(canvas: HTMLCanvasElement) {
    if (!('VideoDecoder' in window)) throw new Error('WebCodecs is not supported by this browser.')
    const context = canvas.getContext('2d')
    if (!context) throw new Error('Unable to create the video canvas context.')
    this.decoder = new VideoDecoder({
      output: (frame) => {
        try {
          if (canvas.width !== frame.displayWidth || canvas.height !== frame.displayHeight) {
            canvas.width = frame.displayWidth
            canvas.height = frame.displayHeight
          }
          context.drawImage(frame, 0, 0, canvas.width, canvas.height)
        } finally {
          frame.close()
        }
      },
      error: () => undefined,
    })
  }

  push(accessUnit: Uint8Array, timestamp: number, keyframeFlag: boolean): void {
    const inspection = inspectAnnexBAccessUnit(accessUnit)
    const codec = inspection.codec ?? this.codec
    if (inspection.hasDecoderConfig && codec && codec !== this.codec) {
      this.codec = codec
      this.decoder.configure({ codec, optimizeForLatency: true })
    }
    const isKeyframe = keyframeFlag || inspection.isKeyframe
    if (this.decoder.state !== 'configured') return
    if (!isKeyframe && this.decoder.decodeQueueSize > 4) return
    this.decoder.decode(new EncodedVideoChunk({
      type: isKeyframe ? 'key' : 'delta',
      timestamp,
      data: accessUnit,
    }))
  }

  close(): void {
    if (this.decoder.state !== 'closed') this.decoder.close()
  }
}
