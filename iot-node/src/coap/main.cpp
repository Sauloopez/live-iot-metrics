// CoAP node: measures and sends to live-iot over WiFi.
//
// With the "data" partition (partitions/tundra.csv) it stores every measurement first and
// pushes them in batches with confirmation (`POST /sync`), so nothing is lost while WiFi is
// down; it keeps measuring offline and an operator can still extract the data over USB.
// Without that partition it sends each measurement as it is taken (`POST /metrics`).
#include <Arduino.h>
#include <LittleFS.h>
#include <WiFi.h>
#include <Wire.h>
#include <esp_mac.h>
#include <vector>

#include "../shared/infrastructure/coap/CoapClient.h"
#include "../shared/infrastructure/coap/CoapSyncTransport.h"
#include "../shared/infrastructure/power/BatteryMonitor.h"
#include "../shared/infrastructure/power/PowerManager.h"
#include "../shared/infrastructure/repositories/LittleFsSensorRepository.h"
#include "../shared/infrastructure/repositories/NvsRepositories.h"
#include "../shared/infrastructure/sensors/SensorReader.h"
#include "../shared/infrastructure/storage/LittleFsFileSystem.h"
#include "../shared/infrastructure/storage/SegmentedMeasurementStore.h"
#include "../shared/infrastructure/storage/StorageTask.h"
#include "../shared/infrastructure/system/DeviceMac.h"
#include "../shared/infrastructure/time/Ds3231Clock.h"
#include "../shared/infrastructure/time/NodeClock.h"
#include "../shared/infrastructure/time/NtpClient.h"
#include "../shared/presentation/controllers/ClockCommands.h"
#include "../shared/presentation/controllers/NetworkCommands.h"
#include "../shared/presentation/controllers/SerialController.h"
#include "../shared/presentation/controllers/SerialProtocol.h"
#include "../shared/presentation/controllers/StatusCommands.h"
#include "../shared/presentation/controllers/SyncCommands.h"
#include "../shared/usecases/RemoteSync.h"
#include "../shared/usecases/UseCases.h"

// --- Board profile (docs/tundra/PLAN.md, section 4.7) ---
static const int PIN_I2C_SDA = 21;
static const int PIN_I2C_SCL = 22;
static const gpio_num_t PIN_SERVICE_BUTTON = GPIO_NUM_0;
static const gpio_num_t PIN_POWER_SWITCH = GPIO_NUM_25;
static const uint8_t PIN_BATTERY = 39;
static const uint32_t BATTERY_R1 = 100000;
static const uint32_t BATTERY_R2 = 100000;

// --- Behaviour ---
static const uint32_t WIFI_RETRY_MS = 30000;
static const uint32_t SYNC_INTERVAL_MS = 5000;
static const uint32_t STATUS_INTERVAL_MS = 10 * 60 * 1000;
static const uint32_t MAX_FRAMES_PER_SYNC = 8;  // keeps the loop responsive between batches
static const uint32_t MIN_VALID_TIME = 1704067200;  // 2024-01-01

// --- Components ---
NvsWifiConfigRepository wifiRepo;
NvsCoapConfigRepository coapRepo;
LittleFsSensorRepository sensorRepo;
WifiUseCases wifiUseCases(&wifiRepo);
CoapUseCases coapUseCases(&coapRepo);
SensorUseCases sensorUseCases(&sensorRepo);
SensorReader sensorReader;

fs::LittleFSFS dataFs;
LittleFsFileSystem dataFiles(dataFs);
SegmentedMeasurementStore store(dataFiles, "/m");
StorageTask storageTask(store);
SyncCommands syncCommands(storageTask);

Ds3231Clock rtc(Wire);
NodeClock nodeClock(rtc);
NtpClient ntpClient;
PowerManager power(PIN_SERVICE_BUTTON, PIN_POWER_SWITCH);
BatteryMonitor battery(PIN_BATTERY, BATTERY_R1, BATTERY_R2);

CoapClient coapClient;
CoapSyncTransport syncTransport(coapClient);
SerialController* serialController = nullptr;

String macAddress;
uint8_t macBytes[6];
bool storageMode = false;
bool sensorsAnnounced = false;
uint32_t lastWifiAttempt = 0;
uint32_t lastSync = 0;
uint32_t lastStatus = 0;
bool wasConnected = false;

struct SensorState {
    int id;
    uint32_t lastReadMs;
};
std::vector<SensorState> sensorStates;

static void startWifi() {
    WifiConfig config = wifiUseCases.getConfig();
    if (!config.isValid()) return;
    WiFi.mode(WIFI_STA);
    WiFi.begin(config.ssid.c_str(), config.password.c_str());  // non blocking: checked in loop()
    lastWifiAttempt = millis();
}

static uint32_t measurementTime() {
    uint32_t now = nodeClock.now();
    return now >= MIN_VALID_TIME ? now : 0;  // 0 = time unknown
}

static void handleConnected() {
    Serial.printf("WiFi connected: %s\n", WiFi.localIP().toString().c_str());
    ntpClient.begin();
    coapClient.updateConfig(coapUseCases.getConfig());
    sensorsAnnounced = false;
    lastStatus = 0;
}

