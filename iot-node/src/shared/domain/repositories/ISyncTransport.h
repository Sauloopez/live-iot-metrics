#ifndef I_SYNC_TRANSPORT_H
#define I_SYNC_TRANSPORT_H

#include <stddef.h>
#include <stdint.h>

// Request/response link to the server used to push stored measurements (CoAP today, LoRa
// later). One call sends `MAC · DATA frame` and waits for the server's answer.
class ISyncTransport {
public:
    virtual ~ISyncTransport() = default;

    // Returns false if the server could not be reached or did not answer in time
    virtual bool exchange(const uint8_t* request, size_t requestLen, uint8_t* response, size_t responseCap,
                          size_t* responseLen) = 0;
};

#endif // I_SYNC_TRANSPORT_H
