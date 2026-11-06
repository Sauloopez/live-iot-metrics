#ifndef GATEWAY_CUSTODY_H
#define GATEWAY_CUSTODY_H

#include <stddef.h>
#include <stdint.h>
#include "../../shared/domain/repositories/IPacketCipher.h"
#include "../../shared/infrastructure/lora/LoraPacket.h"
#include "../../shared/infrastructure/lora/ReplayGuard.h"
#include "../../shared/infrastructure/storage/MeasurementCodec.h"
#include "../../shared/infrastructure/sync/Crc16.h"
#include "../../shared/usecases/SyncStream.h"
#include "../infrastructure/OriginStores.h"

// LoRa gateway node, receiving side: takes custody of the measurements of its field nodes
// (docs/tundra/PLAN.md, decision D3). For every valid DATA packet it stores the new
// measurements in the origin's store, with their original seq, and answers an ACK with the
// custody watermark (last seq stored) and its time. The field node releases what the ACK
// confirms, even if the gateway has no network: GatewayForwarder sends it on later.
//
// Only contiguous measurements are kept: resends (seq already stored) are skipped and a gap
// stops the frame, so the watermark never jumps over missing data. The first frame of a new
// origin sets where its numbering starts.
//
// Invalid packets get no answer (bad MIC, replayed counter, unknown version...).
class GatewayCustody {
public:
    enum class Outcome { Stored, BadPacket, NotData, Replay, BadFrame, NoRoom };

    struct Result {
        Outcome outcome = Outcome::BadPacket;
        uint32_t stored = 0;      // new measurements kept from this packet
        uint32_t custodySeq = 0;  // watermark sent in the ACK
    };

    static const size_t ACK_PAYLOAD_SIZE = 8;

    // `epoch`: boot count of the gateway, saved before receiving anything (see LoraPacket.h)
    GatewayCustody(IPacketCipher& cipher, OriginStores& origins, uint16_t epoch)
        : cipher(cipher), origins(origins), epoch(epoch) {}

    // Handles one received packet. Returns the length of the ACK written to `ack`, or 0 when
    // nothing must be sent back.
    size_t handle(const uint8_t* packet, size_t len, uint32_t now, uint8_t* ack, size_t cap, Result* result = nullptr) {
        Result local;
        Result& r = result ? *result : local;
        r = Result();

        LoraPacket::Header header;
        uint8_t frame[LoraPacket::MAX_PAYLOAD];
        size_t frameLen = 0;
        if (LoraPacket::open(cipher, packet, len, &header, frame, sizeof(frame), &frameLen) !=
            LoraPacket::Status::Ok) {
            return 0;
        }
        if (header.type != LoraPacket::TYPE_DATA) {
            r.outcome = Outcome::NotData;
            return 0;
        }
        if (!validFrame(frame, frameLen)) {
            r.outcome = Outcome::BadFrame;
            return 0;
        }
        OriginStores::Origin* origin = origins.get(header.mac);
        if (!origin) {
            r.outcome = Outcome::NoRoom;
            return 0;
        }
        // Checked last: a packet that is dropped for another reason does not use up its counter
        if (!guard.accept(header.mac, header.counter)) {
            r.outcome = Outcome::Replay;
            return 0;
        }

        r.stored = store(*origin->store, frame, frameLen);
        r.custodySeq = origin->store->status().nextSeq - 1;
        r.outcome = Outcome::Stored;

        uint8_t payload[ACK_PAYLOAD_SIZE];
        LoraPacket::writeU32(payload, r.custodySeq);
        LoraPacket::writeU32(payload + 4, now);
        LoraPacket::Header ackHeader = header;
        ackHeader.type = LoraPacket::TYPE_ACK;
        ackHeader.epoch = epoch;
        return LoraPacket::seal(cipher, ackHeader, payload, sizeof(payload), ack, cap);
    }

private:
    IPacketCipher& cipher;
    OriginStores& origins;
    uint16_t epoch;
    ReplayGuard guard;

    static const size_t RECORDS_OFFSET = SyncStream::HEADER_SIZE;

    static bool validFrame(const uint8_t* frame, size_t len) {
        if (len < SyncStream::HEADER_SIZE + SyncStream::CRC_SIZE || frame[0] != SyncStream::FRAME_DATA) return false;
        uint16_t crc = frame[len - 2] | (frame[len - 1] << 8);
        return Crc16::compute(frame, len - 2) == crc;
    }

    static uint32_t store(SegmentedMeasurementStore& store, const uint8_t* frame, size_t len) {
        uint8_t count = frame[7];
        uint32_t firstSeq = LoraPacket::readU32(frame + 3);
        if (count > 0 && firstSeq > 1) store.startAfter(firstSeq - 1);  // only does something the first time

        const uint8_t* p = frame + RECORDS_OFFSET;
        const uint8_t* end = frame + len - SyncStream::CRC_SIZE;
        uint32_t stored = 0;
        for (uint8_t i = 0; i < count && p < end; i++) {
            Measurement m;
            size_t used = 0;
            if (MeasurementCodec::decode(p, end - p, &m, &used) != MeasurementCodec::DecodeResult::Ok) break;
            p += used;

            uint32_t expected = store.status().nextSeq;
            if (m.seq < expected) continue;  // already in custody
            if (m.seq > expected) break;     // gap: wait for the missing ones
            if (!store.record(m.ts, m.sensorId, m.value)) break;
            stored++;
        }
        return stored;
    }
};

#endif // GATEWAY_CUSTODY_H
