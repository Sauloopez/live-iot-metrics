// Splits the bytes coming from the node into JSON lines and binary DATA frames.
//
// Frames travel as 0x00 · COBS(frame) · 0x00 and lines end with "\n"; JSON lines never contain
// 0x00, so a 0x00 always starts or ends a frame (docs/tundra/SERIAL_API.md, `sync`).
// Mirrors iot-node/src/shared/infrastructure/sync/{Cobs,Crc16}.h and usecases/SyncStream.h.

export const FRAME_DATA = 0x01;
const HEADER_SIZE = 8;
const CRC_SIZE = 2;

export class FrameReader {
  constructor({ onLine, onFrame }) {
    this.onLine = onLine;
    this.onFrame = onFrame;
    this.inFrame = false;
    this.frameBytes = [];
    this.lineBytes = [];
    this.textDecoder = new TextDecoder();
  }

  push(chunk) {
    for (const byte of chunk) {
      if (this.inFrame) {
        if (byte === 0x00) {
          this.inFrame = false;
          if (this.frameBytes.length > 0) this.emitFrame(Uint8Array.from(this.frameBytes));
          this.frameBytes = [];
        } else {
          this.frameBytes.push(byte);
        }
      } else if (byte === 0x00) {
        this.inFrame = true;
        this.frameBytes = [];
      } else if (byte === 0x0a) {
        this.onLine(this.textDecoder.decode(Uint8Array.from(this.lineBytes)).trim());
        this.lineBytes = [];
      } else {
        this.lineBytes.push(byte);
      }
    }
  }

  emitFrame(encoded) {
    const frame = cobsDecode(encoded);
    this.onFrame(frame ? parseDataFrame(frame) : { valid: false, reason: "invalid COBS" });
  }
}

export function cobsDecode(input) {
  const out = [];
  let i = 0;
  while (i < input.length) {
    const code = input[i++];
    if (code === 0 || i + code - 1 > input.length) return null;
    for (let j = 1; j < code; j++) out.push(input[i++]);
    if (code !== 0xff && i < input.length) out.push(0);
  }
  return Uint8Array.from(out);
}

// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF)
export function crc16(bytes, length = bytes.length) {
  let crc = 0xffff;
  for (let i = 0; i < length; i++) {
    crc ^= bytes[i] << 8;
    for (let bit = 0; bit < 8; bit++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc;
}

// type u8 · frame_no u16 · first_seq u32 · count u8 · CBOR records · crc u16 (little endian)
export function parseDataFrame(frame) {
  if (frame.length < HEADER_SIZE + CRC_SIZE) return { valid: false, reason: "short frame" };

  const view = new DataView(frame.buffer, frame.byteOffset, frame.byteLength);
  const crc = view.getUint16(frame.length - CRC_SIZE, true);
  if (crc16(frame, frame.length - CRC_SIZE) !== crc) return { valid: false, reason: "bad CRC" };
  if (frame[0] !== FRAME_DATA) return { valid: false, reason: "unknown frame type" };

  return {
    valid: true,
    frameNo: view.getUint16(1, true),
    firstSeq: view.getUint32(3, true),
    count: frame[7],
    records: frame.slice(HEADER_SIZE, frame.length - CRC_SIZE),
  };
}
