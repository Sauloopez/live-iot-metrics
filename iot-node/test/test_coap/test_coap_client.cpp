#include <Arduino.h>
#include <unity.h>
#include "../../src/infrastructure/coap/CoapClient.h"

// Note: These tests test the initial state and validation of the CoAP client.
// Full integration testing sending packets requires a live backend and WiFi.

CoapClient* coapClient;

void setUp(void) {
    coapClient = new CoapClient();
}

void tearDown(void) {
    delete coapClient;
}

void test_send_metric_fails_with_invalid_config(void) {
    // Config with empty host is invalid
    CoapConfig invalidConfig("", 5683);
    coapClient->begin(invalidConfig);

    bool result = coapClient->sendMetric("00:11:22:33:44:55", 1, "temp", 0.5, 23.5);

    // Should fail gracefully and return false without crashing
    TEST_ASSERT_FALSE(result);
}


void setup() {
    delay(2000); // Allow board to settle
    UNITY_BEGIN();

    RUN_TEST(test_send_metric_fails_with_invalid_config);

    UNITY_END();
}

void loop() {
    delay(100); // Prevent watchdog timeout
}
