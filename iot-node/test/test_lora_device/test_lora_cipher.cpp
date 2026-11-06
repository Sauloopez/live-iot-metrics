// On-board tests of AES-128-CCM (mbedTLS) against known vectors: the native tests use a
// stand-in cipher, this checks the real one. `pio test -e coap -f test_lora_device`
#include <Arduino.h>
#include <unity.h>
#include "../../src/shared/infrastructure/lora/LoraPacket.h"
#include "../../src/shared/infrastructure/lora/MbedtlsCcmCipher.h"

void setUp(void) {}
void tearDown(void) {}

// NIST SP 800-38C, appendix C, example 1 (4 byte tag, like the LoRa MIC)
void test_nist_vector(void) {
    const uint8_t key[16] = {0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47,
                             0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f};
    const uint8_t nonce[7] = {0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16};
    const uint8_t aad[8] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07};
    const uint8_t plain[4] = {0x20, 0x21, 0x22, 0x23};
    const uint8_t expectedCipher[4] = {0x71, 0x62, 0x01, 0x5b};
    const uint8_t expectedTag[4] = {0x4d, 0xac, 0x25, 0x5d};

    MbedtlsCcmCipher cipher;
    TEST_ASSERT_TRUE(cipher.setKey(key));
    uint8_t out[4], tag[4];
    TEST_ASSERT_TRUE(cipher.seal(nonce, sizeof(nonce), aad, sizeof(aad), plain, sizeof(plain), out, tag));
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expectedCipher, out, 4);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expectedTag, tag, 4);

    uint8_t back[4];
    TEST_ASSERT_TRUE(cipher.open(nonce, sizeof(nonce), aad, sizeof(aad), out, sizeof(out), tag, back));
    TEST_ASSERT_EQUAL_UINT8_ARRAY(plain, back, 4);
    tag[0] ^= 1;
    TEST_ASSERT_FALSE(cipher.open(nonce, sizeof(nonce), aad, sizeof(aad), out, sizeof(out), tag, back));
}

// Full packet, expected bytes computed independently (Python `cryptography`, AESCCM)
void test_packet_vector(void) {
    uint8_t key[16];
    for (int i = 0; i < 16; i++) key[i] = i;
    MbedtlsCcmCipher cipher;
    TEST_ASSERT_TRUE(cipher.setKey(key));

    LoraPacket::Header header;
    header.type = LoraPacket::TYPE_ACK;
    const uint8_t mac[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0xe1};
    memcpy(header.mac, mac, 6);
    header.counter = 1;
    header.epoch = 0x0102;
    const uint8_t payload[2] = {0x01, 0xff};

    uint8_t packet[LoraPacket::MAX_SIZE];
    size_t len = LoraPacket::seal(cipher, header, payload, sizeof(payload), packet, sizeof(packet));
    const uint8_t expected[] = {0x01, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00, 0xe1, 0x01, 0x00,
                                0x00, 0x00, 0x02, 0x01, 0x3f, 0x24, 0x0b, 0xf2, 0x6a, 0x26};
    TEST_ASSERT_EQUAL(sizeof(expected), len);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, packet, len);

    LoraPacket::Header received;
    uint8_t out[LoraPacket::MAX_PAYLOAD];
    size_t outLen = 0;
    TEST_ASSERT_TRUE(LoraPacket::open(cipher, packet, len, &received, out, sizeof(out), &outLen) ==
                     LoraPacket::Status::Ok);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(payload, out, sizeof(payload));
}

void test_without_key_nothing_is_sealed(void) {
    MbedtlsCcmCipher cipher;
    LoraPacket::Header header;
    uint8_t payload[1] = {0}, packet[LoraPacket::MAX_SIZE];
    TEST_ASSERT_EQUAL(0, LoraPacket::seal(cipher, header, payload, 1, packet, sizeof(packet)));
}

void setup() {
    delay(2000);
    UNITY_BEGIN();
    RUN_TEST(test_nist_vector);
    RUN_TEST(test_packet_vector);
    RUN_TEST(test_without_key_nothing_is_sealed);
    UNITY_END();
}

void loop() {}
