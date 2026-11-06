#ifndef ORIGIN_STORES_H
#define ORIGIN_STORES_H

#include <stdio.h>
#include <string.h>
#include <string>
#include "../../shared/domain/repositories/IFileSystem.h"
#include "../../shared/infrastructure/storage/SegmentedMeasurementStore.h"
#include "../../shared/usecases/RemoteSync.h"

// Custody stores of a LoRa gateway node: one measurement store per field node, in
// `<root>/<mac as 12 hex digits>/`, keeping the field node's seq. `<root>/index` lists the
// known MACs (6 bytes each) so custody survives a reboot.
//
// Each origin also has its RemoteSync, which forwards that store to the server as if the
// field node itself were sending: the server sees the field node's MAC and seq.
class OriginStores {
public:
    static const size_t CAPACITY = 32;
    static const size_t MAC_SIZE = 6;

    struct Origin {
        uint8_t mac[MAC_SIZE];
        SegmentedMeasurementStore* store;
        RemoteSync* forward;
    };

    explicit OriginStores(IFileSystem& fs, const std::string& root = "/o",
                          uint32_t recordsPerSegment = SegmentedMeasurementStore::DEFAULT_RECORDS_PER_SEGMENT)
        : fs(fs), root(root), recordsPerSegment(recordsPerSegment) {}

    ~OriginStores() {
        for (size_t i = 0; i < count; i++) {
            delete origins[i].store;
            delete origins[i].forward;
        }
    }

    // Opens the stores listed in the index
    bool begin() {
        if (!fs.mkdirs(root)) return false;
        uint8_t index[CAPACITY * MAC_SIZE];
        size_t len = fs.read(indexPath(), 0, index, sizeof(index));
        for (size_t offset = 0; offset + MAC_SIZE <= len; offset += MAC_SIZE) {
            if (!open(index + offset)) return false;
        }
        return true;
    }

    // Store of `mac`; creates it the first time. nullptr if the table is full or it failed
    Origin* get(const uint8_t mac[MAC_SIZE]) {
        Origin* origin = find(mac);
        if (origin || count == CAPACITY) return origin;

        origin = open(mac);
        if (!origin) return nullptr;
        if (!saveIndex()) {
            count--;  // not remembered after a reboot: do not take custody
            delete origin->store;
            delete origin->forward;
            return nullptr;
        }
        return origin;
    }

    Origin* find(const uint8_t mac[MAC_SIZE]) {
        for (size_t i = 0; i < count; i++) {
            if (memcmp(origins[i].mac, mac, MAC_SIZE) == 0) return &origins[i];
        }
        return nullptr;
    }

    size_t size() const { return count; }
    Origin& at(size_t i) { return origins[i]; }

private:
    IFileSystem& fs;
    std::string root;
    uint32_t recordsPerSegment;
    Origin origins[CAPACITY];
    size_t count = 0;

    std::string indexPath() const { return root + "/index"; }

    std::string dirOf(const uint8_t mac[MAC_SIZE]) const {
        char hex[13];
        snprintf(hex, sizeof(hex), "%02x%02x%02x%02x%02x%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        return root + "/" + hex;
    }

    Origin* open(const uint8_t mac[MAC_SIZE]) {
        if (count == CAPACITY) return nullptr;
        SegmentedMeasurementStore* store = new SegmentedMeasurementStore(fs, dirOf(mac), recordsPerSegment);
        if (!store->open()) {
            delete store;
            return nullptr;
        }
        Origin& origin = origins[count++];
        memcpy(origin.mac, mac, MAC_SIZE);
        origin.store = store;
        origin.forward = new RemoteSync(mac);
        return &origin;
    }

    bool saveIndex() {
        uint8_t index[CAPACITY * MAC_SIZE];
        for (size_t i = 0; i < count; i++) memcpy(index + i * MAC_SIZE, origins[i].mac, MAC_SIZE);
        return fs.writeAtomic(indexPath(), index, count * MAC_SIZE);
    }
};

#endif // ORIGIN_STORES_H
