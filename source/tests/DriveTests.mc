using Toybox.Test;
using Toybox.Application;

// Keyless driving: the command bytes and the on-watch PIN guard.
(:test)
module DriveTests {

    // UnsignedMessage { RKEAction = RKE_ACTION_REMOTE_DRIVE (20) }, checked
    // against the official vcsec.proto with protobuf-python.
    (:test)
    function testRemoteDrivePayload(logger) {
        Test.assertEqual(TeslaCrypto.toHex(TeslaProto.rkeAction(TeslaProto.RKE_REMOTE_DRIVE)), "1014");
        return true;
    }

    function setup(allow, pin) {
        Application.Properties.setValue("allowDrive", allow);
        Application.Properties.setValue("drivePin", pin);
        Application.Storage.deleteValue(DriveGuard.STORE_FAILURES);
        Application.Storage.deleteValue(DriveGuard.STORE_LOCKED_UNTIL);
    }

    function restore() {
        setup(false, "");
    }

    (:test)
    function testDriveGuard(logger) {
        setup(false, "1234");
        Test.assertEqual(DriveGuard.verify("1234"), DriveGuard.DRIVE_DISABLED);

        setup(true, "");
        Test.assertEqual(DriveGuard.precheck(), DriveGuard.PIN_NOT_SET);
        setup(true, "12a4");
        Test.assertEqual(DriveGuard.precheck(), DriveGuard.PIN_NOT_SET);
        setup(true, "123");
        Test.assertEqual(DriveGuard.precheck(), DriveGuard.PIN_NOT_SET);

        setup(true, "0420");
        Test.assertEqual(DriveGuard.precheck(), DriveGuard.PIN_OK);
        Test.assertEqual(DriveGuard.verify("0420"), DriveGuard.PIN_OK);

        // Two wrong PINs, then the right one clears the count.
        Test.assertEqual(DriveGuard.verify("0000"), DriveGuard.PIN_WRONG);
        Test.assertEqual(DriveGuard.verify("0421"), DriveGuard.PIN_WRONG);
        Test.assertEqual(DriveGuard.verify("0420"), DriveGuard.PIN_OK);

        // Three wrong PINs lock Drive out, even for the right PIN.
        Test.assertEqual(DriveGuard.verify("1111"), DriveGuard.PIN_WRONG);
        Test.assertEqual(DriveGuard.verify("2222"), DriveGuard.PIN_WRONG);
        Test.assertEqual(DriveGuard.verify("3333"), DriveGuard.PIN_LOCKED);
        Test.assertEqual(DriveGuard.verify("0420"), DriveGuard.PIN_LOCKED);
        Test.assertMessage(DriveGuard.lockedForSeconds() > 0, "no lockout");
        logger.debug(DriveGuard.message(DriveGuard.PIN_LOCKED));

        restore();
        return true;
    }
}
