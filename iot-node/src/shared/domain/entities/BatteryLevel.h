#ifndef BATTERY_LEVEL_H
#define BATTERY_LEVEL_H

#include <stddef.h>
#include <stdint.h>

// State of charge of a single Li-ion / LiPo cell from its resting voltage.
// The discharge curve is not linear, so a linear 3.0–4.2 V map would show 50% while the cell
// still has most of its energy; this table follows a typical cell curve.
namespace BatteryLevel {

struct Point {
    uint16_t millivolts;
    uint8_t percent;
};

static const Point CURVE[] = {
    {4200, 100}, {4100, 90}, {4000, 80}, {3920, 70}, {3850, 60}, {3800, 50},
    {3750, 40},  {3700, 30}, {3650, 20}, {3550, 10}, {3450, 5},  {3300, 0},
};

inline uint8_t percentFromMillivolts(uint32_t mv) {
    const size_t n = sizeof(CURVE) / sizeof(CURVE[0]);
    if (mv >= CURVE[0].millivolts) return 100;
    if (mv <= CURVE[n - 1].millivolts) return 0;

    for (size_t i = 1; i < n; i++) {
        if (mv >= CURVE[i].millivolts) {
            const Point& hi = CURVE[i - 1];
            const Point& lo = CURVE[i];
            uint32_t span = hi.millivolts - lo.millivolts;
            uint32_t offset = mv - lo.millivolts;
            return static_cast<uint8_t>(lo.percent + (hi.percent - lo.percent) * offset / span);
        }
    }
    return 0;
}

// Battery voltage from the ADC pin behind a resistive divider (Vbat → R1 → pin → R2 → GND)
inline uint32_t batteryMillivolts(uint32_t pinMillivolts, uint32_t r1Ohms, uint32_t r2Ohms) {
    if (r2Ohms == 0) return 0;
    return static_cast<uint32_t>(static_cast<uint64_t>(pinMillivolts) * (r1Ohms + r2Ohms) / r2Ohms);
}

} // namespace BatteryLevel

#endif // BATTERY_LEVEL_H
