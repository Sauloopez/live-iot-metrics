#ifndef I_FILE_SYSTEM_H
#define I_FILE_SYSTEM_H

#include <stddef.h>
#include <stdint.h>
#include <string>
#include <vector>

// Minimal file system used by the measurement store. Implemented over LittleFS (internal
// flash), the SD card, or memory in the native tests, so the store logic is the same for all.
class IFileSystem {
public:
    virtual ~IFileSystem() = default;

    virtual bool exists(const std::string& path) = 0;
    virtual bool mkdirs(const std::string& dir) = 0;

    // File names (not full paths) directly inside `dir`
    virtual std::vector<std::string> list(const std::string& dir) = 0;

    // Reads up to `len` bytes starting at `offset`; returns the number of bytes read
    virtual size_t read(const std::string& path, size_t offset, uint8_t* buf, size_t len) = 0;

    // Appends to the file, creating it if needed
    virtual bool append(const std::string& path, const uint8_t* data, size_t len) = 0;

    // Replaces the whole file so that a power loss leaves either the old or the new content
    virtual bool writeAtomic(const std::string& path, const uint8_t* data, size_t len) = 0;

    virtual bool remove(const std::string& path) = 0;

    virtual uint64_t freeBytes() = 0;
    virtual uint64_t totalBytes() = 0;
};

#endif // I_FILE_SYSTEM_H
