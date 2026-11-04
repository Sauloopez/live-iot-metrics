#ifndef WIFI_CONFIG_H
#define WIFI_CONFIG_H

#include <Arduino.h>

struct WifiConfig {
    String ssid;
    String password;

    WifiConfig() : ssid(""), password("") {}
    WifiConfig(String s, String p) : ssid(s), password(p) {}
    
    bool isValid() const {
        return ssid.length() > 0;
    }
};

#endif // WIFI_CONFIG_H