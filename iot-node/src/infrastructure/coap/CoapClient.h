#ifndef COAP_CLIENT_H
#define COAP_CLIENT_H

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <coap-simple.h>
#include <ArduinoJson.h>
#include "../../domain/entities/CoapConfig.h"
#include "HardwareSerial.h"

class CoapClient {
private:
    CoapConfig config;
    WiFiUDP udp;
    Coap* coap = nullptr;
    IPAddress serverIp;
    bool isStarted = false;

    bool resolveServer() {
        if (serverIp.fromString(config.host)) {
            return true; // Already a valid IP address string
        }
        if (WiFi.hostByName(config.host.c_str(), serverIp)) {
            return true; // Successfully resolved hostname
        }
        Serial.println("DNS resolution failed for CoAP host");
        return false;
    }

public:
    CoapClient() {}

    ~CoapClient() {
        if (coap) {
            delete coap;
        }
    }

    void begin(const CoapConfig& cfg) {
        config = cfg;
    }

    void updateConfig(const CoapConfig& newConfig) {
        config = newConfig;
    }

    void ensureStarted() {
        if (!isStarted && WiFi.status() == WL_CONNECTED) {
            if (!coap) {
                coap = new Coap(udp);
            }
            udp.begin(rand() % 1000 + 10000); // Explicit UDP socket initialization
            coap->start();
            isStarted = true;
            Serial.println("CoAP client started");
        }
    }

    bool sendMetric(const String& macAddress, int sensorId, const String& sensorType, float precision, float value, const String& readingTime) {
        ensureStarted();

        if (!isStarted) {
            return false;
        }

        if (!config.isValid()) {
            Serial.println("CoAP config is invalid. Skipping send.");
            return false;
        }

        if (!resolveServer()) {
            return false;
        }

        // Use StaticJsonDocument for predictable memory allocation
        StaticJsonDocument<256> doc;
        doc["mac_address"] = macAddress;
        doc["sensor_id"] = sensorId;
        doc["sensor_type"] = sensorType;
        doc["precision"] = precision;
        doc["value"] = value;
        doc["reading_time"] = readingTime;

        String payload;
        serializeJson(doc, payload);

        // Send POST request
        uint16_t messageId = coap->send(
            serverIp,
            config.port,
            "metrics",
            COAP_CON,
            COAP_POST,
            NULL,
            0,
            (uint8_t*)payload.c_str(),
            payload.length(),
            COAP_APPLICATION_JSON
        );

        if (messageId > 0) {
            Serial.printf("CoAP message sent (id: %d). Payload: %s\n", messageId, payload.c_str());
            return true;
        } else {
            Serial.printf("Failed to send CoAP message to %s:%d. Payload was: %s", serverIp.toString(), config.port, payload.c_str());
            return false;
        }
    }

    void loop() {
        ensureStarted();
        if (isStarted && coap) {
            // Keep the CoAP client responsive for ACKs and retransmissions
            coap->loop();
        }
    }
};

#endif // COAP_CLIENT_H
