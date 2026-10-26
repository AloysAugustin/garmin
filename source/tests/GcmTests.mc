using Toybox.Test;
using Toybox.Lang;
using Toybox.System;

// AES-128-GCM (TeslaGcm) against known-good implementations: the published
// McGrew & Viega / NIST vectors and seeded random vectors produced by
// pyca/cryptography and PyCryptodome (tools/vectors/gcm_vectors.py).
(:test)
module GcmTests {

    function hex(s) {
        return TeslaCrypto.fromHex(s);
    }

    (:test)
    function testGcmEncryptVectors(logger) {
        var v = GcmVectors.VECTORS;
        for (var i = 0; i < v.size(); i++) {
            var r = TeslaGcm.encrypt(hex(v[i][0]), hex(v[i][1]), hex(v[i][2]), hex(v[i][3]));
            Test.assertEqualMessage(TeslaCrypto.toHex(r[0]), v[i][4], "ciphertext mismatch, vector " + i);
            Test.assertEqualMessage(TeslaCrypto.toHex(r[1]), v[i][5], "tag mismatch, vector " + i);
        }
        logger.debug(v.size() + " vectors");
        return true;
    }

    (:test)
    function testGcmDecryptVectors(logger) {
        var v = GcmVectors.VECTORS;
        for (var i = 0; i < v.size(); i++) {
            var p = TeslaGcm.decrypt(hex(v[i][0]), hex(v[i][1]), hex(v[i][4]), hex(v[i][3]), hex(v[i][5]));
            Test.assertMessage(p != null, "valid tag rejected, vector " + i);
            Test.assertEqualMessage(TeslaCrypto.toHex(p), v[i][2], "plaintext mismatch, vector " + i);
        }
        return true;
    }

    // Any change to ciphertext, tag, AAD or nonce must be rejected.
    (:test)
    function testGcmRejectsTampering(logger) {
        var v = GcmVectors.VECTORS[3]; // NIST test case 4 (has AAD)
        var key = hex(v[0]);
        var flips = [1, 4, 3, 5]; // nonce, ciphertext, aad, tag
        for (var f = 0; f < flips.size(); f++) {
            var parts = [hex(v[1]), hex(v[3]), hex(v[4]), hex(v[5])]; // nonce, aad, ct, tag
            var idx = f == 0 ? 0 : (f == 1 ? 2 : (f == 2 ? 1 : 3));
            parts[idx][parts[idx].size() - 1] = parts[idx][parts[idx].size() - 1] ^ 0x01;
            Test.assertMessage(TeslaGcm.decrypt(key, parts[0], parts[2], parts[1], parts[3]) == null,
                "tampered field " + flips[f] + " accepted");
        }
        Test.assertMessage(TeslaGcm.decrypt(key, hex(v[1]), hex(v[4]), hex(v[3]), hex(v[5]).slice(0, 12)) == null,
            "truncated tag accepted");
        return true;
    }

    // --- Tesla protocol -------------------------------------------------------

    // Tesla's own published example (protocol.md "AES-GCM encryption"):
    // HVAC-on command, documented metadata, nonce, ciphertext and tag.
    (:test)
    function testTeslaDocumentedGcmExample(logger) {
        var meta = hex(CryptoTests.COMMAND_META);
        var r = TeslaGcm.encrypt(hex(CryptoTests.SHARED_K), hex("dbf79447fa156674dae1caed"),
            hex("120452020801"), TeslaCrypto.sha256(meta));
        Test.assertEqualMessage(TeslaCrypto.toHex(r[0]), "38038e8c0f2e", "documented ciphertext mismatch");
        Test.assertEqualMessage(TeslaCrypto.toHex(r[1]), "c228e0ff64991481db3a7bbc133696c5", "documented tag mismatch");
        return true;
    }

