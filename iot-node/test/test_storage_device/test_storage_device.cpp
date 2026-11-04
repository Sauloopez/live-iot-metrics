// On-device tests: the measurement store over the real LittleFS and the FreeRTOS storage task.
// Run with `pio test -e coap -f test_storage_device` (needs the ESP32 connected).
#include <Arduino.h>
#include <LittleFS.h>
#include <unity.h>
#include "../../src/shared/infrastructure/storage/LittleFsFileSystem.h"
#include "../../src/shared/infrastructure/storage/SegmentedMeasurementStore.h"
#include "../../src/shared/infrastructure/storage/StorageTask.h"

static const char* DIR = "/tundra_test";
static LittleFsFileSystem* fsys;

static void wipe() {
    for (const std::string& name : fsys->list(DIR)) fsys->remove(std::string(DIR) + "/" + name);
}

void setUp(void) { wipe(); }
void tearDown(void) { wipe(); }

void test_record_ack_and_reboot_on_flash(void) {
    {
        SegmentedMeasurementStore store(*fsys, DIR, 16);
        TEST_ASSERT_TRUE(store.open());
        for (uint32_t i = 0; i < 40; i++) TEST_ASSERT_TRUE(store.record(1762000000 + i, 1, i));
        TEST_ASSERT_TRUE(store.ack(20));
    }

    SegmentedMeasurementStore rebooted(*fsys, DIR, 16);
    TEST_ASSERT_TRUE(rebooted.open());
    TEST_ASSERT_EQUAL_UINT32(20, rebooted.status().ackedSeq);
    TEST_ASSERT_EQUAL_UINT32(41, rebooted.status().nextSeq);

    size_t count = rebooted.readFrom(1, SIZE_MAX, [](const Measurement&) { return true; });
    TEST_ASSERT_EQUAL(20, count);
    TEST_ASSERT_FALSE(fsys->exists(std::string(DIR) + "/0000000001.cbor"));
}

void test_storage_task_writes_queued_values(void) {
    SegmentedMeasurementStore store(*fsys, DIR, 16);
    TEST_ASSERT_TRUE(store.open());
    static StorageTask* task = new StorageTask(store);  // tasks are never deleted
    TEST_ASSERT_TRUE(task->begin());

    for (uint16_t i = 0; i < 50; i++) TEST_ASSERT_TRUE(task->enqueue(1762000000 + i, i % 3, i, pdMS_TO_TICKS(100)));
    TEST_ASSERT_TRUE(task->waitUntilIdle(pdMS_TO_TICKS(5000)));
    TEST_ASSERT_EQUAL_UINT32(0, task->failedWrites());

    StoreStatus status{};
    task->withStore([&](IMeasurementStore& s) { status = s.status(); });
    TEST_ASSERT_EQUAL_UINT32(50, status.pending());
}

void setup() {
    delay(2000);
    LittleFS.begin(true);
    fsys = new LittleFsFileSystem(LittleFS);

    UNITY_BEGIN();
    RUN_TEST(test_record_ack_and_reboot_on_flash);
    RUN_TEST(test_storage_task_writes_queued_values);
    UNITY_END();
}

void loop() { delay(100); }
