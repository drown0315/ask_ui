export type H264AccessUnit = {
  bytes: Uint8Array<ArrayBufferLike>;
  nalTypes: number[];
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

  push(chunk: Uint8Array<ArrayBufferLike>): H264AccessUnit[] {
    this.bufferedBytes = concatenateBytes(this.bufferedBytes, chunk);

    const nalUnits = splitAnnexBNalUnits(this.bufferedBytes);
    if (nalUnits.length === 0) {
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

    const nalTypes = nalUnits.map((nalUnit) => nalUnit[0] & 0x1f);
    if (!nalTypes.some(isVclNalType)) {
      return [];
    }

    const bytes = this.bufferedBytes;
    this.bufferedBytes = new Uint8Array();
    return [
      {
        bytes,
        nalTypes,
      },
    ];
  }
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

function splitAnnexBNalUnits(
  bytes: Uint8Array<ArrayBufferLike>,
): Array<Uint8Array<ArrayBufferLike>> {
  const startCodes = findStartCodes(bytes);
  const nalUnits: Array<Uint8Array<ArrayBufferLike>> = [];

  for (let index = 0; index < startCodes.length; index += 1) {
    const start = startCodes[index];
    const nextStart = startCodes[index + 1]?.index ?? bytes.length;
    const nalStart = start.index + start.length;
    if (nalStart < nextStart) {
      nalUnits.push(bytes.slice(nalStart, nextStart));
    }
  }

  return nalUnits;
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
