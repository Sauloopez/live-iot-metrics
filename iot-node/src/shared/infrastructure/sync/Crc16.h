#ifndef CRC16_H
#define CRC16_H

#include <stddef.h>
#include <stdint.h>

// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF). The browser computes the same CRC to drop
// frames damaged on the serial line. Check value: "123456789" -> 0x29B1.
namespace Crc16 {

inline uint16_t compute(const uint8_t* data, size_t len, uint16_t crc = 0xFFFF) {
    for (size_t i = 0; i < len; i++) {
        crc ^= static_cast<uint16_t>(data[i]) << 8;
        for (uint8_t bit = 0; bit < 8; bit++) {
            crc = (crc & 0x8000) ? static_cast<uint16_t>((crc << 1) ^ 0x1021) : static_cast<uint16_t>(crc << 1);
        }
    }
    return crc;
}

} // namespace Crc16

#endif // CRC16_H
