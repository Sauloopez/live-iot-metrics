// Isolated node: measures on a fixed schedule, stores everything in its internal flash and
// sleeps in between. An operator extracts the data over USB (docs/tundra/PLAN.md, section 6.1).
//
// Every wake-up starts here (deep sleep restarts the CPU):
//   * woken by the timer      -> measure, store, sleep again
//   * powered on / BOOT button -> service mode: stay awake attending USB until idle
#include <Arduino.h>
#include <LittleFS.h>
#include <Wire.h>

#include "../shared/presentation/controllers/SerialProtocol.h"
#include "../shared/infrastructure/power/BatteryMonitor.h"
#include "../shared/infrastructure/power/PowerManager.h"
#include "../shared/infrastructure/repositories/LittleFsSensorRepository.h"
#include "../shared/infrastructure/sensors/SensorReader.h"
#include "../shared/infrastructure/storage/LittleFsFileSystem.h"
#include "../shared/infrastructure/storage/SegmentedMeasurementStore.h"
#include "../shared/infrastructure/storage/StorageTask.h"
#include "../shared/infrastructure/system/DeviceMac.h"
#include "../shared/infrastructure/time/Ds3231Clock.h"
#include "../shared/infrastructure/time/NodeClock.h"
#include "../shared/presentation/controllers/ClockCommands.h"
#include "../shared/presentation/controllers/SerialController.h"
#include "../shared/usecases/SensorUseCases.h"
#include "../shared/usecases/WakeCycle.h"
#include "presentation/controllers/StatusCommands.h"

// --- Board profile (docs/tundra/PLAN.md, section 4.7) ---
static const int PIN_I2C_SDA = 21;
static const int PIN_I2C_SCL = 22;
static const gpio_num_t PIN_SERVICE_BUTTON = GPIO_NUM_0;  // BOOT button
static const gpio_num_t PIN_POWER_SWITCH = GPIO_NUM_25;   // MOSFET for sensors / SD
static const uint8_t PIN_BATTERY = 39;
static const uint32_t BATTERY_R1 = 100000;  // divider: Vbat -> R1 -> pin -> R2 -> GND
static const uint32_t BATTERY_R2 = 100000;

// --- Behaviour ---
static const uint32_t MIN_CYCLE_SECONDS = 10;
static const uint32_t SERVICE_IDLE_TIMEOUT_MS = 5 * 60 * 1000;
static const uint32_t NO_SENSORS_SLEEP_SECONDS = 60 * 60;
static const TickType_t STORAGE_FLUSH_TIMEOUT = pdMS_TO_TICKS(5000);

// --- Components ---
LittleFsSensorRepository sensorRepo;  // configuration, on the default "spiffs" partition
SensorUseCases sensorUseCases(&sensorRepo);
SensorReader sensorReader;

fs::LittleFSFS dataFs;                 // measurements, on their own "data" partition
LittleFsFileSystem dataFiles(dataFs);
SegmentedMeasurementStore store(dataFiles, "/m");
StorageTask storageTask(store);

Ds3231Clock rtc(Wire);
NodeClock nodeClock(rtc);
PowerManager power(PIN_SERVICE_BUTTON, PIN_POWER_SWITCH);
BatteryMonitor battery(PIN_BATTERY, BATTERY_R1, BATTERY_R2);

SerialController* serialController = nullptr;
uint32_t serviceStartedMs = 0;

// Every wake reads all sensors; the cycle follows the fastest configured sensor
static uint32_t cycleSeconds(const std::vector<SensorConfig>& sensors) {
    uint32_t shortest = UINT32_MAX;
    for (const auto& s : sensors) shortest = std::min<uint32_t>(shortest, s.interval_ms / 1000);
    return std::max(shortest, MIN_CYCLE_SECONDS);
}

static void measureOnce(const std::vector<SensorConfig>& sensors) {
    // Measurements taken without a valid clock are stored with ts = 0 (time unknown)
    uint32_t ts = nodeClock.isValid() ? nodeClock.now() : 0;

    power.powerPeripherals(true, 50);
    for (const auto& sensor : sensors) {
        sensorReader.begin(sensor);
        float raw;
        if (sensorReader.read(sensor, raw)) {
            storageTask.enqueue(ts, static_cast<uint16_t>(sensor.id), sensor.apply(raw), pdMS_TO_TICKS(100));
        } else {
            Serial.printf("Sensor %d (pin %d, %s): no valid reading\n", sensor.id, sensor.pin, sensor.driver.c_str());
        }
    }
    power.powerPeripherals(false);
}

[[noreturn]] static void sleepUntilNextCycle(const std::vector<SensorConfig>& sensors) {
    storageTask.waitUntilIdle(STORAGE_FLUSH_TIMEOUT);

    uint32_t seconds = sensors.empty()
                           ? NO_SENSORS_SLEEP_SECONDS
                           : WakeCycle::secondsUntilNextWake(nodeClock.now(), nodeClock.isValid(), cycleSeconds(sensors));
    power.deepSleep(seconds);
}

static void startServiceMode() {
    serialController = new SerialController(&sensorUseCases, deviceMac(), "isolated");
    ClockCommands::registerOn(*serialController, &nodeClock);
    StatusCommands::registerOn(*serialController, {&nodeClock, &dataFiles, &storageTask, &battery, &power});
    serialController->begin();
    serviceStartedMs = millis();
}

void setup() {
    power.begin();
    Serial.begin(115200);
    Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
    nodeClock.begin();

    sensorRepo.begin();
    if (!dataFs.begin(true, "/measurements", 5, "data") || !store.open() || !storageTask.begin()) {
        SerialProtocol::error("Measurement storage unavailable");
    }

    std::vector<SensorConfig> sensors = sensorUseCases.getSensors();
    WakeCycle::Action action = WakeCycle::decide(power.wakeReason(), !sensors.empty());

    if (action == WakeCycle::Action::Measure) {
        measureOnce(sensors);
        sleepUntilNextCycle(sensors);
    }
    startServiceMode();
}

void loop() {
    serialController->handle();

    uint32_t lastActivity = std::max(serialController->lastActivityMs(), serviceStartedMs);
    if (WakeCycle::serviceModeExpired(millis(), lastActivity, SERVICE_IDLE_TIMEOUT_MS)) {
        SerialProtocol::ok("Service mode idle, going to sleep");
        sleepUntilNextCycle(sensorUseCases.getSensors());
    }
    delay(5);
}
