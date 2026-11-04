#ifndef LITTLE_FS_FILE_SYSTEM_H
#define LITTLE_FS_FILE_SYSTEM_H

#include <LittleFS.h>
#include "../../domain/repositories/IFileSystem.h"

// IFileSystem over an ESP32 LittleFS instance (internal flash). Pass a dedicated instance
// mounted on its own partition so measurements never compete with the configuration files.
class LittleFsFileSystem : public IFileSystem {
public:
    explicit LittleFsFileSystem(fs::LittleFSFS& fs) : fs(fs) {}

    bool exists(const std::string& path) override { return fs.exists(path.c_str()); }

    bool mkdirs(const std::string& dir) override {
        return fs.exists(dir.c_str()) || fs.mkdir(dir.c_str());
    }

    std::vector<std::string> list(const std::string& dir) override {
        std::vector<std::string> names;
        File root = fs.open(dir.c_str());
        if (!root || !root.isDirectory()) return names;

        for (File entry = root.openNextFile(); entry; entry = root.openNextFile()) {
            std::string name = entry.name();
            size_t slash = name.rfind('/');
            names.push_back(slash == std::string::npos ? name : name.substr(slash + 1));
            entry.close();
        }
        root.close();
        return names;
    }

    size_t read(const std::string& path, size_t offset, uint8_t* buf, size_t len) override {
        File file = fs.open(path.c_str(), FILE_READ);
        if (!file) return 0;
        size_t n = 0;
        if (file.seek(offset)) n = file.read(buf, len);
        file.close();
        return n;
    }

    bool append(const std::string& path, const uint8_t* data, size_t len) override {
        File file = fs.open(path.c_str(), FILE_APPEND);
        if (!file) return false;
        size_t written = file.write(data, len);
        file.close();  // close commits the data to flash
        return written == len;
    }

    bool writeAtomic(const std::string& path, const uint8_t* data, size_t len) override {
        std::string tmp = path + ".tmp";
        File file = fs.open(tmp.c_str(), FILE_WRITE);
        if (!file) return false;
        size_t written = file.write(data, len);
        file.close();
        if (written != len) {
            fs.remove(tmp.c_str());
            return false;
        }
        // LittleFS renames atomically, replacing the destination
        if (fs.rename(tmp.c_str(), path.c_str())) return true;

        // Fallback if the platform refuses to overwrite: not atomic, but the old state is
        // only gone once the new one is fully written in the .tmp file
        fs.remove(path.c_str());
        return fs.rename(tmp.c_str(), path.c_str());
    }

    bool remove(const std::string& path) override { return fs.remove(path.c_str()); }

    uint64_t freeBytes() override { return fs.totalBytes() - fs.usedBytes(); }
    uint64_t totalBytes() override { return fs.totalBytes(); }

private:
    fs::LittleFSFS& fs;
};

#endif // LITTLE_FS_FILE_SYSTEM_H
