using Toybox.Timer;
using Toybox.Lang;

// TeslaController orchestrates a complete operation (a command or a pairing
// request) over a single BLE connection, driving the handshake and command
// exchange and reporting human-readable progress to the UI.
class TeslaController {

    // High-level intents.
    enum {
        INTENT_UNLOCK,
        INTENT_LOCK,
        INTENT_TRUNK,
        INTENT_FRUNK,
        INTENT_WAKE,
        INTENT_PAIR_DRIVER,
        INTENT_PAIR_OWNER
    }

    // Internal flow state.
    enum {
        STATE_IDLE,
        STATE_CONNECTING,
        STATE_WAIT_SESSION,
        STATE_WAIT_RESULT,
        STATE_WAIT_PAIR
    }

    // MessageFault_E codes we recover from by refreshing session state.
    const FAULT_INVALID_SIGNATURE = 5;
    const FAULT_INVALID_TOKEN_OR_COUNTER = 6;
    const FAULT_INCORRECT_EPOCH = 15;
    const FAULT_TIME_EXPIRED = 17;
    const FAULT_UNKNOWN_KEY = 3;
    const FAULT_INACTIVE_KEY = 4;

    const REPLY_TIMEOUT_MS = 12000;

    hidden var mKey;        // TeslaKey
    hidden var mBle;        // TeslaBleManager
    hidden var mSink;       // UI sink with onStatus(str) / onResult(ok, str)
    hidden var mState;
    hidden var mIntent;
    hidden var mDomain;
    hidden var mRetried;
    hidden var mReplyTimer;

    function initialize(key) {
        mKey = key;
        mBle = new TeslaBleManager(self);
        mState = STATE_IDLE;
        mRetried = false;
    }

    function setup() {
        mBle.setup();
    }

    function setSink(sink) {
        mSink = sink;
    }

    function isBusy() {
        return mState != STATE_IDLE;
    }

    // --- Public operations --------------------------------------------------

    function start(intent) {
        if (isBusy()) {
            report("Busy, please wait");
            return;
        }
        if (!mKey.hasVin()) {
            result(false, "Set your VIN first");
            return;
        }
        mIntent = intent;
        mDomain = TeslaProto.DOMAIN_VEHICLE_SECURITY;
        mRetried = false;
        mState = STATE_CONNECTING;
        mKey.resetSessions();
        mKey.newRoutingAddress();
        report("Searching for vehicle...");
        mBle.connect(mKey.localName());
    }

    function cancel() {
        clearReplyTimer();
        mBle.disconnect();
        mState = STATE_IDLE;
    }

    // --- Intent helpers -----------------------------------------------------

    hidden function isPairing() {
        return mIntent == INTENT_PAIR_DRIVER || mIntent == INTENT_PAIR_OWNER;
    }

    hidden function payloadForIntent() {
        if (mIntent == INTENT_UNLOCK) {
            return TeslaProto.rkeAction(TeslaProto.RKE_UNLOCK);
        } else if (mIntent == INTENT_LOCK) {
            return TeslaProto.rkeAction(TeslaProto.RKE_LOCK);
        } else if (mIntent == INTENT_WAKE) {
            return TeslaProto.rkeAction(TeslaProto.RKE_WAKE);
        } else if (mIntent == INTENT_TRUNK) {
            return TeslaProto.openTrunk();
        } else if (mIntent == INTENT_FRUNK) {
            return TeslaProto.openFrunk();
        }
        return null;
    }

    hidden function intentName() {
        if (mIntent == INTENT_UNLOCK) { return "Unlock"; }
        if (mIntent == INTENT_LOCK) { return "Lock"; }
        if (mIntent == INTENT_WAKE) { return "Wake"; }
        if (mIntent == INTENT_TRUNK) { return "Trunk"; }
        if (mIntent == INTENT_FRUNK) { return "Frunk"; }
        return "Command";
    }

    // --- BLE listener callbacks --------------------------------------------

