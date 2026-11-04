#ifndef WAKE_CYCLE_H
#define WAKE_CYCLE_H

#include <stdint.h>

// Decisions taken on every wake-up of a sleeping node. Pure logic, no hardware access.
namespace WakeCycle {

enum class WakeReason { PowerOn, Timer, ServiceButton, Other };

enum class Action {
    Measure,  // read sensors, store, go back to sleep
    Service   // stay awake attending USB (configuration, data extraction)
};

// Woken by the timer: measure. Powered on or woken by the button: an operator is there, so
// stay awake for USB. Without sensors there is nothing to measure, so stay reachable too.
inline Action decide(WakeReason reason, bool hasSensors) {
    if (reason == WakeReason::Timer && hasSensors) return Action::Measure;
    if (reason == WakeReason::Other && hasSensors) return Action::Measure;
    return Action::Service;
}

// Seconds to sleep so wake-ups land on a fixed grid (e.g. every 15 min at :00, :15, :30, :45).
// Aligned measurements of several nodes are easier to compare, and the grid does not drift
// with the time each cycle spends awake. Without a valid clock, sleep the plain interval.
// If the next slot is closer than `minSleepSec`, the one after it is used.
inline uint32_t secondsUntilNextWake(uint32_t nowUnix, bool clockValid, uint32_t intervalSec,
                                     uint32_t minSleepSec = 2) {
    if (intervalSec == 0) intervalSec = 1;
    if (!clockValid) return intervalSec;

    uint32_t remaining = intervalSec - (nowUnix % intervalSec);
    if (remaining < minSleepSec) remaining += intervalSec;
    return remaining;
}

// Service mode ends after `idleTimeoutMs` without USB activity, so a node left in service
// mode by mistake goes back to measuring instead of draining the battery.
inline bool serviceModeExpired(uint32_t nowMs, uint32_t lastActivityMs, uint32_t idleTimeoutMs) {
    return nowMs - lastActivityMs >= idleTimeoutMs;  // unsigned math survives millis() overflow
}

} // namespace WakeCycle

#endif // WAKE_CYCLE_H
