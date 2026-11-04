#ifndef NETWORK_COMMANDS_H
#define NETWORK_COMMANDS_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include "SerialProtocol.h"
#include "../../usecases/NetworkUseCases.h"
#include "SerialController.h"

// `wifi` and `coap` serial commands, registered only by configurations with a network.
namespace NetworkCommands {

inline void handleWifiCommand(WifiUseCases* wifiUseCases, JsonObject& doc) {
    String action = doc["action"] | "";
    
    if (action == "set") {
        String ssid = doc["ssid"] | "";
        String password = doc["password"] | "";
        
        if (wifiUseCases->saveConfig(ssid, password)) {
            SerialProtocol::ok("WiFi config saved");
        } else {
            SerialProtocol::error("Failed to save WiFi config");
        }
    } else if (action == "get") {
        WifiConfig config = wifiUseCases->getConfig();
        Serial.printf("{\"s\":\"ok\",\"ss\":\"%s\"}\n", config.ssid.c_str());
    } else {
        SerialProtocol::error("Unknown action");
    }
}

inline void handleCoapCommand(CoapUseCases* coapUseCases, JsonObject& doc) {
    String action = doc["action"] | "";
    
    if (action == "set") {
        String host = doc["host"] | "";
        int port = doc["port"] | 5683;
        
        if (coapUseCases->saveConfig(host, port)) {
            SerialProtocol::ok("CoAP config saved");
        } else {
            SerialProtocol::error("Failed to save CoAP config");
        }
    } else if (action == "get") {
        CoapConfig config = coapUseCases->getConfig();
        Serial.printf("{\"s\":\"ok\",\"h\":\"%s\",\"pt\":%d}\n", config.host.c_str(), config.port);
    } else {
        SerialProtocol::error("Unknown action");
    }
}

inline void registerOn(SerialController& controller, WifiUseCases* wifi, CoapUseCases* coap) {
    controller.registerCommand("wifi", [wifi](JsonObject& data) { handleWifiCommand(wifi, data); });
    controller.registerCommand("coap", [coap](JsonObject& data) { handleCoapCommand(coap, data); });
}

} // namespace NetworkCommands

#endif // NETWORK_COMMANDS_H
