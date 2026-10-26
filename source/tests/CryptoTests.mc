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

    // ECDH + SHA1 -> the shared 128-bit key K. CLIENT_PRIV is big-endian (as
    // in protocol.md); Connect IQ keys are little-endian.
    (:test)
    function testSharedKey(logger) {
        var priv = TeslaCrypto.reverseBytes(TeslaCrypto.fromHex(CLIENT_PRIV));
        var vpub = TeslaCrypto.fromHex(VEHICLE_PUB);
        var k = TeslaCrypto.deriveSharedKey(priv, vpub);
        var got = TeslaCrypto.toHex(k);
        logger.debug("K = " + got);
        Test.assertEqualMessage(got, SHARED_K, "K derivation mismatch");
        return true;
    }

    // The public key we enroll/send must be Tesla's 65-byte format; protocol.md
    // gives the test client's public key for CLIENT_PRIV.
    (:test)
    function testPublicKeyFromPrivate(logger) {
        var priv = TeslaCrypto.reverseBytes(TeslaCrypto.fromHex(CLIENT_PRIV));
        Test.assertEqualMessage(TeslaCrypto.toHex(TeslaCrypto.publicKeyFromPrivate(priv)),
            CLIENT_PUB, "public key format mismatch");
        return true;
    }

    // A freshly generated key round-trips through both formats.
    (:test)
    function testGeneratedKeyFormat(logger) {
        var priv = TeslaCrypto.generatePrivateKey();
        Test.assertEqual(priv.size(), 32);
        var pub = TeslaCrypto.publicKeyFromPrivate(priv);
        Test.assertEqual(pub.size(), 65);
        Test.assertEqual(pub[0], 0x04);
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
        var m = TeslaCrypto.sessionInfoMetadata(TeslaCrypto.strBytes(VIN), TeslaCrypto.fromHex(CHALLENGE));
        Test.assertEqualMessage(TeslaCrypto.toHex(m), SESSION_META, "session metadata mismatch");
        return true;
    }

    // Command metadata TLV serialization (uses the documented HVAC example
    // values: AES_GCM_PERSONALIZED type=5, infotainment domain=3).
    (:test)
    function testCommandMetadata(logger) {
        var m = TeslaCrypto.commandMetadata(
            5, 3, TeslaCrypto.strBytes(VIN), TeslaCrypto.fromHex(EPOCH),
            2655, 7, 2);
        Test.assertEqualMessage(TeslaCrypto.toHex(m), COMMAND_META, "command metadata mismatch");
        return true;
    }

    // End-to-end: verify the vehicle's session-info integrity tag.
    (:test)
    function testVerifySessionInfo(logger) {
        var k = TeslaCrypto.fromHex(SHARED_K);
        var ok = TeslaCrypto.verifySessionInfo(
            k, TeslaCrypto.strBytes(VIN), TeslaCrypto.fromHex(CHALLENGE),
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

    // ---- Message builders / parsers ---------------------------------------
    // Expected bytes below were produced by serializing the same messages with
    // the official .proto files (protobuf-python), so they check our hand-rolled
    // encoder against the real schema rather than against itself.

    const CLIENT_PUB = "04b2b6bc68c2da0665ce656815594996c62394edd8bea905fe781a754fe6a845a714330902f225e9269d466e05b349981fda9d85cc23c6fb444aa73b629105dc6e";
    const ROUTING_ADDR = "2c907bd76c640d360b3027dc7404efde";
    // protocol.md's handshake uuid. It equals CHALLENGE above: the session-info
    // HMAC is bound to the request uuid.
    const REQUEST_UUID = "1588d5a30eabc6f8fc9a951b11f6fd11";

    // The handshake example from protocol.md (to DOMAIN_INFOTAINMENT).
    (:test)
    function testHandshakeRequest(logger) {
        var msg = TeslaProto.handshakeRequest(TeslaProto.DOMAIN_INFOTAINMENT,
            TeslaCrypto.fromHex(CLIENT_PUB), TeslaCrypto.fromHex(ROUTING_ADDR),
            TeslaCrypto.fromHex(REQUEST_UUID));
        Test.assertEqualMessage(TeslaCrypto.toHex(msg),
            "320208033a1212102c907bd76c640d360b3027dc7404efde72430a41" + CLIENT_PUB
            + "9a0310" + REQUEST_UUID,
            "handshake request mismatch");
        return true;
    }

    // A complete HMAC-personalized unlock addressed to VCSEC.
    (:test)
    function testSignedUnlockCommand(logger) {
        var p = TeslaProto.rkeAction(TeslaProto.RKE_UNLOCK);
        Test.assertEqual(TeslaCrypto.toHex(p), "1000");
        var epoch = TeslaCrypto.fromHex(EPOCH);
        var meta = TeslaCrypto.commandMetadata(
            TeslaCrypto.SIGNATURE_TYPE_HMAC_PERSONALIZED, TeslaProto.DOMAIN_VEHICLE_SECURITY,
            TeslaCrypto.strBytes(VIN), epoch, 2655, 7, 0);
        var tag = TeslaCrypto.commandTag(TeslaCrypto.fromHex(SHARED_K), meta, p);
        Test.assertEqualMessage(TeslaCrypto.toHex(tag),
            "48469506544f0a1d1f2ef05993ba040fb12968d885a8e8dbcfc4abb9901dbfdf", "unlock tag mismatch");
        var msg = TeslaProto.signedCommand(TeslaProto.DOMAIN_VEHICLE_SECURITY, p,
            TeslaCrypto.fromHex(CLIENT_PUB), TeslaCrypto.fromHex(ROUTING_ADDR),
            epoch, 7, 2655, tag, TeslaCrypto.fromHex(REQUEST_UUID));
        Test.assertEqualMessage(TeslaCrypto.toHex(msg),
            "320208023a1212102c907bd76c640d360b3027dc7404efde520210006a82010a430a41" + CLIENT_PUB
            + "423b0a10" + EPOCH + "10071d5f0a00002220" + TeslaCrypto.toHex(tag)
            + "9a0310" + REQUEST_UUID,
            "signed command mismatch");
        return true;
    }

    (:test)
    function testClosurePayloads(logger) {
        Test.assertEqual(TeslaCrypto.toHex(TeslaProto.openTrunk()), "22022803");
        Test.assertEqual(TeslaCrypto.toHex(TeslaProto.openFrunk()), "22023003");
        // closureMoveRequest { frontDriverDoor .. rearPassengerDoor = OPEN }
        Test.assertEqual(TeslaCrypto.toHex(TeslaProto.openDoor(TeslaProto.DOOR_FRONT_DRIVER)), "22020803");
        Test.assertEqual(TeslaCrypto.toHex(TeslaProto.openDoor(TeslaProto.DOOR_FRONT_PASSENGER)), "22021003");
        Test.assertEqual(TeslaCrypto.toHex(TeslaProto.openDoor(TeslaProto.DOOR_REAR_DRIVER)), "22021803");
        Test.assertEqual(TeslaCrypto.toHex(TeslaProto.openDoor(TeslaProto.DOOR_REAR_PASSENGER)), "22022003");
        return true;
    }

    (:test)
    function testAddKeyEnvelope(logger) {
        var env = TeslaProto.addKeyEnvelope(TeslaCrypto.fromHex(CLIENT_PUB),
            TeslaProto.ROLE_DRIVER, TeslaProto.FORM_FACTOR_ANDROID);
        Test.assertEqualMessage(TeslaCrypto.toHex(env),
            "0a54125082014d2a470a430a41" + CLIENT_PUB + "2003320208071802",
            "add-key envelope mismatch");
        return true;
    }

    // FromVCSECMessage replies: busy/waiting, whitelist results, nominal error.
    (:test)
    function testParseFromVcsec(logger) {
        var wait = TeslaCrypto.fromHex("22020801");
        Test.assert(!TeslaProto.isRoutable(wait));
        var r = TeslaProto.parseFromVcsec(wait);
        Test.assertEqual(r[:opStatus], TeslaProto.OPSTATUS_WAIT);
        Test.assert(!r.hasKey(:whitelistInfo));

        r = TeslaProto.parseFromVcsec(TeslaCrypto.fromHex("220608021a020819"));
        Test.assertEqual(r[:opStatus], TeslaProto.OPSTATUS_ERROR);
        Test.assertEqual(r[:whitelistInfo], TeslaProto.WL_INFO_TIMED_OUT_WAITING_FOR_TAP);

        r = TeslaProto.parseFromVcsec(TeslaCrypto.fromHex("22021a00"));
        Test.assertEqual(r[:whitelistInfo], TeslaProto.WL_INFO_NONE);

        r = TeslaProto.parseFromVcsec(TeslaCrypto.fromHex("f202020802"));
        Test.assertEqual(r[:nominalError], 2); // GENERICERROR_CLOSURES_OPEN
        Test.assert(!r.hasKey(:opStatus));

        r = TeslaProto.parseFromVcsec([]b);
        Test.assert(r.hasKey(:empty));
        return true;
    }

    // A protocol-layer fault reply (INVALID_SIGNATURE) from VCSEC.
    (:test)
    function testParseRoutableFault(logger) {
        var bytes = TeslaCrypto.fromHex(
            "321212102c907bd76c640d360b3027dc7404efde3a0208026204080210059203101588d5a30eabc6f8fc9a951b11f6fd11");
        Test.assert(TeslaProto.isRoutable(bytes));
        var r = TeslaProto.parseRoutable(bytes);
        Test.assertEqual(TeslaCrypto.toHex(r[:toAddress]), ROUTING_ADDR);
        Test.assertEqual(r[:fromDomain], TeslaProto.DOMAIN_VEHICLE_SECURITY);
        Test.assertEqual(TeslaCrypto.toHex(r[:requestUuid]), REQUEST_UUID);
        Test.assertEqual(r[:operationStatus], TeslaProto.OPSTATUS_ERROR);
        Test.assertEqual(r[:fault], 5);
        return true;
    }

    // Truncated input must stop decoding, not throw.
    (:test)
    function testDecodeTruncated(logger) {
        var full = TeslaCrypto.fromHex("320208023a1212102c907bd76c640d360b3027dc7404efde52021000");
        var fields = Pb.decode(full.slice(0, 20));
        Test.assert(fields.hasKey(6));
        Test.assert(!fields.hasKey(10));
        return true;
    }
}
