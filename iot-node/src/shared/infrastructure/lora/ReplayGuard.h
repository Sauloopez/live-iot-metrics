#ifndef REPLAY_GUARD_H
#define REPLAY_GUARD_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// Gateway side anti-replay: remembers the last frame counter accepted from each field node and
// rejects anything not newer. Call accept() only for packets whose MIC was verified, otherwise
// a forged packet could push the counter forward and block the real node.
//
// The table has a fixed size: once full, packets from unknown nodes are rejected instead of
// forgetting a known node (forgetting would let its old packets be replayed).
class ReplayGuard {
public:
    static const size_t CAPACITY = 32;
    static const size_t MAC_SIZE = 6;

    bool accept(const uint8_t mac[MAC_SIZE], uint32_t counter) {
        Entry* entry = find(mac);
        if (entry) {
            if (counter <= entry->counter) return false;
            entry->counter = counter;
            return true;
        }
        if (count == CAPACITY) return false;
        memcpy(entries[count].mac, mac, MAC_SIZE);
        entries[count].counter = counter;
        count++;
        return true;
    }

    // Last accepted counter of `mac`, or false if never seen
    bool last(const uint8_t mac[MAC_SIZE], uint32_t* counter) const {
        for (size_t i = 0; i < count; i++) {
            if (memcmp(entries[i].mac, mac, MAC_SIZE) == 0) {
                *counter = entries[i].counter;
                return true;
            }
        }
        return false;
    }

    size_t size() const { return count; }

private:
    struct Entry {
        uint8_t mac[MAC_SIZE];
        uint32_t counter;
    };
    Entry entries[CAPACITY];
    size_t count = 0;

    Entry* find(const uint8_t mac[MAC_SIZE]) {
        for (size_t i = 0; i < count; i++) {
            if (memcmp(entries[i].mac, mac, MAC_SIZE) == 0) return &entries[i];
        }
        return nullptr;
    }
};

#endif // REPLAY_GUARD_H