    function onBleReady() {
        // Notifications enabled; begin the protocol exchange.
        if (isPairing()) {
            report("Sending pairing request...");
            var role = (mIntent == INTENT_PAIR_OWNER)
                ? TeslaProto.ROLE_OWNER : TeslaProto.ROLE_DRIVER;
            mBle.send(mKey.buildAddKey(role));
            mState = STATE_WAIT_PAIR;
            armReplyTimer();
        } else {
            report("Authenticating...");
            mBle.send(mKey.buildHandshake(mDomain));
            mState = STATE_WAIT_SESSION;
            armReplyTimer();
        }
    }

    function onBleMessage(message) {
        clearReplyTimer();
        var routable = TeslaProto.parseRoutable(message);

        if (mState == STATE_WAIT_SESSION) {
            handleSessionResponse(routable);
        } else if (mState == STATE_WAIT_RESULT) {
            handleCommandResponse(routable);
        } else if (mState == STATE_WAIT_PAIR) {
            // Any response to a pairing request means the vehicle received it.
            result(true, "Request sent. Tap your key card on the console, then confirm on screen.");
        }
    }

    hidden function handleSessionResponse(routable) {
        if (!mKey.applySessionInfo(mDomain, routable)) {
            result(false, "Handshake failed");
            return;
        }
        report(intentName() + "...");
        sendCommand();
    }

    hidden function sendCommand() {
        var payload = payloadForIntent();
        var cmd = mKey.buildCommand(mDomain, payload);
        if (cmd == null) {
            result(false, "No session");
            return;
        }
        mBle.send(cmd);
        mState = STATE_WAIT_RESULT;
        armReplyTimer();
    }

    hidden function handleCommandResponse(routable) {
        var fault = routable.hasKey(:fault) ? routable[:fault] : 0;

        if (fault == 0) {
            result(true, intentName() + " OK");
            return;
        }

        if (fault == FAULT_UNKNOWN_KEY) {
            result(false, "Key not recognized. Pair this watch first.");
            return;
        }
        if (fault == FAULT_INACTIVE_KEY) {
            result(false, "This key has been disabled.");
            return;
        }

        var recoverable = (fault == FAULT_INVALID_SIGNATURE)
            || (fault == FAULT_INVALID_TOKEN_OR_COUNTER)
            || (fault == FAULT_INCORRECT_EPOCH)
            || (fault == FAULT_TIME_EXPIRED);

        if (recoverable && !mRetried) {
            mRetried = true;
            mKey.refreshFromResponse(mDomain, routable);
            report("Retrying...");
            sendCommand();
            return;
        }

        result(false, "Vehicle rejected command (fault " + fault + ")");
    }

    function onBleConnected() {
    }

    function onBleDisconnected() {
        if (mState != STATE_IDLE) {
            // Unexpected drop.
            clearReplyTimer();
            if (mState == STATE_WAIT_PAIR) {
                // Pairing often drops the link after the request; treat as sent.
                result(true, "Request sent. Tap your key card on the console.");
            } else {
                result(false, "Disconnected");
            }
        }
    }

    function onBleError(msg) {
        result(false, msg);
    }

    // --- Timers / reporting -------------------------------------------------

    hidden function armReplyTimer() {
        clearReplyTimer();
        mReplyTimer = new Timer.Timer();
        mReplyTimer.start(method(:onReplyTimeout), REPLY_TIMEOUT_MS, false);
    }

    hidden function clearReplyTimer() {
        if (mReplyTimer != null) {
            mReplyTimer.stop();
            mReplyTimer = null;
        }
    }

    function onReplyTimeout() {
        result(false, "No response from vehicle");
    }

    hidden function report(msg) {
        if (mSink != null) {
            mSink.onStatus(msg);
        }
    }

    hidden function result(ok, msg) {
        clearReplyTimer();
        mBle.disconnect();
        mState = STATE_IDLE;
        if (mSink != null) {
            mSink.onResult(ok, msg);
        }
    }
}
