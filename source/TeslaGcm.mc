using Toybox.Cryptography;
using Toybox.Lang;

// AES-128-GCM (NIST SP 800-38D) with a 96-bit nonce and 128-bit tag, built on
// Connect IQ's AES-ECB, which is the only AES mode besides CBC that the
// Cipher class offers.
//
//   H   = E(K, 0^128)   (its multiples are cached per key, see useTable)
//   J0  = nonce || 00000001
//   C   = P xor E(K, inc32(J0)), E(K, inc32^2(J0)), ...
//   tag = E(K, J0) xor GHASH_H(A || pad || C || pad || len64(A) || len64(C))
//
// Checked in the simulator against the McGrew & Viega / NIST vectors and
// against vectors from pyca/cryptography, PyCryptodome and Tesla's Go client
// (source/tests). The caller must never reuse a nonce with the same key:
// TeslaKey draws a fresh random nonce for every message.
module TeslaGcm {

    const BLOCK = 16;
    const NONCE_SIZE = 12;
    const TAG_SIZE = 16;

    // Returns [ciphertext, tag].
    function encrypt(key, nonce, plaintext, aad) {
        useTable(key, aesEcb(key, new [BLOCK]b));
        var blocks = counterBlocks(nonce, plaintext.size());
        var stream = aesEcb(key, blocks);
        var ct = xorPrefix(plaintext, stream.slice(BLOCK, null));
        var tag = xorPrefix(stream.slice(0, BLOCK), ghash(aad, ct));
        return [ct, tag];
    }

    // Returns the plaintext, or null if the tag does not verify. The tag is
    // checked before anything is decrypted.
    function decrypt(key, nonce, ciphertext, aad, tag) {
        if (nonce == null || nonce.size() != NONCE_SIZE || tag == null || tag.size() != TAG_SIZE) {
            return null;
        }
        useTable(key, aesEcb(key, new [BLOCK]b));
        var blocks = counterBlocks(nonce, ciphertext.size());
        var stream = aesEcb(key, blocks);
        var expected = xorPrefix(stream.slice(0, BLOCK), ghash(aad, ciphertext));
        if (!TeslaCrypto.constantTimeEquals(expected, tag)) {
            return null;
        }
        return xorPrefix(ciphertext, stream.slice(BLOCK, null));
    }

    // J0 followed by one counter block per 16 bytes of data.
    function counterBlocks(nonce, dataLen) {
        var n = (dataLen + BLOCK - 1) / BLOCK;
        var out = []b;
        for (var i = 0; i <= n; i++) {
            out.addAll(nonce);
            out.addAll(TeslaCrypto.u32be(i + 1));
        }
        return out;
    }

    // AES-128 encryption of whole blocks (data.size() is a multiple of 16).
    // Connect IQ's ECB encrypt() only processes the first block of its input
    // (the rest comes back as zeros, seen in the simulator), so feed it one
    // block per call.
    function aesEcb(key, data) {
        var cipher = new Cryptography.Cipher({
            :algorithm => Cryptography.CIPHER_AES128,
            :mode => Cryptography.MODE_ECB,
            :key => key,
            :iv => new [BLOCK]b
        });
        var out = []b;
        for (var off = 0; off < data.size(); off += BLOCK) {
            out.addAll(cipher.encrypt(data.slice(off, off + BLOCK)));
        }
        return out;
    }

    // a xor b over a.size() bytes (b must be at least as long).
    function xorPrefix(a, b) {
        var out = new [a.size()]b;
        for (var i = 0; i < a.size(); i++) {
            out[i] = (a[i] ^ b[i]) & 0xff;
        }
        return out;
    }

    // --- GHASH ----------------------------------------------------------------
    //
    // Shoup's 4-bit table method (as in OpenSSL's gcm_gmult_4bit): a table of
    // the 16 multiples of H turns each 128-bit multiplication into 32 nibble
    // steps instead of 128 bit steps. 128-bit values are four 32-bit Numbers,
    // most significant first (GCM's first bit is the MSB of word 0); Numbers
    // are signed, so right shifts are masked to stay logical. Measured in the
    // simulator: ~5.6 ms per multiply with the bitwise Long version before.

    // R4[i]: reduction of the 4 bits shifted out of the low end, for word 0.
    const R4 = [0x0000, 0x1C20, 0x3840, 0x2460, 0x7080, 0x6CA0, 0x48C0, 0x54E0,
                0xE100, 0xFD20, 0xD940, 0xC560, 0x9180, 0x8DA0, 0xA9C0, 0xB5E0];
    // 0xE1000000 as a signed 32-bit Number (the GCM reduction polynomial).
    const POLY = -520093696;

    var gTableKey = null;   // key the cached table belongs to
    var gTable = null;      // 16 multiples of H, 4 words each (64 Numbers)

