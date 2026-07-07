#ifndef SERIAL_CONTROLLER_H
#define SERIAL_CONTROLLER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include "../../usecases/UseCases.h"

class SerialController {
private:
    WifiUseCases* wifiUseCases;
    CoapUseCases* coapUseCases;
    SensorUseCases* sensorUseCases;

    void handleWifiCommand(JsonObject& doc) {
        String action = doc["action"] | "";
        
        if (action == "set") {
            String ssid = doc["ssid"] | "";
            String password = doc["password"] | "";
            
            if (wifiUseCases->saveConfig(ssid, password)) {
                Serial.println("{\"status\":\"ok\",\"message\":\"WiFi config saved\"}");
            } else {
                Serial.println("{\"status\":\"error\",\"message\":\"Failed to save WiFi config\"}");
            }
        } else if (action == "get") {
            WifiConfig config = wifiUseCases->getConfig();
            Serial.printf("{\"status\":\"ok\",\"ssid\":\"%s\"}\n", config.ssid.c_str());
        } else {
            Serial.println("{\"status\":\"error\",\"message\":\"Unknown action\"}");
        }
    }

    void handleCoapCommand(JsonObject& doc) {
        String action = doc["action"] | "";
        
        if (action == "set") {
            String host = doc["host"] | "";
            int port = doc["port"] | 5683;
            
            if (coapUseCases->saveConfig(host, port)) {
                Serial.println("{\"status\":\"ok\",\"message\":\"CoAP config saved\"}");
            } else {
                Serial.println("{\"status\":\"error\",\"message\":\"Failed to save CoAP config\"}");
            }
        } else if (action == "get") {
            CoapConfig config = coapUseCases->getConfig();
            Serial.printf("{\"status\":\"ok\",\"host\":\"%s\",\"port\":%d}\n", config.host.c_str(), config.port);
        } else {
            Serial.println("{\"status\":\"error\",\"message\":\"Unknown action\"}");
        }
    }

    void handleSensorCommand(JsonObject& doc) {
        String action = doc["action"] | "";
        
        if (action == "add") {
            int id = doc["id"] | -1;
            int pin = doc["pin"] | -1;
            String type = doc["type"] | "unknown";
            float precision = doc["precision"] | 1.0f;
            unsigned long interval = doc["interval"] | 10000;
            
            if (id == -1 || pin == -1) {
                Serial.println("{\"status\":\"error\",\"message\":\"Missing id or pin\"}");
                return;
            }

            if (sensorUseCases->addSensor(id, pin, type, precision, interval)) {
                Serial.println("{\"status\":\"ok\",\"message\":\"Sensor added\"}");
            } else {
                Serial.println("{\"status\":\"error\",\"message\":\"Failed to add sensor\"}");
            }
        } else if (action == "update") {
            int id = doc["id"] | -1;
            int pin = doc["pin"] | -1;
            String type = doc["type"] | "unknown";
            float precision = doc["precision"] | 1.0f;
            unsigned long interval = doc["interval"] | 10000;
            
            if (id == -1 || pin == -1) {
                Serial.println("{\"status\":\"error\",\"message\":\"Missing id or pin\"}");
                return;
            }

            if (sensorUseCases->updateSensor(id, pin, type, precision, interval)) {
                Serial.println("{\"status\":\"ok\",\"message\":\"Sensor updated\"}");
            } else {
                Serial.println("{\"status\":\"error\",\"message\":\"Failed to update sensor\"}");
            }
        } else if (action == "remove") {
            int id = doc["id"] | -1;
            
            if (sensorUseCases->removeSensor(id)) {
                Serial.println("{\"status\":\"ok\",\"message\":\"Sensor removed\"}");
            } else {
                Serial.println("{\"status\":\"error\",\"message\":\"Failed to remove sensor\"}");
            }
        } else if (action == "list") {
            auto sensors = sensorUseCases->getSensors();
            
            DynamicJsonDocument response(1024);
            response["status"] = "ok";
            JsonArray data = response.createNestedArray("data");
            
            for (const auto& sensor : sensors) {
                JsonObject s = data.createNestedObject();
                s["id"] = sensor.id;
                s["pin"] = sensor.pin;
                s["type"] = sensor.type;
                s["precision"] = sensor.precision;
                s["interval"] = sensor.interval_ms;
            }
            
            serializeJson(response, Serial);
            Serial.println();
        } else {
            Serial.println("{\"status\":\"error\",\"message\":\"Unknown action\"}");
        }
    }

public:
    SerialController(WifiUseCases* wifi, CoapUseCases* coap, SensorUseCases* sensor) 
        : wifiUseCases(wifi), coapUseCases(coap), sensorUseCases(sensor) {}

    void begin() {
        Serial.println("{\"status\":\"ok\",\"message\":\"Serial controller ready\"}");
    }

    void handle() {
        if (Serial.available()) {
            String input = Serial.readStringUntil('\n');
            input.trim();
            
            if (input.length() == 0) return;

            DynamicJsonDocument doc(512);
            DeserializationError error = deserializeJson(doc, input);

            if (error) {
                Serial.printf("{\"status\":\"error\",\"message\":\"Invalid JSON: %s\"}\n", error.c_str());
                return;
            }

            String command = doc["command"] | "";

            if (command == "wifi") {
                JsonObject data = doc["data"].as<JsonObject>();
                handleWifiCommand(data);
            } else if (command == "coap") {
                JsonObject data = doc["data"].as<JsonObject>();
                handleCoapCommand(data);
            } else if (command == "sensor") {
                JsonObject data = doc["data"].as<JsonObject>();
                handleSensorCommand(data);
            } else if (command == "ping") {
                Serial.println("{\"status\":\"ok\",\"message\":\"pong\"}");
            } else {
                Serial.println("{\"status\":\"error\",\"message\":\"Unknown command\"}");
            }
        }
    }
};

#endif // SERIAL_CONTROLLER_H