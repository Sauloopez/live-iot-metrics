#ifndef SYNC_COMMANDS_H
#define SYNC_COMMANDS_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include "../../infrastructure/storage/StorageTask.h"
#include "../../infrastructure/sync/Cobs.h"
#include "../../usecases/SyncStream.h"
#include "SerialController.h"
#include "SerialProtocol.h"

// `sync` serial command: data extraction over USB with credit based flow control
// (docs/tundra/SERIAL_API.md).
//
//   status                 -> {"s":"ok","n":next_seq,"a":acked_seq,"pd":pending}
//   stream {from, credit}  -> starts sending DATA frames from `from`
//   credit {ack, credit}   -> releases everything <= ack and grants more credit
//   stop                   -> stops the stream
//
// DATA frames are binary, COBS encoded and wrapped in 0x00 bytes; JSON lines never contain
// 0x00, so the receiver can always tell them apart. When nothing is left the node prints
// {"s":"ok","m":"Stream end","l":last_seq}.
class SyncCommands {
public:
    static const size_t RECORDS_PER_FRAME = 16;

    explicit SyncCommands(StorageTask& storage) : storage(storage), stream(RECORDS_PER_FRAME) {}

    void registerOn(SerialController& controller) {
        controller.registerCommand("sync", [this](JsonObject& data) { handle(data); });
    }

    bool isStreaming() const { return stream.isActive(); }

    // Call from loop(): sends at most one frame per call so commands keep being processed
    void tick() {
        if (!stream.isActive() || stream.credit() == 0) return;

        size_t len = 0;
        uint32_t lastSeq = 0;
        SyncStream::Output output = SyncStream::Output::None;
        storage.withStore([&](IMeasurementStore& store) {
            output = stream.next(store, frame, sizeof(frame), &len, &lastSeq);
        });

        if (output == SyncStream::Output::Data) {
            size_t encoded = Cobs::encode(frame, len, cobs + 1, sizeof(cobs) - 2);
            cobs[0] = 0x00;
            cobs[encoded + 1] = 0x00;
            Serial.write(cobs, encoded + 2);
        } else if (output == SyncStream::Output::End) {
            Serial.printf("{\"s\":\"ok\",\"m\":\"Stream end\",\"l\":%lu}\n", static_cast<unsigned long>(lastSeq));
        }
    }

private:
    StorageTask& storage;
    SyncStream stream;
    uint8_t frame[SyncStream::HEADER_SIZE + RECORDS_PER_FRAME * MeasurementCodec::MAX_RECORD_SIZE +
                  SyncStream::CRC_SIZE];
    uint8_t cobs[sizeof(frame) + sizeof(frame) / 254 + 3];

    void handle(JsonObject& doc) {
        String action = doc["action"] | "";

        if (action == "status") {
            StoreStatus status{1, 0};
            storage.withStore([&](IMeasurementStore& store) { status = store.status(); });
            Serial.printf("{\"s\":\"ok\",\"n\":%lu,\"a\":%lu,\"pd\":%lu}\n", static_cast<unsigned long>(status.nextSeq),
                          static_cast<unsigned long>(status.ackedSeq), static_cast<unsigned long>(status.pending()));
        } else if (action == "stream") {
            uint32_t from = doc["from"] | 1UL;
            uint32_t credit = doc["credit"] | 0UL;
            storage.withStore([&](IMeasurementStore& store) { stream.start(store, from, credit); });
            SerialProtocol::ok("Stream started");
        } else if (action == "credit") {
            uint32_t ack = doc["ack"] | 0UL;
            uint32_t credit = doc["credit"] | 0UL;
            bool acked = true;
            StoreStatus status{1, 0};
            storage.withStore([&](IMeasurementStore& store) {
                if (ack > 0) acked = store.ack(ack);
                status = store.status();
            });
            stream.addCredit(credit);
            if (acked) {
                Serial.printf("{\"s\":\"ok\",\"a\":%lu}\n", static_cast<unsigned long>(status.ackedSeq));
            } else {
                SerialProtocol::error("Could not save the confirmation");
            }
        } else if (action == "stop") {
            stream.stop();
            SerialProtocol::ok("Stream stopped");
        } else {
            SerialProtocol::error("Unknown action");
        }
    }
};

#endif // SYNC_COMMANDS_H
