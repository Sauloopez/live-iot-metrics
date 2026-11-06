// Native (PC) tests for the LoRa P2P packet: format, authentication, anti-replay and the frame
// counter that survives power loss.
#include <unity.h>
#include <vector>
#include "FakeCipher.h"
#include "../../src/shared/infrastructure/lora/FrameCounter.h"
#include "../../src/shared/infrastructure/lora/LoraPacket.h"
#include "../../src/shared/infrastructure/lora/ReplayGuard.h"
#include "../../src/shared/infrastructure/storage/MeasurementCodec.h"
#include "../../src/shared/usecases/SyncStream.h"

static const uint8_t MAC_A[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0xA1};
static const uint8_t MAC_B[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0xB2};

void setUp(void) {}
void tearDown(void) {}

static LoraPacket::Header header(uint8_t type, const uint8_t mac[6], uint32_t counter, uint16_t epoch = 0) {
    LoraPacket::Header h;
    h.type = type;
    memcpy(h.mac, mac, 6);
    h.counter = counter;
    h.epoch = epoch;
    return h;
}

static std::vector<uint8_t> seal(IPacketCipher& cipher, const LoraPacket::Header& h, const std::vector<uint8_t>& payload) {
    std::vector<uint8_t> packet(LoraPacket::MAX_SIZE);
    size_t len = LoraPacket::seal(cipher, h, payload.data(), payload.size(), packet.data(), packet.size());
    packet.resize(len);
    return packet;
}

static LoraPacket::Status open(IPacketCipher& cipher, const std::vector<uint8_t>& packet, LoraPacket::Header* h,
                               std::vector<uint8_t>* payload) {
    payload->assign(LoraPacket::MAX_PAYLOAD, 0);
    size_t len = 0;
    LoraPacket::Status status = LoraPacket::open(cipher, packet.data(), packet.size(), h, payload->data(),
                                                 payload->size(), &len);
    payload->resize(len);
    return status;
}

// --- Packet ---

void test_round_trip(void) {
    FakeCipher cipher;
    std::vector<uint8_t> payload = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    std::vector<uint8_t> packet = seal(cipher, header(LoraPacket::TYPE_ACK, MAC_A, 42, 7), payload);
    TEST_ASSERT_EQUAL(LoraPacket::OVERHEAD + payload.size(), packet.size());

    LoraPacket::Header h;
    std::vector<uint8_t> out;
    TEST_ASSERT_TRUE(open(cipher, packet, &h, &out) == LoraPacket::Status::Ok);
    TEST_ASSERT_EQUAL_UINT8(LoraPacket::TYPE_ACK, h.type);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(MAC_A, h.mac, 6);
    TEST_ASSERT_EQUAL_UINT32(42, h.counter);
    TEST_ASSERT_EQUAL_UINT16(7, h.epoch);
    TEST_ASSERT_TRUE(out == payload);
}

void test_header_is_clear_and_payload_is_not(void) {
    FakeCipher cipher;
    std::vector<uint8_t> payload(20, 0xAB);
    std::vector<uint8_t> packet = seal(cipher, header(LoraPacket::TYPE_DATA, MAC_A, 0x01020304, 0x0506), payload);

    const uint8_t expected[] = {LoraPacket::VERSION, LoraPacket::TYPE_DATA, 0x02, 0x00, 0x00, 0x00, 0x00,
                                0xA1,                0x04,                  0x03, 0x02, 0x01, 0x06, 0x05};
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, packet.data(), LoraPacket::HEADER_SIZE);
    TEST_ASSERT_FALSE(std::vector<uint8_t>(packet.begin() + 14, packet.begin() + 34) == payload);
}

void test_nonce_layout(void) {
    uint8_t nonce[LoraPacket::NONCE_SIZE];
    LoraPacket::buildNonce(header(LoraPacket::TYPE_ACK, MAC_A, 0x01020304, 0x0506), nonce);
    const uint8_t expected[] = {0x02, 0x00, 0x00, 0x00, 0x00, 0xA1, 0x04, 0x03, 0x02, 0x01, 0x02, 0x06, 0x05};
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, nonce, LoraPacket::NONCE_SIZE);
}

