import assert from 'node:assert/strict';
import test from 'node:test';

import { createDeviceVideoPipeline } from './deviceVideoPipeline.ts';

test('reports WebCodecs unavailable when required browser APIs are missing', () => {
  const pipeline = createDeviceVideoPipeline({
    webCodecs: {},
    onFrame: () => {},
    onFirstFrameRendered: () => {},
  });

  assert.deepEqual(pipeline.status, {
    type: 'unsupported',
    message: 'WebCodecs is not available in this browser.',
  });
});

test('decodes Annex B access units and reports the first rendered frame', () => {
  const decodedChunks: Array<{ type: string; timestamp: number; bytes: number[] }> = [];
  let firstFrameCount = 0;
  let renderedFrame: unknown = null;
  const frame = { close() {} };

  const pipeline = createDeviceVideoPipeline({
    webCodecs: {
      EncodedVideoChunk: class FakeEncodedVideoChunk {
        type: string;
        timestamp: number;
        data: Uint8Array;

        constructor(init: {
          type: string;
          timestamp: number;
          data: Uint8Array;
        }) {
          this.type = init.type;
          this.timestamp = init.timestamp;
          this.data = init.data;
        }
      },
      VideoDecoder: class FakeVideoDecoder {
        decodeQueueSize = 0;
        private output: (frame: unknown) => void;

        constructor(init: { output: (frame: unknown) => void }) {
          this.output = init.output;
        }

        configure() {}

        decode(chunk: { type: string; timestamp: number; data: Uint8Array }) {
          decodedChunks.push({
            type: chunk.type,
            timestamp: chunk.timestamp,
            bytes: Array.from(chunk.data.slice(0, 4)),
          });
          this.output(frame);
        }

        close() {}
      },
    },
    onFrame: (nextFrame) => {
      renderedFrame = nextFrame;
    },
    onFirstFrameRendered: () => {
      firstFrameCount += 1;
    },
  });

  assert.equal(pipeline.status.type, 'ready');
  pipeline.push(
    new Uint8Array([
      0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1f, 0x00, 0x00, 0x01, 0x68,
      0xce, 0x06, 0xe2, 0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x21,
    ]),
  );

  assert.deepEqual(decodedChunks, [
    {
      type: 'key',
      timestamp: 0,
      bytes: [0x00, 0x00, 0x00, 0x01],
    },
  ]);
  assert.equal(firstFrameCount, 1);
  assert.equal(renderedFrame, frame);
});

test('drops delta access units when the decode queue is pressured', () => {
  let decodeCount = 0;
  const pipeline = createDeviceVideoPipeline({
    webCodecs: {
      EncodedVideoChunk: class FakeEncodedVideoChunk {
        type: string;
        timestamp: number;
        data: Uint8Array;

        constructor(init: {
          type: string;
          timestamp: number;
          data: Uint8Array;
        }) {
          this.type = init.type;
          this.timestamp = init.timestamp;
          this.data = init.data;
        }
      },
      VideoDecoder: class FakeVideoDecoder {
        decodeQueueSize = 3;

        configure() {}

        decode() {
          decodeCount += 1;
        }

        close() {}
      },
    },
    onFrame: () => {},
    onFirstFrameRendered: () => {},
  });

  pipeline.push(
    new Uint8Array([
      0x00, 0x00, 0x00, 0x01, 0x61, 0x88, 0x84, 0x21,
    ]),
  );

  assert.equal(decodeCount, 0);
});
