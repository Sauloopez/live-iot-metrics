#ifndef CLOCK_COMMANDS_H
#define CLOCK_COMMANDS_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include "SerialProtocol.h"
#include "../../domain/repositories/IClock.h"
#include "SerialController.h"

// `time` serial command for nodes that stamp measurements with their own clock. The setup
// screen sends the browser time on every connection, so the clock is corrected on each visit.
namespace ClockCommands {

inline void handleTimeCommand(IClock* clock, JsonObject& doc) {
    String action = doc["action"] | "";

    if (action == "get") {
        Serial.printf("{\"s\":\"ok\",\"t\":%lu,\"v\":%s}\n", static_cast<unsigned long>(clock->now()),
                      clock->isValid() ? "true" : "false");
    } else if (action == "set") {
        uint32_t ts = doc["ts"] | 0UL;
        if (ts < 1704067200UL) {  // before 2024: certainly not the current time
            SerialProtocol::error("Invalid timestamp");
        } else if (clock->set(ts)) {
            SerialProtocol::ok("Time set");
        } else {
            SerialProtocol::error("Failed to set time");
        }
    } else {
        SerialProtocol::error("Unknown action");
    }
}

inline void registerOn(SerialController& controller, IClock* clock) {
    controller.registerCommand("time", [clock](JsonObject& data) { handleTimeCommand(clock, data); });
}

} // namespace ClockCommands

#endif // CLOCK_COMMANDS_H
