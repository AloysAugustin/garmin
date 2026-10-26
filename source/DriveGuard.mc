using Toybox.Application;
using Toybox.Lang;
using Toybox.Time;

// Guards keyless driving (RKE_ACTION_REMOTE_DRIVE). That command lets the car
// be driven for two minutes without any other key and, per Tesla's manual,
// also gets past PIN to Drive, so a lost watch must not be enough to drive
// away. Drive is therefore:
//   * off unless the "allowDrive" app setting is on, and
//   * only sent after the 4-digit "drivePin" from the app settings is
//     entered on the watch, with a lockout after repeated wrong PINs.
module DriveGuard {

    const MAX_FAILURES = 3;
    const LOCKOUT_SECONDS = 300;

    const STORE_FAILURES = "driveFails";
    const STORE_LOCKED_UNTIL = "driveLockUntil";

    enum {
        PIN_OK,
        PIN_WRONG,
        PIN_LOCKED,
        PIN_NOT_SET,
        DRIVE_DISABLED
    }

    function isEnabled() {
        return property("allowDrive") == true;
    }

    // The configured PIN if it is exactly 4 digits, else null.
    function configuredPin() {
        var pin = property("drivePin");
        if (pin instanceof Lang.Number) {
            pin = pin.format("%04d");
        }
        if (!(pin instanceof Lang.String) || pin.length() != 4) {
            return null;
        }
        for (var i = 0; i < 4; i++) {
            if ("0123456789".find(pin.substring(i, i + 1)) == null) {
                return null;
            }
        }
        return pin;
    }

    // Seconds left in a lockout after too many wrong PINs (0 if none).
    function lockedForSeconds() {
        var until = Application.Storage.getValue(STORE_LOCKED_UNTIL);
        if (until == null) {
            return 0;
        }
        var left = until - Time.now().value();
        if (left <= 0 || left > LOCKOUT_SECONDS) { // expired, or the clock moved back
            Application.Storage.deleteValue(STORE_LOCKED_UNTIL);
            return 0;
        }
        return left;
    }

    // Whether Drive may be attempted at all; one of PIN_OK (go on and ask for
    // the PIN), DRIVE_DISABLED, PIN_NOT_SET, PIN_LOCKED.
    function precheck() {
        if (!isEnabled()) {
            return DRIVE_DISABLED;
        }
        if (configuredPin() == null) {
            return PIN_NOT_SET;
        }
        if (lockedForSeconds() > 0) {
            return PIN_LOCKED;
        }
        return PIN_OK;
    }

    // Check an entered PIN (String of 4 digits). Counts failures and starts a
    // lockout after MAX_FAILURES; success clears the count.
    function verify(entered) {
        var pre = precheck();
        if (pre != PIN_OK) {
            return pre;
        }
        var pin = configuredPin();
        var diff = entered.length() == pin.length() ? 0 : 1;
        for (var i = 0; i < pin.length() && i < entered.length(); i++) {
            diff = diff | (pin.substring(i, i + 1).equals(entered.substring(i, i + 1)) ? 0 : 1);
        }
        if (diff == 0) {
            Application.Storage.deleteValue(STORE_FAILURES);
            return PIN_OK;
        }
        var fails = Application.Storage.getValue(STORE_FAILURES);
        fails = (fails == null ? 0 : fails) + 1;
        if (fails >= MAX_FAILURES) {
            Application.Storage.setValue(STORE_LOCKED_UNTIL, Time.now().value() + LOCKOUT_SECONDS);
            Application.Storage.deleteValue(STORE_FAILURES);
            return PIN_LOCKED;
        }
        Application.Storage.setValue(STORE_FAILURES, fails);
        return PIN_WRONG;
    }

    // User-facing text for a non-OK result.
    function message(code) {
        if (code == DRIVE_DISABLED) {
            return "Keyless driving is off. Turn on \"Allow keyless driving\" in the app settings.";
        }
        if (code == PIN_NOT_SET) {
            return "Set a 4-digit Drive PIN in the app settings first.";
        }
        if (code == PIN_LOCKED) {
            return "Too many wrong PINs. Try again in " + ((lockedForSeconds() + 59) / 60) + " min.";
        }
        if (code == PIN_WRONG) {
            return "Wrong PIN.";
        }
        return "";
    }

    function property(name) {
        try {
            return Application.Properties.getValue(name);
        } catch (e) {
            return null;
        }
    }
}
