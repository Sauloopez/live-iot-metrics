#ifndef LORA_PACKET_H
#define LORA_PACKET_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "../../domain/repositories/IPacketCipher.h"

// LoRa P2P packet between a field node and its LoRa gateway node (docs/tundra/PLAN.md,
// section 6.3). Little endian:
//
//   version  u8     VERSION
//   type     u8     TYPE_DATA (field → gateway) or TYPE_ACK (gateway → field)
//   mac      6      field node MAC, in both directions
//   counter  u32    field node frame counter; an ACK repeats the counter of its DATA
//   epoch    u16    0 in DATA; in an ACK, the gateway boot count
//   payload  ...    encrypted with AES-128-CCM
//   mic      4      CCM tag over the clear header (AAD) and the payload
//
// Nonce (13 bytes): mac · counter · type · epoch. A nonce must never repeat:
//   * DATA: the field node never reuses a counter (FrameCounter);
//   * ACK: the gateway answers each DATA counter once per boot (ReplayGuard) and the epoch
//     changes on every boot, so forgetting the guard after a reboot does not repeat nonces.
//
// Payloads: DATA carries a DATA frame (SyncStream.h); ACK carries acked_seq u32 · time u32.
class LoraPacket {
public:
    static const uint8_t VERSION = 1;
    static const uint8_t TYPE_DATA = 0x01;
    static const uint8_t TYPE_ACK = 0x02;
    static const size_t MAC_SIZE = 6;
    static const size_t HEADER_SIZE = 14;
    static const size_t MIC_SIZE = IPacketCipher::TAG_SIZE;
    static const size_t OVERHEAD = HEADER_SIZE + MIC_SIZE;
    static const size_t MAX_SIZE = 255;  // largest LoRa packet
    static const size_t MAX_PAYLOAD = MAX_SIZE - OVERHEAD;
    static const size_t NONCE_SIZE = 13;

    struct Header {
        uint8_t type = 0;
        uint8_t mac[MAC_SIZE] = {0};
        uint32_t counter = 0;
        uint16_t epoch = 0;
    };

    enum class Status { Ok, Malformed, UnknownVersion, BadMic };

    // Builds the packet into `out`. Returns its length, or 0 if it does not fit
    static size_t seal(IPacketCipher& cipher, const Header& header, const uint8_t* payload, size_t len, uint8_t* out,
                       size_t cap) {
        if (len > MAX_PAYLOAD || cap < OVERHEAD + len) return 0;
        writeHeader(header, out);
        uint8_t nonce[NONCE_SIZE];
        buildNonce(header, nonce);
        if (!cipher.seal(nonce, NONCE_SIZE, out, HEADER_SIZE, payload, len, out + HEADER_SIZE,
                         out + HEADER_SIZE + len)) {
            return 0;
        }
        return OVERHEAD + len;
    }

    // Checks and decrypts a received packet. The payload is only valid when the result is Ok
    static Status open(IPacketCipher& cipher, const uint8_t* packet, size_t len, Header* header, uint8_t* payload,
                       size_t cap, size_t* payloadLen) {
        *payloadLen = 0;
        if (len < OVERHEAD || len > MAX_SIZE) return Status::Malformed;
        if (packet[0] != VERSION) return Status::UnknownVersion;

        size_t bodyLen = len - OVERHEAD;
        if (cap < bodyLen) return Status::Malformed;

        Header h;
        h.type = packet[1];
        memcpy(h.mac, packet + 2, MAC_SIZE);
        h.counter = readU32(packet + 8);
        h.epoch = packet[12] | (packet[13] << 8);

        uint8_t nonce[NONCE_SIZE];
        buildNonce(h, nonce);
        if (!cipher.open(nonce, NONCE_SIZE, packet, HEADER_SIZE, packet + HEADER_SIZE, bodyLen,
                         packet + HEADER_SIZE + bodyLen, payload)) {
            return Status::BadMic;
        }
        *header = h;
        *payloadLen = bodyLen;
        return Status::Ok;
    }

    static void buildNonce(const Header& header, uint8_t nonce[NONCE_SIZE]) {
        memcpy(nonce, header.mac, MAC_SIZE);
        writeU32(nonce + 6, header.counter);
        nonce[10] = header.type;
        nonce[11] = header.epoch & 0xFF;
        nonce[12] = header.epoch >> 8;
    }

    static uint32_t readU32(const uint8_t* p) {
        return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
               (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
    }

    static void writeU32(uint8_t* p, uint32_t v) {
        for (int i = 0; i < 4; i++) p[i] = (v >> (8 * i)) & 0xFF;
    }

private:
    static void writeHeader(const Header& header, uint8_t* out) {
        out[0] = VERSION;
        out[1] = header.type;
        memcpy(out + 2, header.mac, MAC_SIZE);
        writeU32(out + 8, header.counter);
        out[12] = header.epoch & 0xFF;
        out[13] = header.epoch >> 8;
    }
};

#endif // LORA_PACKET_H
