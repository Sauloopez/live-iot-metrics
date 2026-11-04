// Native (PC) tests for the measurement store: run with `pio test -e native`.
#include <unity.h>
#include <vector>
#include "InMemoryFileSystem.h"
#include "../../src/shared/infrastructure/storage/MeasurementCodec.h"
#include "../../src/shared/infrastructure/storage/SegmentedMeasurementStore.h"

static InMemoryFileSystem* fs;

void setUp(void) { fs = new InMemoryFileSystem(); }
void tearDown(void) { delete fs; }

static std::vector<Measurement> readAll(SegmentedMeasurementStore& store, uint32_t from = 1,
                                        size_t max = SIZE_MAX) {
    std::vector<Measurement> out;
    store.readFrom(from, max, [&](const Measurement& m) {
        out.push_back(m);
        return true;
    });
    return out;
}

static void recordMany(SegmentedMeasurementStore& store, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        TEST_ASSERT_TRUE(store.record(1700000000 + i, i % 4, i * 0.5f));
    }
}

// --- Codec ---

void test_codec_round_trip(void) {
    Measurement in{4000000000u, 1762000000u, 65535, -12.75f};
    uint8_t buf[MeasurementCodec::MAX_RECORD_SIZE];
    size_t len = MeasurementCodec::encode(in, buf, sizeof(buf));
    TEST_ASSERT_GREATER_THAN(0, len);
    TEST_ASSERT_LESS_OR_EQUAL(MeasurementCodec::MAX_RECORD_SIZE, len);

    Measurement out{};
    size_t used = 0;
    TEST_ASSERT_TRUE(MeasurementCodec::decode(buf, len, &out, &used) == MeasurementCodec::DecodeResult::Ok);
    TEST_ASSERT_EQUAL_UINT32(len, used);
    TEST_ASSERT_EQUAL_UINT32(in.seq, out.seq);
    TEST_ASSERT_EQUAL_UINT32(in.ts, out.ts);
    TEST_ASSERT_EQUAL_UINT16(in.sensorId, out.sensorId);
    TEST_ASSERT_EQUAL_FLOAT(in.value, out.value);
}

void test_codec_reports_truncated_records(void) {
    Measurement in{1, 1762000000u, 3, 21.5f};
    uint8_t buf[MeasurementCodec::MAX_RECORD_SIZE];
    size_t len = MeasurementCodec::encode(in, buf, sizeof(buf));

    for (size_t cut = 0; cut < len; cut++) {
        Measurement out{};
        size_t used = 0;
        TEST_ASSERT_TRUE_MESSAGE(
            MeasurementCodec::decode(buf, cut, &out, &used) == MeasurementCodec::DecodeResult::NeedMore,
            "a record cut at any byte must need more data");
    }
}

void test_codec_rejects_garbage(void) {
    uint8_t garbage[] = {0xff, 0x00, 0x13, 0x37};
    Measurement out{};
    size_t used = 0;
    TEST_ASSERT_TRUE(MeasurementCodec::decode(garbage, sizeof(garbage), &out, &used) ==
                     MeasurementCodec::DecodeResult::Invalid);
}

// --- Store ---

void test_record_assigns_increasing_seq(void) {
    SegmentedMeasurementStore store(*fs);
    TEST_ASSERT_TRUE(store.open());

    uint32_t a = 0, b = 0;
    TEST_ASSERT_TRUE(store.record(1762000000, 1, 20.0f, &a));
    TEST_ASSERT_TRUE(store.record(1762000060, 2, 55.0f, &b));
    TEST_ASSERT_EQUAL_UINT32(1, a);
    TEST_ASSERT_EQUAL_UINT32(2, b);
    TEST_ASSERT_EQUAL_UINT32(2, store.status().pending());

    std::vector<Measurement> all = readAll(store);
    TEST_ASSERT_EQUAL(2, all.size());
    TEST_ASSERT_EQUAL_UINT16(2, all[1].sensorId);
    TEST_ASSERT_EQUAL_FLOAT(55.0f, all[1].value);
}

void test_records_roll_over_into_segments(void) {
    SegmentedMeasurementStore store(*fs, "/data", 10);
    store.open();
    recordMany(store, 25);

    TEST_ASSERT_EQUAL(3, store.segmentCount());
    TEST_ASSERT_TRUE(fs->exists("/data/0000000001.cbor"));
    TEST_ASSERT_TRUE(fs->exists("/data/0000000011.cbor"));
    TEST_ASSERT_TRUE(fs->exists("/data/0000000021.cbor"));
    TEST_ASSERT_EQUAL(25, readAll(store).size());
}

