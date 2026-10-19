#include <Arduino.h>
#include <WiFi.h>
#include <vector>

// Infrastructure Repositories
#include "infrastructure/repositories/NvsRepositories.h"
#include "infrastructure/repositories/LittleFsSensorRepository.h"

// Infrastructure Services
#include "infrastructure/coap/CoapClient.h"
#include "infrastructure/time/NtpClient.h"
#include "infrastructure/sensors/SensorReader.h"

// Use Cases
#include "usecases/UseCases.h"

// Presentation Controllers
#include "presentation/controllers/SerialController.h"

// Global instances for Dependency Injection
NvsWifiConfigRepository wifiRepo;
NvsCoapConfigRepository coapRepo;
LittleFsSensorRepository sensorRepo;

WifiUseCases* wifiUseCases;
CoapUseCases* coapUseCases;
SensorUseCases* sensorUseCases;

SerialController* serialController;
CoapClient coapClient;
NtpClient ntpClient;
SensorReader sensorReader;

String macAddress = "00:00:00:00:00:00";
unsigned long lastWifiRetry = 0;
const unsigned long WIFI_RETRY_INTERVAL_MS = 10000;

// State tracking for sensors
struct SensorState {
    int id;
    unsigned long lastReadTime;
};
std::vector<SensorState> sensorStates;

void connectToWifi() {
    WifiConfig wifiConfig = wifiUseCases->getConfig();
    if (!wifiConfig.isValid()) {
        Serial.println("No valid WiFi configuration found. Use serial API to set credentials.");
        return;
    }

    Serial.printf("Attempting to connect to WiFi SSID: %s\n", wifiConfig.ssid.c_str());
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(true);
    delay(100);
    WiFi.begin(wifiConfig.ssid.c_str(), wifiConfig.password.c_str());

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
        delay(500);
        Serial.print(".");
        attempts++;
    }
    Serial.println();

    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("WiFi connected successfully!");
        Serial.print("IP Address: ");
        Serial.println(WiFi.localIP());
        macAddress = WiFi.macAddress();

        // Initialize Time sync once connected
        ntpClient.begin();
    } else {
        Serial.println("WiFi connection failed.");
    }
}

void setup() {
    // 1. Initialize Serial
    Serial.begin(115200);
    delay(1000);
    Serial.println("\n--- Starting IoT Node ---");

    // 2. Instantiate Use Cases
    wifiUseCases = new WifiUseCases(&wifiRepo);
    coapUseCases = new CoapUseCases(&coapRepo);
    sensorUseCases = new SensorUseCases(&sensorRepo);

    // 3. Instantiate Controllers
    serialController = new SerialController(wifiUseCases, coapUseCases, sensorUseCases);

    // Announce serial API is ready
    Serial.println("{\"status\":\"ok\",\"message\":\"Serial controller ready\"}");

    // 4. Start WiFi
    connectToWifi();

    // 5. Initialize CoAP Client
    CoapConfig coapConfig = coapUseCases->getConfig();
    coapClient.begin(coapConfig);

    // 6. Initialize Sensors Pins
    std::vector<SensorConfig> sensors = sensorUseCases->getSensors();
    for (const auto& sensor : sensors) {
        sensorReader.begin(sensor);
        sensorStates.push_back({sensor.id, 0});
    }
}

void loop() {
    unsigned long currentMillis = millis();

    // 1. Handle incoming Serial API commands (Configuration)
    serialController->handle();

    // 2. Handle WiFi Reconnection if connection is lost
    if (WiFi.status() != WL_CONNECTED) {
        if (currentMillis - lastWifiRetry >= WIFI_RETRY_INTERVAL_MS) {
            lastWifiRetry = currentMillis;
            Serial.println("WiFi disconnected. Reconnecting...");
            connectToWifi();
        }
        return; // Skip sensor readings and CoAP processing if no network
    }

    // 3. Keep CoAP client processing incoming messages/ACKs
    coapClient.loop();

    // 4. Read Sensors and Publish
    std::vector<SensorConfig> sensors = sensorUseCases->getSensors();

    for (const auto& sensor : sensors) {
        // Find existing state for this sensor to check interval
        SensorState* state = nullptr;
        for (auto& st : sensorStates) {
            if (st.id == sensor.id) {
                state = &st;
                break;
            }
        }

        // If a new sensor was added dynamically via Serial API, initialize its state
        if (!state) {
            sensorReader.begin(sensor);
            sensorStates.push_back({sensor.id, currentMillis});
            continue; // Skip the first immediate read to stagger it slightly
        }

        // Check if interval has elapsed
        if (currentMillis - state->lastReadTime >= sensor.interval_ms) {
            state->lastReadTime = currentMillis;

            // Ensure CoAP client has latest config in case it was updated via Serial API
            coapClient.updateConfig(coapUseCases->getConfig());

            float rawValue;
            if (!sensorReader.read(sensor, rawValue)) {
                Serial.printf("Warning: Sensor ID: %d (Pin: %d, driver: %s) returned no valid reading.\n",
                              sensor.id, sensor.pin, sensor.driver.c_str());
                continue;
            }

            // Apply linear calibration: value = raw * precision + offset
            float value = sensor.apply(rawValue);

            Serial.printf("Reading Sensor ID: %d (Pin: %d) | Raw: %.1f | Value: %.2f ",
                          sensor.id, sensor.pin, rawValue, value);

            // Dispatch via CoAP
            bool success = coapClient.sendMetric(
                macAddress,
                sensor.id,
                sensor.type,
                sensor.precision,
                value
            );

            if (!success) {
                Serial.println("Warning: Failed to enqueue CoAP message.");
            }
        }
    }
}
