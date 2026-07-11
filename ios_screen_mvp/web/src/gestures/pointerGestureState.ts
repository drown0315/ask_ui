export interface PointerSample {
  pointerId: number
  clientX: number
  clientY: number
  x: number
  y: number
}

export interface PointerMessage {
  type: 'pointer'
  action: 'down' | 'move' | 'up' | 'cancel'
  x: number
  y: number
  pointerId: 0
}

type SendPointer = (message: PointerMessage) => void
type LongPressChanged = (active: boolean) => void

export class PointerGestureState {
  private owner?: number
  private start?: PointerSample
  private latest?: PointerSample
  private longPressTimer?: ReturnType<typeof setTimeout>
  private longPressActive = false
  private lastMoveSentAt = 0

  constructor(
    private readonly send: SendPointer,
    private readonly onLongPressChanged: LongPressChanged = () => undefined,
  ) {}

  pointerDown(sample: PointerSample): boolean {
    if (this.owner !== undefined) return false
    this.owner = sample.pointerId
    this.start = sample
    this.latest = sample
    this.lastMoveSentAt = Date.now()
    this.emit('down', sample)
    this.longPressTimer = setTimeout(() => {
      if (this.owner === sample.pointerId) {
        this.longPressActive = true
        this.onLongPressChanged(true)
      }
    }, 600)
    return true
  }

  pointerMove(sample: PointerSample): void {
    if (sample.pointerId !== this.owner) return
    this.latest = sample
    if (this.start && Math.hypot(sample.clientX - this.start.clientX, sample.clientY - this.start.clientY) > 12) {
      this.clearLongPressTimer()
    }
    const now = Date.now()
    if (now - this.lastMoveSentAt >= 1000 / 30) {
      this.lastMoveSentAt = now
      this.emit('move', sample)
    }
  }

  pointerUp(sample: PointerSample): void {
    if (sample.pointerId !== this.owner) return
    this.emit('up', sample)
    this.reset()
  }

  pointerCancel(sample: PointerSample): void {
    if (sample.pointerId !== this.owner) return
    this.emit('cancel', sample)
    this.reset()
  }

  socketClosed(): void {
    if (this.latest) this.emit('cancel', this.latest)
    this.reset()
  }

  private emit(action: PointerMessage['action'], sample: PointerSample): void {
    this.send({ type: 'pointer', action, x: sample.x, y: sample.y, pointerId: 0 })
  }

  private clearLongPressTimer(): void {
    if (this.longPressTimer !== undefined) clearTimeout(this.longPressTimer)
    this.longPressTimer = undefined
  }

  private reset(): void {
    this.clearLongPressTimer()
    if (this.longPressActive) this.onLongPressChanged(false)
    this.longPressActive = false
    this.owner = undefined
    this.start = undefined
    this.latest = undefined
  }
}
