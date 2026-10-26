using Toybox.Test;
using Toybox.Lang;

// Unit tests ("Run No Evil") that validate the crypto/serialization pipeline
// against the official test vectors published in Tesla's protocol specification
// (pkg/protocol/protocol.md in teslamotors/vehicle-command).
//
// These run entirely in the Connect IQ simulator - no vehicle required - and
// prove that our ECDH key agreement, key derivation, metadata TLV serialization
// and HMAC authentication exactly match the reference implementation.
module CryptoTests {

    // Published test keys/values (see protocol.md "Test keys" and examples).
    const CLIENT_PRIV = "2538cdc29a97c19c1e99a637d6cf4f8c970c118b56ede1e6323e6d162c4b30db";
    const VEHICLE_PUB = "04c7a1f47138486aa4729971494878d33b1a24e39571f748a6e16c5955b3d877d3a6aaa0e955166474af5d32c410f439a2234137ad1bb085fd4e8813c958f11d97";
    const SHARED_K = "1b2fce19967b79db696f909cff89ea9a";
    const SESSION_INFO_KEY = "fceb679ee7bca756fcd441bf238bf2f338629b41d9eb9c67be1b32c9672ce300";

    const VIN = "5YJ30123456789ABC";
    const CHALLENGE = "1588d5a30eabc6f8fc9a951b11f6fd11";
    const EPOCH = "4c463f9cc0d3d26906e982ed224adde6";

    const SESSION_INFO = "0806124104c7a1f47138486aa4729971494878d33b1a24e39571f748a6e16c5955b3d877d3a6aaa0e955166474af5d32c410f439a2234137ad1bb085fd4e8813c958f11d971a104c463f9cc0d3d26906e982ed224adde6255a0a0000";
    const SESSION_INFO_TAG = "996c1fe38331be138f8039c194b14db2198846ed7d8251e6749284d7b32ea002";

    const SESSION_META = "000106021135594a333031323334353637383941424306101588d5a30eabc6f8fc9a951b11f6fd11ff";
    const COMMAND_META = "000105010103021135594a333031323334353637383941424303104c463f9cc0d3d26906e982ed224adde6040400000a5f050400000007070400000002ff";

    // ECDH + SHA1 -> the shared 128-bit key K.
    (:test)
    function testSharedKey(logger) {
        var priv = TeslaCrypto.fromHex(CLIENT_PRIV);
        var vpub = TeslaCrypto.fromHex(VEHICLE_PUB);
        var k = TeslaCrypto.deriveSharedKey(priv, vpub);
        var got = TeslaCrypto.toHex(k);
        logger.debug("K = " + got);
        Test.assertEqualMessage(got, SHARED_K, "K derivation mismatch");
        return true;
    }

    // HMAC-SHA256(K, "session info") sub-key.
    (:test)
    function testSessionInfoKey(logger) {
        var k = TeslaCrypto.fromHex(SHARED_K);
        var sk = TeslaCrypto.sessionInfoKey(k);
        Test.assertEqualMessage(TeslaCrypto.toHex(sk), SESSION_INFO_KEY, "session info key mismatch");
        return true;
    }

    // Session-info metadata TLV serialization.
    (:test)
    function testSessionMetadata(logger) {
        var m = TeslaCrypto.sessionInfoMetadata(VIN.toUtf8Array(), TeslaCrypto.fromHex(CHALLENGE));
        Test.assertEqualMessage(TeslaCrypto.toHex(m), SESSION_META, "session metadata mismatch");
        return true;
    }

    // Command metadata TLV serialization (uses the documented HVAC example
    // values: AES_GCM_PERSONALIZED type=5, infotainment domain=3).
    (:test)
    function testCommandMetadata(logger) {
        var m = TeslaCrypto.commandMetadata(
            5, 3, VIN.toUtf8Array(), TeslaCrypto.fromHex(EPOCH),
            2655, 7, 2);
        Test.assertEqualMessage(TeslaCrypto.toHex(m), COMMAND_META, "command metadata mismatch");
        return true;
    }

    // End-to-end: verify the vehicle's session-info integrity tag.
    (:test)
    function testVerifySessionInfo(logger) {
        var k = TeslaCrypto.fromHex(SHARED_K);
        var ok = TeslaCrypto.verifySessionInfo(
            k, VIN.toUtf8Array(), TeslaCrypto.fromHex(CHALLENGE),
            TeslaCrypto.fromHex(SESSION_INFO), TeslaCrypto.fromHex(SESSION_INFO_TAG));
        Test.assertMessage(ok, "session info HMAC did not verify");
        return true;
    }

    // Protobuf varint + fixed32 sanity checks.
    (:test)
    function testProtobufEncoding(logger) {
        // varint(300) = 0xAC 0x02
        Test.assertEqual(TeslaCrypto.toHex(Pb.varint(300)), "ac02");
        // fixed32 field #3 of 2655 -> tag 0x1d, then LE bytes 5f0a0000
        Test.assertEqual(TeslaCrypto.toHex(Pb.fieldFixed32(3, 2655)), "1d5f0a0000");
        // round-trip decode
        var buf = Pb.fieldBytes(10, [0xde, 0xad, 0xbe, 0xef]b);
        var fields = Pb.decode(buf);
        Test.assertEqual(TeslaCrypto.toHex(Pb.firstBytes(fields, 10)), "deadbeef");
        return true;
    }
}
