#ifndef REMOTE_SYNC_H
#define REMOTE_SYNC_H

#include <stdint.h>
#include <string.h>
#include "../domain/repositories/IMeasurementStore.h"
#include "../domain/repositories/ISyncTransport.h"
#include "../infrastructure/sync/Crc16.h"
#include "SyncStream.h"

// Pushes stored measurements to the server over a request/response transport (CoAP now, LoRa
// later), one DATA frame per exchange (docs/tundra/PLAN.md, section 6.2).
//
//   request:  MAC (6 bytes) · DATA frame (see SyncStream.h)
//   response: acked_seq u32 · server_time u32   (little endian)
//
// The server processes frames in the background, so `acked_seq` is its last *processed*
// watermark: the frame just sent is confirmed in a later exchange. Hence:
//
//   * frames are sent in sequence from a cursor, not from the watermark, so waiting for a
//     confirmation never resends the same frame;
//   * at most WINDOW measurements stay unconfirmed; with the window full (or nothing new to
//     send) an empty frame asks for the watermark. If it did not move, the server is probably
//     still processing: the session ends and waits. Only after STALL_LIMIT such queries in a
//     row the server is assumed to have lost data and the cursor goes back to the watermark
//     (resends are ignored by the server);
//   * the store only releases what the server confirmed. A failed exchange stops the session
//     and keeps everything for the next one.
class RemoteSync {
public:
    static const size_t RECORDS_PER_FRAME = 16;  // largest frame; LoRa uses LORA_RECORDS_PER_FRAME
    static const size_t LORA_RECORDS_PER_FRAME = 8;  // fits one LoRa packet
    static const uint32_t WINDOW = 64;
    static const uint32_t STALL_LIMIT = 3;
    static const size_t MAC_SIZE = 6;
    static const size_t RESPONSE_SIZE = 8;

    struct Result {
        uint32_t frames = 0;        // exchanges done (data and watermark queries)
        uint32_t ackedSeq = 0;
        uint32_t serverTime = 0;    // 0 if the server never answered
        bool complete = false;      // everything stored is confirmed
        bool transportError = false;
    };

    explicit RemoteSync(const uint8_t mac[MAC_SIZE], size_t recordsPerFrame = RECORDS_PER_FRAME)
        : perFrame(recordsPerFrame == 0 || recordsPerFrame > RECORDS_PER_FRAME ? RECORDS_PER_FRAME : recordsPerFrame) {
        memcpy(this->mac, mac, MAC_SIZE);
    }

    // Runs up to `maxExchanges` exchanges. Call it with the store locked (StorageTask::withStore).
    // Keep the same instance between sessions: it remembers how far it sent.
    Result run(IMeasurementStore& store, ISyncTransport& transport, uint32_t maxExchanges) {
        Result result;
        result.ackedSeq = store.status().ackedSeq;
        if (cursor <= result.ackedSeq) cursor = result.ackedSeq + 1;

        for (uint32_t i = 0; i < maxExchanges; i++) {
            uint32_t lastStored = store.status().nextSeq - 1;
            uint32_t acked = store.status().ackedSeq;
            if (acked >= lastStored) {
                result.complete = true;
                return result;
            }

            bool windowFull = cursor - 1 - acked >= WINDOW;
            bool nothingNew = cursor > lastStored;
            size_t frameLen = (windowFull || nothingNew) ? buildQuery(cursor) : buildData(store);

            if (!exchange(store, transport, frameLen, result)) return result;

            if (windowFull || nothingNew) {
                if (result.ackedSeq > acked) {
                    stalledQueries = 0;
                    continue;
                }
                // The watermark did not move: wait for the server, and after several sessions
                // without progress assume the data past the watermark was lost
                if (++stalledQueries >= STALL_LIMIT) {
                    cursor = acked + 1;
                    stalledQueries = 0;
                }
                return result;
            }
            stalledQueries = 0;
        }
        return result;
    }

    uint32_t nextToSend() const { return cursor; }

    static uint32_t readU32(const uint8_t* p) {
        return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
               (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
    }

private:
    uint8_t mac[MAC_SIZE];
    uint8_t request[MAC_SIZE + SyncStream::HEADER_SIZE + RECORDS_PER_FRAME * MeasurementCodec::MAX_RECORD_SIZE +
                    SyncStream::CRC_SIZE];
    size_t perFrame;
    uint32_t cursor = 1;
    uint32_t stalledQueries = 0;

    size_t buildData(IMeasurementStore& store) {
        SyncStream stream(perFrame);
        stream.start(store, cursor, perFrame);
        size_t len = 0;
        uint32_t last = 0;
        if (stream.next(store, request + MAC_SIZE, sizeof(request) - MAC_SIZE, &len, &last) !=
            SyncStream::Output::Data) {
            return buildQuery(cursor);
        }
        cursor = last + 1;
        return len;
    }

    // DATA frame with no measurements: only asks for the watermark
    size_t buildQuery(uint32_t firstSeq) {
        uint8_t* f = request + MAC_SIZE;
        f[0] = SyncStream::FRAME_DATA;
        f[1] = 0;
        f[2] = 0;
        for (int i = 0; i < 4; i++) f[3 + i] = (firstSeq >> (8 * i)) & 0xFF;
        f[7] = 0;
        uint16_t crc = Crc16::compute(f, SyncStream::HEADER_SIZE);
        f[8] = crc & 0xFF;
        f[9] = crc >> 8;
        return SyncStream::HEADER_SIZE + SyncStream::CRC_SIZE;
    }

    bool exchange(IMeasurementStore& store, ISyncTransport& transport, size_t frameLen, Result& result) {
        memcpy(request, mac, MAC_SIZE);
        uint8_t response[RESPONSE_SIZE];
        size_t responseLen = 0;
        if (!transport.exchange(request, MAC_SIZE + frameLen, response, sizeof(response), &responseLen) ||
            responseLen < RESPONSE_SIZE) {
            result.transportError = true;
            cursor = store.status().ackedSeq + 1;  // the frame may be lost: resend from the watermark
            return false;
        }

        result.frames++;
        result.serverTime = readU32(response + 4);
        uint32_t acked = readU32(response);
        if (acked > store.status().ackedSeq) store.ack(acked);
        result.ackedSeq = store.status().ackedSeq;
        return true;
    }
};

#endif // REMOTE_SYNC_H
