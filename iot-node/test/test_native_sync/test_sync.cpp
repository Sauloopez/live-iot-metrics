// Native (PC) tests for the USB sync stream: COBS framing, CRC and credit flow control.
#include <unity.h>
#include <vector>
#include "../test_native_storage/InMemoryFileSystem.h"
#include "../../src/shared/infrastructure/storage/SegmentedMeasurementStore.h"
#include "../../src/shared/infrastructure/sync/Cobs.h"
#include "../../src/shared/infrastructure/sync/Crc16.h"
#include "../../src/shared/usecases/SyncStream.h"

static InMemoryFileSystem* fs;
static SegmentedMeasurementStore* store;

void setUp(void) {
    fs = new InMemoryFileSystem();
    store = new SegmentedMeasurementStore(*fs, "/data", 64);
    store->open();
}

void tearDown(void) {
    delete store;
    delete fs;
}

static void recordMany(uint32_t count) {
    for (uint32_t i = 0; i < count; i++) store->record(1762000000 + i, i % 5, i * 0.25f);
}

struct ParsedFrame {
    uint16_t frameNo;
    uint32_t firstSeq;
    std::vector<Measurement> records;
};

// Mirrors what the browser does with a DATA frame
static bool parseFrame(const uint8_t* frame, size_t len, ParsedFrame* out) {
    if (len < SyncStream::HEADER_SIZE + SyncStream::CRC_SIZE || frame[0] != SyncStream::FRAME_DATA) return false;
    uint16_t crc = frame[len - 2] | (frame[len - 1] << 8);
    if (Crc16::compute(frame, len - 2) != crc) return false;

    out->frameNo = frame[1] | (frame[2] << 8);
    out->firstSeq = frame[3] | (frame[4] << 8) | (frame[5] << 16) | (static_cast<uint32_t>(frame[6]) << 24);
    uint8_t count = frame[7];
    size_t pos = SyncStream::HEADER_SIZE;
    out->records.clear();
    for (uint8_t i = 0; i < count; i++) {
        Measurement m;
        size_t used = 0;
        if (MeasurementCodec::decode(frame + pos, len - 2 - pos, &m, &used) != MeasurementCodec::DecodeResult::Ok) {
            return false;
        }
        out->records.push_back(m);
        pos += used;
    }
    return pos == len - 2;
}

// --- COBS ---

static void assertCobsRoundTrip(const std::vector<uint8_t>& input) {
    std::vector<uint8_t> encoded(Cobs::maxEncodedSize(input.size()));
    size_t n = Cobs::encode(input.data(), input.size(), encoded.data(), encoded.size());
    TEST_ASSERT_GREATER_THAN(0, n);
    for (size_t i = 0; i < n; i++) TEST_ASSERT_NOT_EQUAL_MESSAGE(0, encoded[i], "encoded data must not contain 0x00");

    std::vector<uint8_t> decoded(input.size() + 1);
    size_t m = Cobs::decode(encoded.data(), n, decoded.data(), decoded.size());
    TEST_ASSERT_EQUAL(input.size(), m);
    if (m) TEST_ASSERT_EQUAL_UINT8_ARRAY(input.data(), decoded.data(), m);
}

void test_cobs_round_trips(void) {
    assertCobsRoundTrip({0x11, 0x22, 0x00, 0x33});
    assertCobsRoundTrip({0x00});
    assertCobsRoundTrip({0x00, 0x00, 0x00});
    assertCobsRoundTrip({0x01, 0x02, 0x03});

    for (size_t size : {253u, 254u, 255u, 600u}) {
        std::vector<uint8_t> data(size);
        for (size_t i = 0; i < size; i++) data[i] = static_cast<uint8_t>((i * 37 + 1) % 256);
        assertCobsRoundTrip(data);
    }
}

void test_cobs_known_vector(void) {
    const uint8_t in[] = {0x11, 0x22, 0x00, 0x33};
    const uint8_t expected[] = {0x03, 0x11, 0x22, 0x02, 0x33};
    uint8_t out[8];
    TEST_ASSERT_EQUAL(5, Cobs::encode(in, sizeof(in), out, sizeof(out)));
    TEST_ASSERT_EQUAL_UINT8_ARRAY(expected, out, 5);
}

void test_cobs_rejects_damaged_input(void) {
    const uint8_t withZero[] = {0x03, 0x11, 0x00, 0x02, 0x33};
    const uint8_t truncated[] = {0x05, 0x11, 0x22};
    uint8_t out[8];
    TEST_ASSERT_EQUAL(0, Cobs::decode(withZero, sizeof(withZero), out, sizeof(out)));
    TEST_ASSERT_EQUAL(0, Cobs::decode(truncated, sizeof(truncated), out, sizeof(out)));
}

// --- CRC ---

void test_crc16_check_value(void) {
    const uint8_t data[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};
    TEST_ASSERT_EQUAL_HEX16(0x29B1, Crc16::compute(data, sizeof(data)));
}

// --- Stream ---

void test_stream_respects_credit_and_frame_size(void) {
    recordMany(100);
    SyncStream stream(16);
    stream.start(*store, 1, 40);

    std::vector<uint8_t> buf(SyncStream::maxFrameSize(16));
    std::vector<size_t> counts;
    size_t len = 0;
    while (stream.next(*store, buf.data(), buf.size(), &len) == SyncStream::Output::Data) {
        ParsedFrame frame;
        TEST_ASSERT_TRUE(parseFrame(buf.data(), len, &frame));
        counts.push_back(frame.records.size());
    }

    // 40 credits -> 16 + 16 + 8, then it waits for more credit
    TEST_ASSERT_EQUAL(3, counts.size());
    TEST_ASSERT_EQUAL(16, counts[0]);
    TEST_ASSERT_EQUAL(8, counts[2]);
    TEST_ASSERT_TRUE(stream.isActive());
    TEST_ASSERT_EQUAL_UINT32(0, stream.credit());
}

