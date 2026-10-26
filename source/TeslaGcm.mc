using Toybox.Cryptography;
using Toybox.Lang;

// AES-128-GCM (NIST SP 800-38D) with a 96-bit nonce and 128-bit tag, built on
// Connect IQ's AES-ECB, which is the only AES mode besides CBC that the
// Cipher class offers.
//
//   H   = E(K, 0^128)
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
        var h = aesEcb(key, new [BLOCK]b);
        var blocks = counterBlocks(nonce, plaintext.size());
        var stream = aesEcb(key, blocks);
        var ct = xorPrefix(plaintext, stream.slice(BLOCK, null));
        var tag = xorPrefix(stream.slice(0, BLOCK), ghash(h, aad, ct));
        return [ct, tag];
    }

    // Returns the plaintext, or null if the tag does not verify. The tag is
    // checked before anything is decrypted.
    function decrypt(key, nonce, ciphertext, aad, tag) {
        if (nonce == null || nonce.size() != NONCE_SIZE || tag == null || tag.size() != TAG_SIZE) {
            return null;
        }
        var h = aesEcb(key, new [BLOCK]b);
        var blocks = counterBlocks(nonce, ciphertext.size());
        var stream = aesEcb(key, blocks);
        var expected = xorPrefix(stream.slice(0, BLOCK), ghash(h, aad, ciphertext));
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
    // 128-bit values are four Longs holding 32 bits each, most significant
    // word first. Longs keep every word non-negative so >> stays logical.

    function ghash(h, aad, ct) {
        var hw = words(h, 0);
        var y = [0l, 0l, 0l, 0l];
        y = absorb(y, hw, aad);
        y = absorb(y, hw, ct);
        var lens = []b;
        lens.addAll(TeslaCrypto.u32be(0));
        lens.addAll(TeslaCrypto.u32be(aad.size() * 8));
        lens.addAll(TeslaCrypto.u32be(0));
        lens.addAll(TeslaCrypto.u32be(ct.size() * 8));
        y = absorb(y, hw, lens);
        var out = []b;
        for (var i = 0; i < 4; i++) {
            out.addAll(TeslaCrypto.u32be(y[i]));
        }
        return out;
    }

    // Y = (Y xor X_i) * H for each 16-byte block of data (last one zero-padded).
    function absorb(y, hw, data) {
        for (var off = 0; off < data.size(); off += BLOCK) {
            var x = words(data, off);
            for (var i = 0; i < 4; i++) {
                x[i] = x[i] ^ y[i];
            }
            y = gfMul(x, hw);
        }
        return y;
    }

    // Big-endian 32-bit words of data[off..off+16), zero-padded.
    function words(data, off) {
        var w = [0l, 0l, 0l, 0l];
        for (var i = 0; i < BLOCK; i++) {
            var b = off + i < data.size() ? data[off + i] & 0xff : 0;
            w[i / 4] = w[i / 4] | (b.toLong() << (8 * (3 - i % 4)));
        }
        return w;
    }

    // Multiplication in GF(2^128) with GCM's bit order (SP 800-38D, Alg. 1).
    function gfMul(x, y) {
        var z0 = 0l; var z1 = 0l; var z2 = 0l; var z3 = 0l;
        var v0 = y[0]; var v1 = y[1]; var v2 = y[2]; var v3 = y[3];
        for (var i = 0; i < 128; i++) {
            if (((x[i / 32] >> (31 - i % 32)) & 1l) != 0l) {
                z0 = z0 ^ v0; z1 = z1 ^ v1; z2 = z2 ^ v2; z3 = z3 ^ v3;
            }
            var lsb = v3 & 1l;
            v3 = (v3 >> 1) | ((v2 & 1l) << 31);
            v2 = (v2 >> 1) | ((v1 & 1l) << 31);
            v1 = (v1 >> 1) | ((v0 & 1l) << 31);
            v0 = v0 >> 1;
            if (lsb != 0l) {
                v0 = v0 ^ 0xE1000000l;
            }
        }
        return [z0, z1, z2, z3];
    }
}
