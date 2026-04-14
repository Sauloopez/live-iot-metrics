#include <Arduino.h>
#include <unity.h>
#include <LittleFS.h>
#include "../../src/infrastructure/repositories/LittleFsSensorRepository.h"

// Note: These tests require a real ESP32 device to run since they use the actual
// LittleFS library which interacts with the ESP32 Flash memory.

LittleFsSensorRepository* sensorRepo;

void setUp(void) {
    // Ensure LittleFS is mounted
    if (!LittleFS.begin(true)) {
        TEST_FAIL_MESSAGE("LittleFS Mount Failed");
    }
    
    // Clean up the file before each test
    LittleFS.remove("/sensors.csv");
    
    sensorRepo = new LittleFsSensorRepository();
}

void tearDown(void) {
    delete sensorRepo;
}

void test_save_and_load_sensors(void) {
    std::vector<SensorConfig> sensorsToSave;
    sensorsToSave.push_back(SensorConfig(1, 34, "temperature", 0.5, 10000));
    sensorsToSave.push_back(SensorConfig(2, 35, "humidity", 1.0, 5000));
    
    bool saved = sensorRepo->saveAll(sensorsToSave);
    TEST_ASSERT_TRUE(saved);
    
    std::vector<SensorConfig> loadedSensors = sensorRepo->loadAll();
    
    TEST_ASSERT_EQUAL(2, loadedSensors.size());
    
    TEST_ASSERT_EQUAL(1, loadedSensors[0].id);
    TEST_ASSERT_EQUAL(34, loadedSensors[0].pin);
    TEST_ASSERT_EQUAL_STRING("temperature", loadedSensors[0].type.c_str());
    TEST_ASSERT_FLOAT_WITHIN(0.01, 0.5, loadedSensors[0].precision);
    TEST_ASSERT_EQUAL(10000, loadedSensors[0].interval_ms);
    TEST_ASSERT_TRUE(loadedSensors[0].isValid());
    
    TEST_ASSERT_EQUAL(2, loadedSensors[1].id);
    TEST_ASSERT_EQUAL(35, loadedSensors[1].pin);
    TEST_ASSERT_EQUAL_STRING("humidity", loadedSensors[1].type.c_str());
    TEST_ASSERT_FLOAT_WITHIN(0.01, 1.0, loadedSensors[1].precision);
    TEST_ASSERT_EQUAL(5000, loadedSensors[1].interval_ms);
    TEST_ASSERT_TRUE(loadedSensors[1].isValid());
}

void test_add_sensor(void) {
    SensorConfig newSensor(3, 36, "soil_moisture", 0.1, 15000);
    
    bool added = sensorRepo->add(newSensor);
    TEST_ASSERT_TRUE(added);
    
    std::vector<SensorConfig> loadedSensors = sensorRepo->loadAll();
    TEST_ASSERT_EQUAL(1, loadedSensors.size());
    TEST_ASSERT_EQUAL(3, loadedSensors[0].id);
    
    // Try to add the same ID again
    SensorConfig duplicateSensor(3, 39, "other", 1.0, 1000);
    bool addedDuplicate = sensorRepo->add(duplicateSensor);
    TEST_ASSERT_FALSE(addedDuplicate);
    
    loadedSensors = sensorRepo->loadAll();
    TEST_ASSERT_EQUAL(1, loadedSensors.size()); // Should still be 1
}

void test_update_sensor(void) {
    // Add initial sensor
    sensorRepo->add(SensorConfig(1, 34, "temperature", 0.5, 10000));
    
    // Update it
    SensorConfig updatedSensor(1, 35, "temp_updated", 0.1, 5000);
    bool updated = sensorRepo->update(updatedSensor);
    TEST_ASSERT_TRUE(updated);
    
    std::vector<SensorConfig> loadedSensors = sensorRepo->loadAll();
    TEST_ASSERT_EQUAL(1, loadedSensors.size());
    TEST_ASSERT_EQUAL(1, loadedSensors[0].id);
    TEST_ASSERT_EQUAL(35, loadedSensors[0].pin);
    TEST_ASSERT_EQUAL_STRING("temp_updated", loadedSensors[0].type.c_str());
    TEST_ASSERT_FLOAT_WITHIN(0.01, 0.1, loadedSensors[0].precision);
    TEST_ASSERT_EQUAL(5000, loadedSensors[0].interval_ms);
    
    // Try to update non-existent sensor
    SensorConfig nonExistentSensor(99, 12, "ghost", 1.0, 1000);
    bool updatedNonExistent = sensorRepo->update(nonExistentSensor);
    TEST_ASSERT_FALSE(updatedNonExistent);
}

void test_remove_sensor(void) {
    // Add sensors
    sensorRepo->add(SensorConfig(1, 34, "temperature", 0.5, 10000));
    sensorRepo->add(SensorConfig(2, 35, "humidity", 1.0, 5000));
    
    std::vector<SensorConfig> loadedSensors = sensorRepo->loadAll();
    TEST_ASSERT_EQUAL(2, loadedSensors.size());
    
    // Remove one
    bool removed = sensorRepo->remove(1);
    TEST_ASSERT_TRUE(removed);
    
    loadedSensors = sensorRepo->loadAll();
    TEST_ASSERT_EQUAL(1, loadedSensors.size());
    TEST_ASSERT_EQUAL(2, loadedSensors[0].id); // Only sensor 2 should remain
    
    // Try to remove non-existent sensor
    bool removedNonExistent = sensorRepo->remove(99);
    TEST_ASSERT_FALSE(removedNonExistent);
}

void setup() {
    delay(2000); // Allow board to settle
    UNITY_BEGIN();
    
    RUN_TEST(test_save_and_load_sensors);
    RUN_TEST(test_add_sensor);
    RUN_TEST(test_update_sensor);
    RUN_TEST(test_remove_sensor);
    
    UNITY_END();
}

void loop() {
    delay(100); // Prevent watchdog timeout
}