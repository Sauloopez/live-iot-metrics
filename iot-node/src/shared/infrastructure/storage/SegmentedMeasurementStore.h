#ifndef SEGMENTED_MEASUREMENT_STORE_H
#define SEGMENTED_MEASUREMENT_STORE_H

#include <algorithm>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <string.h>
#include <vector>
#include "../../domain/repositories/IFileSystem.h"
#include "../../domain/repositories/IMeasurementStore.h"
#include "MeasurementCodec.h"

// Measurement store over any IFileSystem (internal flash or SD).
//
// Measurements are appended to segment files named after their first seq
// (`<dir>/0000000001.cbor`). Releasing confirmed data deletes whole segments, which is much
// safer on flash than rewriting a big file. `<dir>/state.cbor` keeps the confirmed seq and is
// replaced atomically.
//
// Power loss safety:
//  * a record cut in half at the end of a segment is ignored, and new records go to a new
//    segment so nothing is ever appended after damaged bytes;
//  * the state is written before deleting segments; leftovers are cleaned on the next open();
//  * nextSeq is rebuilt from the last segment, so it is never reused after a reset.
class SegmentedMeasurementStore : public IMeasurementStore {
public:
    static const uint32_t DEFAULT_RECORDS_PER_SEGMENT = 256;  // ~4 KB, one flash block

    SegmentedMeasurementStore(IFileSystem& fs, const std::string& dir = "/data",
                              uint32_t recordsPerSegment = DEFAULT_RECORDS_PER_SEGMENT)
        : fs(fs), dir(dir), recordsPerSegment(recordsPerSegment) {}

    // Loads the state and recovers from an interrupted write. Call once before using the store.
    bool open() {
        if (!fs.mkdirs(dir)) return false;

        state = {1, 0};
        loadState();
        segments.clear();
        currentCount = 0;

        for (const std::string& name : fs.list(dir)) {
            uint32_t first = 0;
            if (parseSegmentName(name, &first)) {
                segments.push_back(first);
            } else if (endsWith(name, ".tmp")) {
                fs.remove(dir + "/" + name);  // an atomic write that never finished
            }
        }
        std::sort(segments.begin(), segments.end());

        if (!segments.empty()) {
            SegmentScan scan = scanSegment(segments.back(), 0, SIZE_MAX, nullptr);
            if (scan.count > 0) state.nextSeq = std::max(state.nextSeq, scan.lastSeq + 1);
            // Never append after damaged bytes: force the next record into a new segment
            currentCount = scan.clean ? scan.count : recordsPerSegment;
        }
        state.nextSeq = std::max(state.nextSeq, state.ackedSeq + 1);

        releaseAckedSegments();
        return true;
    }

    bool record(uint32_t ts, uint16_t sensorId, float value, uint32_t* seqOut = nullptr) override {
        Measurement m{state.nextSeq, ts, sensorId, value};
        uint8_t buf[MeasurementCodec::MAX_RECORD_SIZE];
        size_t len = MeasurementCodec::encode(m, buf, sizeof(buf));
        if (len == 0) return false;

        bool newSegment = segments.empty() || currentCount >= recordsPerSegment;
        uint32_t segment = newSegment ? m.seq : segments.back();
        if (!fs.append(segmentPath(segment), buf, len)) return false;

        if (newSegment) {
            segments.push_back(segment);
            currentCount = 0;
        }
        currentCount++;
        state.nextSeq++;
        if (seqOut) *seqOut = m.seq;
        return true;
    }

    size_t readFrom(uint32_t fromSeq, size_t maxRecords, const Visitor& visit) override {
        fromSeq = std::max(fromSeq, state.ackedSeq + 1);
        if (maxRecords == 0 || fromSeq >= state.nextSeq) return 0;

        // Start at the last segment whose first seq is <= fromSeq
        auto it = std::upper_bound(segments.begin(), segments.end(), fromSeq);
        size_t index = (it == segments.begin()) ? 0 : static_cast<size_t>(it - segments.begin()) - 1;

        size_t visited = 0;
        bool stopped = false;
        for (; index < segments.size() && visited < maxRecords && !stopped; index++) {
            scanSegment(segments[index], fromSeq, maxRecords - visited, [&](const Measurement& m) {
                visited++;
                if (!visit(m)) {
                    stopped = true;
                    return false;
                }
                return true;
            });
        }
        return visited;
    }

    bool ack(uint32_t seq) override {
        seq = std::min(seq, state.nextSeq - 1);
        if (seq <= state.ackedSeq) return true;

        StoreStatus updated = state;
        updated.ackedSeq = seq;
        if (!saveState(updated)) return false;  // keep the data if the state can not be saved

        state = updated;
        releaseAckedSegments();
        return true;
    }