void test_data_and_ack_with_same_counter_use_different_nonces(void) {
    FakeCipher cipher;
    std::vector<uint8_t> payload(8, 0);
    std::vector<uint8_t> data = seal(cipher, header(LoraPacket::TYPE_DATA, MAC_A, 7), payload);
    std::vector<uint8_t> ack = seal(cipher, header(LoraPacket::TYPE_ACK, MAC_A, 7), payload);
    TEST_ASSERT_FALSE(std::equal(data.begin() + 14, data.end(), ack.begin() + 14));

    // The same ACK after a gateway reboot (new epoch) is encrypted differently
    std::vector<uint8_t> ackAfterReboot = seal(cipher, header(LoraPacket::TYPE_ACK, MAC_A, 7, 1), payload);
    TEST_ASSERT_FALSE(std::equal(ack.begin() + 14, ack.end(), ackAfterReboot.begin() + 14));
}

void test_tampering_is_detected(void) {
    FakeCipher cipher;
    std::vector<uint8_t> packet = seal(cipher, header(LoraPacket::TYPE_DATA, MAC_A, 9), {10, 20, 30, 40});
    LoraPacket::Header h;
    std::vector<uint8_t> out;

    // Every byte after the version: type, MAC, counter, payload and MIC
    for (size_t i = 1; i < packet.size(); i++) {
        std::vector<uint8_t> tampered = packet;
        tampered[i] ^= 0x01;
        TEST_ASSERT_TRUE_MESSAGE(open(cipher, tampered, &h, &out) == LoraPacket::Status::BadMic, "byte not covered");
        TEST_ASSERT_EQUAL(0, out.size());
    }
}

void test_wrong_key_is_rejected(void) {
    FakeCipher sender(0x11), receiver(0x22);
    std::vector<uint8_t> packet = seal(sender, header(LoraPacket::TYPE_DATA, MAC_A, 1), {1, 2, 3});
    LoraPacket::Header h;
    std::vector<uint8_t> out;
    TEST_ASSERT_TRUE(open(receiver, packet, &h, &out) == LoraPacket::Status::BadMic);
}

void test_malformed_and_unknown_version(void) {
    FakeCipher cipher;
    LoraPacket::Header h;
    std::vector<uint8_t> out;
    TEST_ASSERT_TRUE(open(cipher, std::vector<uint8_t>(LoraPacket::OVERHEAD - 1, 1), &h, &out) ==
                     LoraPacket::Status::Malformed);
    TEST_ASSERT_TRUE(open(cipher, std::vector<uint8_t>(LoraPacket::MAX_SIZE + 1, 1), &h, &out) ==
                     LoraPacket::Status::Malformed);

    std::vector<uint8_t> packet = seal(cipher, header(LoraPacket::TYPE_DATA, MAC_A, 1), {1});
    packet[0] = LoraPacket::VERSION + 1;
    TEST_ASSERT_TRUE(open(cipher, packet, &h, &out) == LoraPacket::Status::UnknownVersion);
}

void test_size_limits(void) {
    FakeCipher cipher;
    uint8_t out[LoraPacket::MAX_SIZE];
    std::vector<uint8_t> payload(LoraPacket::MAX_PAYLOAD + 1, 0);
    LoraPacket::Header h = header(LoraPacket::TYPE_DATA, MAC_A, 1);

    TEST_ASSERT_EQUAL(0, LoraPacket::seal(cipher, h, payload.data(), payload.size(), out, sizeof(out)));
    TEST_ASSERT_EQUAL(LoraPacket::MAX_SIZE,
                      LoraPacket::seal(cipher, h, payload.data(), LoraPacket::MAX_PAYLOAD, out, sizeof(out)));
    TEST_ASSERT_EQUAL(0, LoraPacket::seal(cipher, h, payload.data(), 10, out, LoraPacket::OVERHEAD + 9));

    // A DATA frame of 8 measurements always fits in one packet
    TEST_ASSERT_TRUE(SyncStream::maxFrameSize(8) <= LoraPacket::MAX_PAYLOAD);
}

// --- Anti-replay ---

void test_replay_guard_accepts_only_newer_counters(void) {
    ReplayGuard guard;
    TEST_ASSERT_TRUE(guard.accept(MAC_A, 5));
    TEST_ASSERT_FALSE(guard.accept(MAC_A, 5));
    TEST_ASSERT_FALSE(guard.accept(MAC_A, 4));
    TEST_ASSERT_TRUE(guard.accept(MAC_A, 9));  // gaps are fine: lost packets

    uint32_t last = 0;
    TEST_ASSERT_TRUE(guard.last(MAC_A, &last));
    TEST_ASSERT_EQUAL_UINT32(9, last);
}

