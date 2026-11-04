#ifndef I_CLOCK_H
#define I_CLOCK_H

#include <stdint.h>

// Wall clock of the node (UTC, Unix seconds). Measurements are stamped with it, so it must
// say when the time is not trustworthy instead of returning a made up value.
class IClock {
public:
    virtual ~IClock() = default;

    // False until the time was set at least once (by USB or the server) and kept running
    virtual bool isValid() = 0;

    virtual uint32_t now() = 0;

    virtual bool set(uint32_t unixTime) = 0;
};

#endif // I_CLOCK_H
