using Toybox.Cryptography;
using Toybox.Lang;
using Toybox.StringUtil;

// Cryptographic primitives for the Tesla Vehicle Command protocol, built on the
// Connect IQ Toybox.Cryptography module.
//
// The protocol (see the vendored copy of Tesla's protocol.md) needs:
//   * NIST P-256 (secp256r1) key generation and ECDH               -> KeyPair / KeyAgreement
//   * SHA-1 to derive the shared key K = SHA1(Sx)[:16]             -> Hash(SHA1)
//   * HMAC-SHA256 to derive sub-keys and authenticate commands     -> HMAC(SHA256)
//
// We deliberately authenticate commands with HMAC-SHA256 (the "personalized
// HMAC" method, SIGNATURE_TYPE_HMAC_PERSONALIZED = 8) rather than AES-GCM.
// Both are accepted by the vehicle; HMAC keeps the command in plaintext and,
// crucially, avoids AES-GCM which Connect IQ's Cipher class does not provide
// (it only supports AES in CBC/ECB mode). As long as we do NOT ask the vehicle
// to encrypt its response (FLAG_ENCRYPT_RESPONSE is left unset), replies come
// back in plaintext too and no GCM is ever required.
module TeslaCrypto {

    // Metadata TLV tags (Signatures.Tag in signatures.proto).
    enum {
        TAG_SIGNATURE_TYPE = 0,
        TAG_DOMAIN = 1,
        TAG_PERSONALIZATION = 2,
        TAG_EPOCH = 3,
        TAG_EXPIRES_AT = 4,
        TAG_COUNTER = 5,
        TAG_CHALLENGE = 6,
        TAG_FLAGS = 7,
        TAG_END = 255
    }

    // Signatures.SignatureType values we use.
    const SIGNATURE_TYPE_HMAC = 6;
    const SIGNATURE_TYPE_HMAC_PERSONALIZED = 8;

    const SHARED_KEY_SIZE = 16; // K is a 128-bit key (first 16 bytes of SHA1).

    // --- Key management -----------------------------------------------------

    // Build a KeyPair object from a stored 32-byte private scalar.
    function keyPairFromPrivate(privBytes) {
        return new Cryptography.KeyPair({
            :algorithm => Cryptography.KEY_PAIR_ELLIPTIC_CURVE_SECP256R1,
            :privateKey => privBytes
        });
    }

    // Generate a brand-new random P-256 key pair. Returns a dictionary with the
    // raw :private (32 bytes) and :public (65 bytes, 0x04||X||Y) ByteArrays.
    function generateKeyPair() {
        // randomBytes gives us a uniformly random scalar. The probability that a
        // random 32-byte value is >= the curve order is about 2^-32, negligible
        // for our purposes, and Connect IQ reduces/validates it on use.
        var priv = Cryptography.randomBytes(32);
        var kp = keyPairFromPrivate(priv);
        return {
            :priv => kp.getPrivateKey().getBytes(),
            :pub => kp.getPublicKey().getBytes()
        };
    }

    // ECDH: derive the shared 128-bit AES key K from our private key and the
    // vehicle's public key bytes (65-byte uncompressed point).
    //   S  = ECDH(c, V)          (shared point)
    //   K  = SHA1(BIG_ENDIAN(Sx, 32))[:16]
    function deriveSharedKey(privBytes, vehiclePubBytes) {
        var kp = keyPairFromPrivate(privBytes);
        var ka = new Cryptography.KeyAgreement({
            :protocol => Cryptography.KEY_AGREEMENT_ECDH,
            :privateKey => kp.getPrivateKey()
        });
        var vehicleKey = Cryptography.createPublicKey(
            Cryptography.KEY_PAIR_ELLIPTIC_CURVE_SECP256R1, vehiclePubBytes);
        ka.addKey(vehicleKey);
        var secret = ka.generateSecret(); // 32-byte shared X coordinate
        var h = new Cryptography.Hash({:algorithm => Cryptography.HASH_SHA1});
        h.update(secret);
        var digest = h.digest();
        return digest.slice(0, SHARED_KEY_SIZE);
    }

    // --- Hashing / MAC helpers ---------------------------------------------

    function sha1(data) {
        var h = new Cryptography.Hash({:algorithm => Cryptography.HASH_SHA1});
        h.update(data);
        return h.digest();
    }

    function sha256(data) {
        var h = new Cryptography.Hash({:algorithm => Cryptography.HASH_SHA256});
        h.update(data);
        return h.digest();
    }

    function hmacSha256(key, data) {
        var mac = new Cryptography.HashBasedMessageAuthenticationCode({
            :algorithm => Cryptography.HASH_SHA256,
            :key => key
        });
        mac.update(data);
        return mac.digest();
    }