// `POST /sensors`: the server types the stored measurements with this list
static bool announceSensors() {
    DynamicJsonDocument doc(2048);
    doc["mc"] = macAddress;
    JsonArray list = doc.createNestedArray("d");
    for (const auto& s : sensorUseCases.getSensors()) {
        JsonObject item = list.createNestedObject();
        item["i"] = s.id;
        item["t"] = s.type;
        item["pr"] = s.precision;
    }
    String json;
    serializeJson(doc, json);
    return coapClient.postJson("sensors", json);
}

static void sendStatus() {
    DynamicJsonDocument doc(1024);
    StatusCommands::fill(doc, {&nodeClock, &dataFiles, &storageTask, &battery, &power});
    doc.remove("s");
    doc["mc"] = macAddress;
    doc["v"] = "coap";
    String json;
    serializeJson(doc, json);
    coapClient.postJson("status", json);
}

static void syncStoredMeasurements() {
    if (!sensorsAnnounced) sensorsAnnounced = announceSensors();

    RemoteSync remote(macBytes);
    RemoteSync::Result result;
    storageTask.withStore([&](IMeasurementStore& s) { result = remote.run(s, syncTransport, MAX_FRAMES_PER_SYNC); });

    // No NTP and no RTC: take the time from the server's answer
    if (result.serverTime >= MIN_VALID_TIME && !nodeClock.isValid()) nodeClock.set(result.serverTime);

    if (result.frames > 0) {
        Serial.printf("Sync: %lu frame(s), server has up to seq %lu%s\n", static_cast<unsigned long>(result.frames),
                      static_cast<unsigned long>(result.ackedSeq), result.transportError ? " (server unreachable)" : "");
    }
}

static void readDueSensors(uint32_t nowMs, bool connected) {
    for (const auto& sensor : sensorUseCases.getSensors()) {
        SensorState* state = nullptr;
        for (auto& st : sensorStates) {
            if (st.id == sensor.id) state = &st;
        }
        if (!state) {
            // Added over USB: start measuring on the next interval
            sensorReader.begin(sensor);
            sensorStates.push_back({sensor.id, nowMs});
            continue;
        }
        if (nowMs - state->lastReadMs < sensor.interval_ms) continue;
        state->lastReadMs = nowMs;

        float raw;
        if (!sensorReader.read(sensor, raw)) {
            Serial.printf("Sensor %d (pin %d, %s): no valid reading\n", sensor.id, sensor.pin, sensor.driver.c_str());
            continue;
        }
        float value = sensor.apply(raw);

        if (storageMode) {
            storageTask.enqueue(measurementTime(), static_cast<uint16_t>(sensor.id), value, pdMS_TO_TICKS(100));
        } else if (connected) {
            coapClient.sendMetric(macAddress, sensor.id, sensor.type, sensor.precision, value);
        }
    }
}

void setup() {
    power.begin();
    power.powerPeripherals(true);  // always powered: this node does not sleep
    Serial.begin(115200);
    Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
    nodeClock.begin();
    sensorRepo.begin();

    macAddress = deviceMac();
    esp_read_mac(macBytes, ESP_MAC_WIFI_STA);

    // The data partition only exists with partitions/tundra.csv
    storageMode = dataFs.begin(true, "/measurements", 5, "data") && store.open() && storageTask.begin();

    serialController = new SerialController(&sensorUseCases, macAddress, "coap");
    NetworkCommands::registerOn(*serialController, &wifiUseCases, &coapUseCases);
    if (storageMode) {
        ClockCommands::registerOn(*serialController, &nodeClock);
        StatusCommands::registerOn(*serialController, {&nodeClock, &dataFiles, &storageTask, &battery, &power});
        syncCommands.registerOn(*serialController);
    }
    SerialProtocol::ok("Serial controller ready");
    Serial.printf("Storage: %s\n", storageMode ? "internal flash (store and sync)" : "none (send immediately)");

    coapClient.begin(coapUseCases.getConfig());
    startWifi();

    for (const auto& sensor : sensorUseCases.getSensors()) {
        sensorReader.begin(sensor);
        sensorStates.push_back({sensor.id, 0});
    }
}

void loop() {
    uint32_t now = millis();
    serialController->handle();
    syncCommands.tick();

    bool connected = WiFi.status() == WL_CONNECTED;
    if (connected && !wasConnected) handleConnected();
    if (!connected && now - lastWifiAttempt >= WIFI_RETRY_MS) startWifi();
    wasConnected = connected;

    if (connected) {
        coapClient.loop();
        // NTP keeps the RTC right while the node has a network
        if (nodeClock.now() < MIN_VALID_TIME || !nodeClock.isValid()) {
            time_t t = time(nullptr);
            if (t >= MIN_VALID_TIME) nodeClock.set(static_cast<uint32_t>(t));
        }
    }

    readDueSensors(now, connected);

    // While a USB extraction runs, the serial stream owns the store
    if (storageMode && connected && !syncCommands.isStreaming() && now - lastSync >= SYNC_INTERVAL_MS) {
        lastSync = now;
        syncStoredMeasurements();
        if (lastStatus == 0 || now - lastStatus >= STATUS_INTERVAL_MS) {
            lastStatus = now;
            sendStatus();
        }
    }

    if (!syncCommands.isStreaming()) delay(5);
}
