import { describe, expect, it } from 'vitest'

import { fitVideoRect, normalizePoint } from './deviceViewGeometry'

describe('device view geometry', () => {
  it('contain-fits a portrait video in the available viewport', () => {
    const rect = fitVideoRect(800, 600, 390, 844)

    expect(rect.x).toBeCloseTo(261.3744)
    expect(rect.y).toBe(0)
    expect(rect.width).toBeCloseTo(277.2512)
    expect(rect.height).toBe(600)
  })

  it('maps fitted coordinates to the inclusive normalized range', () => {
    const rect = { x: 100, y: 20, width: 200, height: 400 }

    expect(normalizePoint(200, 220, rect)).toEqual({ x: 0.5, y: 0.5 })
    expect(normalizePoint(100, 20, rect)).toEqual({ x: 0, y: 0 })
    expect(normalizePoint(300, 420, rect)).toEqual({ x: 1, y: 1 })
  })

  it('rejects pointer coordinates outside the fitted video rectangle', () => {
    const rect = { x: 100, y: 20, width: 200, height: 400 }

    expect(normalizePoint(99.9, 200, rect)).toBeNull()
    expect(normalizePoint(200, 420.1, rect)).toBeNull()
  })
})
