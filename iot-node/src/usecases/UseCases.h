#ifndef USE_CASES_H
#define USE_CASES_H

#include "../domain/repositories/IRepositories.h"
#include <vector>

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

class SensorUseCases {
private:
    ISensorConfigRepository* repository;

public:
    SensorUseCases(ISensorConfigRepository* repo) : repository(repo) {}

    std::vector<SensorConfig> getSensors() {
        return repository->loadAll();
    }

    bool addSensor(int id, int pin, const String& type, float precision, unsigned long interval_ms) {
        SensorConfig sensor(id, pin, type, precision, interval_ms);
        if (!sensor.isValid()) return false;
        return repository->add(sensor);
    }

    bool updateSensor(int id, int pin, const String& type, float precision, unsigned long interval_ms) {
        SensorConfig sensor(id, pin, type, precision, interval_ms);
        if (!sensor.isValid()) return false;
        return repository->update(sensor);
    }

    bool removeSensor(int id) {
        return repository->remove(id);
    }
};

#endif // USE_CASES_H
