#ifndef I_COUNTER_STORE_H
#define I_COUNTER_STORE_H

#include <stdint.h>

// Persists the radio frame counter so it never goes back after a power loss (NVS on the ESP32)
class ICounterStore {
public:
    virtual ~ICounterStore() = default;
    virtual uint32_t load() = 0;  // 0 if never saved
    virtual bool save(uint32_t value) = 0;
};

#endif // I_COUNTER_STORE_H
