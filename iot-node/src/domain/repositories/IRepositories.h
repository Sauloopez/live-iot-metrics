#ifndef I_REPOSITORIES_H
#define I_REPOSITORIES_H

#include "../entities/WifiConfig.h"
#include "../entities/CoapConfig.h"
#include "../entities/SensorConfig.h"
#include <vector>

class IWifiConfigRepository {
public:
    virtual ~IWifiConfigRepository() = default;
    virtual WifiConfig load() = 0;
    virtual bool save(const WifiConfig& config) = 0;
};

class ICoapConfigRepository {
public:
    virtual ~ICoapConfigRepository() = default;
    virtual CoapConfig load() = 0;
    virtual bool save(const CoapConfig& config) = 0;
};

class ISensorConfigRepository {
public:
    virtual ~ISensorConfigRepository() = default;
    virtual std::vector<SensorConfig> loadAll() = 0;
    virtual bool saveAll(const std::vector<SensorConfig>& sensors) = 0;
    virtual bool add(const SensorConfig& sensor) = 0;
    virtual bool update(const SensorConfig& sensor) = 0;
    virtual bool remove(int id) = 0;
};

#endif // I_REPOSITORIES_H