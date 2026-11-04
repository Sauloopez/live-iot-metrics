#ifndef POWER_MANAGER_H
#define POWER_MANAGER_H

#include <Arduino.h>
#include <driver/gpio.h>
#include <esp_sleep.h>
#include <esp_system.h>
#include "../../usecases/WakeCycle.h"

// Survives deep sleep (RTC slow memory), lost on power loss or reset.
struct RuntimeState {
    uint32_t magic;
    uint32_t bootCount;      // wake-ups since the last power on
    uint64_t awakeMsTotal;   // time spent awake since the last power on
};

// Deep sleep, wake-up sources and the switch that powers sensors and storage.
class PowerManager {
public:
    PowerManager(gpio_num_t serviceButton, gpio_num_t powerSwitch)
        : serviceButton(serviceButton), powerSwitch(powerSwitch) {}

    // Call first thing in setup()
    void begin() {
        if (rtcState().magic != MAGIC) rtcState() = {MAGIC, 0, 0};
        rtcState().bootCount++;

        // The switch was held low during sleep; release it so it can be driven again
        gpio_hold_dis(powerSwitch);
        gpio_deep_sleep_hold_dis();
        pinMode(powerSwitch, OUTPUT);
        digitalWrite(powerSwitch, LOW);
    }

    WakeCycle::WakeReason wakeReason() const {
        switch (esp_sleep_get_wakeup_cause()) {
            case ESP_SLEEP_WAKEUP_TIMER: return WakeCycle::WakeReason::Timer;
            case ESP_SLEEP_WAKEUP_EXT0: return WakeCycle::WakeReason::ServiceButton;
            case ESP_SLEEP_WAKEUP_UNDEFINED: return WakeCycle::WakeReason::PowerOn;
            default: return WakeCycle::WakeReason::Other;
        }
    }

    esp_reset_reason_t resetReason() const { return esp_reset_reason(); }

    const RuntimeState& state() const { return rtcState(); }

    // Powers sensors (and the SD card) through the MOSFET; waits for them to settle
    void powerPeripherals(bool on, uint32_t settleMs = 20) {
        digitalWrite(powerSwitch, on ? HIGH : LOW);
        if (on && settleMs) delay(settleMs);
    }

    // Never returns: wakes after `seconds` or when the service button (active low) is pressed
    [[noreturn]] void deepSleep(uint32_t seconds) {
        powerPeripherals(false);
        gpio_hold_en(powerSwitch);  // keep peripherals off while sleeping
        gpio_deep_sleep_hold_en();

        esp_sleep_enable_timer_wakeup(static_cast<uint64_t>(seconds) * 1000000ULL);
        esp_sleep_enable_ext0_wakeup(serviceButton, 0);

        rtcState().awakeMsTotal += millis();
        Serial.flush();
        esp_deep_sleep_start();
        for (;;) {}
    }

private:
    static const uint32_t MAGIC = 0x54554E44;  // "TUND"

    gpio_num_t serviceButton;
    gpio_num_t powerSwitch;

    static RuntimeState& rtcState() {
        static RTC_DATA_ATTR RuntimeState state;
        return state;
    }
};

#endif // POWER_MANAGER_H
