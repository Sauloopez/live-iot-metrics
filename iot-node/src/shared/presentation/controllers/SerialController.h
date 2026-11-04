#ifndef SERIAL_CONTROLLER_H
#define SERIAL_CONTROLLER_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <functional>
#include <vector>
#include "SerialProtocol.h"
#include "../../usecases/SensorUseCases.h"

// JSON command API over USB serial, one command per line.
//
// Built in: `ping`, `info` and `sensor`. Each node configuration registers the commands it
// supports (e.g. `wifi`/`coap` for networked nodes, `time` for nodes with a clock), so a node
// never offers commands that make no sense for it.
class SerialController {
public:
    using Handler = std::function<void(JsonObject&)>;

    SerialController(SensorUseCases* sensor, const String& mac = "", const String& variant = "")
        : sensorUseCases(sensor), deviceMac(mac), variant(variant) {}

    void registerCommand(const String& name, Handler handler) {
        commands.push_back({name, handler});
    }

    void begin() {
        SerialProtocol::ok("Serial controller ready");
    }

    // millis() of the last command received; used to leave service mode when idle
    uint32_t lastActivityMs() const { return lastActivity; }

    void handle() {
        if (Serial.available()) {
            String input = Serial.readStringUntil('\n');
            input.trim();

            if (input.length() == 0) return;
            lastActivity = millis();

            DynamicJsonDocument doc(512);
            DeserializationError error = deserializeJson(doc, input);

            if (error) {
                SerialProtocol::error((String("Invalid JSON: ") + error.c_str()).c_str());
                return;
            }

            String command = doc["command"] | "";
            JsonObject data = doc["data"].as<JsonObject>();

            if (command == "sensor") {
                handleSensorCommand(data);
            } else if (command == "ping") {
                SerialProtocol::ok("pong");
            } else if (command == "info") {
                // Identifies the node to the web setup screen (same MAC sent in CoAP payloads)
                Serial.printf("{\"s\":\"ok\",\"mc\":\"%s\",\"v\":\"%s\"}\n", deviceMac.c_str(),
                              variant.c_str());
            } else if (!dispatchRegistered(command, data)) {
                SerialProtocol::error("Unknown command");
            }
        }
    }

private:
    struct Command {
        String name;
        Handler handler;
    };

    SensorUseCases* sensorUseCases;
    String deviceMac;
    String variant;
    std::vector<Command> commands;
    uint32_t lastActivity = 0;

    bool dispatchRegistered(const String& name, JsonObject& data) {
        for (Command& command : commands) {
            if (command.name == name) {
                command.handler(data);
                return true;
            }
        }
        return false;
    }

    void handleSensorCommand(JsonObject& doc) {
        String action = doc["action"] | "";
        
        if (action == "add") {
            int id = doc["id"] | -1;
            int pin = doc["pin"] | -1;
            String type = doc["type"] | "unknown";
            float precision = doc["precision"] | 1.0f;
            float offset = doc["offset"] | 0.0f;
            String driver = doc["driver"] | SENSOR_DRIVER_ANALOG;
            unsigned long interval = doc["interval"] | 10000;
            
            if (id == -1 || pin == -1) {
                SerialProtocol::error("Missing id or pin");
                return;
            }

            if (!SensorConfig::isKnownDriver(driver)) {
                SerialProtocol::error("Unknown driver");
                return;
            }

            if (sensorUseCases->addSensor(id, pin, type, precision, interval, offset, driver)) {
                SerialProtocol::ok("Sensor added");
            } else {
                SerialProtocol::error("Failed to add sensor");
            }
        } else if (action == "update") {
            int id = doc["id"] | -1;
            int pin = doc["pin"] | -1;
            String type = doc["type"] | "unknown";
            float precision = doc["precision"] | 1.0f;
            float offset = doc["offset"] | 0.0f;
            String driver = doc["driver"] | SENSOR_DRIVER_ANALOG;
            unsigned long interval = doc["interval"] | 10000;
            
            if (id == -1 || pin == -1) {
                SerialProtocol::error("Missing id or pin");
                return;
            }

            if (!SensorConfig::isKnownDriver(driver)) {
                SerialProtocol::error("Unknown driver");
                return;
            }

            if (sensorUseCases->updateSensor(id, pin, type, precision, interval, offset, driver)) {
                SerialProtocol::ok("Sensor updated");
            } else {
                SerialProtocol::error("Failed to update sensor");
            }
        } else if (action == "remove") {
            int id = doc["id"] | -1;
            
            if (sensorUseCases->removeSensor(id)) {
                SerialProtocol::ok("Sensor removed");
            } else {
                SerialProtocol::error("Failed to remove sensor");
            }
        } else if (action == "list") {
            auto sensors = sensorUseCases->getSensors();
            
            DynamicJsonDocument response(2048);
            response["s"] = "ok";
            JsonArray data = response.createNestedArray("d");
            
            for (const auto& sensor : sensors) {
                JsonObject s = data.createNestedObject();
                s["i"] = sensor.id;
                s["p"] = sensor.pin;
                s["t"] = sensor.type;
                s["pr"] = sensor.precision;
                s["o"] = sensor.offset;
                s["dr"] = sensor.driver;
                s["iv"] = sensor.interval_ms;
            }
            
            serializeJson(response, Serial);
            Serial.println();
        } else {
            SerialProtocol::error("Unknown action");
        }
    }
};

#endif // SERIAL_CONTROLLER_H
