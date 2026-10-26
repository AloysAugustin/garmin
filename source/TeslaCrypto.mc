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
// By default commands are authenticated with HMAC-SHA256 (the "personalized
// HMAC" method, SIGNATURE_TYPE_HMAC_PERSONALIZED = 8) and sent in plaintext,
// without FLAG_ENCRYPT_RESPONSE, so replies are plaintext too. The optional
// "encrypt" setting switches to AES-GCM (SIGNATURE_TYPE_AES_GCM_PERSONALIZED
// = 5) with FLAG_ENCRYPT_RESPONSE, as Tesla's Go client does over BLE; GCM is
// implemented in TeslaGcm on top of AES-ECB, since Connect IQ's Cipher class
// has no GCM mode.
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
        TAG_REQUEST_HASH = 8,
        TAG_FAULT = 9,
        TAG_END = 255
    }

    // Signatures.SignatureType values we use.
    const SIGNATURE_TYPE_HMAC = 6;
    const SIGNATURE_TYPE_HMAC_PERSONALIZED = 8;
    const SIGNATURE_TYPE_AES_GCM_PERSONALIZED = 5;
    const SIGNATURE_TYPE_AES_GCM_RESPONSE = 9;

    // UniversalMessage.Flags bit mask: 1 << FLAG_ENCRYPT_RESPONSE.
    const FLAG_ENCRYPT_RESPONSE_MASK = 2;

    const SHARED_KEY_SIZE = 16; // K is a 128-bit key (first 16 bytes of SHA1).

    // --- Key management -----------------------------------------------------
    //
    // Byte order: Connect IQ represents EC keys LITTLE-endian and without the
    // 0x04 prefix (see the KeyAgreement example in the SDK docs): a private key
    // is the 32-byte scalar reversed, a public key is reverse(X) || reverse(Y)
    // (64 bytes), and KeyAgreement.generateSecret() returns reverse(Sx). Tesla
    // uses big-endian scalars and 65-byte uncompressed points (0x04 || X || Y).
    // Private keys stay in Connect IQ's native order; everything that crosses
    // the wire is converted with the helpers below. Verified in the simulator
    // against the protocol.md test vectors (see CryptoTests).

    // Build a KeyPair object from a stored 32-byte native (little-endian)
    // private scalar.
    function keyPairFromPrivate(privBytes) {
        return new Cryptography.KeyPair({
            :algorithm => Cryptography.KEY_PAIR_ELLIPTIC_CURVE_SECP256R1,
            :privateKey => privBytes
        });
    }

    // Generate a brand-new random P-256 private key (native byte order).
    function generatePrivateKey() {
        var kp = new Cryptography.KeyPair({
            :algorithm => Cryptography.KEY_PAIR_ELLIPTIC_CURVE_SECP256R1
        });
        return kp.getPrivateKey().getBytes();
    }

    // Tesla-format public key (65 bytes, 0x04 || X || Y) for a native private key.
    function publicKeyFromPrivate(privBytes) {
        return publicFromNative(keyPairFromPrivate(privBytes).getPublicKey().getBytes());
    }

    // Native 64-byte public key -> Tesla 65-byte uncompressed point.
    function publicFromNative(nativeBytes) {
        var out = []b;
        out.add(0x04);
        out.addAll(reverseBytes(nativeBytes.slice(0, 32)));
        out.addAll(reverseBytes(nativeBytes.slice(32, 64)));
        return out;
    }

    // Tesla 65-byte uncompressed point -> native 64-byte public key.
    function publicToNative(point) {
        var out = reverseBytes(point.slice(1, 33));
        out.addAll(reverseBytes(point.slice(33, 65)));
        return out;
    }

    function reverseBytes(bytes) {
        var out = []b;
        for (var i = bytes.size() - 1; i >= 0; i--) {
            out.add(bytes[i]);
        }
        return out;
    }

    // ECDH: derive the shared 128-bit AES key K from our native private key and
    // the vehicle's public key (Tesla format: 65-byte uncompressed point).
    //   S  = ECDH(c, V)          (shared point)
    //   K  = SHA1(BIG_ENDIAN(Sx, 32))[:16]
    function deriveSharedKey(privBytes, vehiclePubBytes) {
        var kp = keyPairFromPrivate(privBytes);
        var ka = new Cryptography.KeyAgreement({
            :protocol => Cryptography.KEY_AGREEMENT_ECDH,
            :privateKey => kp.getPrivateKey()
        });
        if (vehiclePubBytes.size() != 65 || vehiclePubBytes[0] != 0x04) {
            return null;
        }
        var vehicleKey = Cryptography.createPublicKey(
            Cryptography.KEY_PAIR_ELLIPTIC_CURVE_SECP256R1, publicToNative(vehiclePubBytes));
        ka.addKey(vehicleKey);
        // generateSecret() returns Sx little-endian; K hashes it big-endian.
        var secret = reverseBytes(ka.generateSecret());
        return sha1(secret).slice(0, SHARED_KEY_SIZE);
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

    // Metadata for decrypting an AES-GCM response (protocol.md "Response
    // metadata"). Unlike requests, flags are always included; the fault is a
    // 32-bit big-endian integer.
    function responseMetadata(domain, vinBytes, counter, flags, requestHash, fault) {
        var m = []b;
        m.addAll(tlv(TAG_SIGNATURE_TYPE, Pb.oneByte(SIGNATURE_TYPE_AES_GCM_RESPONSE)));
        m.addAll(tlv(TAG_DOMAIN, Pb.oneByte(domain)));
        m.addAll(tlv(TAG_PERSONALIZATION, vinBytes));
        m.addAll(tlv(TAG_COUNTER, u32be(counter)));
        m.addAll(tlv(TAG_FLAGS, u32be(flags)));
        m.addAll(tlv(TAG_REQUEST_HASH, requestHash));
        m.addAll(tlv(TAG_FAULT, u32be(fault)));
        m.add(TAG_END);
        return m;
    }

    // The "request hash" a response is bound to: the request's signature type
    // followed by its tag, truncated to 17 bytes for VCSEC (which only
    // shortens HMAC tags; GCM tags are 16 bytes).
    function requestHash(signatureType, tag, domain) {
        var out = Pb.oneByte(signatureType);
        out.addAll(tag);
        if (domain == TeslaProto.DOMAIN_VEHICLE_SECURITY && out.size() > 17) {
            out = out.slice(0, 17);
        }
        return out;
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

    // String -> UTF-8 ByteArray. (String.toUtf8Array() returns an Array of
    // Numbers, which Hash/HMAC reject.)
    function strBytes(s) {
        var chars = s.toUtf8Array();
        var out = []b;
        for (var i = 0; i < chars.size(); i++) {
            out.add(chars[i]);
        }
        return out;
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
