#ifndef FRAME_COUNTER_H
#define FRAME_COUNTER_H

#include <stdint.h>
#include "../../domain/repositories/ICounterStore.h"

// Field node frame counter that never repeats, not even after a power loss, without writing
// flash on every packet: it reserves blocks of BLOCK values and saves only the end of the
// reserved block. After a reboot it continues past that end, skipping what was left unused.
class FrameCounter {
public:
    static const uint32_t BLOCK = 64;

    explicit FrameCounter(ICounterStore& store) : store(store) {}

    void begin() {
        reserved = store.load();
        nextValue = reserved + 1;  // counters start at 1
    }

    // Next counter, or false if it could not be reserved (do not transmit then)
    bool next(uint32_t* value) {
        if (nextValue > reserved) {
            if (nextValue > UINT32_MAX - BLOCK) return false;  // exhausted: the key must be renewed
            if (!store.save(nextValue + BLOCK - 1)) return false;
            reserved = nextValue + BLOCK - 1;
        }
        *value = nextValue++;
        return true;
    }

private:
    ICounterStore& store;
    uint32_t reserved = 0;
    uint32_t nextValue = 1;
};

#endif // FRAME_COUNTER_H
