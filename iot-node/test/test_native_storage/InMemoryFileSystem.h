#ifndef IN_MEMORY_FILE_SYSTEM_H
#define IN_MEMORY_FILE_SYSTEM_H

#include <map>
#include <set>
#include <string>
#include <vector>
#include "../../src/shared/domain/repositories/IFileSystem.h"

// In-memory IFileSystem for native tests. Files survive "reboots" as long as the same
// instance is reused, and failures or power cuts can be simulated.
class InMemoryFileSystem : public IFileSystem {
public:
    std::map<std::string, std::vector<uint8_t>> files;
    std::set<std::string> dirs;
    uint64_t capacity = 1024 * 1024;
    bool failAppends = false;
    bool failAtomicWrites = false;

    bool exists(const std::string& path) override { return files.count(path) || dirs.count(path); }

    bool mkdirs(const std::string& dir) override {
        dirs.insert(dir);
        return true;
    }

    std::vector<std::string> list(const std::string& dir) override {
        std::vector<std::string> names;
        std::string prefix = dir + "/";
        for (const auto& entry : files) {
            const std::string& path = entry.first;
            if (path.compare(0, prefix.size(), prefix) == 0 &&
                path.find('/', prefix.size()) == std::string::npos) {
                names.push_back(path.substr(prefix.size()));
            }
        }
        return names;
    }

    size_t read(const std::string& path, size_t offset, uint8_t* buf, size_t len) override {
        auto it = files.find(path);
        if (it == files.end() || offset >= it->second.size()) return 0;
        size_t n = std::min(len, it->second.size() - offset);
        std::copy(it->second.begin() + offset, it->second.begin() + offset + n, buf);
        return n;
    }

    bool append(const std::string& path, const uint8_t* data, size_t len) override {
        if (failAppends || usedBytes() + len > capacity) return false;
        auto& file = files[path];
        file.insert(file.end(), data, data + len);
        return true;
    }

    bool writeAtomic(const std::string& path, const uint8_t* data, size_t len) override {
        if (failAtomicWrites) return false;
        files[path] = std::vector<uint8_t>(data, data + len);
        return true;
    }

    bool remove(const std::string& path) override { return files.erase(path) > 0; }

    uint64_t freeBytes() override { return capacity - usedBytes(); }
    uint64_t totalBytes() override { return capacity; }

    // Simulates a power cut in the middle of the last append
    void cutLastBytes(const std::string& path, size_t count) {
        auto& file = files[path];
        file.resize(file.size() > count ? file.size() - count : 0);
    }

private:
    uint64_t usedBytes() const {
        uint64_t used = 0;
        for (const auto& entry : files) used += entry.second.size();
        return used;
    }
};

#endif // IN_MEMORY_FILE_SYSTEM_H