    // A key with the published test identity and a session at the vectors'
    // epoch/counter, then the encrypted unlock built with the fixed nonce.
    function encryptedSetup() {
        var key = new TeslaKey();
        key.setTestIdentity(TeslaCrypto.reverseBytes(hex(CryptoTests.CLIENT_PRIV)),
            CryptoTests.VIN, hex(CryptoTests.ROUTING_ADDR));
        var sess = key.setTestSession(TeslaProto.DOMAIN_VEHICLE_SECURITY, hex(CryptoTests.SHARED_K),
            hex(TeslaGcmVectors.EPOCH), TeslaGcmVectors.COUNTER - 1, 0);
        sess[:replyCounters] = [];
        var cmd = key.buildEncryptedCommand(TeslaProto.DOMAIN_VEHICLE_SECURITY, sess,
            TeslaProto.rkeAction(TeslaProto.RKE_UNLOCK), TeslaGcmVectors.COUNTER,
            TeslaGcmVectors.EXPIRES_AT, hex(TeslaGcmVectors.NONCE), hex(CryptoTests.REQUEST_UUID));
        return [key, sess, cmd];
    }

    (:test)
    function testEncryptedCommandBytes(logger) {
        var s = encryptedSetup();
        Test.assertEqualMessage(TeslaCrypto.toHex(s[2]), TeslaGcmVectors.COMMAND, "encrypted command mismatch");
        Test.assertEqualMessage(TeslaCrypto.toHex(s[1][:requestHash]), TeslaGcmVectors.REQUEST_HASH,
            "request hash mismatch");
        return true;
    }

    function openHex(key, h) {
        var routable = TeslaProto.parseRoutable(hex(h));
        var ok = key.openReply(TeslaProto.DOMAIN_VEHICLE_SECURITY, routable);
        return ok ? routable : null;
    }

    (:test)
    function testEncryptedReplies(logger) {
        var key = encryptedSetup()[0];

        var r = openHex(key, TeslaGcmVectors.REPLY_REFUSED);
        Test.assertMessage(r != null, "valid encrypted reply rejected");
        Test.assertEqual(TeslaCrypto.toHex(r[:payload]), TeslaGcmVectors.REPLY_REFUSED_PLAINTEXT);
        Test.assertEqual(TeslaProto.parseFromVcsec(r[:payload])[:nominalError], 2); // CLOSURES_OPEN

        r = openHex(key, TeslaGcmVectors.REPLY_EMPTY);
        Test.assertMessage(r != null, "empty encrypted reply rejected");
        Test.assertEqual(r[:payload].size(), 0);

        r = openHex(key, TeslaGcmVectors.REPLY_FAULT);
        Test.assertMessage(r != null, "fault reply rejected");
        Test.assertEqual(r[:fault], TeslaGcmVectors.REPLY_FAULT_CODE);

        // Plaintext replies (firmware before 2024.38) pass through.
        Test.assertMessage(openHex(key, "3a020802520100") != null, "plaintext reply rejected");
        return true;
    }

    (:test)
    function testEncryptedReplyRejections(logger) {
        var key = encryptedSetup()[0];
        Test.assertMessage(openHex(key, TeslaGcmVectors.REPLY_REFUSED) != null, "first delivery rejected");
        Test.assertMessage(openHex(key, TeslaGcmVectors.REPLY_REFUSED) == null, "replayed reply accepted");

        // Flip one bit in the ciphertext, then in the tag (last byte).
        key = encryptedSetup()[0];
        var bad = hex(TeslaGcmVectors.REPLY_REFUSED);
        var i = TeslaCrypto.toHex(bad).find("664cef4e9e") / 2;
        bad[i] = bad[i] ^ 0x01;
        Test.assertMessage(key.openReply(TeslaProto.DOMAIN_VEHICLE_SECURITY, TeslaProto.parseRoutable(bad)) == false,
            "tampered ciphertext accepted");
        bad = hex(TeslaGcmVectors.REPLY_REFUSED);
        bad[bad.size() - 1] = bad[bad.size() - 1] ^ 0x80;
        Test.assertMessage(key.openReply(TeslaProto.DOMAIN_VEHICLE_SECURITY, TeslaProto.parseRoutable(bad)) == false,
            "tampered tag accepted");

        // A changed fault code is authenticated too.
        var f = TeslaCrypto.toHex(hex(TeslaGcmVectors.REPLY_FAULT));
        var j = f.find("62040802100") ;
        var forged = hex(f.substring(0, j) + "620408021007" + f.substring(j + 12, f.length()));
        Test.assertMessage(key.openReply(TeslaProto.DOMAIN_VEHICLE_SECURITY, TeslaProto.parseRoutable(forged)) == false,
            "altered fault accepted");

        // A reply to an earlier request does not verify against a new one.
        var s = encryptedSetup();
        s[0].buildEncryptedCommand(TeslaProto.DOMAIN_VEHICLE_SECURITY, s[1],
            TeslaProto.rkeAction(TeslaProto.RKE_LOCK), TeslaGcmVectors.COUNTER + 1,
            TeslaGcmVectors.EXPIRES_AT, hex("000000000000000000000001"), hex(CryptoTests.REQUEST_UUID));
        s[1][:replyCounters] = [];
        Test.assertMessage(openHex(s[0], TeslaGcmVectors.REPLY_REFUSED) == null,
            "reply bound to another request accepted");
        return true;
    }

