#ifndef NVS_REPOSITORIES_H
#define NVS_REPOSITORIES_H

#include <Preferences.h>
#include "../../domain/repositories/IRepositories.h"

class NvsWifiConfigRepository : public IWifiConfigRepository {
private:
    Preferences preferences;
    const char* NAMESPACE = "wifi_cfg"; // Max length for namespace is 15 chars

public:
    WifiConfig load() override {
        preferences.begin(NAMESPACE, true); // true = read-only
        String ssid = preferences.getString("ssid", "");
        String password = preferences.getString("password", "");
        preferences.end();
        
        return WifiConfig(ssid, password);
    }

    bool save(const WifiConfig& config) override {
        preferences.begin(NAMESPACE, false); // false = read/write
        size_t ssidLen = preferences.putString("ssid", config.ssid);
        size_t passLen = preferences.putString("password", config.password);
        preferences.end();
        
        return (ssidLen > 0 || config.ssid.length() == 0) && 
               (passLen > 0 || config.password.length() == 0);
    }
};

class NvsCoapConfigRepository : public ICoapConfigRepository {
private:
    Preferences preferences;
    const char* NAMESPACE = "coap_cfg";

public:
    CoapConfig load() override {
        preferences.begin(NAMESPACE, true);
        String host = preferences.getString("host", "");
        int port = preferences.getInt("port", 5683);
        preferences.end();
        
        return CoapConfig(host, port);
    }

    bool save(const CoapConfig& config) override {
        preferences.begin(NAMESPACE, false);
        size_t hostLen = preferences.putString("host", config.host);
        size_t portLen = preferences.putInt("port", config.port);
        preferences.end();
        
        return (hostLen > 0 || config.host.length() == 0) && (portLen > 0);
    }
};

#endif // NVS_REPOSITORIES_H