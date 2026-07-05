import assert from 'node:assert/strict';
import test from 'node:test';

import { H264AnnexBParser, H264AnnexBParseError } from './h264AnnexB.ts';

test('assembles SPS, PPS, and IDR NAL units from Annex B start codes', () => {
  const parser = new H264AnnexBParser();

  const accessUnits = parser.push(
    new Uint8Array([
      0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1f, 0x00, 0x00, 0x01, 0x68,
      0xce, 0x06, 0xe2, 0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x21, 0x00,
      0x00, 0x00, 0x01, 0x61, 0x88, 0x84, 0x21, 0x00, 0x00, 0x01, 0x09,
      0xf0,
    ]),
  );

  assert.equal(accessUnits.length, 1);
  assert.deepEqual(accessUnits[0].nalTypes, [7, 8, 5]);
  assert.equal(accessUnits[0].codec, 'avc1.42001F');
  assert.deepEqual(Array.from(accessUnits[0].bytes.slice(0, 4)), [
    0x00, 0x00, 0x00, 0x01,
  ]);
});

test('keeps NAL units intact when start codes and payloads are split across chunks', () => {
  const parser = new H264AnnexBParser();

  assert.deepEqual(parser.push(new Uint8Array([0x00, 0x00])), []);
  assert.deepEqual(
    parser.push(new Uint8Array([0x00, 0x01, 0x67, 0x42, 0x00, 0x1f])),
    [],
  );

  const accessUnits = parser.push(
    new Uint8Array([
      0x00, 0x00, 0x01, 0x68, 0xce, 0x06, 0xe2, 0x00, 0x00, 0x00, 0x01, 0x65,
      0x88, 0x84, 0x21, 0x00, 0x00, 0x00, 0x01, 0x61, 0x88, 0x84, 0x21, 0x00,
      0x00, 0x01, 0x09, 0xf0,
    ]),
  );

  assert.equal(accessUnits.length, 1);
  assert.deepEqual(accessUnits[0].nalTypes, [7, 8, 5]);
});

test('preserves consecutive four-byte Annex B start codes exactly', () => {
  const parser = new H264AnnexBParser();
  const firstAccessUnitBytes = [
    0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1f, 0x00, 0x00, 0x00, 0x01,
    0x68, 0xce, 0x06, 0xe2, 0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x21,
  ];

  const accessUnits = parser.push(
    new Uint8Array([
      ...firstAccessUnitBytes,
      0x00, 0x00, 0x00, 0x01, 0x61, 0x88, 0x84, 0x21,
      0x00, 0x00, 0x00, 0x01, 0x09, 0xf0,
    ]),
  );

  assert.equal(accessUnits.length, 1);
  assert.deepEqual(Array.from(accessUnits[0].bytes), firstAccessUnitBytes);
});

test('does not emit an access unit until the last NAL is complete', () => {
  const parser = new H264AnnexBParser();

  const accessUnits = parser.push(
    new Uint8Array([
      0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x21,
    ]),
  );

  assert.deepEqual(accessUnits, []);
});

test('flushes a complete final access unit without a following start code', () => {
  const parser = new H264AnnexBParser();

  assert.deepEqual(
    parser.push(
      new Uint8Array([
        0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1f, 0x00, 0x00, 0x01,
        0x68, 0xce, 0x06, 0xe2, 0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84,
        0x21,
      ]),
    ),
    [],
  );

  const accessUnits = parser.flush();

  assert.equal(accessUnits.length, 1);
  assert.deepEqual(accessUnits[0].nalTypes, [7, 8, 5]);
  assert.equal(accessUnits[0].codec, 'avc1.42001F');
});

test('returns no access units when flushing an incomplete start code prefix', () => {
  const parser = new H264AnnexBParser();

  assert.deepEqual(parser.push(new Uint8Array([0x00, 0x00])), []);

  assert.deepEqual(parser.flush(), []);
});

test('keeps SPS and PPS for a later IDR access unit', () => {
  const parser = new H264AnnexBParser();

  assert.deepEqual(
    parser.push(
      new Uint8Array([
        0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1f, 0x00, 0x00, 0x01,
        0x68, 0xce, 0x06, 0xe2, 0x00, 0x00, 0x00, 0x01,
      ]),
    ),
    [],
  );

  const accessUnits = parser.push(
    new Uint8Array([
      0x65, 0x88, 0x84, 0x21, 0x00, 0x00, 0x01, 0x61, 0x88, 0x84, 0x21, 0x00,
      0x00, 0x01, 0x09, 0xf0,
    ]),
  );

  assert.equal(accessUnits.length, 1);
  assert.deepEqual(accessUnits[0].nalTypes, [7, 8, 5]);
});

test('returns multiple complete access units from one chunk', () => {
  const parser = new H264AnnexBParser();

  const accessUnits = parser.push(
    new Uint8Array([
      0x00, 0x00, 0x01, 0x61, 0x88, 0x84, 0x21, 0x00, 0x00, 0x01, 0x61, 0x88,
      0x84, 0x21, 0x00, 0x00, 0x01, 0x61, 0x88, 0x84, 0x21, 0x00, 0x00, 0x01,
      0x09, 0xf0,
    ]),
  );

  assert.equal(accessUnits.length, 2);
  assert.deepEqual(
    accessUnits.map((accessUnit) => accessUnit.nalTypes),
    [[1], [1]],
  );
});

test('rejects malformed streams without an Annex B start code', () => {
  const parser = new H264AnnexBParser();

  assert.throws(() => {
    parser.push(new Uint8Array([0x67, 0x42, 0x00, 0x1f]));
  }, H264AnnexBParseError);
});
