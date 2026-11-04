#ifndef NETWORK_USE_CASES_H
#define NETWORK_USE_CASES_H

#include "../domain/repositories/IRepositories.h"

class WifiUseCases {
private:
    IWifiConfigRepository* repository;

public:
    WifiUseCases(IWifiConfigRepository* repo) : repository(repo) {}

    WifiConfig getConfig() {
        return repository->load();
    }

    bool saveConfig(const String& ssid, const String& password) {
        WifiConfig config(ssid, password);
        return repository->save(config);
    }
};

class CoapUseCases {
private:
    ICoapConfigRepository* repository;

public:
    CoapUseCases(ICoapConfigRepository* repo) : repository(repo) {}

    CoapConfig getConfig() {
        return repository->load();
    }

    bool saveConfig(const String& host, int port) {
        CoapConfig config(host, port);
        return repository->save(config);
    }
};

#endif // NETWORK_USE_CASES_H
