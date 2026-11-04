#ifndef SENSOR_USE_CASES_H
#define SENSOR_USE_CASES_H

#include "../domain/repositories/IRepositories.h"
#include <vector>

class SensorUseCases {
private:
    ISensorConfigRepository* repository;

public:
    SensorUseCases(ISensorConfigRepository* repo) : repository(repo) {}

    std::vector<SensorConfig> getSensors() {
        return repository->loadAll();
    }

    bool addSensor(int id, int pin, const String& type, float precision, unsigned long interval_ms, float offset = 0.0f, const String& driver = SENSOR_DRIVER_ANALOG) {
        SensorConfig sensor(id, pin, type, precision, interval_ms, offset, driver);
        if (!sensor.isValid()) return false;
        return repository->add(sensor);
    }

    bool updateSensor(int id, int pin, const String& type, float precision, unsigned long interval_ms, float offset = 0.0f, const String& driver = SENSOR_DRIVER_ANALOG) {
        SensorConfig sensor(id, pin, type, precision, interval_ms, offset, driver);
        if (!sensor.isValid()) return false;
        return repository->update(sensor);
    }

    bool removeSensor(int id) {
        return repository->remove(id);
    }
};

#endif // SENSOR_USE_CASES_H
