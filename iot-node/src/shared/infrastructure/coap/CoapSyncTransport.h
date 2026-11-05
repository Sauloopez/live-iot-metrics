#ifndef COAP_SYNC_TRANSPORT_H
#define COAP_SYNC_TRANSPORT_H

#include "../../domain/repositories/ISyncTransport.h"
#include "CoapClient.h"

// `POST /sync` over CoAP: sends `MAC · DATA frame`, returns `acked_seq · server_time`
// (LiveMetrics.Sync.CoapResources on the server).
class CoapSyncTransport : public ISyncTransport {
public:
    explicit CoapSyncTransport(CoapClient& client) : client(client) {}

    bool exchange(const uint8_t* request, size_t requestLen, uint8_t* response, size_t responseCap,
                  size_t* responseLen) override {
        return client.request("sync", request, requestLen, COAP_APPLICATION_OCTET_STREAM, response, responseCap,
                              responseLen);
    }

private:
    CoapClient& client;
};

#endif // COAP_SYNC_TRANSPORT_H
