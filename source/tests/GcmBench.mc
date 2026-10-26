using Toybox.Test;
using Toybox.System;

// Timing of AES-GCM in the simulator (not correctness: see GcmTests). The
// simulator is faster than a watch, so compare numbers relative to each
// other. (The unit-test runner does not enforce the watchdog, so these
// cannot measure watchdog headroom.)
(:test)
module GcmBench {

    function roundTrips(n) {
        for (var i = 0; i < n; i++) {
            var s = GcmTests.encryptedSetup();
            GcmTests.openHex(s[0], TeslaGcmVectors.REPLY_REFUSED);
        }
    }

    (:test)
    function testBenchRoundTrip(logger) {
        var t0 = System.getTimer();
        roundTrips(10);
        logger.debug("round trip: " + (System.getTimer() - t0) / 10.0 + " ms");
        var key = TeslaCrypto.fromHex(CryptoTests.SHARED_K);
        var aad = new [32]b;
        var pt = new [2]b;
        var nonce = new [12]b;
        t0 = System.getTimer();
        for (var i = 0; i < 20; i++) {
            TeslaGcm.encrypt(key, nonce, pt, aad);
        }
        logger.debug("gcm encrypt (2 B, 32 B aad): " + (System.getTimer() - t0) / 20.0 + " ms");
        return true;
    }

    (:test)
    function testBenchParts(logger) {
        var key = TeslaCrypto.fromHex(CryptoTests.SHARED_K);
        var n = 50;
        var t0 = System.getTimer();
        for (var i = 0; i < n; i++) { TeslaGcm.aesEcb(key, new [16]b); }
        logger.debug("aes block (new Cipher): " + (System.getTimer() - t0) * 1.0 / n + " ms");
        TeslaGcm.useTable(key, TeslaGcm.aesEcb(key, new [16]b));
        var y = [1, 2, 3, 4];
        t0 = System.getTimer();
        for (var i = 0; i < n; i++) { TeslaGcm.gmult(y, TeslaGcm.gTable); }
        logger.debug("gmult (4-bit table): " + (System.getTimer() - t0) * 1.0 / n + " ms");
        t0 = System.getTimer();
        for (var i = 0; i < n; i++) { TeslaCrypto.sha256(key); }
        logger.debug("sha256: " + (System.getTimer() - t0) * 1.0 / n + " ms");
        t0 = System.getTimer();
        for (var i = 0; i < n; i++) { TeslaGcm.counterBlocks(new [12]b, 2); }
        logger.debug("counterBlocks: " + (System.getTimer() - t0) * 1.0 / n + " ms");
        var k2 = TeslaCrypto.fromHex(CryptoTests.SHARED_K);
        t0 = System.getTimer();
        for (var i = 0; i < n; i++) { k2[15] = i; TeslaGcm.useTable(k2, TeslaGcm.aesEcb(k2, new [16]b)); }
        logger.debug("table build (new key): " + (System.getTimer() - t0) * 1.0 / n + " ms");
        t0 = System.getTimer();
        for (var i = 0; i < 5; i++) { GcmTests.encryptedSetup(); }
        logger.debug("test setup incl. new TeslaKey (keygen): " + (System.getTimer() - t0) / 5.0 + " ms");
        return true;
    }
}
