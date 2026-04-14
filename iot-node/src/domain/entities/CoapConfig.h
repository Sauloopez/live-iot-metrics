#ifndef COAP_CONFIG_H
#define COAP_CONFIG_H

#include <Arduino.h>

struct CoapConfig {
    String host;
    int port;

    CoapConfig() : host(""), port(5683) {}
    CoapConfig(String h, int p) : host(h), port(p) {}

    bool isValid() const {
        return host.length() > 0 && port > 0;
    }
};

#endif // COAP_CONFIG_H
