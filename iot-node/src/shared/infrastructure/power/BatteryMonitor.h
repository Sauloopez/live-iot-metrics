#ifndef BATTERY_MONITOR_H
#define BATTERY_MONITOR_H

#include <Arduino.h>
#include "../../domain/entities/BatteryLevel.h"

// Battery voltage through a resistive divider on an ADC1 pin (ADC2 does not work with WiFi).
// analogReadMilliVolts() applies the factory calibration stored in the chip.
class BatteryMonitor {
public:
    struct Reading {
        uint32_t millivolts;
        uint8_t percent;
    };

    BatteryMonitor(uint8_t pin, uint32_t r1Ohms, uint32_t r2Ohms) : pin(pin), r1(r1Ohms), r2(r2Ohms) {}

    Reading read(uint8_t samples = 16) {
        uint32_t sum = 0;
        for (uint8_t i = 0; i < samples; i++) {
            sum += analogReadMilliVolts(pin);
            delayMicroseconds(200);
        }
        uint32_t mv = BatteryLevel::batteryMillivolts(sum / samples, r1, r2);
        return {mv, BatteryLevel::percentFromMillivolts(mv)};
    }

private:
    uint8_t pin;
    uint32_t r1;
    uint32_t r2;
};

#endif // BATTERY_MONITOR_H
