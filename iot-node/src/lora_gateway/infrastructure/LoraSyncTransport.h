#ifndef LORA_SYNC_TRANSPORT_H
#define LORA_SYNC_TRANSPORT_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "../../shared/domain/repositories/IPacketCipher.h"
#include "../../shared/domain/repositories/IRadio.h"
#include "../../shared/domain/repositories/ISyncTransport.h"
#include "../../shared/infrastructure/lora/FrameCounter.h"
#include "../../shared/infrastructure/lora/LoraPacket.h"

// RemoteSync transport of a LoRa field node: each exchange sends the DATA frame to the LoRa
// gateway node and waits for its ACK (docs/tundra/PLAN.md, section 6.3).
//
// The gateway answers with its custody watermark for this node: what it confirms is stored
// there and this node may release it. Without a valid ACK the DATA goes again, with a new
// counter, after a random wait (collisions); after `attempts` tries the exchange fails and
// RemoteSync keeps the data for the next wake up.
//
// Packets that are not the expected ACK (other nodes, replays, bad MIC) are ignored.
class LoraSyncTransport : public ISyncTransport {
public:
    struct Timing {
        uint32_t ackTimeoutMs = 2000;
        uint8_t attempts = 3;
        uint32_t backoffMinMs = 200;
        uint32_t backoffMaxMs = 1500;
    };

    // `wait` sleeps between attempts (delay() on the board)
    LoraSyncTransport(IRadio& radio, IPacketCipher& cipher, FrameCounter& counter, const uint8_t mac[6],
                      void (*wait)(uint32_t ms), Timing timing = Timing())
        : radio(radio), cipher(cipher), counter(counter), wait(wait), timing(timing) {
        memcpy(this->mac, mac, 6);
        random = 0x9E3779B9u;
        for (int i = 0; i < 6; i++) random = random * 31 + mac[i];  // differs between nodes
    }

    bool exchange(const uint8_t* request, size_t requestLen, uint8_t* response, size_t responseCap,
                  size_t* responseLen) override {
        *responseLen = 0;
        // request = MAC · DATA frame; the MAC travels in the packet header
        if (requestLen < 6 || memcmp(request, mac, 6) != 0) return false;
        if (requestLen - 6 > LoraPacket::MAX_PAYLOAD) return false;

        for (uint8_t attempt = 0; attempt < timing.attempts; attempt++) {
            if (attempt > 0) wait(backoff());

            LoraPacket::Header header;
            header.type = LoraPacket::TYPE_DATA;
            memcpy(header.mac, mac, 6);
            if (!counter.next(&header.counter)) return false;

            uint8_t packet[LoraPacket::MAX_SIZE];
            size_t len = LoraPacket::seal(cipher, header, request + 6, requestLen - 6, packet, sizeof(packet));
            if (len == 0 || !radio.send(packet, len)) continue;

            if (awaitAck(header.counter, response, responseCap, responseLen)) return true;
        }
        return false;
    }

private:
    IRadio& radio;
    IPacketCipher& cipher;
    FrameCounter& counter;
    void (*wait)(uint32_t ms);
    Timing timing;
    uint8_t mac[6];
    uint32_t random;

    // Keeps listening for the remaining time when something else arrives first
    bool awaitAck(uint32_t sentCounter, uint8_t* response, size_t responseCap, size_t* responseLen) {
        uint8_t packet[LoraPacket::MAX_SIZE];
        uint8_t payload[LoraPacket::MAX_PAYLOAD];
        for (int received = 0; received < MAX_FOREIGN_PACKETS; received++) {
            size_t len = 0;
            if (!radio.receive(packet, sizeof(packet), &len, timing.ackTimeoutMs)) return false;

            LoraPacket::Header header;
            size_t payloadLen = 0;
            if (LoraPacket::open(cipher, packet, len, &header, payload, sizeof(payload), &payloadLen) !=
                LoraPacket::Status::Ok) {
                continue;
            }
            if (header.type != LoraPacket::TYPE_ACK || header.counter != sentCounter ||
                memcmp(header.mac, mac, 6) != 0 || payloadLen > responseCap) {
                continue;
            }
            memcpy(response, payload, payloadLen);
            *responseLen = payloadLen;
            return true;
        }
        return false;
    }

    static const int MAX_FOREIGN_PACKETS = 8;

    uint32_t backoff() {
        random ^= random << 13;
        random ^= random >> 17;
        random ^= random << 5;
        uint32_t span = timing.backoffMaxMs - timing.backoffMinMs + 1;
        return timing.backoffMinMs + random % span;
    }
};

#endif // LORA_SYNC_TRANSPORT_H
