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

    bool async = false;  // like the real server: answer first, process in the background
    std::vector<std::pair<int, std::vector<uint8_t>>> backlog;  // exchange number, request
    uint32_t maxUnconfirmed = 0;

    bool exchange(const uint8_t* req, size_t len, uint8_t* resp, size_t cap, size_t* respLen) override {
        int n = exchanges++;
        if (n == failAt) return false;

        if (async) {
            // What arrived before was processed meanwhile; this frame is processed after answering
            for (auto& item : backlog) process(item.second.data(), item.second.size(), item.first);
            backlog.clear();
            uint32_t lastSent = lastSeqOf(req + 6);
            if (lastSent > watermark) maxUnconfirmed = std::max(maxUnconfirmed, lastSent - watermark);
            respond(resp, cap, respLen);
            backlog.emplace_back(n, std::vector<uint8_t>(req, req + len));
            return true;
        }

        process(req, len, n);
        respond(resp, cap, respLen);
        return true;
    }

    static uint32_t lastSeqOf(const uint8_t* frame) {
        uint32_t first = frame[3] | (frame[4] << 8) | (frame[5] << 16) | (static_cast<uint32_t>(frame[6]) << 24);
        return frame[7] ? first + frame[7] - 1 : 0;
    }

    void respond(uint8_t* resp, size_t cap, size_t* respLen) {
        TEST_ASSERT_GREATER_OR_EQUAL(8, cap);
        for (int i = 0; i < 4; i++) resp[i] = (watermark >> (8 * i)) & 0xFF;
        for (int i = 0; i < 4; i++) resp[4 + i] = (serverTime >> (8 * i)) & 0xFF;
        *respLen = 8;
    }

    void process(const uint8_t* req, size_t len, int n) {
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

    // The gap shows up as a watermark that stops moving; after STALL_LIMIT sessions without
    // progress the node resends from it
    RemoteSync::Result result;
    for (int session = 0; session < 10 && !result.complete; session++) result = sync.run(*store, server, 100);
    TEST_ASSERT_TRUE(result.complete);
    TEST_ASSERT_EQUAL_UINT32(40, result.ackedSeq);
    // Every seq stored exactly once, in order
    TEST_ASSERT_EQUAL_UINT32(40, server.stored.size());
    for (uint32_t i = 0; i < 40; i++) TEST_ASSERT_EQUAL_UINT32(i + 1, server.stored[i]);
}

void test_async_server_confirms_in_later_exchanges(void) {
    recordMany(200);
    FakeServer server;
    server.async = true;
    RemoteSync sync(MAC);

    // Sessions every few seconds: the confirmations arrive one exchange late
    RemoteSync::Result result;
    for (int session = 0; session < 10 && !result.complete; session++) result = sync.run(*store, server, 8);

    TEST_ASSERT_TRUE(result.complete);
    TEST_ASSERT_EQUAL_UINT32(200, result.ackedSeq);
    TEST_ASSERT_EQUAL_UINT32(200, server.stored.size());
    TEST_ASSERT_EQUAL_UINT32(0, store->status().pending());
    // Never more than the window (plus the frame in flight) unconfirmed
    TEST_ASSERT_LESS_OR_EQUAL(RemoteSync::WINDOW + RemoteSync::RECORDS_PER_FRAME, server.maxUnconfirmed);
}

void test_async_server_does_not_resend_while_waiting(void) {
    recordMany(32);
    FakeServer server;
    server.async = true;
    RemoteSync sync(MAC);

    RemoteSync::Result result = sync.run(*store, server, 10);
    // 2 data frames + 1 query that brings the confirmation of both
    TEST_ASSERT_TRUE(result.complete);
    TEST_ASSERT_EQUAL_UINT32(3, result.frames);
    TEST_ASSERT_EQUAL_UINT32(32, server.stored.size());
}

void test_async_server_losing_a_frame_is_recovered(void) {
    recordMany(48);
    FakeServer server;
    server.async = true;
    server.skipFirstRecordAt = 0;  // seq 1 is lost in the first frame
    RemoteSync sync(MAC);

    RemoteSync::Result result;
    for (int session = 0; session < 10 && !result.complete; session++) result = sync.run(*store, server, 8);

    TEST_ASSERT_TRUE(result.complete);
    TEST_ASSERT_EQUAL_UINT32(48, server.stored.size());
    for (uint32_t i = 0; i < 48; i++) TEST_ASSERT_EQUAL_UINT32(i + 1, server.stored[i]);
}

void test_a_slow_server_is_waited_for_not_flooded(void) {
    recordMany(200);
    // Processes nothing for a while: every query returns the same watermark
    struct Slow : ISyncTransport {
        int exchanges = 0;
        bool exchange(const uint8_t*, size_t, uint8_t* resp, size_t, size_t* len) override {
            exchanges++;
            for (int i = 0; i < 8; i++) resp[i] = 0;
            *len = 8;
            return true;
        }
    } server;
    RemoteSync sync(MAC);

    sync.run(*store, server, 100);
    // Window (4 frames of 16) + one query, then it stops and waits instead of resending
    TEST_ASSERT_EQUAL(5, server.exchanges);
    TEST_ASSERT_EQUAL_UINT32(65, sync.nextToSend());

    sync.run(*store, server, 100);  // still stalled: one query, no resend
    TEST_ASSERT_EQUAL(6, server.exchanges);
    sync.run(*store, server, 100);  // third stalled query: rewinds to resend from the watermark
    TEST_ASSERT_EQUAL_UINT32(1, sync.nextToSend());
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
    RUN_TEST(test_async_server_confirms_in_later_exchanges);
    RUN_TEST(test_async_server_does_not_resend_while_waiting);
    RUN_TEST(test_async_server_losing_a_frame_is_recovered);
    RUN_TEST(test_a_slow_server_is_waited_for_not_flooded);
    RUN_TEST(test_short_answer_is_a_transport_error);
    RUN_TEST(test_nothing_pending_is_complete_without_traffic);
    return UNITY_END();
}
