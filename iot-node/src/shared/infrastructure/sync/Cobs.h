#ifndef COBS_H
#define COBS_H

#include <stddef.h>
#include <stdint.h>

// Consistent Overhead Byte Stuffing: encodes any bytes without 0x00, so 0x00 can delimit
// binary frames on the serial line (JSON lines never contain 0x00 either). Overhead is one
// byte per 254 bytes of input plus one.
namespace Cobs {

// Worst case output size for `len` input bytes
inline size_t maxEncodedSize(size_t len) { return len + len / 254 + 1; }

// Returns the encoded size, or 0 if `cap` is too small
inline size_t encode(const uint8_t* in, size_t len, uint8_t* out, size_t cap) {
    if (cap < maxEncodedSize(len)) return 0;

    size_t codeIndex = 0;
    size_t outIndex = 1;
    uint8_t code = 1;

    for (size_t i = 0; i < len; i++) {
        if (in[i] == 0) {
            out[codeIndex] = code;
            codeIndex = outIndex++;
            code = 1;
        } else {
            out[outIndex++] = in[i];
            code++;
            if (code == 0xFF) {
                out[codeIndex] = code;
                codeIndex = outIndex++;
                code = 1;
            }
        }
    }
    out[codeIndex] = code;
    return outIndex;
}

// Returns the decoded size, or 0 if the input is not valid COBS or `cap` is too small
inline size_t decode(const uint8_t* in, size_t len, uint8_t* out, size_t cap) {
    size_t inIndex = 0;
    size_t outIndex = 0;

    while (inIndex < len) {
        uint8_t code = in[inIndex++];
        if (code == 0 || inIndex + code - 1 > len) return 0;

        for (uint8_t i = 1; i < code; i++) {
            if (outIndex >= cap || in[inIndex] == 0) return 0;
            out[outIndex++] = in[inIndex++];
        }
        if (code != 0xFF && inIndex < len) {
            if (outIndex >= cap) return 0;
            out[outIndex++] = 0;
        }
    }
    return outIndex;
}

} // namespace Cobs

#endif // COBS_H