void test_read_from_streams_from_any_seq_with_limit(void) {
    SegmentedMeasurementStore store(*fs, "/data", 10);
    store.open();
    recordMany(store, 25);

    std::vector<Measurement> page = readAll(store, 14, 5);
    TEST_ASSERT_EQUAL(5, page.size());
    TEST_ASSERT_EQUAL_UINT32(14, page.front().seq);
    TEST_ASSERT_EQUAL_UINT32(18, page.back().seq);

    // The visitor can stop the stream early
    size_t visited = store.readFrom(1, SIZE_MAX, [](const Measurement& m) { return m.seq < 3; });
    TEST_ASSERT_EQUAL(3, visited);
}

void test_ack_releases_whole_confirmed_segments_only(void) {
    SegmentedMeasurementStore store(*fs, "/data", 10);
    store.open();
    recordMany(store, 25);

    TEST_ASSERT_TRUE(store.ack(15));
    TEST_ASSERT_EQUAL_UINT32(15, store.status().ackedSeq);
    TEST_ASSERT_EQUAL_UINT32(10, store.status().pending());
    // 1..10 released; 11..20 still has unconfirmed records
    TEST_ASSERT_FALSE(fs->exists("/data/0000000001.cbor"));
    TEST_ASSERT_TRUE(fs->exists("/data/0000000011.cbor"));

    // Confirmed records are not streamed again
    std::vector<Measurement> rest = readAll(store);
    TEST_ASSERT_EQUAL(10, rest.size());
    TEST_ASSERT_EQUAL_UINT32(16, rest.front().seq);
}

void test_ack_of_everything_empties_the_store_and_keeps_counting(void) {
    SegmentedMeasurementStore store(*fs, "/data", 10);
    store.open();
    recordMany(store, 12);

    TEST_ASSERT_TRUE(store.ack(1000));  // clamped to the last recorded seq
    TEST_ASSERT_EQUAL_UINT32(12, store.status().ackedSeq);
    TEST_ASSERT_EQUAL(0, store.segmentCount());

    uint32_t seq = 0;
    store.record(1762000000, 1, 1.0f, &seq);
    TEST_ASSERT_EQUAL_UINT32(13, seq);
}

void test_old_or_repeated_acks_are_ignored(void) {
    SegmentedMeasurementStore store(*fs, "/data", 10);
    store.open();
    recordMany(store, 5);

    store.ack(4);
    TEST_ASSERT_TRUE(store.ack(2));
    TEST_ASSERT_EQUAL_UINT32(4, store.status().ackedSeq);
}

void test_state_survives_a_reboot(void) {
    {
        SegmentedMeasurementStore store(*fs, "/data", 10);
        store.open();
        recordMany(store, 23);
        store.ack(12);
    }

    SegmentedMeasurementStore rebooted(*fs, "/data", 10);
    TEST_ASSERT_TRUE(rebooted.open());
    TEST_ASSERT_EQUAL_UINT32(12, rebooted.status().ackedSeq);
    TEST_ASSERT_EQUAL_UINT32(24, rebooted.status().nextSeq);
    TEST_ASSERT_EQUAL(11, readAll(rebooted).size());
}

void test_next_seq_is_rebuilt_from_segments_without_state(void) {
    {
        SegmentedMeasurementStore store(*fs, "/data", 10);
        store.open();
        recordMany(store, 7);  // never acked: no state file yet
    }
    TEST_ASSERT_FALSE(fs->exists("/data/state.cbor"));

    SegmentedMeasurementStore rebooted(*fs, "/data", 10);
    rebooted.open();
    uint32_t seq = 0;
    rebooted.record(1762000000, 1, 1.0f, &seq);
    TEST_ASSERT_EQUAL_UINT32(8, seq);  // no seq is ever reused
}

