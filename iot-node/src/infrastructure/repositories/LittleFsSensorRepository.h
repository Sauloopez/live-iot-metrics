#ifndef LITTLE_FS_SENSOR_REPOSITORY_H
#define LITTLE_FS_SENSOR_REPOSITORY_H

#include <LittleFS.h>
#include "../../domain/repositories/IRepositories.h"
#include <vector>

class LittleFsSensorRepository : public ISensorConfigRepository {
private:
    const char* FILENAME = "/sensors.csv";

    std::vector<String> split(const String& str, char delim) {
        std::vector<String> tokens;
        int start = 0;
        int end = str.indexOf(delim);
        while (end != -1) {
            tokens.push_back(str.substring(start, end));
            start = end + 1;
            end = str.indexOf(delim, start);
        }
        tokens.push_back(str.substring(start));
        return tokens;
    }

public:
    LittleFsSensorRepository() {
        if (!LittleFS.begin(true)) {
            Serial.println("LittleFS Mount Failed");
        }
    }

    std::vector<SensorConfig> loadAll() override {
        std::vector<SensorConfig> sensors;
        
        File file = LittleFS.open(FILENAME, "r");
        if (!file) {
            return sensors;
        }

        while (file.available()) {
            String line = file.readStringUntil('\n');
            line.trim();
            if (line.length() == 0) continue;

            std::vector<String> tokens = split(line, ',');
            // Format: id,pin,type,precision,interval[,offset] (offset optional for files written before it existed)
            if (tokens.size() == 5 || tokens.size() == 6) {
                int id = tokens[0].toInt();
                int pin = tokens[1].toInt();
                String type = tokens[2];
                float precision = tokens[3].toFloat();
                unsigned long interval = tokens[4].toInt(); // toInt() works up to long in Arduino String
                float offset = tokens.size() == 6 ? tokens[5].toFloat() : 0.0f;
                
                sensors.push_back(SensorConfig(id, pin, type, precision, interval, offset));
            }
        }
        
        file.close();
        return sensors;
    }

    bool saveAll(const std::vector<SensorConfig>& sensors) override {
        File file = LittleFS.open(FILENAME, "w");
        if (!file) {
            return false;
        }

        for (const auto& s : sensors) {
            file.print(s.id);
            file.print(",");
            file.print(s.pin);
            file.print(",");
            file.print(s.type);
            file.print(",");
            file.print(s.precision, 6);
            file.print(",");
            file.print(s.interval_ms);
            file.print(",");
            file.println(s.offset, 6);
        }

        file.close();
        return true;
    }

    bool add(const SensorConfig& sensor) override {
        auto sensors = loadAll();
        for (const auto& s : sensors) {
            if (s.id == sensor.id) {
                return false; // Already exists
            }
        }
        sensors.push_back(sensor);
        return saveAll(sensors);
    }

    bool update(const SensorConfig& sensor) override {
        auto sensors = loadAll();
        bool found = false;
        for (auto& s : sensors) {
            if (s.id == sensor.id) {
                s = sensor;
                found = true;
                break;
            }
        }
        if (!found) return false;
        return saveAll(sensors);
    }

    bool remove(int id) override {
        auto sensors = loadAll();
        bool found = false;
        std::vector<SensorConfig> updated;
        
        for (const auto& s : sensors) {
            if (s.id == id) {
                found = true;
            } else {
                updated.push_back(s);
            }
        }
        
        if (!found) return false;
        return saveAll(updated);
    }
};

#endif // LITTLE_FS_SENSOR_REPOSITORY_H