void test_replay_guard_tracks_each_node(void) {
    ReplayGuard guard;
    TEST_ASSERT_TRUE(guard.accept(MAC_A, 100));
    TEST_ASSERT_TRUE(guard.accept(MAC_B, 1));
    TEST_ASSERT_FALSE(guard.accept(MAC_B, 1));
    TEST_ASSERT_TRUE(guard.accept(MAC_A, 101));
    TEST_ASSERT_EQUAL(2, guard.size());
}

void test_replay_guard_full_keeps_known_nodes(void) {
    ReplayGuard guard;
    uint8_t mac[6] = {0x02, 0, 0, 0, 0, 0};
    for (size_t i = 0; i < ReplayGuard::CAPACITY; i++) {
        mac[5] = i;
        TEST_ASSERT_TRUE(guard.accept(mac, 1));
    }
    mac[5] = 0xFF;
    TEST_ASSERT_FALSE(guard.accept(mac, 1));  // unknown node, table full

    mac[5] = 0;
    TEST_ASSERT_FALSE(guard.accept(mac, 1));  // still remembered: replay rejected
    TEST_ASSERT_TRUE(guard.accept(mac, 2));
}

// --- Frame counter ---

struct MemoryCounterStore : ICounterStore {
    uint32_t value = 0;
    uint32_t saves = 0;
    bool fail = false;
    uint32_t load() override { return value; }
    bool save(uint32_t v) override {
        if (fail) return false;
        value = v;
        saves++;
        return true;
    }
};

void test_frame_counter_saves_once_per_block(void) {
    MemoryCounterStore nvs;
    FrameCounter counter(nvs);
    counter.begin();

    uint32_t v = 0;
    for (uint32_t i = 1; i <= FrameCounter::BLOCK; i++) {
        TEST_ASSERT_TRUE(counter.next(&v));
        TEST_ASSERT_EQUAL_UINT32(i, v);
    }
    TEST_ASSERT_EQUAL_UINT32(1, nvs.saves);
    TEST_ASSERT_TRUE(counter.next(&v));
    TEST_ASSERT_EQUAL_UINT32(FrameCounter::BLOCK + 1, v);
    TEST_ASSERT_EQUAL_UINT32(2, nvs.saves);
}

void test_frame_counter_never_repeats_after_power_loss(void) {
    MemoryCounterStore nvs;
    uint32_t highest = 0;
    for (int boot = 0; boot < 5; boot++) {
        FrameCounter counter(nvs);  // power loss: everything in RAM is gone
        counter.begin();
        for (int i = 0; i < 10 + boot * 37; i++) {
            uint32_t v = 0;
            TEST_ASSERT_TRUE(counter.next(&v));
            TEST_ASSERT_TRUE(v > highest);
            highest = v;
        }
    }
}

void test_frame_counter_refuses_when_it_cannot_save(void) {
    MemoryCounterStore nvs;
    nvs.fail = true;
    FrameCounter counter(nvs);
    counter.begin();
    uint32_t v = 0;
    TEST_ASSERT_FALSE(counter.next(&v));
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_round_trip);
    RUN_TEST(test_header_is_clear_and_payload_is_not);
    RUN_TEST(test_nonce_layout);
    RUN_TEST(test_data_and_ack_with_same_counter_use_different_nonces);
    RUN_TEST(test_tampering_is_detected);
    RUN_TEST(test_wrong_key_is_rejected);
    RUN_TEST(test_malformed_and_unknown_version);
    RUN_TEST(test_size_limits);
    RUN_TEST(test_replay_guard_accepts_only_newer_counters);
    RUN_TEST(test_replay_guard_tracks_each_node);
    RUN_TEST(test_replay_guard_full_keeps_known_nodes);
    RUN_TEST(test_frame_counter_saves_once_per_block);
    RUN_TEST(test_frame_counter_never_repeats_after_power_loss);
    RUN_TEST(test_frame_counter_refuses_when_it_cannot_save);
    return UNITY_END();
}
