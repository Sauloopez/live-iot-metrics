#ifndef SENSOR_CONFIG_H
#define SENSOR_CONFIG_H

#include <Arduino.h>

// Supported hardware drivers. "analog" reads the raw 12-bit ADC (0..4095),
// the digital drivers return values already expressed in physical units.
#define SENSOR_DRIVER_ANALOG "analog"
#define SENSOR_DRIVER_DHT22_TEMP "dht22_temp"
#define SENSOR_DRIVER_DHT22_HUM "dht22_hum"
#define SENSOR_DRIVER_DS18B20 "ds18b20"

struct SensorConfig {
    int id;
    int pin;
    String type;
    float precision;
    float offset;
    unsigned long interval_ms;
    String driver;

    SensorConfig() : id(0), pin(-1), type("unknown"), precision(1.0), offset(0.0), interval_ms(10000), driver(SENSOR_DRIVER_ANALOG) {}

    SensorConfig(int i, int p, String t, float prec, unsigned long interval, float off = 0.0f, String drv = SENSOR_DRIVER_ANALOG)
        : id(i), pin(p), type(t), precision(prec), offset(off), interval_ms(interval), driver(drv) {}

    static bool isKnownDriver(const String& drv) {
        return drv == SENSOR_DRIVER_ANALOG
            || drv == SENSOR_DRIVER_DHT22_TEMP
            || drv == SENSOR_DRIVER_DHT22_HUM
            || drv == SENSOR_DRIVER_DS18B20;
    }

    bool isValid() const {
        return pin >= 0 && interval_ms > 0 && isKnownDriver(driver);
    }

    // Linear calibration applied to the driver reading: value = raw * precision + offset
    float apply(float rawValue) const {
        return rawValue * precision + offset;
    }
};

#endif // SENSOR_CONFIG_H
