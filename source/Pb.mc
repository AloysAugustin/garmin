using Toybox.Lang;

// Minimal protocol-buffers (proto3) encoder/decoder.
//
// Only the wire-format features the Tesla protocol needs are implemented:
//   * varint          (wire type 0) - enums, int32/uint32, bools
//   * length-delimited (wire type 2) - bytes, strings, embedded messages
//   * fixed32         (wire type 5) - the `fixed32 expires_at` / `clock_time`
//
// Encoding is done field-by-field by the caller; this module just handles the
// tag/length framing and integer serialization. Decoding returns a flat map of
// field number -> array of entries so callers can pull out the fields they care
// about regardless of order.
module Pb {

    enum {
        WIRE_VARINT = 0,
        WIRE_FIXED64 = 1,
        WIRE_LEN = 2,
        WIRE_FIXED32 = 5
    }

    // --- Encoding -----------------------------------------------------------

    // Encode an unsigned integer (given as Long to avoid 32-bit sign issues)
    // as a base-128 varint.
    function varint(value) {
        var out = []b;
        // Mask to 32 bits: every varint we emit is a uint32 or small enum.
        var v = value.toLong() & 0xFFFFFFFFl;
        while (true) {
            var b = (v & 0x7f).toNumber();
            v = v >> 7;
            if (v != 0) {
                out.add(b | 0x80);
            } else {
                out.add(b);
                break;
            }
        }
        return out;
    }

    function tag(fieldNum, wireType) {
        return varint((fieldNum << 3) | wireType);
    }

    // field = varint
    function fieldVarint(fieldNum, value) {
        var out = tag(fieldNum, WIRE_VARINT);
        out.addAll(varint(value));
        return out;
    }

    // A single-byte ByteArray built from a (possibly variable) Number.
    function oneByte(value) {
        var out = []b;
        out.add(value & 0xff);
        return out;
    }

    // field = length-delimited bytes (ByteArray). Also used for embedded
    // messages and strings (pass the UTF-8 ByteArray).
    function fieldBytes(fieldNum, bytes) {
        var out = tag(fieldNum, WIRE_LEN);
        out.addAll(varint(bytes.size().toLong()));
        out.addAll(bytes);
        return out;
    }

    // field = fixed32, serialized little-endian on the wire.
    function fieldFixed32(fieldNum, value) {
        var v = value.toLong() & 0xFFFFFFFFl;
        var out = tag(fieldNum, WIRE_FIXED32);
        out.add((v & 0xff).toNumber());
        out.add(((v >> 8) & 0xff).toNumber());
        out.add(((v >> 16) & 0xff).toNumber());
        out.add(((v >> 24) & 0xff).toNumber());
        return out;
    }

    // --- Decoding -----------------------------------------------------------

    // Read a varint starting at `offset`. Returns [valueLong, newOffset].
    function readVarint(buf, offset) {
        var shift = 0;
        var result = 0l;
        var pos = offset;
        while (pos < buf.size()) {
            var b = buf[pos] & 0xff;
            result = result | ((b & 0x7f).toLong() << shift);
            pos++;
            if ((b & 0x80) == 0) {
                break;
            }
            shift += 7;
        }
        return [result, pos];
    }

    // Decode a message into { fieldNum => [ entry, entry, ... ] }.
    // For WIRE_LEN entries the value is a ByteArray (the raw field contents).
    // For WIRE_VARINT entries the value is a Long.
    // For WIRE_FIXED32 entries the value is a Long (decoded little-endian).
    // Unsupported wire types are skipped as best as possible. Truncated input
    // stops decoding (returning the fields read so far) instead of throwing.
    function decode(buf) {
        var fields = {};
        var pos = 0;
        var n = buf.size();
        while (pos < n) {
            var r = readVarint(buf, pos);
            var key = r[0].toNumber();
            pos = r[1];
            var fieldNum = key >> 3;
            var wire = key & 0x7;
            var value = null;
            if (wire == WIRE_VARINT) {
                r = readVarint(buf, pos);
                value = r[0];
                pos = r[1];
            } else if (wire == WIRE_LEN) {
                r = readVarint(buf, pos);
                var len = r[0].toNumber();
                pos = r[1];
                if (len < 0 || pos + len > n) {
                    break; // truncated / malformed: stop rather than throw
                }
                value = buf.slice(pos, pos + len);
                pos += len;
            } else if (wire == WIRE_FIXED32) {
                if (pos + 4 > n) {
                    break;
                }
                value = ((buf[pos] & 0xff).toLong())
                    | ((buf[pos + 1] & 0xff).toLong() << 8)
                    | ((buf[pos + 2] & 0xff).toLong() << 16)
                    | ((buf[pos + 3] & 0xff).toLong() << 24);
                pos += 4;
            } else if (wire == WIRE_FIXED64) {
                pos += 8;
            } else {
                // Unknown wire type: cannot safely continue.
                break;
            }
            if (value != null) {
                if (fields.hasKey(fieldNum)) {
                    fields[fieldNum].add(value);
                } else {
                    fields[fieldNum] = [value];
                }
            }
        }
        return fields;
    }

    // Convenience: first length-delimited (ByteArray) value for a field, or null.
    function firstBytes(fields, fieldNum) {
        if (fields.hasKey(fieldNum)) {
            return fields[fieldNum][0];
        }
        return null;
    }

    // Convenience: first varint/fixed (Long) value for a field, or null.
    function firstInt(fields, fieldNum) {
        if (fields.hasKey(fieldNum)) {
            return fields[fieldNum][0];
        }
        return null;
    }
}
