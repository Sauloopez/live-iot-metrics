#ifndef COAP_CLIENT_H
#define COAP_CLIENT_H

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <coap-simple.h>
#include <ArduinoJson.h>
#include "../../domain/entities/CoapConfig.h"
#include "HardwareSerial.h"
#include "IPAddress.h"

class CoapClient {
private:
    CoapConfig config;
    WiFiUDP udp;
    Coap* coap = nullptr;
    IPAddress serverIp;
    bool isStarted = false;
    uint16_t msgIdCounter = 1;

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
            testRawUDP();
            if (!coap) {
                coap = new Coap(udp);
            }
            coap->response(CoapClient::callback);
            coap->start();
            isStarted = true;
            Serial.println("CoAP client started");
        }
    }

    bool sendMetric(const String& macAddress, int sensorId, const String& sensorType, float precision, float value) {
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
        StaticJsonDocument<128> doc;
        doc["m"] = macAddress;
        doc["s"] = sensorId;
        doc["t"] = sensorType;
        doc["p"] = precision;
        doc["v"] = value;

        String payload;
        serializeJson(doc, payload);
        uint16_t msgId = msgIdCounter++;
        if (msgIdCounter == 0) msgIdCounter = 1;

        Serial.printf("Sending COAP message %d \n", msgId);

        int pl = payload.length();
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
            pl,
            COAP_APPLICATION_JSON,
            msgId
        );

        if (messageId > 0) {
            Serial.printf("CoAP message sent (id: %d). Payload: %s length: %d \n", messageId, payload.c_str(), pl);
            return true;
        } else {
            Serial.printf("Failed to send CoAP message %d to %s:%d. Payload was: %s", messageId, serverIp.toString(), config.port, payload.c_str());
            return false;
        }
    }

    static void callback(CoapPacket& p, IPAddress ad, int a) {
        Serial.printf("Coap message %d response code %d: ", p.messageid, p.code);
    }

    void loop() {
        ensureStarted();
        if (isStarted && coap) {
            // Keep the CoAP client responsive for ACKs and retransmissions
            coap->loop();
        }
    }

    void testRawUDP() {
        Serial.printf("WiFi status: %d\n", WiFi.status());
        Serial.printf("ESP IP: %s\n", WiFi.localIP().toString().c_str());
        Serial.printf("Gateway: %s\n", WiFi.gatewayIP().toString().c_str());
        Serial.printf("Subnet mask: %s\n", WiFi.subnetMask().toString().c_str());

        if (!resolveServer()) {
            Serial.println("Resolución de servidor falló");
            return;
        }
        Serial.printf("Server: %s:%d\n", serverIp.toString().c_str(), config.port);

        WiFiUDP testUdp;
        int beginResult = testUdp.begin(54321);
        Serial.printf("testUdp.begin(54321) result: %d\n", beginResult);

        int beginPacketResult = testUdp.beginPacket(serverIp, 5683);
        Serial.printf("beginPacket result: %d\n", beginPacketResult);

        const char* msg = "HELLO_FROM_ESP";
        size_t written = testUdp.write((const uint8_t*)msg, strlen(msg));
        Serial.printf("bytes written: %d\n", written);

        int endPacketResult = testUdp.endPacket();
        Serial.printf("endPacket result: %d (1=ok, 0=fail)\n", endPacketResult);

        testUdp.stop();
        Serial.println("=== Fin test ===");
    }
};

#endif // COAP_CLIENT_H
