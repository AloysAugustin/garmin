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
        INTENT_PAIR_OWNER,
        INTENT_DOOR_FRONT_DRIVER,
        INTENT_DOOR_FRONT_PASSENGER,
        INTENT_DOOR_REAR_DRIVER,
        INTENT_DOOR_REAR_PASSENGER,
        INTENT_DRIVE
    }

    // Internal flow state.
    enum {
        STATE_IDLE,
        STATE_CONNECTING,
        STATE_WAIT_SESSION,
        STATE_WAIT_RESULT,
        STATE_WAIT_PAIR
    }

    // MessageFault_E codes (universal_message.proto).
    const FAULT_BUSY = 1;
    const FAULT_TIMEOUT = 2;
    const FAULT_UNKNOWN_KEY = 3;
    const FAULT_INACTIVE_KEY = 4;
    const FAULT_INVALID_SIGNATURE = 5;
    const FAULT_INVALID_TOKEN_OR_COUNTER = 6;
    const FAULT_INSUFFICIENT_PRIVILEGES = 7;
    const FAULT_INTERNAL = 11;
    const FAULT_WRONG_PERSONALIZATION = 12;
    const FAULT_INCORRECT_EPOCH = 15;
    const FAULT_TIME_EXPIRED = 17;
    const FAULT_TIME_TO_LIVE_TOO_LONG = 20;
    const FAULT_REMOTE_ACCESS_DISABLED = 21;
    const FAULT_RESPONSE_MTU_EXCEEDED = 25;
    const FAULT_REQUIRES_RESPONSE_ENCRYPTION = 28;

    // Errors.GenericError_E (VCSEC nominalError).
    const GENERIC_CLOSURES_OPEN = 2;
    const GENERIC_ALREADY_ON = 3;
    const GENERIC_DISABLED_FOR_USER_COMMAND = 4;
    const GENERIC_VEHICLE_NOT_IN_PARK = 5;
    const GENERIC_UNAUTHORIZED = 6;
    const GENERIC_NOT_ALLOWED_OVER_TRANSPORT = 7;

    const REPLY_TIMEOUT_MS = 12000;
    // After VCSEC says it is waiting for the NFC card tap, give the user time
    // to tap the card and confirm on the touchscreen.
    const PAIR_TAP_TIMEOUT_MS = 60000;
    // Same retry interval the reference client uses over BLE.
    const RETRY_DELAY_MS = 1000;
    // Total command transmissions per operation (first try + retries).
    const MAX_ATTEMPTS = 4;

    hidden var mKey;        // TeslaKey
    hidden var mBle;        // TeslaBleManager
    hidden var mSink;       // UI sink with onStatus(str) / onResult(ok, str)
    hidden var mState;
    hidden var mIntent;
    hidden var mDomain;
    hidden var mAttempts;
    hidden var mPairWaiting;
    hidden var mRejectedReply; // an encrypted reply failed verification
    hidden var mReplyTimer;
    hidden var mRetryTimer;

    function initialize(key) {
        mKey = key;
        mBle = new TeslaBleManager(self);
        mState = STATE_IDLE;
        mAttempts = 0;
        mPairWaiting = false;
        mRejectedReply = false;
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
        mAttempts = 0;
        mPairWaiting = false;
        mRejectedReply = false;
        mState = STATE_CONNECTING;
        mKey.resetSessions();
        mKey.newRoutingAddress();
        report("Searching for vehicle...");
        mBle.connect(mKey.localName());
    }

    function cancel() {
        clearReplyTimer();
        clearRetryTimer();
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
        } else if (mIntent == INTENT_DRIVE) {
            return TeslaProto.rkeAction(TeslaProto.RKE_REMOTE_DRIVE);
        } else if (mIntent == INTENT_DOOR_FRONT_DRIVER) {
            return TeslaProto.openDoor(TeslaProto.DOOR_FRONT_DRIVER);
        } else if (mIntent == INTENT_DOOR_FRONT_PASSENGER) {
            return TeslaProto.openDoor(TeslaProto.DOOR_FRONT_PASSENGER);
        } else if (mIntent == INTENT_DOOR_REAR_DRIVER) {
            return TeslaProto.openDoor(TeslaProto.DOOR_REAR_DRIVER);
        } else if (mIntent == INTENT_DOOR_REAR_PASSENGER) {
            return TeslaProto.openDoor(TeslaProto.DOOR_REAR_PASSENGER);
        }
        return null;
    }

    hidden function successMessage() {
        if (mIntent == INTENT_DRIVE) {
            return "Keyless driving on. Start driving within 2 minutes.";
        }
        return intentName() + " OK";
    }

    hidden function intentName() {
        if (mIntent == INTENT_UNLOCK) { return "Unlock"; }
        if (mIntent == INTENT_LOCK) { return "Lock"; }
        if (mIntent == INTENT_WAKE) { return "Wake"; }
        if (mIntent == INTENT_TRUNK) { return "Trunk"; }
        if (mIntent == INTENT_FRUNK) { return "Frunk"; }
        if (mIntent == INTENT_DRIVE) { return "Drive"; }
        if (mIntent == INTENT_DOOR_FRONT_DRIVER) { return "Front driver door"; }
        if (mIntent == INTENT_DOOR_FRONT_PASSENGER) { return "Front passenger door"; }
        if (mIntent == INTENT_DOOR_REAR_DRIVER) { return "Rear driver door"; }
        if (mIntent == INTENT_DOOR_REAR_PASSENGER) { return "Rear passenger door"; }
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
        if (mState == STATE_IDLE || mState == STATE_CONNECTING) {
            return;
        }
        // A malformed frame must not crash the app; ignore it and keep waiting
        // (the reply timer still bounds the operation).
        try {
            if (mState == STATE_WAIT_PAIR) {
                handlePairResponse(message);
                return;
            }
            var routable = TeslaProto.parseRoutable(message);
            if (!mKey.isForUs(routable)
                    || (routable.hasKey(:fromDomain) && routable[:fromDomain] != mDomain)) {
                return;
            }
            if (mState == STATE_WAIT_SESSION) {
                handleSessionResponse(routable);
            } else if (mState == STATE_WAIT_RESULT) {
                // Encrypted replies must verify against our last command;
                // anything else is dropped (a forged "OK" must not show).
                if (!mKey.openReply(mDomain, routable)) {
                    mRejectedReply = true;
                    return;
                }
                handleCommandResponse(routable);
            }
        } catch (e) {
            return;
        }
    }

    // --- Pairing ------------------------------------------------------------

    // The add-key request is a raw ToVCSECMessage, so VCSEC may answer with a
    // raw FromVCSECMessage; newer firmware may wrap it in a RoutableMessage.
    // VCSEC first reports OPERATIONSTATUS_WAIT (waiting for the NFC tap) and
    // the reply carrying whitelistOperationStatus is terminal.
    hidden function handlePairResponse(message) {
        var vc;
        if (TeslaProto.isRoutable(message)) {
            var routable = TeslaProto.parseRoutable(message);
            if (routable.hasKey(:fault) && routable[:fault] != 0) {
                result(false, faultMessage(routable[:fault]));
                return;
            }
            if (!routable.hasKey(:payload)) {
                return;
            }
            vc = TeslaProto.parseFromVcsec(routable[:payload]);
        } else {
            vc = TeslaProto.parseFromVcsec(message);
        }

        if (vc.hasKey(:whitelistInfo)) {
            var info = vc[:whitelistInfo];
            if (info == TeslaProto.WL_INFO_NONE) {
                result(true, "Watch paired!");
            } else if (info == TeslaProto.WL_INFO_ALREADY_ON_WHITELIST) {
                result(true, "This watch is already paired.");
            } else {
                result(false, whitelistMessage(info));
            }
            return;
        }
        if (vc.hasKey(:nominalError)) {
            result(false, nominalMessage(vc[:nominalError]));
            return;
        }
        if (vc.hasKey(:opStatus) && vc[:opStatus] == TeslaProto.OPSTATUS_WAIT && !mPairWaiting) {
            mPairWaiting = true;
            report("Tap your key card on the console, then confirm on screen.");
            armReplyTimerFor(PAIR_TAP_TIMEOUT_MS);
        }
        // Anything else (empty / legacy status messages) is not terminal.
    }

    // --- Commands -----------------------------------------------------------

    hidden function handleSessionResponse(routable) {
        if (routable.hasKey(:fault) && routable[:fault] != 0) {
            failOrRetryHandshake(routable[:fault]);
            return;
        }
        if (!routable.hasKey(:sessionInfo)) {
            return; // not the handshake reply; keep waiting
        }
        var status = mKey.applySessionInfo(mDomain, routable);
        if (status == TeslaKey.SESSION_NOT_PAIRED) {
            result(false, "Watch not paired with this car. Pair it first.");
            return;
        }
        if (status != TeslaKey.SESSION_OK) {
            result(false, "Handshake failed (check VIN)");
            return;
        }
        clearReplyTimer();
        report(intentName() + "...");
        sendCommand();
    }

    hidden function failOrRetryHandshake(fault) {
        if (isTransient(fault) && mAttempts < MAX_ATTEMPTS) {
            mAttempts++;
            report("Vehicle busy, retrying...");
            scheduleRetry();
            return;
        }
        result(false, faultMessage(fault));
    }

    hidden function sendCommand() {
        var payload = payloadForIntent();
        var cmd = mKey.buildCommand(mDomain, payload);
        if (cmd == null) {
            result(false, "No session");
            return;
        }
        mAttempts++;
        mRejectedReply = false; // late replies to an earlier attempt don't count
        mBle.send(cmd);
        mState = STATE_WAIT_RESULT;
        armReplyTimer();
    }

    // VCSEC can send up to three replies to one command (protocol.md
    // "VCSEC application-layer responses"). For RKE and closure commands a
    // reply without commandStatus is terminal: empty means success,
    // nominalError means the car refused. OPERATIONSTATUS_WAIT means busy.
    hidden function handleCommandResponse(routable) {
        var hasInfo = routable.hasKey(:sessionInfo);
        if (hasInfo) {
            // The car attaches fresh session info when it suspects a desync.
            mKey.refreshFromResponse(mDomain, routable);
        }

        var fault = routable.hasKey(:fault) ? routable[:fault] : 0;
        if (fault != 0) {
            if (fault == FAULT_RESPONSE_MTU_EXCEEDED) {
                result(true, intentName() + " sent");
            } else if (isRetryable(fault) && mAttempts < MAX_ATTEMPTS) {
                report("Retrying...");
                if (isTransient(fault)) {
                    scheduleRetry();
                } else {
                    sendCommand();
                }
            } else {
                result(false, faultMessage(fault));
            }
            return;
        }

        var op = routable.hasKey(:operationStatus) ? routable[:operationStatus] : TeslaProto.OPSTATUS_OK;
        if (op == TeslaProto.OPSTATUS_WAIT) {
            retryBusy();
            return;
        }
        if (op == TeslaProto.OPSTATUS_ERROR) {
            result(false, "Vehicle reported an error");
            return;
        }

        if (!routable.hasKey(:payload)) {
            if (hasInfo) {
                return; // session-info-only message; keep waiting
            }
            result(true, successMessage());
            return;
        }

        var vc = TeslaProto.parseFromVcsec(routable[:payload]);
        if (vc.hasKey(:nominalError)) {
            result(false, nominalMessage(vc[:nominalError]));
            return;
        }
        if (!vc.hasKey(:opStatus)) {
            result(true, successMessage());
            return;
        }
        var vop = vc[:opStatus];
        if (vop == TeslaProto.OPSTATUS_WAIT) {
            retryBusy();
        } else if (vop == TeslaProto.OPSTATUS_ERROR) {
            if (vc.hasKey(:whitelistInfo) && vc[:whitelistInfo] != TeslaProto.WL_INFO_NONE) {
                result(false, whitelistMessage(vc[:whitelistInfo]));
            } else if (!vc.hasKey(:signedStatus)) {
                result(false, "Vehicle reported an error");
            }
            // Otherwise a legacy error notice: wait for the specific reply.
        }
        // OPERATIONSTATUS_OK with a commandStatus is not terminal; keep waiting.
    }

    hidden function retryBusy() {
        if (mAttempts < MAX_ATTEMPTS) {
            report("Vehicle busy, retrying...");
            scheduleRetry();
        } else {
            result(false, "Vehicle busy. Try again.");
        }
    }

    // Faults the reference client retries (pkg/protocol/error.go).
    hidden function isRetryable(fault) {
        return isTransient(fault)
            || fault == FAULT_INVALID_SIGNATURE
            || fault == FAULT_INVALID_TOKEN_OR_COUNTER
            || fault == FAULT_INCORRECT_EPOCH
            || fault == FAULT_TIME_EXPIRED
            || fault == FAULT_TIME_TO_LIVE_TOO_LONG;
    }

    // Faults that clear up by themselves after a short wait.
    hidden function isTransient(fault) {
        return fault == FAULT_BUSY || fault == FAULT_TIMEOUT || fault == FAULT_INTERNAL;
    }

    hidden function scheduleRetry() {
        clearReplyTimer();
        clearRetryTimer();
        mRetryTimer = new Timer.Timer();
        mRetryTimer.start(method(:onRetryTimer), RETRY_DELAY_MS, false);
    }

    function onRetryTimer() {
        mRetryTimer = null;
        if (mState == STATE_WAIT_SESSION) {
            mBle.send(mKey.buildHandshake(mDomain));
            armReplyTimer();
        } else if (mState == STATE_WAIT_RESULT) {
            sendCommand();
        }
    }

    hidden function clearRetryTimer() {
        if (mRetryTimer != null) {
            mRetryTimer.stop();
            mRetryTimer = null;
        }
    }

    // --- Error text ---------------------------------------------------------

    hidden function faultMessage(fault) {
        if (fault == FAULT_UNKNOWN_KEY) { return "Key not recognized. Pair this watch first."; }
        if (fault == FAULT_INACTIVE_KEY) { return "This key has been disabled."; }
        if (fault == FAULT_INSUFFICIENT_PRIVILEGES) { return "Key role not allowed to do this."; }
        if (fault == FAULT_WRONG_PERSONALIZATION) { return "Wrong VIN for this car."; }
        if (fault == FAULT_REMOTE_ACCESS_DISABLED) { return "Mobile access is disabled in the car."; }
        if (fault == FAULT_REQUIRES_RESPONSE_ENCRYPTION) {
            return "Car requires encrypted replies (unsupported).";
        }
        if (fault == FAULT_BUSY || fault == FAULT_TIMEOUT || fault == FAULT_INTERNAL) {
            return "Vehicle busy. Try again.";
        }
        return "Vehicle rejected command (fault " + fault + ")";
    }

    hidden function nominalMessage(code) {
        if (code == GENERIC_CLOSURES_OPEN) { return "A door or trunk is open."; }
        if (code == GENERIC_ALREADY_ON) { return "Already done."; }
        if (code == GENERIC_DISABLED_FOR_USER_COMMAND) { return "Disabled for this command."; }
        if (code == GENERIC_VEHICLE_NOT_IN_PARK) { return "Vehicle not in Park."; }
        if (code == GENERIC_UNAUTHORIZED) { return "Not authorized."; }
        if (code == GENERIC_NOT_ALLOWED_OVER_TRANSPORT) { return "Not allowed over Bluetooth."; }
        return intentName() + " refused (error " + code + ")";
    }

    hidden function whitelistMessage(info) {
        if (info == TeslaProto.WL_INFO_WHITELIST_FULL) { return "Car's key list is full."; }
        if (info == TeslaProto.WL_INFO_UI_DENIED) { return "Pairing denied on the car."; }
        if (info == TeslaProto.WL_INFO_TIMED_OUT_WAITING_FOR_TAP) { return "Timed out waiting for key card."; }
        if (info == TeslaProto.WL_INFO_TIMED_OUT_WAITING_FOR_UI_ACK) { return "Timed out waiting for confirmation."; }
        if (info == TeslaProto.WL_INFO_CANCELLED) { return "Pairing cancelled."; }
        return "Pairing failed (code " + info + ")";
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
        armReplyTimerFor(REPLY_TIMEOUT_MS);
    }

    hidden function armReplyTimerFor(ms) {
        clearReplyTimer();
        mReplyTimer = new Timer.Timer();
        mReplyTimer.start(method(:onReplyTimeout), ms, false);
    }

    hidden function clearReplyTimer() {
        if (mReplyTimer != null) {
            mReplyTimer.stop();
            mReplyTimer = null;
        }
    }

    function onReplyTimeout() {
        mReplyTimer = null;
        if (mState == STATE_WAIT_PAIR) {
            if (mPairWaiting) {
                result(false, "Timed out waiting for key card.");
            } else {
                // Some firmware never answers the raw add-key request (the
                // reference client does not wait for a reply either).
                result(true, "Request sent. Tap your key card on the console, then confirm on screen.");
            }
        } else if (mState == STATE_WAIT_RESULT) {
            // The car may have acted even though no reply arrived.
            if (mRejectedReply) {
                result(false, "Reply failed verification. " + intentName() + " may have worked.");
            } else {
                result(false, "No reply. " + intentName() + " may have worked.");
            }
        } else {
            result(false, "No response from vehicle");
        }
    }

    hidden function report(msg) {
        if (mSink != null) {
            mSink.onStatus(msg);
        }
    }

    hidden function result(ok, msg) {
        clearReplyTimer();
        clearRetryTimer();
        mBle.disconnect();
        mState = STATE_IDLE;
        if (mSink != null) {
            mSink.onResult(ok, msg);
        }
    }
}
