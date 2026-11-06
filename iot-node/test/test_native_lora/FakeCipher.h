#ifndef FAKE_CIPHER_H
#define FAKE_CIPHER_H

#include <string.h>
#include "../../src/shared/domain/repositories/IPacketCipher.h"

// Stand-in for AES-CCM in native tests (the PC has no mbedTLS headers). NOT secure: it only
// behaves like an AEAD so the packet logic can be tested: the output depends on the key and
// nonce, and the tag changes if the key, nonce, clear header or ciphertext change. The real
// cipher is checked on the board against NIST vectors (test_lora_device).
class FakeCipher : public IPacketCipher {
public:
    explicit FakeCipher(uint8_t keySeed = 0x5A) {
        for (size_t i = 0; i < sizeof(key); i++) key[i] = keySeed + i;
    }

    bool seal(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen, const uint8_t* plain,
              size_t len, uint8_t* out, uint8_t* tag) override {
        for (size_t i = 0; i < len; i++) out[i] = plain[i] ^ keystream(nonce, nonceLen, i);
        writeTag(nonce, nonceLen, aad, aadLen, out, len, tag);
        return true;
    }

    bool open(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen, const uint8_t* cipher,
              size_t len, const uint8_t* tag, uint8_t* out) override {
        uint8_t expected[TAG_SIZE];
        writeTag(nonce, nonceLen, aad, aadLen, cipher, len, expected);
        if (memcmp(expected, tag, TAG_SIZE) != 0) return false;
        for (size_t i = 0; i < len; i++) out[i] = cipher[i] ^ keystream(nonce, nonceLen, i);
        return true;
    }

private:
    uint8_t key[16];

    static uint32_t fnv(uint32_t h, const uint8_t* data, size_t len) {
        for (size_t i = 0; i < len; i++) h = (h ^ data[i]) * 16777619u;
        return h;
    }

    uint8_t keystream(const uint8_t* nonce, size_t nonceLen, size_t i) const {
        uint8_t index[4] = {static_cast<uint8_t>(i), static_cast<uint8_t>(i >> 8), 0, 0};
        uint32_t h = fnv(fnv(fnv(2166136261u, key, sizeof(key)), nonce, nonceLen), index, sizeof(index));
        return h >> 24;
    }

    void writeTag(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen, const uint8_t* cipher,
                  size_t len, uint8_t* tag) const {
        uint32_t h = fnv(fnv(fnv(fnv(2166136261u, key, sizeof(key)), nonce, nonceLen), aad, aadLen), cipher, len);
        for (size_t i = 0; i < TAG_SIZE; i++) tag[i] = (h >> (8 * i)) & 0xFF;
    }
};

#endif // FAKE_CIPHER_H