    // GCM is done in Monkey C (GHASH bit by bit): make sure a command round
    // trip stays far from the watchdog on slow watches.
    (:test)
    function testGcmCost(logger) {
        var t0 = System.getTimer();
        var s = encryptedSetup();
        openHex(s[0], TeslaGcmVectors.REPLY_REFUSED);
        var ms = System.getTimer() - t0;
        logger.debug("encrypt command + decrypt reply: " + ms + " ms");
        return true;
    }

    // --- Tesla's Go implementation as the vehicle ------------------------------
    //
    // TeslaGoVectors comes from tools/vectors/tesla_gcm_vectors.go: Tesla's
    // vehicle-command Verifier accepted COMMAND and encrypted the replies.

    function goSetup() {
        var key = new TeslaKey();
        key.setTestIdentity(TeslaCrypto.reverseBytes(hex(CryptoTests.CLIENT_PRIV)),
            CryptoTests.VIN, hex(CryptoTests.ROUTING_ADDR));
        var sess = key.setTestSession(TeslaProto.DOMAIN_VEHICLE_SECURITY, hex(CryptoTests.SHARED_K),
            hex(TeslaGoVectors.EPOCH), TeslaGoVectors.COUNTER - 1, 0);
        var cmd = key.buildEncryptedCommand(TeslaProto.DOMAIN_VEHICLE_SECURITY, sess,
            hex(TeslaGoVectors.PLAINTEXT), TeslaGoVectors.COUNTER,
            TeslaGoVectors.EXPIRES_AT, hex(TeslaGoVectors.NONCE), hex(CryptoTests.REQUEST_UUID));
        return [key, sess, cmd];
    }

    // Go serializes oneof fields last, so compare field by field.
    (:test)
    function testCommandAcceptedByTeslaVerifier(logger) {
        var s = goSetup();
        var ours = Pb.decode(s[2]);
        var theirs = Pb.decode(hex(TeslaGoVectors.COMMAND));
        var fields = [6, 7, 10, 13, 51, 52];
        Test.assertEqual(ours.size(), theirs.size());
        for (var i = 0; i < fields.size(); i++) {
            var a = ours[fields[i]][0];
            var b = theirs[fields[i]][0];
            var same = (a instanceof Lang.ByteArray) ? TeslaCrypto.toHex(a).equals(TeslaCrypto.toHex(b)) : a == b;
            Test.assertMessage(same, "field " + fields[i] + " differs from the command Tesla's Verifier accepted");
        }
        Test.assertEqual(TeslaCrypto.toHex(s[1][:requestHash]), TeslaGoVectors.REQUEST_HASH);
        return true;
    }

    (:test)
    function testRepliesFromTeslaVerifier(logger) {
        var key = goSetup()[0];
        var r = openHex(key, TeslaGoVectors.REPLY_REFUSED);
        Test.assertMessage(r != null, "reply encrypted by Tesla's Verifier rejected");
        Test.assertEqual(TeslaCrypto.toHex(r[:payload]), TeslaGoVectors.REPLY_REFUSED_PLAINTEXT);
        r = openHex(key, TeslaGoVectors.REPLY_EMPTY);
        Test.assertMessage(r != null, "empty reply from Tesla's Verifier rejected");
        Test.assertEqual(r[:payload].size(), 0);
        Test.assertMessage(openHex(key, TeslaGoVectors.REPLY_REFUSED) == null, "replayed reply accepted");
        return true;
    }
}
