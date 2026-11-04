#ifndef NTP_CLIENT_H
#define NTP_CLIENT_H

#include <Arduino.h>
#include <time.h>

class NtpClient {
private:
    const char* ntpServer1 = "pool.ntp.org";
    const char* ntpServer2 = "time.nist.gov";
    const long  gmtOffset_sec = 0; // We want UTC for ISO 8601
    const int   daylightOffset_sec = 0;

public:
    NtpClient() {}

    void begin() {
        Serial.println("Initializing NTP...");
        configTime(gmtOffset_sec, daylightOffset_sec, ntpServer1, ntpServer2);
    }

    bool isTimeSynced() {
        time_t now;
        time(&now);
        struct tm timeinfo;
        gmtime_r(&now, &timeinfo);
        
        // tm_year is years since 1900. 
        // If year is greater than 120 (i.e. > 2020), we consider it synced.
        return timeinfo.tm_year > 120;
    }

    String getIso8601Time() {
        time_t now;
        time(&now);
        struct tm timeinfo;
        
        if (!gmtime_r(&now, &timeinfo)) {
            return "1970-01-01T00:00:00Z"; // Fallback if time is completely unset
        }

        char buffer[30];
        // Format: YYYY-MM-DDThh:mm:ssZ
        strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
        return String(buffer);
    }
};

#endif // NTP_CLIENT_H