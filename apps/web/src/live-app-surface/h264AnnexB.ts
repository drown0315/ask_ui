export type H264AccessUnit = {
  bytes: Uint8Array<ArrayBufferLike>;
  codec?: string;
  nalTypes: number[];
};

type H264NalUnit = {
  bytes: Uint8Array<ArrayBufferLike>;
  payload: Uint8Array<ArrayBufferLike>;
  type: number;
};

export class H264AnnexBParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'H264AnnexBParseError';
  }
}

/**
 * Parses raw H.264 Annex B bytes from Device WebSocket binary messages.
 *
 * The parser accepts arbitrary WebSocket chunk boundaries and returns complete
 * access units that can be passed to the WebCodecs decoder path.
 */
export class H264AnnexBParser {
  private bufferedBytes: Uint8Array<ArrayBufferLike> = new Uint8Array();
  private accessUnitNalUnits: H264NalUnit[] = [];
  private accessUnitHasVcl = false;
  private accessUnitCodec: string | undefined;
  private latestParameterSets: H264NalUnit[] = [];
  private latestCodec: string | undefined;

  push(chunk: Uint8Array<ArrayBufferLike>): H264AccessUnit[] {
    this.bufferedBytes = concatenateBytes(this.bufferedBytes, chunk);

    const { nalUnits, remainingBytes } = splitCompleteAnnexBNalUnits(
      this.bufferedBytes,
    );
    this.bufferedBytes = remainingBytes;

    if (nalUnits.length === 0) {
      if (findStartCodes(this.bufferedBytes).length > 0) {
        return [];
      }

      if (
        this.bufferedBytes.length >= 4 &&
        !couldBeStartCodePrefix(this.bufferedBytes)
      ) {
        throw new H264AnnexBParseError(
          'H.264 Annex B stream is missing a start code.',
        );
      }

      return [];
    }

    const accessUnits: H264AccessUnit[] = [];
    for (const nalUnit of nalUnits) {
      if (nalUnit.type === 7 || nalUnit.type === 8) {
        this.latestParameterSets = this.latestParameterSets.filter(
          (parameterSet) => parameterSet.type !== nalUnit.type,
        );
        this.latestParameterSets.push(nalUnit);
      }

      if (nalUnit.type === 7) {
        this.latestCodec = readAvcCodecFromSps(nalUnit.payload);
      }

      if (nalUnit.type === 9 && this.accessUnitHasVcl) {
        accessUnits.push(this.emitAccessUnit());
      }

      if (
        isVclNalType(nalUnit.type) &&
        this.accessUnitHasVcl &&
        startsNewPicture(nalUnit)
      ) {
        accessUnits.push(this.emitAccessUnit());
      }

      if (
        nalUnit.type === 5 &&
        !this.accessUnitHasVcl &&
        !this.accessUnitNalUnits.some((unit) => unit.type === 7) &&
        this.latestParameterSets.length > 0
      ) {
        this.accessUnitNalUnits.push(...this.latestParameterSets);
      }

      this.accessUnitNalUnits.push(nalUnit);
      this.accessUnitCodec = this.accessUnitCodec ?? this.latestCodec;
      this.accessUnitHasVcl =
        this.accessUnitHasVcl || isVclNalType(nalUnit.type);
    }

    return accessUnits;
  }

  private emitAccessUnit(): H264AccessUnit {
    const bytes = concatenateMany(
      this.accessUnitNalUnits.map((nalUnit) => nalUnit.bytes),
    );
    const codec = this.accessUnitCodec;
    const nalTypes = this.accessUnitNalUnits.map((nalUnit) => nalUnit.type);
    this.accessUnitNalUnits = [];
    this.accessUnitHasVcl = false;
    this.accessUnitCodec = undefined;

    return {
      bytes,
      codec,
      nalTypes,
    };
  }
}

function readAvcCodecFromSps(
  payload: Uint8Array<ArrayBufferLike>,
): string | undefined {
  if (payload.length < 4) {
    return undefined;
  }

  return `avc1.${toHexByte(payload[1])}${toHexByte(payload[2])}${toHexByte(payload[3])}`;
}

function toHexByte(byte: number): string {
  return byte.toString(16).padStart(2, '0').toUpperCase();
}

function couldBeStartCodePrefix(bytes: Uint8Array<ArrayBufferLike>): boolean {
  return bytes.every((byte, index) => {
    if (index < bytes.length - 1) {
      return byte === 0x00;
    }

    return byte === 0x00 || byte === 0x01;
  });
}

