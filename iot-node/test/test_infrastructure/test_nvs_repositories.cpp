#include <Arduino.h>
#include <unity.h>
#include "../../src/infrastructure/repositories/NvsRepositories.h"

// Note: These tests require a real ESP32 device to run since they use the actual
// Preferences library which interacts with the ESP32 Non-Volatile Storage.

NvsWifiConfigRepository* wifiRepo;
NvsCoapConfigRepository* coapRepo;

void setUp(void) {
    wifiRepo = new NvsWifiConfigRepository();
    coapRepo = new NvsCoapConfigRepository();
    
    // Clear previous config
    WifiConfig emptyWifi("", "");
    wifiRepo->save(emptyWifi);
    
    CoapConfig emptyCoap("", 5683);
    coapRepo->save(emptyCoap);
}

void tearDown(void) {
    delete wifiRepo;
    delete coapRepo;
}

void test_wifi_save_and_load(void) {
    WifiConfig configToSave("TestSSID", "TestPass123");
    
    bool saved = wifiRepo->save(configToSave);
    TEST_ASSERT_TRUE(saved);
    
    WifiConfig loadedConfig = wifiRepo->load();
    TEST_ASSERT_EQUAL_STRING("TestSSID", loadedConfig.ssid.c_str());
    TEST_ASSERT_EQUAL_STRING("TestPass123", loadedConfig.password.c_str());
    TEST_ASSERT_TRUE(loadedConfig.isValid());
}

void test_wifi_empty_config(void) {
    WifiConfig loadedConfig = wifiRepo->load();
    
    TEST_ASSERT_EQUAL_STRING("", loadedConfig.ssid.c_str());
    TEST_ASSERT_EQUAL_STRING("", loadedConfig.password.c_str());
    TEST_ASSERT_FALSE(loadedConfig.isValid());
}

void test_coap_save_and_load(void) {
    CoapConfig configToSave("192.168.1.100", 5683);
    
    bool saved = coapRepo->save(configToSave);
    TEST_ASSERT_TRUE(saved);
    
    CoapConfig loadedConfig = coapRepo->load();
    TEST_ASSERT_EQUAL_STRING("192.168.1.100", loadedConfig.host.c_str());
    TEST_ASSERT_EQUAL(5683, loadedConfig.port);
    TEST_ASSERT_TRUE(loadedConfig.isValid());
}

void test_coap_empty_config(void) {
    CoapConfig loadedConfig = coapRepo->load();
    
    TEST_ASSERT_EQUAL_STRING("", loadedConfig.host.c_str());
    TEST_ASSERT_EQUAL(5683, loadedConfig.port); // Default port
    TEST_ASSERT_FALSE(loadedConfig.isValid());
}

void setup() {
    delay(2000); // Allow board to settle
    UNITY_BEGIN();
    
    RUN_TEST(test_wifi_save_and_load);
    RUN_TEST(test_wifi_empty_config);
    RUN_TEST(test_coap_save_and_load);
    RUN_TEST(test_coap_empty_config);
    
    UNITY_END();
}

void loop() {
    delay(100); // Prevent watchdog timeout
}