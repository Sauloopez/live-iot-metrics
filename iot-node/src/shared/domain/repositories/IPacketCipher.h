#ifndef I_PACKET_CIPHER_H
#define I_PACKET_CIPHER_H

#include <stddef.h>
#include <stdint.h>

// Authenticated encryption of radio packets: AES-128-CCM with a 4 byte tag (MIC).
// The ESP32 uses mbedTLS (MbedtlsCcmCipher.h); native tests use a stand-in.
//
// A nonce must never repeat under the same key: LoraPacket builds it from the sender MAC,
// its frame counter and the packet type.
class IPacketCipher {
public:
    static const size_t TAG_SIZE = 4;

    virtual ~IPacketCipher() = default;

    // Encrypts `len` bytes of `plain` into `out` and writes the TAG_SIZE byte tag, which also
    // covers `aad` (sent in clear)
    virtual bool seal(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen, const uint8_t* plain,
                      size_t len, uint8_t* out, uint8_t* tag) = 0;

    // Decrypts into `out`. Returns false if the tag does not match: `out` must then be ignored
    virtual bool open(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen, const uint8_t* cipher,
                      size_t len, const uint8_t* tag, uint8_t* out) = 0;
};

#endif // I_PACKET_CIPHER_H