function isVclNalType(nalType: number): boolean {
  return nalType >= 1 && nalType <= 5;
}

function concatenateBytes(
  left: Uint8Array<ArrayBufferLike>,
  right: Uint8Array<ArrayBufferLike>,
): Uint8Array<ArrayBufferLike> {
  const bytes = new Uint8Array(left.length + right.length);
  bytes.set(left, 0);
  bytes.set(right, left.length);
  return bytes;
}

function splitCompleteAnnexBNalUnits(
  bytes: Uint8Array<ArrayBufferLike>,
): {
  nalUnits: H264NalUnit[];
  remainingBytes: Uint8Array<ArrayBufferLike>;
} {
  const startCodes = findStartCodes(bytes);
  const nalUnits: H264NalUnit[] = [];

  if (startCodes.length < 2) {
    return {
      nalUnits,
      remainingBytes: startCodes.length === 1 ? bytes.slice(startCodes[0].index) : bytes,
    };
  }

  for (let index = 0; index < startCodes.length - 1; index += 1) {
    const start = startCodes[index];
    const nextStart = startCodes[index + 1].index;
    const nalStart = start.index + start.length;
    if (nalStart < nextStart) {
      const payload = bytes.slice(nalStart, nextStart);
      nalUnits.push({
        bytes: bytes.slice(start.index, nextStart),
        payload,
        type: payload[0] & 0x1f,
      });
    }
  }

  return {
    nalUnits,
    remainingBytes: bytes.slice(startCodes[startCodes.length - 1].index),
  };
}

function findStartCodes(
  bytes: Uint8Array<ArrayBufferLike>,
): Array<{ index: number; length: 3 | 4 }> {
  const starts: Array<{ index: number; length: 3 | 4 }> = [];

  for (let index = 0; index <= bytes.length - 3; index += 1) {
    if (
      bytes[index] === 0x00 &&
      bytes[index + 1] === 0x00 &&
      bytes[index + 2] === 0x01
    ) {
      starts.push({ index, length: 3 });
      index += 2;
      continue;
    }

    if (
      index <= bytes.length - 4 &&
      bytes[index] === 0x00 &&
      bytes[index + 1] === 0x00 &&
      bytes[index + 2] === 0x00 &&
      bytes[index + 3] === 0x01
    ) {
      starts.push({ index, length: 4 });
      index += 3;
    }
  }

  return starts;
}

function startsNewPicture(nalUnit: H264NalUnit): boolean {
  const rbsp = removeEmulationPreventionBytes(nalUnit.payload.slice(1));
  const firstMbInSlice = readUnsignedExpGolomb(rbsp);

  return firstMbInSlice === 0;
}

function removeEmulationPreventionBytes(
  bytes: Uint8Array<ArrayBufferLike>,
): Uint8Array<ArrayBufferLike> {
  const output: number[] = [];

  for (let index = 0; index < bytes.length; index += 1) {
    if (
      index >= 2 &&
      bytes[index - 2] === 0x00 &&
      bytes[index - 1] === 0x00 &&
      bytes[index] === 0x03
    ) {
      continue;
    }

    output.push(bytes[index]);
  }

  return new Uint8Array(output);
}

function readUnsignedExpGolomb(bytes: Uint8Array<ArrayBufferLike>): number {
  let leadingZeroBits = 0;
  let bitOffset = 0;

  while (bitOffset < bytes.length * 8 && readBit(bytes, bitOffset) === 0) {
    leadingZeroBits += 1;
    bitOffset += 1;
  }

  if (bitOffset >= bytes.length * 8) {
    return -1;
  }

  bitOffset += 1;
  let suffix = 0;
  for (let index = 0; index < leadingZeroBits; index += 1) {
    suffix = (suffix << 1) | readBit(bytes, bitOffset);
    bitOffset += 1;
  }

  return 2 ** leadingZeroBits - 1 + suffix;
}

function readBit(bytes: Uint8Array<ArrayBufferLike>, bitOffset: number): number {
  const byte = bytes[Math.floor(bitOffset / 8)];
  const shift = 7 - (bitOffset % 8);

  return (byte >> shift) & 1;
}

function concatenateMany(
  chunks: Array<Uint8Array<ArrayBufferLike>>,
): Uint8Array<ArrayBufferLike> {
  const length = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const bytes = new Uint8Array(length);
  let offset = 0;

  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }

  return bytes;
}
