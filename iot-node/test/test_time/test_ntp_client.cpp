#include <Arduino.h>
#include <unity.h>
#include "../../src/infrastructure/time/NtpClient.h"

// Note: Testing NTP synchronization reliably requires an active WiFi connection,
// which is usually out of scope for pure unit tests since it depends on the local network.
// However, we can test the fallback logic when time is NOT synced.

NtpClient* ntpClient;

void setUp(void) {
    ntpClient = new NtpClient();
}

void tearDown(void) {
    delete ntpClient;
}

void test_time_is_not_synced_initially(void) {
    // Before connecting to WiFi and getting NTP, time shouldn't be synced
    bool synced = ntpClient->isTimeSynced();
    TEST_ASSERT_FALSE(synced);
}

void test_fallback_iso8601_time(void) {
    // If not synced, the year will be near 1970
    String timeStr = ntpClient->getIso8601Time();
    
    // We expect something starting with 1970 (the Unix epoch)
    TEST_ASSERT_TRUE(timeStr.startsWith("1970"));
    
    // We also expect the formatting to strictly follow ISO 8601 with Zulu time
    // YYYY-MM-DDThh:mm:ssZ
    TEST_ASSERT_EQUAL(20, timeStr.length());
    TEST_ASSERT_EQUAL('T', timeStr.charAt(10));
    TEST_ASSERT_EQUAL('Z', timeStr.charAt(19));
}

void setup() {
    delay(2000); // Allow board to settle
    UNITY_BEGIN();
    
    RUN_TEST(test_time_is_not_synced_initially);
    RUN_TEST(test_fallback_iso8601_time);
    
    UNITY_END();
}

void loop() {
    // Empty
}