void test_stream_sends_everything_in_order_then_ends(void) {
    recordMany(70);
    SyncStream stream(16);
    stream.start(*store, 1, 1000);

    std::vector<uint8_t> buf(SyncStream::maxFrameSize(16));
    uint32_t expectedSeq = 1;
    uint16_t expectedFrame = 0;
    size_t len = 0;
    uint32_t lastSeq = 0;
    SyncStream::Output out;
    while ((out = stream.next(*store, buf.data(), buf.size(), &len, &lastSeq)) == SyncStream::Output::Data) {
        ParsedFrame frame;
        TEST_ASSERT_TRUE(parseFrame(buf.data(), len, &frame));
        TEST_ASSERT_EQUAL_UINT16(expectedFrame++, frame.frameNo);
        TEST_ASSERT_EQUAL_UINT32(expectedSeq, frame.firstSeq);
        for (const Measurement& m : frame.records) TEST_ASSERT_EQUAL_UINT32(expectedSeq++, m.seq);
    }

    TEST_ASSERT_TRUE(out == SyncStream::Output::End);
    TEST_ASSERT_EQUAL_UINT32(71, expectedSeq);
    TEST_ASSERT_EQUAL_UINT32(70, lastSeq);
    TEST_ASSERT_FALSE(stream.isActive());
}

void test_credit_renewal_with_ack_releases_storage_while_streaming(void) {
    recordMany(200);  // segments of 64 records
    SyncStream stream(16);
    stream.start(*store, 1, 64);

    std::vector<uint8_t> buf(SyncStream::maxFrameSize(16));
    size_t len = 0;
    uint32_t received = 0;
    while (stream.next(*store, buf.data(), buf.size(), &len) == SyncStream::Output::Data) received += buf[7];
    TEST_ASSERT_EQUAL_UINT32(64, received);

    // The server confirmed everything received: the node frees it and gets more credit
    store->ack(64);
    stream.addCredit(64);
    TEST_ASSERT_FALSE(fs->exists("/data/0000000001.cbor"));

    ParsedFrame frame;
    TEST_ASSERT_TRUE(stream.next(*store, buf.data(), buf.size(), &len) == SyncStream::Output::Data);
    TEST_ASSERT_TRUE(parseFrame(buf.data(), len, &frame));
    TEST_ASSERT_EQUAL_UINT32(65, frame.firstSeq);
}

void test_stream_never_resends_confirmed_data(void) {
    recordMany(30);
    store->ack(20);

    SyncStream stream(16);
    stream.start(*store, 1, 100);  // asks from 1, but 1..20 are already confirmed

    std::vector<uint8_t> buf(SyncStream::maxFrameSize(16));
    size_t len = 0;
    ParsedFrame frame;
    TEST_ASSERT_TRUE(stream.next(*store, buf.data(), buf.size(), &len) == SyncStream::Output::Data);
    TEST_ASSERT_TRUE(parseFrame(buf.data(), len, &frame));
    TEST_ASSERT_EQUAL_UINT32(21, frame.firstSeq);
    TEST_ASSERT_EQUAL(10, frame.records.size());
}

void test_resuming_after_a_cut_starts_from_the_requested_seq(void) {
    recordMany(50);
    SyncStream stream(16);
    stream.start(*store, 33, 100);  // the browser lost the connection after receiving 1..32

    std::vector<uint8_t> buf(SyncStream::maxFrameSize(16));
    size_t len = 0;
    ParsedFrame frame;
    stream.next(*store, buf.data(), buf.size(), &len);
    TEST_ASSERT_TRUE(parseFrame(buf.data(), len, &frame));
    TEST_ASSERT_EQUAL_UINT32(33, frame.firstSeq);
}

void test_damaged_frame_is_detected_by_crc(void) {
    recordMany(5);
    SyncStream stream(16);
    stream.start(*store, 1, 100);

    std::vector<uint8_t> buf(SyncStream::maxFrameSize(16));
    size_t len = 0;
    stream.next(*store, buf.data(), buf.size(), &len);
    buf[10] ^= 0x40;  // a bit flipped on the wire

    ParsedFrame frame;
    TEST_ASSERT_FALSE(parseFrame(buf.data(), len, &frame));
}

void test_empty_store_ends_immediately(void) {
    SyncStream stream(16);
    stream.start(*store, 1, 100);
    std::vector<uint8_t> buf(SyncStream::maxFrameSize(16));
    size_t len = 0;
    TEST_ASSERT_TRUE(stream.next(*store, buf.data(), buf.size(), &len) == SyncStream::Output::End);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_cobs_round_trips);
    RUN_TEST(test_cobs_known_vector);
    RUN_TEST(test_cobs_rejects_damaged_input);
    RUN_TEST(test_crc16_check_value);
    RUN_TEST(test_stream_respects_credit_and_frame_size);
    RUN_TEST(test_stream_sends_everything_in_order_then_ends);
    RUN_TEST(test_credit_renewal_with_ack_releases_storage_while_streaming);
    RUN_TEST(test_stream_never_resends_confirmed_data);
    RUN_TEST(test_resuming_after_a_cut_starts_from_the_requested_seq);
    RUN_TEST(test_damaged_frame_is_detected_by_crc);
    RUN_TEST(test_empty_store_ends_immediately);
    return UNITY_END();
}
