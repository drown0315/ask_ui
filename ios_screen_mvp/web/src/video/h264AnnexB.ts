export interface AccessUnitInspection {
  isKeyframe: boolean
  hasDecoderConfig: boolean
  codec?: string
}

export function splitAnnexBNalus(data: Uint8Array): Uint8Array[] {
  const starts: Array<{ offset: number; length: number }> = []
  for (let index = 0; index + 3 <= data.length; index += 1) {
    if (data[index] !== 0 || data[index + 1] !== 0) continue
    if (data[index + 2] === 1) {
      starts.push({ offset: index, length: 3 })
      index += 2
    } else if (index + 3 < data.length && data[index + 2] === 0 && data[index + 3] === 1) {
      starts.push({ offset: index, length: 4 })
      index += 3
    }
  }

  return starts
    .map((start, index) => {
      const from = start.offset + start.length
      const to = starts[index + 1]?.offset ?? data.length
      return data.subarray(from, to)
    })
    .filter((nal) => nal.length > 0)
}

export function inspectAnnexBAccessUnit(data: Uint8Array): AccessUnitInspection {
  const nals = splitAnnexBNalus(data)
  const sps = nals.find((nal) => (nal[0] & 0x1f) === 7)
  return {
    isKeyframe: nals.some((nal) => (nal[0] & 0x1f) === 5),
    hasDecoderConfig: Boolean(sps && nals.some((nal) => (nal[0] & 0x1f) === 8)),
    codec: sps && sps.length >= 4
      ? `avc1.${[sps[1], sps[2], sps[3]].map((byte) => byte.toString(16).padStart(2, '0')).join('')}`
      : undefined,
  }
}
