#ifndef SYNC_STREAM_H
#define SYNC_STREAM_H

#include <algorithm>
#include <stddef.h>
#include <stdint.h>
#include "../domain/repositories/IMeasurementStore.h"
#include "../infrastructure/storage/MeasurementCodec.h"
#include "../infrastructure/sync/Crc16.h"

// Streams stored measurements to the server with credit based flow control
// (docs/tundra/PLAN.md, section 6.1).
//
// The receiver grants credits ("send up to N more measurements") and renews them as the
// server confirms, so neither side buffers more than the credit. Each call to next() builds
// at most one frame and reads the store with its fixed window: memory stays constant no matter
// how much data is pending.
//
// DATA frame (little endian), before COBS encoding:
//   type      u8    0x01
//   frame_no  u16   increases by one per frame, starting at 0 on every stream
//   first_seq u32   seq of the first measurement in the frame
//   count     u8    number of measurements
//   records   ...   `count` CBOR measurements [seq, ts, sensorId, value] back to back
//   crc       u16   CRC-16/CCITT-FALSE of every previous byte
class SyncStream {
public:
    static const uint8_t FRAME_DATA = 0x01;
    static const size_t HEADER_SIZE = 8;
    static const size_t CRC_SIZE = 2;

    enum class Output { None, Data, End };

    explicit SyncStream(size_t maxRecordsPerFrame = 16) : maxPerFrame(maxRecordsPerFrame) {}

    static size_t maxFrameSize(size_t recordsPerFrame) {
        return HEADER_SIZE + recordsPerFrame * MeasurementCodec::MAX_RECORD_SIZE + CRC_SIZE;
    }

    void start(const IMeasurementStore& store, uint32_t fromSeq, uint32_t credit) {
        StoreStatus status = store.status();
        cursor = std::max(fromSeq, status.ackedSeq + 1);
        credits = credit;
        frameNo = 0;
        active = true;
    }

    void addCredit(uint32_t credit) { credits += credit; }
    void stop() { active = false; }
    bool isActive() const { return active; }
    uint32_t credit() const { return credits; }

    // Builds the next frame into `out`. Returns None while waiting for credit (or when not
    // streaming), Data with `*len` bytes, or End once everything pending was sent.
    Output next(IMeasurementStore& store, uint8_t* out, size_t cap, size_t* len, uint32_t* lastSeq = nullptr) {
        *len = 0;
        if (!active || credits == 0) return Output::None;

        size_t limit = std::min<size_t>(maxPerFrame, credits);
        if (cap < maxFrameSize(limit)) return Output::None;

        size_t pos = HEADER_SIZE;
        uint32_t first = 0;
        uint32_t last = 0;
        uint8_t count = 0;

        store.readFrom(cursor, limit, [&](const Measurement& m) {
            size_t used = MeasurementCodec::encode(m, out + pos, cap - pos - CRC_SIZE);
            if (used == 0) return false;
            if (count == 0) first = m.seq;
            last = m.seq;
            pos += used;
            count++;
            return true;
        });

        if (count == 0) {
            active = false;
            if (lastSeq) *lastSeq = store.status().nextSeq - 1;
            return Output::End;
        }

        out[0] = FRAME_DATA;
        writeU16(out + 1, frameNo);
        writeU32(out + 3, first);
        out[7] = count;
        writeU16(out + pos, Crc16::compute(out, pos));
        *len = pos + CRC_SIZE;

        cursor = last + 1;
        credits -= count;
        frameNo++;
        if (lastSeq) *lastSeq = last;
        return Output::Data;
    }

private:
    size_t maxPerFrame;
    uint32_t cursor = 1;
    uint32_t credits = 0;
    uint16_t frameNo = 0;
    bool active = false;

    static void writeU16(uint8_t* p, uint16_t v) {
        p[0] = v & 0xFF;
        p[1] = v >> 8;
    }

    static void writeU32(uint8_t* p, uint32_t v) {
        for (int i = 0; i < 4; i++) p[i] = (v >> (8 * i)) & 0xFF;
    }
};

#endif // SYNC_STREAM_H
