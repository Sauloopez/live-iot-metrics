#ifndef DS3231_CODEC_H
#define DS3231_CODEC_H

#include <stdint.h>

// Conversions for the DS3231 time registers (BCD, UTC). Pure functions so they are tested on
// the PC; the I2C driver only moves the 7 bytes.
namespace Ds3231Codec {

inline uint8_t toBcd(uint8_t value) { return static_cast<uint8_t>(((value / 10) << 4) | (value % 10)); }
inline uint8_t fromBcd(uint8_t bcd) { return static_cast<uint8_t>((bcd >> 4) * 10 + (bcd & 0x0F)); }

// Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm, valid for any year)
inline int64_t daysFromCivil(int64_t y, unsigned m, unsigned d) {
    y -= m <= 2;
    const int64_t era = (y >= 0 ? y : y - 399) / 400;
    const unsigned yoe = static_cast<unsigned>(y - era * 400);
    const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + static_cast<int64_t>(doe) - 719468;
}

inline void civilFromDays(int64_t z, int64_t* y, unsigned* m, unsigned* d) {
    z += 719468;
    const int64_t era = (z >= 0 ? z : z - 146096) / 146097;
    const unsigned doe = static_cast<unsigned>(z - era * 146097);
    const unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const unsigned mp = (5 * doy + 2) / 153;
    *d = doy - (153 * mp + 2) / 5 + 1;
    *m = mp < 10 ? mp + 3 : mp - 9;
    *y = static_cast<int64_t>(yoe) + era * 400 + (*m <= 2);
}

// Registers 0x00..0x06: seconds, minutes, hours (24 h), weekday, date, month, year (2000-2099)
inline void encode(uint32_t unixTime, uint8_t regs[7]) {
    int64_t days = unixTime / 86400;
    uint32_t secs = unixTime % 86400;
    int64_t y;
    unsigned m, d;
    civilFromDays(days, &y, &m, &d);

    regs[0] = toBcd(secs % 60);
    regs[1] = toBcd((secs / 60) % 60);
    regs[2] = toBcd(secs / 3600);  // bit 6 = 0: 24-hour mode
    regs[3] = static_cast<uint8_t>(((days + 4) % 7) + 1);  // 1970-01-01 was a Thursday; 1 = Sunday
    regs[4] = toBcd(static_cast<uint8_t>(d));
    regs[5] = toBcd(static_cast<uint8_t>(m));  // century bit 0: years 2000-2099
    regs[6] = toBcd(static_cast<uint8_t>(y - 2000));
}

// Returns false if the registers do not hold a valid date
inline bool decode(const uint8_t regs[7], uint32_t* unixTime) {
    unsigned sec = fromBcd(regs[0] & 0x7F);
    unsigned min = fromBcd(regs[1] & 0x7F);
    unsigned hour;
    if (regs[2] & 0x40) {  // 12-hour mode
        hour = fromBcd(regs[2] & 0x1F) % 12 + ((regs[2] & 0x20) ? 12 : 0);
    } else {
        hour = fromBcd(regs[2] & 0x3F);
    }
    unsigned day = fromBcd(regs[4] & 0x3F);
    unsigned month = fromBcd(regs[5] & 0x1F);
    unsigned year = 2000 + fromBcd(regs[6]) + ((regs[5] & 0x80) ? 100 : 0);

    if (sec > 59 || min > 59 || hour > 23 || day < 1 || day > 31 || month < 1 || month > 12) return false;

    int64_t days = daysFromCivil(year, month, day);
    int64_t value = days * 86400 + hour * 3600 + min * 60 + sec;
    if (value < 0 || value > UINT32_MAX) return false;
    *unixTime = static_cast<uint32_t>(value);
    return true;
}

} // namespace Ds3231Codec

#endif // DS3231_CODEC_H
