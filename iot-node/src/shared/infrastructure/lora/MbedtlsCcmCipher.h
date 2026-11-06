#ifndef MBEDTLS_CCM_CIPHER_H
#define MBEDTLS_CCM_CIPHER_H

#include <mbedtls/ccm.h>
#include <string.h>
#include "../../domain/repositories/IPacketCipher.h"

// AES-128-CCM with the mbedTLS bundled in the ESP32 SDK (hardware AES)
class MbedtlsCcmCipher : public IPacketCipher {
public:
    static const size_t KEY_SIZE = 16;

    MbedtlsCcmCipher() { mbedtls_ccm_init(&ctx); }
    ~MbedtlsCcmCipher() override { mbedtls_ccm_free(&ctx); }

    bool setKey(const uint8_t key[KEY_SIZE]) {
        ready = mbedtls_ccm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, key, KEY_SIZE * 8) == 0;
        return ready;
    }

    bool hasKey() const { return ready; }

    bool seal(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen, const uint8_t* plain,
              size_t len, uint8_t* out, uint8_t* tag) override {
        return ready &&
               mbedtls_ccm_encrypt_and_tag(&ctx, len, nonce, nonceLen, aad, aadLen, plain, out, tag, TAG_SIZE) == 0;
    }

    bool open(const uint8_t* nonce, size_t nonceLen, const uint8_t* aad, size_t aadLen, const uint8_t* cipher,
              size_t len, const uint8_t* tag, uint8_t* out) override {
        return ready &&
               mbedtls_ccm_auth_decrypt(&ctx, len, nonce, nonceLen, aad, aadLen, cipher, out, tag, TAG_SIZE) == 0;
    }

private:
    mbedtls_ccm_context ctx;
    bool ready = false;
};

#endif // MBEDTLS_CCM_CIPHER_H
