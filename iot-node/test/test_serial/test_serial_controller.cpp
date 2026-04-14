#include <Arduino.h>
#include <unity.h>
#include <ArduinoJson.h>

#include "../../src/domain/repositories/IRepositories.h"
#include "../../src/usecases/UseCases.h"
#include "../../src/presentation/controllers/SerialController.h"

// --- Mock Repositories for testing without actual hardware memory side-effects ---

class MockWifiRepo : public IWifiConfigRepository {
public:
    WifiConfig config;
    WifiConfig load() override { return config; }
    bool save(const WifiConfig& cfg) override { 
        config = cfg; 
        return true; 
    }
};

class MockCoapRepo : public ICoapConfigRepository {
public:
    CoapConfig config;
    CoapConfig load() override { return config; }
    bool save(const CoapConfig& cfg) override { 
        config = cfg; 
        return true; 
    }
};

class MockSensorRepo : public ISensorConfigRepository {
public:
    std::vector<SensorConfig> sensors;
    
    std::vector<SensorConfig> loadAll() override { return sensors; }
    
    bool saveAll(const std::vector<SensorConfig>& s) override {
        sensors = s;
        return true;
    }
    
    bool add(const SensorConfig& sensor) override {
        for (const auto& s : sensors) {
            if (s.id == sensor.id) return false;
        }
        sensors.push_back(sensor);
        return true;
    }
    
    bool update(const SensorConfig& sensor) override {
        for (auto& s : sensors) {
            if (s.id == sensor.id) {
                s = sensor;
                return true;
            }
        }
        return false;
    }
    
    bool remove(int id) override {
        for (size_t i = 0; i < sensors.size(); i++) {
            if (sensors[i].id == id) {
                sensors.erase(sensors.begin() + i);
                return true;
            }
        }
        return false;
    }
};

// --- Test State ---
MockWifiRepo* mockWifiRepo;
MockCoapRepo* mockCoapRepo;
MockSensorRepo* mockSensorRepo;

WifiUseCases* wifiUseCases;
CoapUseCases* coapUseCases;
SensorUseCases* sensorUseCases;

SerialController* serialController;

void setUp(void) {
    mockWifiRepo = new MockWifiRepo();
    mockCoapRepo = new MockCoapRepo();
    mockSensorRepo = new MockSensorRepo();

    wifiUseCases = new WifiUseCases(mockWifiRepo);
    coapUseCases = new CoapUseCases(mockCoapRepo);
    sensorUseCases = new SensorUseCases(mockSensorRepo);

    serialController = new SerialController(wifiUseCases, coapUseCases, sensorUseCases);
}

void tearDown(void) {
    delete serialController;
    delete sensorUseCases;
    delete coapUseCases;
    delete wifiUseCases;
    delete mockSensorRepo;
    delete mockCoapRepo;
    delete mockWifiRepo;
}

// Since Serial reads from the hardware UART buffer, testing handle() directly
// requires injecting bytes into the Serial buffer. We can test the underlying UseCases directly
// as the controller is mostly a JSON parsing wrapper.

void test_wifi_set_command_effect(void) {
    // Simulate what happens when a valid "set wifi" command triggers the use case
    bool result = wifiUseCases->saveConfig("MyTestNetwork", "SuperSecret");
    TEST_ASSERT_TRUE(result);
    
    WifiConfig config = wifiUseCases->getConfig();
    TEST_ASSERT_EQUAL_STRING("MyTestNetwork", config.ssid.c_str());
    TEST_ASSERT_EQUAL_STRING("SuperSecret", config.password.c_str());
}

void test_coap_set_command_effect(void) {
    // Simulate what happens when a valid "set coap" command triggers the use case
    bool result = coapUseCases->saveConfig("10.0.0.50", 1234);
    TEST_ASSERT_TRUE(result);
    
    CoapConfig config = coapUseCases->getConfig();
    TEST_ASSERT_EQUAL_STRING("10.0.0.50", config.host.c_str());
    TEST_ASSERT_EQUAL(1234, config.port);
}

void test_sensor_add_command_effect(void) {
    bool result = sensorUseCases->addSensor(5, 34, "temperature", 0.1f, 5000);
    TEST_ASSERT_TRUE(result);
    
    std::vector<SensorConfig> sensors = sensorUseCases->getSensors();
    TEST_ASSERT_EQUAL(1, sensors.size());
    TEST_ASSERT_EQUAL(5, sensors[0].id);
    TEST_ASSERT_EQUAL(34, sensors[0].pin);
    TEST_ASSERT_EQUAL_STRING("temperature", sensors[0].type.c_str());
    TEST_ASSERT_FLOAT_WITHIN(0.01, 0.1f, sensors[0].precision);
    TEST_ASSERT_EQUAL(5000, sensors[0].interval_ms);
}

void test_sensor_add_invalid_pin(void) {
    // Pin -1 is invalid based on SensorConfig.isValid()
    bool result = sensorUseCases->addSensor(6, -1, "temp", 1.0f, 1000);
    TEST_ASSERT_FALSE(result);
    
    std::vector<SensorConfig> sensors = sensorUseCases->getSensors();
    TEST_ASSERT_EQUAL(0, sensors.size());
}

void test_sensor_update_command_effect(void) {
    // Add first
    sensorUseCases->addSensor(5, 34, "temperature", 0.1f, 5000);
    
    // Update
    bool result = sensorUseCases->updateSensor(5, 35, "updated_temp", 0.5f, 10000);
    TEST_ASSERT_TRUE(result);
    
    std::vector<SensorConfig> sensors = sensorUseCases->getSensors();
    TEST_ASSERT_EQUAL(1, sensors.size());
    TEST_ASSERT_EQUAL(5, sensors[0].id);
    TEST_ASSERT_EQUAL(35, sensors[0].pin);
    TEST_ASSERT_EQUAL_STRING("updated_temp", sensors[0].type.c_str());
}

void test_sensor_remove_command_effect(void) {
    // Add
    sensorUseCases->addSensor(1, 32, "test", 1.0f, 1000);
    sensorUseCases->addSensor(2, 33, "test2", 1.0f, 1000);
    
    TEST_ASSERT_EQUAL(2, sensorUseCases->getSensors().size());
    
    // Remove
    bool result = sensorUseCases->removeSensor(1);
    TEST_ASSERT_TRUE(result);
    
    std::vector<SensorConfig> sensors = sensorUseCases->getSensors();
    TEST_ASSERT_EQUAL(1, sensors.size());
    TEST_ASSERT_EQUAL(2, sensors[0].id);
}

void setup() {
    delay(2000); // Allow board to settle
    UNITY_BEGIN();
    
    RUN_TEST(test_wifi_set_command_effect);
    RUN_TEST(test_coap_set_command_effect);
    RUN_TEST(test_sensor_add_command_effect);
    RUN_TEST(test_sensor_add_invalid_pin);
    RUN_TEST(test_sensor_update_command_effect);
    RUN_TEST(test_sensor_remove_command_effect);
    
    UNITY_END();
}

void loop() {
    // Empty
}