#ifndef MEASUREMENT_H
#define MEASUREMENT_H

#include <stdint.h>

// One sensor value taken by the node. `seq` is assigned by the store and grows by one for
// every measurement the node ever records, so the server can confirm "everything up to N".
struct Measurement {
    uint32_t seq;
    uint32_t ts;        // Unix time in seconds, from the node clock
    uint16_t sensorId;
    float value;
};

// Synchronization progress of the local store.
struct StoreStatus {
    uint32_t nextSeq;   // seq the next measurement will get
    uint32_t ackedSeq;  // highest seq confirmed by the server (0 = none)

    uint32_t pending() const { return nextSeq - 1 - ackedSeq; }
};

#endif // MEASUREMENT_H
