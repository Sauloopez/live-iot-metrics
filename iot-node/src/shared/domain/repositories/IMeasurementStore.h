#ifndef I_MEASUREMENT_STORE_H
#define I_MEASUREMENT_STORE_H

#include <functional>
#include <stddef.h>
#include <stdint.h>
#include "../entities/Measurement.h"

// Persistent queue of measurements waiting to be confirmed by the server.
class IMeasurementStore {
public:
    using Visitor = std::function<bool(const Measurement&)>;

    virtual ~IMeasurementStore() = default;

    // Stores a measurement and assigns its seq. Returns false if it could not be written.
    virtual bool record(uint32_t ts, uint16_t sensorId, float value, uint32_t* seqOut = nullptr) = 0;

    // Streams stored measurements with seq >= fromSeq, oldest first, without loading them all
    // in memory. Stops after `maxRecords` or when the visitor returns false. Returns how many
    // measurements were visited.
    virtual size_t readFrom(uint32_t fromSeq, size_t maxRecords, const Visitor& visit) = 0;

    // The server has everything up to `seq`: those measurements can be released.
    virtual bool ack(uint32_t seq) = 0;

    virtual StoreStatus status() const = 0;
};

#endif // I_MEASUREMENT_STORE_H
