#ifndef STATUS_COMMANDS_H
#define STATUS_COMMANDS_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include "../../domain/repositories/IClock.h"
#include "../../domain/repositories/IFileSystem.h"
#include "../../infrastructure/power/BatteryMonitor.h"
#include "../../infrastructure/power/PowerManager.h"
#include "../../infrastructure/storage/StorageTask.h"
#include "SerialController.h"

// `status` serial command: battery, clock, storage and power counters of a node with local
// storage. fill() builds the same document for `POST /status` over CoAP.
//
// Response (one line; keys documented in SerialProtocol.h and docs/tundra/SERIAL_API.md):
//
//   {"s":"ok",
//    "c":  {"t":1762164450,"v":true},                         clock: Unix time, valid
//    "b":  {"mv":3912,"p":69},                                battery: millivolts, percent
//    "st": {"n":1201,"a":1000,"pd":200,"f":2097152,"tt":2228224,"fw":0}
//                                                             storage: next seq, acked seq,
//                                                             pending, free / total bytes,
//                                                             failed writes
//    "pw": {"bc":96,"aw":153000,"rr":8}}                       power: boot count, awake ms,
//                                                             reset reason (esp_reset_reason_t)
namespace StatusCommands {

struct Dependencies {
    IClock* clock;
    IFileSystem* dataFiles;
    StorageTask* storage;
    BatteryMonitor* battery;
    PowerManager* power;
};

inline void fill(JsonDocument& doc, const Dependencies& deps) {
    StoreStatus store{1, 0};
    deps.storage->withStore([&](IMeasurementStore& s) { store = s.status(); });
    BatteryMonitor::Reading battery = deps.battery->read();
    const RuntimeState& runtime = deps.power->state();

    doc["s"] = "ok";
    doc["c"]["t"] = deps.clock->now();
    doc["c"]["v"] = deps.clock->isValid();
    doc["b"]["mv"] = battery.millivolts;
    doc["b"]["p"] = battery.percent;
    doc["st"]["n"] = store.nextSeq;
    doc["st"]["a"] = store.ackedSeq;
    doc["st"]["pd"] = store.pending();
    doc["st"]["f"] = deps.dataFiles->freeBytes();
    doc["st"]["tt"] = deps.dataFiles->totalBytes();
    doc["st"]["fw"] = deps.storage->failedWrites();
    doc["pw"]["bc"] = runtime.bootCount;
    doc["pw"]["aw"] = runtime.awakeMsTotal + millis();
    doc["pw"]["rr"] = static_cast<int>(deps.power->resetReason());
}

inline void handleStatus(const Dependencies& deps) {
    DynamicJsonDocument doc(768);
    fill(doc, deps);
    serializeJson(doc, Serial);
    Serial.println();
}

inline void registerOn(SerialController& controller, const Dependencies& deps) {
    controller.registerCommand("status", [deps](JsonObject&) { handleStatus(deps); });
}

} // namespace StatusCommands

#endif // STATUS_COMMANDS_H