    // GHASH over aad and ct with the table installed by useTable().
    function ghash(aad, ct) {
        var t = gTable;
        var y = [0, 0, 0, 0];
        absorb(y, t, aad);
        absorb(y, t, ct);
        var lens = new [16]b;
        var la = aad.size() * 8;
        var lc = ct.size() * 8;
        for (var i = 0; i < 4; i++) {
            lens[7 - i] = (la >> (8 * i)) & 0xff;
            lens[15 - i] = (lc >> (8 * i)) & 0xff;
        }
        absorb(y, t, lens);
        var out = new [16]b;
        for (var i = 0; i < 16; i++) {
            out[i] = (y[i >> 2] >> (24 - ((i & 3) << 3))) & 0xff;
        }
        return out;
    }

    // Build (or reuse) the multiples-of-H table for `key`; h = E(K, 0^128).
    function useTable(key, h) {
        if (gTableKey != null && sameBytes(gTableKey, key)) {
            return;
        }
        var t = new [64];
        for (var i = 0; i < 64; i++) {
            t[i] = 0;
        }
        var v = [0, 0, 0, 0];
        for (var i = 0; i < 16; i++) {
            v[i >> 2] = v[i >> 2] | ((h[i] & 0xff) << (24 - ((i & 3) << 3)));
        }
        // t[8] = H, t[4] = H*x, t[2] = H*x^2, t[1] = H*x^3
        for (var n = 8; n > 0; n = n >> 1) {
            for (var k = 0; k < 4; k++) {
                t[n * 4 + k] = v[k];
            }
            var lsb = v[3] & 1;
            v[3] = ((v[3] >> 1) & 0x7FFFFFFF) | (v[2] << 31);
            v[2] = ((v[2] >> 1) & 0x7FFFFFFF) | (v[1] << 31);
            v[1] = ((v[1] >> 1) & 0x7FFFFFFF) | (v[0] << 31);
            v[0] = (v[0] >> 1) & 0x7FFFFFFF;
            if (lsb != 0) {
                v[0] = v[0] ^ POLY;
            }
        }
        // t[a ^ b] = t[a] ^ t[b]
        for (var n = 2; n < 16; n = n << 1) {
            for (var j = 1; j < n; j++) {
                for (var k = 0; k < 4; k++) {
                    t[(n + j) * 4 + k] = t[n * 4 + k] ^ t[j * 4 + k];
                }
            }
        }
        gTable = t;
        gTableKey = key.slice(0, null); // a copy: callers may reuse their array
    }

    function sameBytes(a, b) {
        if (a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    // y = (y xor X_i) * H for each 16-byte block of data (last one zero-padded).
    function absorb(y, t, data) {
        var n = data.size();
        for (var off = 0; off < n; off += BLOCK) {
            for (var i = 0; i < BLOCK && off + i < n; i++) {
                y[i >> 2] = y[i >> 2] ^ ((data[off + i] & 0xff) << (24 - ((i & 3) << 3)));
            }
            gmult(y, t);
        }
    }

    // y = y * H in place, using the 4-bit table t.
    function gmult(y, t) {
        var b = y[3] & 0xff;
        var j = (b & 0xf) * 4;
        var z0 = t[j]; var z1 = t[j + 1]; var z2 = t[j + 2]; var z3 = t[j + 3];
        var nib = b >> 4;
        var cnt = 15;
        while (true) {
            var rem = z3 & 0xf;
            z3 = ((z3 >> 4) & 0x0FFFFFFF) | (z2 << 28);
            z2 = ((z2 >> 4) & 0x0FFFFFFF) | (z1 << 28);
            z1 = ((z1 >> 4) & 0x0FFFFFFF) | (z0 << 28);
            z0 = ((z0 >> 4) & 0x0FFFFFFF) ^ (R4[rem] << 16);
            j = nib * 4;
            z0 = z0 ^ t[j]; z1 = z1 ^ t[j + 1]; z2 = z2 ^ t[j + 2]; z3 = z3 ^ t[j + 3];
            cnt--;
            if (cnt < 0) {
                break;
            }
            b = (y[cnt >> 2] >> (24 - ((cnt & 3) << 3))) & 0xff;
            nib = b >> 4;
            rem = z3 & 0xf;
            z3 = ((z3 >> 4) & 0x0FFFFFFF) | (z2 << 28);
            z2 = ((z2 >> 4) & 0x0FFFFFFF) | (z1 << 28);
            z1 = ((z1 >> 4) & 0x0FFFFFFF) | (z0 << 28);
            z0 = ((z0 >> 4) & 0x0FFFFFFF) ^ (R4[rem] << 16);
            j = (b & 0xf) * 4;
            z0 = z0 ^ t[j]; z1 = z1 ^ t[j + 1]; z2 = z2 ^ t[j + 2]; z3 = z3 ^ t[j + 3];
        }
        y[0] = z0; y[1] = z1; y[2] = z2; y[3] = z3;
    }
}
