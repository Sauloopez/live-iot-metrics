#ifndef SENSOR_CONFIG_H
#define SENSOR_CONFIG_H

#include <Arduino.h>

struct SensorConfig {
    int id;
    int pin;
    String type;
    float precision;
    unsigned long interval_ms;

    SensorConfig() : id(0), pin(-1), type("unknown"), precision(1.0), interval_ms(10000) {}
    
    SensorConfig(int i, int p, String t, float prec, unsigned long interval) 
        : id(i), pin(p), type(t), precision(prec), interval_ms(interval) {}

    bool isValid() const {
        return pin >= 0 && interval_ms > 0;
    }
};

#endif // SENSOR_CONFIG_H