    // Sub-keys derived from K, matching the reference client:
    //   K'              = HMAC-SHA256(K, "authenticated command")
    //   SESSION_INFO_KEY = HMAC-SHA256(K, "session info")
    function commandKey(k) {
        return hmacSha256(k, strBytes("authenticated command"));
    }

    function sessionInfoKey(k) {
        return hmacSha256(k, strBytes("session info"));
    }

    // --- Metadata (TLV) serialization --------------------------------------

    // Serialize one TLV item: tag || len || value. Values must be <= 255 bytes.
    function tlv(tagByte, value) {
        var out = []b;
        out.add(tagByte);
        out.add(value.size());
        out.addAll(value);
        return out;
    }

    function u32be(value) {
        var v = value.toLong() & 0xFFFFFFFFl;
        var out = []b;
        out.add(((v >> 24) & 0xff).toNumber());
        out.add(((v >> 16) & 0xff).toNumber());
        out.add(((v >> 8) & 0xff).toNumber());
        out.add((v & 0xff).toNumber());
        return out;
    }

    // Build the serialized metadata string M for a personalized command.
    // Items MUST be in ascending tag order, terminated by 0xFF.
    //   signatureType, domain, VIN, epoch, expiresAt(BE), counter(BE) [, flags(BE)]
    function commandMetadata(signatureType, domain, vinBytes, epoch, expiresAt, counter, flags) {
        var m = []b;
        m.addAll(tlv(TAG_SIGNATURE_TYPE, Pb.oneByte(signatureType)));
        m.addAll(tlv(TAG_DOMAIN, Pb.oneByte(domain)));
        m.addAll(tlv(TAG_PERSONALIZATION, vinBytes));
        m.addAll(tlv(TAG_EPOCH, epoch));
        m.addAll(tlv(TAG_EXPIRES_AT, u32be(expiresAt)));
        m.addAll(tlv(TAG_COUNTER, u32be(counter)));
        if (flags > 0) {
            m.addAll(tlv(TAG_FLAGS, u32be(flags)));
        }
        m.add(TAG_END);
        return m;
    }

    // Build the serialized metadata for verifying a session-info response:
    //   signatureType(HMAC), VIN, challenge
    function sessionInfoMetadata(vinBytes, challenge) {
        var m = []b;
        m.addAll(tlv(TAG_SIGNATURE_TYPE, Pb.oneByte(SIGNATURE_TYPE_HMAC)));
        m.addAll(tlv(TAG_PERSONALIZATION, vinBytes));
        m.addAll(tlv(TAG_CHALLENGE, challenge));
        m.add(TAG_END);
        return m;
    }

    // --- Command authentication --------------------------------------------

    // Compute the personalized-HMAC authentication tag over a command:
    //   tag = HMAC-SHA256(K', M || P)
    // where M already ends in 0xFF and P is the plaintext command protobuf.
    function commandTag(k, metadata, plaintext) {
        var input = []b;
        input.addAll(metadata);
        input.addAll(plaintext);
        return hmacSha256(commandKey(k), input);
    }

    // Verify the HMAC tag the vehicle attaches to its session-info response:
    //   expected = HMAC-SHA256(SESSION_INFO_KEY, M || encodedSessionInfo)
    function verifySessionInfo(k, vinBytes, challenge, encodedInfo, tag) {
        var m = sessionInfoMetadata(vinBytes, challenge);
        var input = []b;
        input.addAll(m);
        input.addAll(encodedInfo);
        var expected = hmacSha256(sessionInfoKey(k), input);
        return constantTimeEquals(expected, tag);
    }

    // --- Utilities ----------------------------------------------------------

    function constantTimeEquals(a, b) {
        if (a == null || b == null || a.size() != b.size()) {
            return false;
        }
        var diff = 0;
        for (var i = 0; i < a.size(); i++) {
            diff = diff | ((a[i] & 0xff) ^ (b[i] & 0xff));
        }
        return diff == 0;
    }

    // ASCII string -> ByteArray.
    function strBytes(s) {
        return s.toUtf8Array();
    }

    // Lower-case hex of a ByteArray.
    function toHex(bytes) {
        var hex = "0123456789abcdef";
        var out = "";
        for (var i = 0; i < bytes.size(); i++) {
            var b = bytes[i] & 0xff;
            out += hex.substring(b >> 4, (b >> 4) + 1);
            out += hex.substring(b & 0xf, (b & 0xf) + 1);
        }
        return out;
    }

    // Parse a hex string into a ByteArray (ignores anything non-hex-ish length).
    function fromHex(s) {
        var out = []b;
        for (var i = 0; i + 1 < s.length(); i += 2) {
            out.add(hexNibble(s.substring(i, i + 1)) * 16 + hexNibble(s.substring(i + 1, i + 2)));
        }
        return out;
    }

    function hexNibble(c) {
        var v = "0123456789abcdef".find(c.toLower());
        return v == null ? 0 : v;
    }
}
