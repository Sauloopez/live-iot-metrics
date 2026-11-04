#ifndef MEASUREMENT_CODEC_H
#define MEASUREMENT_CODEC_H

#include <stddef.h>
#include <stdint.h>
#include <tinycbor/cbor.h>
#include "../../domain/entities/Measurement.h"

// CBOR encoding of the stored data. A measurement is a 4-item array instead of a map so the
// keys are not repeated in every record: [seq, ts, sensorId, value]  (~15 bytes).
namespace MeasurementCodec {

// Large enough for any encoded measurement (worst case 1 + 5 + 5 + 3 + 5 bytes)
static const size_t MAX_RECORD_SIZE = 24;

enum class DecodeResult { Ok, NeedMore, Invalid };

// Returns the encoded size, or 0 if `len` is too small.
inline size_t encode(const Measurement& m, uint8_t* buf, size_t len) {
    CborEncoder encoder, array;
    cbor_encoder_init(&encoder, buf, len, 0);

    CborError err = cbor_encoder_create_array(&encoder, &array, 4);
    err = static_cast<CborError>(err | cbor_encode_uint(&array, m.seq));
    err = static_cast<CborError>(err | cbor_encode_uint(&array, m.ts));
    err = static_cast<CborError>(err | cbor_encode_uint(&array, m.sensorId));
    err = static_cast<CborError>(err | cbor_encode_float(&array, m.value));
    err = static_cast<CborError>(err | cbor_encoder_close_container(&encoder, &array));

    if (err != CborNoError) return 0;
    return cbor_encoder_get_buffer_size(&encoder, buf);
}

namespace detail {
inline bool readUint(CborValue* it, uint64_t* out) {
    if (!cbor_value_is_unsigned_integer(it)) return false;
    return cbor_value_get_uint64(it, out) == CborNoError && cbor_value_advance_fixed(it) == CborNoError;
}
} // namespace detail

// Every step that can run past the end of the buffer reports CborErrorUnexpectedEOF: that
// means the record is incomplete (read more, or it was cut by a power loss).
#define MEASUREMENT_CODEC_STEP(expr)                                   \
    do {                                                               \
        CborError stepErr = (expr);                                    \
        if (stepErr == CborErrorUnexpectedEOF) return DecodeResult::NeedMore; \
        if (stepErr != CborNoError) return DecodeResult::Invalid;      \
    } while (0)

#define MEASUREMENT_CODEC_UINT(it, out)                                \
    do {                                                               \
        if (!cbor_value_is_unsigned_integer(it)) return DecodeResult::Invalid; \
        MEASUREMENT_CODEC_STEP(cbor_value_get_uint64(it, out));        \
        MEASUREMENT_CODEC_STEP(cbor_value_advance_fixed(it));          \
    } while (0)

// Decodes one measurement from the start of `buf` and reports how many bytes it used.
inline DecodeResult decode(const uint8_t* buf, size_t len, Measurement* out, size_t* consumed) {
    if (len == 0) return DecodeResult::NeedMore;

    CborParser parser;
    CborValue root, item;
    size_t items = 0;
    uint64_t seq = 0, ts = 0, sensor = 0;
    float value = 0;

    MEASUREMENT_CODEC_STEP(cbor_parser_init(buf, len, 0, &parser, &root));
    if (!cbor_value_is_array(&root)) return DecodeResult::Invalid;
    MEASUREMENT_CODEC_STEP(cbor_value_get_array_length(&root, &items));
    if (items != 4) return DecodeResult::Invalid;

    MEASUREMENT_CODEC_STEP(cbor_value_enter_container(&root, &item));
    MEASUREMENT_CODEC_UINT(&item, &seq);
    MEASUREMENT_CODEC_UINT(&item, &ts);
    MEASUREMENT_CODEC_UINT(&item, &sensor);
    if (!cbor_value_is_float(&item)) return DecodeResult::Invalid;
    MEASUREMENT_CODEC_STEP(cbor_value_get_float(&item, &value));
    MEASUREMENT_CODEC_STEP(cbor_value_advance_fixed(&item));
    MEASUREMENT_CODEC_STEP(cbor_value_leave_container(&root, &item));

    if (seq > UINT32_MAX || ts > UINT32_MAX || sensor > UINT16_MAX) return DecodeResult::Invalid;

    out->seq = static_cast<uint32_t>(seq);
    out->ts = static_cast<uint32_t>(ts);
    out->sensorId = static_cast<uint16_t>(sensor);
    out->value = value;
    *consumed = static_cast<size_t>(cbor_value_get_next_byte(&root) - buf);
    return DecodeResult::Ok;
}

#undef MEASUREMENT_CODEC_UINT
#undef MEASUREMENT_CODEC_STEP

// Store state: [version, ackedSeq, nextSeq]
inline size_t encodeState(const StoreStatus& state, uint8_t* buf, size_t len) {
    CborEncoder encoder, array;
    cbor_encoder_init(&encoder, buf, len, 0);
    CborError err = cbor_encoder_create_array(&encoder, &array, 3);
    err = static_cast<CborError>(err | cbor_encode_uint(&array, 1));
    err = static_cast<CborError>(err | cbor_encode_uint(&array, state.ackedSeq));
    err = static_cast<CborError>(err | cbor_encode_uint(&array, state.nextSeq));
    err = static_cast<CborError>(err | cbor_encoder_close_container(&encoder, &array));
    if (err != CborNoError) return 0;
    return cbor_encoder_get_buffer_size(&encoder, buf);
}

inline bool decodeState(const uint8_t* buf, size_t len, StoreStatus* out) {
    CborParser parser;
    CborValue root, item;
    size_t items = 0;
    if (cbor_parser_init(buf, len, 0, &parser, &root) != CborNoError) return false;
    if (!cbor_value_is_array(&root)) return false;
    if (cbor_value_get_array_length(&root, &items) != CborNoError || items != 3) return false;
    if (cbor_value_enter_container(&root, &item) != CborNoError) return false;

    uint64_t version = 0, acked = 0, next = 0;
    if (!detail::readUint(&item, &version) || version != 1) return false;
    if (!detail::readUint(&item, &acked) || !detail::readUint(&item, &next)) return false;
    if (acked > UINT32_MAX || next > UINT32_MAX) return false;

    out->ackedSeq = static_cast<uint32_t>(acked);
    out->nextSeq = static_cast<uint32_t>(next);
    return true;
}

} // namespace MeasurementCodec

#endif // MEASUREMENT_CODEC_H
