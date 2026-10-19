#ifndef SENSOR_CONFIG_H
#define SENSOR_CONFIG_H

#include <Arduino.h>

struct SensorConfig {
    int id;
    int pin;
    String type;
    float precision;
    float offset;
    unsigned long interval_ms;

    SensorConfig() : id(0), pin(-1), type("unknown"), precision(1.0), offset(0.0), interval_ms(10000) {}

    SensorConfig(int i, int p, String t, float prec, unsigned long interval, float off = 0.0f)
        : id(i), pin(p), type(t), precision(prec), offset(off), interval_ms(interval) {}

    bool isValid() const {
        return pin >= 0 && interval_ms > 0;
    }

    // Linear calibration applied to the raw ADC reading: value = raw * precision + offset
    float apply(float rawValue) const {
        return rawValue * precision + offset;
    }
};

#endif // SENSOR_CONFIG_H
