#ifndef GATEWAY_FORWARDER_H
#define GATEWAY_FORWARDER_H

#include <stdint.h>
#include "../../shared/domain/repositories/ISyncTransport.h"
#include "../infrastructure/OriginStores.h"

// LoRa gateway node, sending side: forwards the custody stores to the server over CoAP. Each
// field node is synced with its own RemoteSync (its MAC and seq), so the server needs nothing
// special for LoRa. Origins take turns so a big backlog does not starve the rest.
class GatewayForwarder {
public:
    struct Result {
        uint32_t exchanges = 0;
        uint32_t serverTime = 0;
        bool transportError = false;
    };

    // Up to `exchangesPerOrigin` exchanges for each field node with pending data
    Result run(OriginStores& origins, ISyncTransport& transport, uint32_t exchangesPerOrigin) {
        Result result;
        size_t n = origins.size();
        for (size_t k = 0; k < n; k++) {
            OriginStores::Origin& origin = origins.at((next + k) % n);
            if (origin.store->status().pending() == 0) continue;

            RemoteSync::Result r = origin.forward->run(*origin.store, transport, exchangesPerOrigin);
            result.exchanges += r.frames;
            if (r.serverTime) result.serverTime = r.serverTime;
            if (r.transportError) {
                result.transportError = true;  // the server is unreachable: try again later
                next = (next + k) % n;
                return result;
            }
        }
        if (n) next = (next + 1) % n;
        return result;
    }

private:
    size_t next = 0;
};

#endif // GATEWAY_FORWARDER_H
