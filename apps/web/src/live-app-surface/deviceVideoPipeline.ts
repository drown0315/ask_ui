import { H264AnnexBParser } from './h264AnnexB.ts';

type EncodedVideoChunkLike = {
  type: string;
  timestamp: number;
  data?: Uint8Array<ArrayBufferLike>;
};

type EncodedVideoChunkConstructor = new (init: {
  type: 'key' | 'delta';
  timestamp: number;
  data: Uint8Array<ArrayBufferLike>;
}) => EncodedVideoChunkLike;

type VideoDecoderLike = {
  decodeQueueSize: number;
  configure(config: { codec: string; optimizeForLatency: boolean }): void;
  decode(chunk: EncodedVideoChunkLike): void;
  close(): void;
};

type VideoDecoderConstructor = new (init: {
  output: (frame: unknown) => void;
  error: (error: Error) => void;
}) => VideoDecoderLike;

/**
 * WebCodecs constructors used by the Device video pipeline.
 *
 * Tests pass fake constructors with the same behavior, while the browser passes
 * `window.VideoDecoder` and `window.EncodedVideoChunk`. Missing constructors
 * mean the current browser cannot run the first-version video path.
 */
export type WebCodecsLike = {
  EncodedVideoChunk?: EncodedVideoChunkConstructor;
  VideoDecoder?: VideoDecoderConstructor;
};

/**
 * Decoder pipeline for binary H.264 chunks received from the Device WebSocket.
 *
 * A ready pipeline accepts raw Annex B bytes, assembles access units, submits
 * them to WebCodecs, and reports decoded frames to the caller. An unsupported
 * pipeline represents a browser without the WebCodecs APIs required by this
 * first version; callers can show its message and ignore later video chunks.
 */
export type DeviceVideoPipeline =
  | {
      status: {
        type: 'unsupported';
        message: string;
      };
      close: () => void;
      push: (chunk: Uint8Array<ArrayBufferLike>) => void;
    }
  | {
      status: {
        type: 'ready';
      };
      close: () => void;
      push: (chunk: Uint8Array<ArrayBufferLike>) => void;
    };

/**
 * Create the low-latency H.264 WebCodecs pipeline for Device video bytes.
 *
 * This method:
 * 1. checks whether the browser exposes the required WebCodecs constructors
 * 2. creates an Annex B parser for raw WebSocket binary chunks
 * 3. configures a low-latency H.264 decoder for the fixture stream
 * 4. returns a `push` method that decodes complete access units as they arrive
 *
 * Args:
 * - `webCodecs`: Browser WebCodecs constructors. Tests pass fake
 *   constructors here; production passes the constructors from `window`.
 *   Missing constructors return an unsupported pipeline instead of throwing.
 * - `onFrame`: Called for each decoded frame so React can draw it into the
 *   Device View canvas.
 * - `onFirstFrameRendered`: Called once after the first decoded frame reaches
 *   the renderer. The Live App Surface uses this to leave `Waiting for video`.
 *
 * Returns:
 * A ready pipeline when WebCodecs exists, otherwise an unsupported-browser
 * pipeline whose `push` method ignores binary video chunks.
 *
 * Example:
 * A binary WebSocket message containing SPS, PPS, and IDR NAL units is pushed
 * into the returned pipeline, decoded as a key chunk, and emitted through
 * `onFrame`.
 */
export function createDeviceVideoPipeline({
  webCodecs,
  onFrame,
  onFirstFrameRendered,
}: {
  webCodecs: WebCodecsLike;
  onFrame: (frame: unknown) => void;
  onFirstFrameRendered: () => void;
}): DeviceVideoPipeline {
  const VideoDecoderConstructor = webCodecs.VideoDecoder;
  const EncodedVideoChunkConstructor = webCodecs.EncodedVideoChunk;

  if (!VideoDecoderConstructor || !EncodedVideoChunkConstructor) {
    return {
      status: {
        type: 'unsupported',
        message: 'WebCodecs is not available in this browser.',
      },
      close() {},
      push() {},
    };
  }

  const parser = new H264AnnexBParser();
  let timestamp = 0;
  let didRenderFirstFrame = false;
  const decoder = new VideoDecoderConstructor({
    output(frame: unknown) {
      onFrame(frame);
      if (!didRenderFirstFrame) {
        didRenderFirstFrame = true;
        onFirstFrameRendered();
      }
    },
    error(error: Error) {
      console.error('Device video decoder failed', error);
    },
  });
  decoder.configure({
    codec: 'avc1.42C00A',
    optimizeForLatency: true,
  });

  return {
    status: {
      type: 'ready',
    },
    close() {
      decoder.close();
    },
    push(chunk: Uint8Array<ArrayBufferLike>) {
      for (const accessUnit of parser.push(chunk)) {
        const chunkType = accessUnit.nalTypes.includes(5) ? 'key' : 'delta';
        // When WebCodecs is already backed up, old delta frames increase
        // interaction latency. Keep key frames because later decoding may need
        // a fresh reference point; drop only delta chunks in this first version.
        if (chunkType === 'delta' && decoder.decodeQueueSize > 2) {
          continue;
        }

        const encodedChunk = new EncodedVideoChunkConstructor({
          type: chunkType,
          timestamp,
          data: accessUnit.bytes,
        });
        timestamp += 1;
        decoder.decode(encodedChunk);
      }
    },
  };
}
