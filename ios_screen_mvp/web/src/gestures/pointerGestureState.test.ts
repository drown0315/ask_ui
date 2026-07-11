import { afterEach, describe, expect, it, vi } from 'vitest'

import { PointerGestureState, type PointerSample } from './pointerGestureState'

const start: PointerSample = {
  pointerId: 7,
  clientX: 100,
  clientY: 200,
  x: 0.25,
  y: 0.5,
}

describe('PointerGestureState', () => {
  afterEach(() => vi.useRealTimers())

  it('sends down, throttled move, and up for one pointer', () => {
    vi.useFakeTimers()
    const messages: unknown[] = []
    const state = new PointerGestureState((message) => messages.push(message))

    expect(state.pointerDown(start)).toBe(true)
    vi.advanceTimersByTime(34)
    state.pointerMove({ ...start, clientY: 240, y: 0.6 })
    state.pointerUp({ ...start, clientY: 250, y: 0.625 })

    expect(messages).toEqual([
      { type: 'pointer', action: 'down', x: 0.25, y: 0.5, pointerId: 0 },
      { type: 'pointer', action: 'move', x: 0.25, y: 0.6, pointerId: 0 },
      { type: 'pointer', action: 'up', x: 0.25, y: 0.625, pointerId: 0 },
    ])
  })

  it('marks a stationary pointer as a long press after 600ms and keeps it down', () => {
    vi.useFakeTimers()
    const messages: unknown[] = []
    const longPressStates: boolean[] = []
    const state = new PointerGestureState(
      (message) => messages.push(message),
      (active) => longPressStates.push(active),
    )

    state.pointerDown(start)
    vi.advanceTimersByTime(600)

    expect(messages).toHaveLength(1)
    expect(longPressStates).toEqual([true])
    state.pointerUp(start)
    expect(longPressStates).toEqual([true, false])
  })

  it('movement beyond 12 CSS pixels prevents long-press feedback', () => {
    vi.useFakeTimers()
    const longPressStates: boolean[] = []
    const state = new PointerGestureState(() => undefined, (active) => longPressStates.push(active))

    state.pointerDown(start)
    vi.advanceTimersByTime(34)
    state.pointerMove({ ...start, clientX: 113 })
    vi.advanceTimersByTime(600)

    expect(longPressStates).toEqual([])
  })

  it('sends cancel for browser cancellation and socket close', () => {
    const messages: Array<{ action: string }> = []
    const state = new PointerGestureState((message) => messages.push(message))

    state.pointerDown(start)
    state.pointerCancel(start)
    state.pointerDown(start)
    state.socketClosed()

    expect(messages.map((message) => message.action)).toEqual([
      'down', 'cancel', 'down', 'cancel',
    ])
  })

  it('ignores a second pointer until the owner finishes', () => {
    const messages: unknown[] = []
    const state = new PointerGestureState((message) => messages.push(message))

    expect(state.pointerDown(start)).toBe(true)
    expect(state.pointerDown({ ...start, pointerId: 8 })).toBe(false)
    state.pointerMove({ ...start, pointerId: 8 })
    state.pointerUp({ ...start, pointerId: 8 })

    expect(messages).toHaveLength(1)
  })
})
