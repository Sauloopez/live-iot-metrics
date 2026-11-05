// Native (PC) tests for pushing stored measurements to the server (CoAP / LoRa sync).
#include <unity.h>
#include <vector>
#include "../test_native_storage/InMemoryFileSystem.h"
#include "../../src/shared/infrastructure/storage/SegmentedMeasurementStore.h"
#include "../../src/shared/usecases/RemoteSync.h"

static const uint8_t MAC[6] = {0x02, 0x00, 0x00, 0x00, 0xC0, 0x01};

// Behaves like LiveMetrics.Sync.Ingest: checks the CRC and only accepts the measurement right
// after its watermark
class FakeServer : public ISyncTransport {
public:
    uint32_t watermark = 0;
    std::vector<uint32_t> stored;
    int failAt = -1;           // exchange number that fails (no answer)
    int skipFirstRecordAt = -1; // exchange in which the server "misses" the first measurement
    int exchanges = 0;
    uint32_t serverTime = 1762164450;

    bool exchange(const uint8_t* req, size_t len, uint8_t* resp, size_t cap, size_t* respLen) override {
        int n = exchanges++;
        if (n == failAt) return false;

        TEST_ASSERT_EQUAL_UINT8_ARRAY(MAC, req, 6);
        const uint8_t* frame = req + 6;
        size_t frameLen = len - 6;
        uint16_t crc = frame[frameLen - 2] | (frame[frameLen - 1] << 8);
        TEST_ASSERT_EQUAL_HEX16(Crc16::compute(frame, frameLen - 2), crc);

        size_t pos = SyncStream::HEADER_SIZE;
        bool skip = n == skipFirstRecordAt;
        for (uint8_t i = 0; i < frame[7]; i++) {
            Measurement m;
            size_t used = 0;
            MeasurementCodec::decode(frame + pos, frameLen - 2 - pos, &m, &used);
            pos += used;
            if (skip) {
                skip = false;
                continue;
            }
            if (m.seq == watermark + 1) {
                watermark = m.seq;
                stored.push_back(m.seq);
            }
        }

        TEST_ASSERT_GREATER_OR_EQUAL(8, cap);
        for (int i = 0; i < 4; i++) resp[i] = (watermark >> (8 * i)) & 0xFF;
        for (int i = 0; i < 4; i++) resp[4 + i] = (serverTime >> (8 * i)) & 0xFF;
        *respLen = 8;
        return true;
    }
};

static InMemoryFileSystem* fs;
static SegmentedMeasurementStore* store;

void setUp(void) {
    fs = new InMemoryFileSystem();
    store = new SegmentedMeasurementStore(*fs, "/data", 32);
    store->open();
}

void tearDown(void) {
    delete store;
    delete fs;
}

static void recordMany(uint32_t count) {
    for (uint32_t i = 0; i < count; i++) store->record(1762164450 + i * 60, 1, i);
}

void test_pushes_everything_and_releases_it(void) {
    recordMany(100);
    FakeServer server;
    RemoteSync sync(MAC);

    RemoteSync::Result result = sync.run(*store, server, 100);

    TEST_ASSERT_TRUE(result.complete);
    TEST_ASSERT_FALSE(result.transportError);
    TEST_ASSERT_EQUAL_UINT32(7, result.frames);  // 6 x 16 + 4
    TEST_ASSERT_EQUAL_UINT32(100, result.ackedSeq);
    TEST_ASSERT_EQUAL_UINT32(100, server.stored.size());
    TEST_ASSERT_EQUAL_UINT32(0, store->status().pending());
    TEST_ASSERT_EQUAL(0, store->segmentCount());
    TEST_ASSERT_EQUAL_UINT32(server.serverTime, result.serverTime);
}

void test_frame_limit_leaves_the_rest_for_later(void) {
    recordMany(100);
    FakeServer server;
    RemoteSync sync(MAC);

    RemoteSync::Result first = sync.run(*store, server, 2);
    TEST_ASSERT_FALSE(first.complete);
    TEST_ASSERT_EQUAL_UINT32(32, first.ackedSeq);

    RemoteSync::Result second = sync.run(*store, server, 100);
    TEST_ASSERT_TRUE(second.complete);
    TEST_ASSERT_EQUAL_UINT32(100, server.stored.size());
}

void test_no_answer_keeps_the_data(void) {
    recordMany(50);
    FakeServer server;
    server.failAt = 1;  // the second exchange is lost
    RemoteSync sync(MAC);

    RemoteSync::Result result = sync.run(*store, server, 100);
    TEST_ASSERT_TRUE(result.transportError);
    TEST_ASSERT_EQUAL_UINT32(16, result.ackedSeq);
    TEST_ASSERT_EQUAL_UINT32(34, store->status().pending());

    // Next session (e.g. WiFi is back) continues where the server stopped
    server.failAt = -1;
    RemoteSync::Result retry = sync.run(*store, server, 100);
    TEST_ASSERT_TRUE(retry.complete);
    TEST_ASSERT_EQUAL_UINT32(50, server.stored.size());
}

void test_server_gap_is_resent(void) {
    recordMany(40);
    FakeServer server;
    server.skipFirstRecordAt = 1;  // the server misses seq 17
    RemoteSync sync(MAC);

    RemoteSync::Result result = sync.run(*store, server, 100);
    TEST_ASSERT_TRUE(result.complete);
    TEST_ASSERT_EQUAL_UINT32(40, result.ackedSeq);
    // Every seq stored exactly once, in order
    TEST_ASSERT_EQUAL_UINT32(40, server.stored.size());
    for (uint32_t i = 0; i < 40; i++) TEST_ASSERT_EQUAL_UINT32(i + 1, server.stored[i]);
}

void test_short_answer_is_a_transport_error(void) {
    recordMany(5);
    struct Short : ISyncTransport {
        bool exchange(const uint8_t*, size_t, uint8_t*, size_t, size_t* len) override {
            *len = 3;
            return true;
        }
    } transport;
    RemoteSync sync(MAC);

    RemoteSync::Result result = sync.run(*store, transport, 10);
    TEST_ASSERT_TRUE(result.transportError);
    TEST_ASSERT_EQUAL_UINT32(5, store->status().pending());
}

void test_nothing_pending_is_complete_without_traffic(void) {
    FakeServer server;
    RemoteSync sync(MAC);
    RemoteSync::Result result = sync.run(*store, server, 10);
    TEST_ASSERT_TRUE(result.complete);
    TEST_ASSERT_EQUAL(0, server.exchanges);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_pushes_everything_and_releases_it);
    RUN_TEST(test_frame_limit_leaves_the_rest_for_later);
    RUN_TEST(test_no_answer_keeps_the_data);
    RUN_TEST(test_server_gap_is_resent);
    RUN_TEST(test_short_answer_is_a_transport_error);
    RUN_TEST(test_nothing_pending_is_complete_without_traffic);
    return UNITY_END();
}
