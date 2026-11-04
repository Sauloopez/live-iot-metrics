#ifndef DS3231_CLOCK_H
#define DS3231_CLOCK_H

#include <Arduino.h>
#include <Wire.h>
#include "../../domain/repositories/IClock.h"
#include "Ds3231Codec.h"

// DS3231 real time clock over I2C. It keeps counting with its coin cell while the node sleeps
// or loses power, and drifts a few minutes per year.
class Ds3231Clock : public IClock {
public:
    static const uint8_t ADDRESS = 0x68;

    explicit Ds3231Clock(TwoWire& wire = Wire) : wire(wire) {}

    // Returns false if no DS3231 answers on the bus
    bool begin() {
        wire.beginTransmission(ADDRESS);
        present = wire.endTransmission() == 0;
        return present;
    }

    bool isPresent() const { return present; }

    // The oscillator-stop flag is set when the clock lost power (no coin cell): time is garbage
    bool isValid() override {
        uint8_t status = 0;
        return present && readRegisters(REG_STATUS, &status, 1) && !(status & STATUS_OSF);
    }

    uint32_t now() override {
        uint8_t regs[7];
        uint32_t value = 0;
        if (!present || !readRegisters(REG_TIME, regs, sizeof(regs))) return 0;
        return Ds3231Codec::decode(regs, &value) ? value : 0;
    }

    bool set(uint32_t unixTime) override {
        if (!present) return false;
        uint8_t regs[7];
        Ds3231Codec::encode(unixTime, regs);
        if (!writeRegisters(REG_TIME, regs, sizeof(regs))) return false;

        // Clear the oscillator-stop flag: from now on the time is trustworthy
        uint8_t status = 0;
        if (!readRegisters(REG_STATUS, &status, 1)) return false;
        status &= ~STATUS_OSF;
        return writeRegisters(REG_STATUS, &status, 1);
    }

private:
    static const uint8_t REG_TIME = 0x00;
    static const uint8_t REG_STATUS = 0x0F;
    static const uint8_t STATUS_OSF = 0x80;

    TwoWire& wire;
    bool present = false;

    bool readRegisters(uint8_t reg, uint8_t* buf, size_t len) {
        wire.beginTransmission(ADDRESS);
        wire.write(reg);
        if (wire.endTransmission(false) != 0) return false;
        if (wire.requestFrom(static_cast<int>(ADDRESS), static_cast<int>(len)) != static_cast<int>(len)) return false;
        for (size_t i = 0; i < len; i++) buf[i] = wire.read();
        return true;
    }

    bool writeRegisters(uint8_t reg, const uint8_t* buf, size_t len) {
        wire.beginTransmission(ADDRESS);
        wire.write(reg);
        wire.write(buf, len);
        return wire.endTransmission() == 0;
    }
};

#endif // DS3231_CLOCK_H
