#ifndef SENSOR_READER_H
#define SENSOR_READER_H

#include <Arduino.h>
#include <map>
#include <DHTesp.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include "../../domain/entities/SensorConfig.h"

// Reads a sensor according to its driver. Digital buses are created lazily and
// shared per pin, so a DHT22 can expose temperature and humidity as two sensors.
class SensorReader {
private:
    std::map<int, DHTesp*> dhtByPin;
    std::map<int, OneWire*> oneWireByPin;
    std::map<int, DallasTemperature*> dallasByPin;

    DHTesp* dht(int pin) {
        auto it = dhtByPin.find(pin);
        if (it != dhtByPin.end()) return it->second;

        DHTesp* sensor = new DHTesp();
        sensor->setup(pin, DHTesp::DHT22);
        dhtByPin[pin] = sensor;
        return sensor;
    }

    DallasTemperature* dallas(int pin) {
        auto it = dallasByPin.find(pin);
        if (it != dallasByPin.end()) return it->second;

        OneWire* bus = new OneWire(pin);
        DallasTemperature* sensor = new DallasTemperature(bus);
        sensor->begin();
        oneWireByPin[pin] = bus;
        dallasByPin[pin] = sensor;
        return sensor;
    }

    bool readAnalog(int pin, float& out) {
        // Average several samples for stability
        long sum = 0;
        for (int i = 0; i < 10; i++) {
            sum += analogRead(pin);
            delay(2);
        }
        out = (float)sum / 10.0f;
        return true;
    }

    bool readDht(int pin, bool humidity, float& out) {
        // DHTesp returns the cached values when called before the 2s minimum sampling period
        TempAndHumidity data = dht(pin)->getTempAndHumidity();
        out = humidity ? data.humidity : data.temperature;
        return !isnan(out);
    }

    bool readDs18b20(int pin, float& out) {
        DallasTemperature* sensor = dallas(pin);
        sensor->requestTemperatures();
        out = sensor->getTempCByIndex(0);
        return out != DEVICE_DISCONNECTED_C;
    }

public:
    // Prepares the pin for the sensor driver. Digital drivers initialize their bus on first read.
    void begin(const SensorConfig& sensor) {
        if (sensor.driver == SENSOR_DRIVER_ANALOG) {
            pinMode(sensor.pin, INPUT);
        }
    }

    // Returns false when the hardware did not provide a valid reading.
    bool read(const SensorConfig& sensor, float& out) {
        if (sensor.driver == SENSOR_DRIVER_ANALOG) return readAnalog(sensor.pin, out);
        if (sensor.driver == SENSOR_DRIVER_DHT22_TEMP) return readDht(sensor.pin, false, out);
        if (sensor.driver == SENSOR_DRIVER_DHT22_HUM) return readDht(sensor.pin, true, out);
        if (sensor.driver == SENSOR_DRIVER_DS18B20) return readDs18b20(sensor.pin, out);
        return false;
    }
};

#endif // SENSOR_READER_H
