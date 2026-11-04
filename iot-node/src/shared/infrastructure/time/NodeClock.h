#ifndef NODE_CLOCK_H
#define NODE_CLOCK_H

#include <sys/time.h>
#include <time.h>
#include "../../domain/repositories/IClock.h"
#include "Ds3231Clock.h"

// Clock used by the node: the DS3231 when it is mounted, the ESP32 internal clock otherwise.
//
// On boot the DS3231 time is copied to the system clock, so the rest of the firmware (and
// libraries) can use time() without touching I2C. The internal clock keeps running through
// deep sleep but not through a power loss, and drifts much more than the DS3231.
class NodeClock : public IClock {
public:
    explicit NodeClock(Ds3231Clock& rtc) : rtc(rtc) {}

    void begin() {
        if (rtc.begin() && rtc.isValid()) {
            uint32_t t = rtc.now();
            if (t != 0) setSystemTime(t);
        }
    }

    bool hasExternalRtc() const { return rtc.isPresent(); }

    bool isValid() override {
        if (rtc.isPresent()) return rtc.isValid();
        return systemNow() >= MIN_VALID_TIME;
    }

    uint32_t now() override { return systemNow(); }

    bool set(uint32_t unixTime) override {
        setSystemTime(unixTime);
        return rtc.isPresent() ? rtc.set(unixTime) : true;
    }

private:
    // Anything before 2024-01-01 means the clock was never set
    static const uint32_t MIN_VALID_TIME = 1704067200;

    Ds3231Clock& rtc;

    static uint32_t systemNow() {
        time_t t = time(nullptr);
        return t > 0 ? static_cast<uint32_t>(t) : 0;
    }

    static void setSystemTime(uint32_t unixTime) {
        struct timeval tv = {static_cast<time_t>(unixTime), 0};
        settimeofday(&tv, nullptr);
    }
};

#endif // NODE_CLOCK_H
