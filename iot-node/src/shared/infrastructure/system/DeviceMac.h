#ifndef DEVICE_MAC_H
#define DEVICE_MAC_H

#include <Arduino.h>
#include <esp_mac.h>

// Station MAC as "AA:BB:CC:DD:EE:FF". Readable before WiFi starts (or without WiFi at all),
// and the same value networked nodes send in their payloads.
inline String deviceMac() {
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char text[18];
    snprintf(text, sizeof(text), "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4],
             mac[5]);
    return String(text);
}

#endif // DEVICE_MAC_H
