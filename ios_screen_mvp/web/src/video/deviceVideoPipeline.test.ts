import { describe, expect, it } from 'vitest'

import { inspectAnnexBAccessUnit, splitAnnexBNalus } from './h264AnnexB'

describe('H.264 Annex B access units', () => {
  it('splits three and four byte start codes without including delimiters', () => {
    const bytes = new Uint8Array([
      0, 0, 0, 1, 0x67, 1, 2,
      0, 0, 1, 0x68, 3,
      0, 0, 0, 1, 0x65, 4, 5,
    ])

    expect(splitAnnexBNalus(bytes).map((nal) => [...nal])).toEqual([
      [0x67, 1, 2],
      [0x68, 3],
      [0x65, 4, 5],
    ])
  })

  it('detects decoder configuration and IDR keyframes', () => {
    const accessUnit = new Uint8Array([
      0, 0, 0, 1, 0x67, 0x42, 0, 0x1f,
      0, 0, 0, 1, 0x68, 1,
      0, 0, 0, 1, 0x65, 2,
    ])

    const inspection = inspectAnnexBAccessUnit(accessUnit)

    expect(inspection.isKeyframe).toBe(true)
    expect(inspection.hasDecoderConfig).toBe(true)
    expect(inspection.codec).toBe('avc1.42001f')
  })
})