    StoreStatus status() const override { return state; }

    size_t segmentCount() const { return segments.size(); }

private:
    struct SegmentScan {
        uint32_t count = 0;    // valid records in the segment
        uint32_t lastSeq = 0;
        bool clean = true;     // false if the segment ends with damaged or cut bytes
    };

    static const size_t READ_WINDOW = 128;

    IFileSystem& fs;
    std::string dir;
    uint32_t recordsPerSegment;
    StoreStatus state{1, 0};
    std::vector<uint32_t> segments;  // first seq of each segment, ascending
    uint32_t currentCount = 0;       // records in the last segment

    std::string segmentPath(uint32_t first) const {
        char name[24];
        snprintf(name, sizeof(name), "/%010u.cbor", static_cast<unsigned>(first));
        return dir + name;
    }

    std::string statePath() const { return dir + "/state.cbor"; }

    static bool endsWith(const std::string& s, const char* suffix) {
        size_t n = strlen(suffix);
        return s.size() >= n && s.compare(s.size() - n, n, suffix) == 0;
    }

    static bool parseSegmentName(const std::string& name, uint32_t* first) {
        if (name.size() != 15 || !endsWith(name, ".cbor")) return false;
        for (size_t i = 0; i < 10; i++) {
            if (name[i] < '0' || name[i] > '9') return false;
        }
        unsigned long value = strtoul(name.substr(0, 10).c_str(), nullptr, 10);
        if (value == 0 || value > UINT32_MAX) return false;
        *first = static_cast<uint32_t>(value);
        return true;
    }

    void loadState() {
        uint8_t buf[32];
        size_t len = fs.read(statePath(), 0, buf, sizeof(buf));
        StoreStatus loaded{0, 0};
        if (len > 0 && MeasurementCodec::decodeState(buf, len, &loaded)) {
            state = loaded;
        }
    }

    bool saveState(const StoreStatus& s) {
        uint8_t buf[32];
        size_t len = MeasurementCodec::encodeState(s, buf, sizeof(buf));
        return len > 0 && fs.writeAtomic(statePath(), buf, len);
    }

    uint32_t lastSeqOf(size_t index) const {
        return index + 1 < segments.size() ? segments[index + 1] - 1 : state.nextSeq - 1;
    }

    // Deletes segments whose measurements are all confirmed
    void releaseAckedSegments() {
        size_t removed = 0;
        while (removed < segments.size() && lastSeqOf(removed) <= state.ackedSeq) {
            if (!fs.remove(segmentPath(segments[removed]))) break;  // retried on the next ack/open
            removed++;
        }
        if (removed == 0) return;

        bool currentRemoved = removed == segments.size();
        segments.erase(segments.begin(), segments.begin() + removed);
        if (currentRemoved) currentCount = 0;
    }

    // Decodes a segment with a small fixed buffer. Calls `visit` for records with
    // seq >= fromSeq until `max` records were visited or the visitor returns false.
    template <typename Fn>
    SegmentScan scanSegment(uint32_t first, uint32_t fromSeq, size_t max, Fn visit) {
        SegmentScan scan;
        std::string path = segmentPath(first);
        uint8_t buf[READ_WINDOW];
        size_t filled = 0;
        size_t offset = 0;
        size_t visited = 0;
        bool eof = false;

        while (true) {
            if (!eof && filled < sizeof(buf)) {
                size_t n = fs.read(path, offset, buf + filled, sizeof(buf) - filled);
                offset += n;
                filled += n;
                if (n == 0) eof = true;
            }

            size_t pos = 0;
            while (pos < filled) {
                Measurement m;
                size_t used = 0;
                MeasurementCodec::DecodeResult result =
                    MeasurementCodec::decode(buf + pos, filled - pos, &m, &used);

                if (result == MeasurementCodec::DecodeResult::NeedMore) break;
                if (result == MeasurementCodec::DecodeResult::Invalid) {
                    scan.clean = false;
                    return scan;
                }

                pos += used;
                scan.count++;
                scan.lastSeq = m.seq;
                if (m.seq >= fromSeq && visited < max) {
                    visited++;
                    if (!callVisit(visit, m) || visited >= max) return scan;
                }
            }

            memmove(buf, buf + pos, filled - pos);
            filled -= pos;

            if (eof) {
                scan.clean = filled == 0;  // leftover bytes: a record cut by a power loss
                return scan;
            }
        }
    }

    static bool callVisit(std::nullptr_t, const Measurement&) { return true; }

    template <typename Fn>
    static bool callVisit(Fn& fn, const Measurement& m) { return fn(m); }
};

#endif // SEGMENTED_MEASUREMENT_STORE_H
