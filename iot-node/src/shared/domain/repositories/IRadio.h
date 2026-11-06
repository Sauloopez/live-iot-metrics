#ifndef I_RADIO_H
#define I_RADIO_H

#include <stddef.h>
#include <stdint.h>

// Half duplex packet radio (LoRa P2P). RadioLib on the board, a simulated channel in tests.
class IRadio {
public:
    virtual ~IRadio() = default;

    // Transmits one packet; returns once it left the antenna
    virtual bool send(const uint8_t* packet, size_t len) = 0;

    // Waits up to `timeoutMs` for one packet. False on timeout or reception error
    virtual bool receive(uint8_t* packet, size_t cap, size_t* len, uint32_t timeoutMs) = 0;
};

#endif // I_RADIO_H
