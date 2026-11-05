#ifndef REMOTE_SYNC_H
#define REMOTE_SYNC_H

#include <stdint.h>
#include <string.h>
#include "../domain/repositories/IMeasurementStore.h"
#include "../domain/repositories/ISyncTransport.h"
#include "SyncStream.h"

// Pushes stored measurements to the server over a request/response transport (CoAP now, LoRa
// later), one DATA frame per exchange (docs/tundra/PLAN.md, section 6.2).
//
//   request:  MAC (6 bytes) · DATA frame (see SyncStream.h)
//   response: acked_seq u32 · server_time u32   (little endian)
//
// After each answer the confirmed measurements are released. When the server confirms less
// than what was sent (it missed something), the next frame starts again right after its
// watermark, so nothing is lost. A failed exchange stops the session and keeps the data for
// the next one.
class RemoteSync {
public:
    static const size_t RECORDS_PER_FRAME = 16;
    static const size_t MAC_SIZE = 6;
    static const size_t RESPONSE_SIZE = 8;

    struct Result {
        uint32_t frames = 0;
        uint32_t ackedSeq = 0;
        uint32_t serverTime = 0;   // 0 if the server never answered
        bool complete = false;     // nothing left to send
        bool transportError = false;
    };

    explicit RemoteSync(const uint8_t mac[MAC_SIZE]) { memcpy(this->mac, mac, MAC_SIZE); }

    // Sends up to `maxFrames` frames. Call it with the store locked (StorageTask::withStore).
    Result run(IMeasurementStore& store, ISyncTransport& transport, uint32_t maxFrames) {
        Result result;
        result.ackedSeq = store.status().ackedSeq;

        for (uint32_t i = 0; i < maxFrames; i++) {
            SyncStream stream(RECORDS_PER_FRAME);
            stream.start(store, store.status().ackedSeq + 1, RECORDS_PER_FRAME);

            size_t frameLen = 0;
            SyncStream::Output output = stream.next(store, request + MAC_SIZE, sizeof(request) - MAC_SIZE, &frameLen);
            if (output != SyncStream::Output::Data) {
                result.complete = true;
                return result;
            }

            memcpy(request, mac, MAC_SIZE);
            uint8_t response[RESPONSE_SIZE];
            size_t responseLen = 0;
            if (!transport.exchange(request, MAC_SIZE + frameLen, response, sizeof(response), &responseLen) ||
                responseLen < RESPONSE_SIZE) {
                result.transportError = true;
                return result;
            }

            result.frames++;
            result.serverTime = readU32(response + 4);
            uint32_t acked = readU32(response);
            if (acked > result.ackedSeq) {
                store.ack(acked);
                result.ackedSeq = store.status().ackedSeq;
            }
        }
        return result;
    }

    static uint32_t readU32(const uint8_t* p) {
        return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
               (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
    }

private:
    uint8_t mac[MAC_SIZE];
    uint8_t request[MAC_SIZE + SyncStream::HEADER_SIZE + RECORDS_PER_FRAME * MeasurementCodec::MAX_RECORD_SIZE +
                    SyncStream::CRC_SIZE];
};

#endif // REMOTE_SYNC_H