void test_power_cut_mid_record_is_ignored_and_never_appended_after(void) {
    {
        SegmentedMeasurementStore store(*fs, "/data", 10);
        store.open();
        recordMany(store, 4);
    }
    fs->cutLastBytes("/data/0000000001.cbor", 3);  // last record half written

    SegmentedMeasurementStore rebooted(*fs, "/data", 10);
    rebooted.open();
    TEST_ASSERT_EQUAL(3, readAll(rebooted).size());

    uint32_t seq = 0;
    TEST_ASSERT_TRUE(rebooted.record(1762000000, 9, 9.0f, &seq));
    TEST_ASSERT_EQUAL_UINT32(4, seq);
    // The new record starts a fresh segment instead of following the damaged bytes
    TEST_ASSERT_TRUE(fs->exists("/data/0000000004.cbor"));

    std::vector<Measurement> all = readAll(rebooted);
    TEST_ASSERT_EQUAL(4, all.size());
    TEST_ASSERT_EQUAL_UINT16(9, all.back().sensorId);
}

void test_reset_between_state_write_and_segment_delete_is_cleaned_on_open(void) {
    {
        SegmentedMeasurementStore store(*fs, "/data", 10);
        store.open();
        recordMany(store, 15);
    }
    // State says 1..10 are confirmed, but the segment is still there (reset before deleting)
    uint8_t buf[32];
    size_t len = MeasurementCodec::encodeState(StoreStatus{16, 10}, buf, sizeof(buf));
    fs->writeAtomic("/data/state.cbor", buf, len);
    fs->files["/data/state.cbor.tmp"] = {1, 2, 3};  // and an unfinished atomic write

    SegmentedMeasurementStore rebooted(*fs, "/data", 10);
    rebooted.open();
    TEST_ASSERT_FALSE(fs->exists("/data/0000000001.cbor"));
    TEST_ASSERT_FALSE(fs->exists("/data/state.cbor.tmp"));
    TEST_ASSERT_EQUAL(5, readAll(rebooted).size());
}

void test_ack_keeps_data_if_state_can_not_be_saved(void) {
    SegmentedMeasurementStore store(*fs, "/data", 10);
    store.open();
    recordMany(store, 15);

    fs->failAtomicWrites = true;
    TEST_ASSERT_FALSE(store.ack(10));
    TEST_ASSERT_EQUAL_UINT32(0, store.status().ackedSeq);
    TEST_ASSERT_TRUE(fs->exists("/data/0000000001.cbor"));
}

void test_failed_write_does_not_consume_a_seq(void) {
    SegmentedMeasurementStore store(*fs, "/data", 10);
    store.open();
    recordMany(store, 2);

    fs->failAppends = true;
    TEST_ASSERT_FALSE(store.record(1762000000, 1, 1.0f));
    fs->failAppends = false;

    uint32_t seq = 0;
    store.record(1762000000, 1, 1.0f, &seq);
    TEST_ASSERT_EQUAL_UINT32(3, seq);
}

void test_memory_use_does_not_depend_on_stored_data(void) {
    // 5000 records spread over many segments are streamed with the fixed read window
    SegmentedMeasurementStore store(*fs, "/data", 256);
    store.open();
    recordMany(store, 5000);

    uint32_t expected = 1;
    bool ordered = true;
    size_t visited = store.readFrom(1, SIZE_MAX, [&](const Measurement& m) {
        ordered = ordered && m.seq == expected++;
        return true;
    });
    TEST_ASSERT_EQUAL(5000, visited);
    TEST_ASSERT_TRUE(ordered);
}

int main(int, char**) {
    UNITY_BEGIN();
    RUN_TEST(test_codec_round_trip);
    RUN_TEST(test_codec_reports_truncated_records);
    RUN_TEST(test_codec_rejects_garbage);
    RUN_TEST(test_record_assigns_increasing_seq);
    RUN_TEST(test_records_roll_over_into_segments);
    RUN_TEST(test_read_from_streams_from_any_seq_with_limit);
    RUN_TEST(test_ack_releases_whole_confirmed_segments_only);
    RUN_TEST(test_ack_of_everything_empties_the_store_and_keeps_counting);
    RUN_TEST(test_old_or_repeated_acks_are_ignored);
    RUN_TEST(test_state_survives_a_reboot);
    RUN_TEST(test_next_seq_is_rebuilt_from_segments_without_state);
    RUN_TEST(test_power_cut_mid_record_is_ignored_and_never_appended_after);
    RUN_TEST(test_reset_between_state_write_and_segment_delete_is_cleaned_on_open);
    RUN_TEST(test_ack_keeps_data_if_state_can_not_be_saved);
    RUN_TEST(test_failed_write_does_not_consume_a_seq);
    RUN_TEST(test_memory_use_does_not_depend_on_stored_data);
    return UNITY_END();
}
