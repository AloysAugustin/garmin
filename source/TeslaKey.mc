using Toybox.Application;
using Toybox.Cryptography;
using Toybox.System;
using Toybox.Lang;

// TeslaKey holds all persistent key material and per-domain session state, and
// turns high-level intents ("unlock") into the exact bytes to put on the wire.
//
// It is transport-agnostic: it produces request ByteArrays and consumes response
// ByteArrays. The BLE layer (TeslaBle) is responsible for actually moving bytes.
class TeslaKey {

    // Persisted storage keys.
    const STORE_PRIV = "clientPriv";
    const STORE_PUB = "clientPub";
    const STORE_VIN = "vin";

    // How far in the future (vehicle seconds) a command is valid.
    const COMMAND_TTL = 30;

    hidden var mPriv;        // ByteArray, 32 bytes
    hidden var mPub;         // ByteArray, 65 bytes (0x04||X||Y)
    hidden var mVin;         // String (17 chars) or null

    // Per-domain session state, keyed by domain Number.
    //   { :key, :epoch, :counter, :clockTime, :timerMs, :verified, :challenge }
    hidden var mSessions;

    // The routing address for the current BLE connection (16 random bytes).
    hidden var mRoutingAddr;

    function initialize() {
        mSessions = {};
        loadKeyPair();
        loadVin();
        newRoutingAddress();
    }

    // --- Identity / key material -------------------------------------------

    hidden function loadKeyPair() {
        mPriv = Application.Storage.getValue(STORE_PRIV);
        mPub = Application.Storage.getValue(STORE_PUB);
        if (mPriv == null || mPub == null) {
            var kp = TeslaCrypto.generateKeyPair();
            mPriv = kp[:priv];
            mPub = kp[:pub];
            Application.Storage.setValue(STORE_PRIV, mPriv);
            Application.Storage.setValue(STORE_PUB, mPub);
        }
    }

    // Public key bytes (65-byte uncompressed point) - this is the identity the
    // vehicle whitelists.
    function publicKey() {
        return mPub;
    }

    function publicKeyHex() {
        return TeslaCrypto.toHex(mPub);
    }

    // --- VIN ----------------------------------------------------------------

    hidden function loadVin() {
        // Prefer the Garmin Connect app setting, fall back to anything stored.
        var v = null;
        try {
            v = Application.Properties.getValue("vin");
        } catch (e) {
            v = null;
        }
        if (v == null || !(v instanceof Lang.String) || v.length() != 17) {
            v = Application.Storage.getValue(STORE_VIN);
        }
        if (v != null && v instanceof Lang.String && v.length() == 17) {
            mVin = v.toUpper();
        } else {
            mVin = null;
        }
    }

    // Called when the user edits app settings in Garmin Connect.
    function reloadSettings() {
        loadVin();
    }

    function setVin(vin) {
        mVin = vin.toUpper();
        Application.Storage.setValue(STORE_VIN, mVin);
    }

    function hasVin() {
        return mVin != null;
    }

    function vin() {
        return mVin;
    }

    hidden function vinBytes() {
        return mVin.toUtf8Array();
    }

    // The BLE advertisement local name the vehicle broadcasts:
    //   "S" + lower-case hex of SHA1(VIN)[:8] + "C"
    function localName() {
        var digest = TeslaCrypto.sha1(vinBytes());
        return "S" + TeslaCrypto.toHex(digest.slice(0, 8)) + "C";
    }

    // --- Connection-scoped state -------------------------------------------

    function newRoutingAddress() {
        mRoutingAddr = Cryptography.randomBytes(16);
    }

    // Drop all session state (e.g. on disconnect).
    function resetSessions() {
        mSessions = {};
    }

    function hasSession(domain) {
        return mSessions.hasKey(domain) && mSessions[domain][:verified];
    }

    // --- Handshake ----------------------------------------------------------

    // Build the handshake request for a domain and remember the challenge.
    function buildHandshake(domain) {
        var challenge = Cryptography.randomBytes(16);
        var uuid = Cryptography.randomBytes(16);
        mSessions[domain] = {
            :challenge => challenge,
            :verified => false
        };
        return TeslaProto.handshakeRequest(domain, mPub, mRoutingAddr, challenge, uuid);
    }

    // Consume a handshake response (parsed RoutableMessage dict). Derives the
    // shared key, verifies the session-info HMAC, and records session state.
    // Returns true on success.
    function applySessionInfo(domain, routable) {
        if (!routable.hasKey(:sessionInfo)) {
            return false;
        }
        var encoded = routable[:sessionInfo];
        var info = TeslaProto.parseSessionInfo(encoded);
        if (info[:publicKey] == null || info[:epoch] == null) {
            return false;
        }

        var key = TeslaCrypto.deriveSharedKey(mPriv, info[:publicKey]);

        // Verify the response integrity tag when present.
        var sess = mSessions[domain];
        if (routable.hasKey(:sessionInfoTag) && sess != null && sess[:challenge] != null) {
            var ok = TeslaCrypto.verifySessionInfo(
                key, vinBytes(), sess[:challenge], encoded, routable[:sessionInfoTag]);
            if (!ok) {
                return false;
            }
        }

        mSessions[domain] = {
            :key => key,
            :epoch => info[:epoch],
            :counter => info[:counter],
            :clockTime => info[:clockTime],
            :timerMs => System.getTimer(),
            :verified => true,
            :challenge => (sess != null ? sess[:challenge] : null)
        };
        return true;
    }

    // Update counter/epoch/clock from a fault response that carried fresh
    // session info (used to recover from counter/epoch/time errors and retry).
    function refreshFromResponse(domain, routable) {
        if (!routable.hasKey(:sessionInfo) || !mSessions.hasKey(domain)) {
            return false;
        }
        var info = TeslaProto.parseSessionInfo(routable[:sessionInfo]);
        var sess = mSessions[domain];
        if (info[:counter] > sess[:counter]) {
            sess[:counter] = info[:counter];
        }
        if (info[:epoch] != null) {
            sess[:epoch] = info[:epoch];
        }
        sess[:clockTime] = info[:clockTime];
        sess[:timerMs] = System.getTimer();
        return true;
    }

    // --- Command construction ----------------------------------------------

    // Estimated current vehicle clock (seconds) for a domain.
    hidden function vehicleClockNow(sess) {
        var elapsedMs = System.getTimer() - sess[:timerMs];
        if (elapsedMs < 0) {
            elapsedMs = 0;
        }
        return sess[:clockTime] + (elapsedMs / 1000);
    }

    // Wrap a plaintext command payload P for `domain` into a signed
    // RoutableMessage. Returns the ByteArray to send, or null if no session.
    function buildCommand(domain, plaintext) {
        if (!hasSession(domain)) {
            return null;
        }
        var sess = mSessions[domain];
        sess[:counter] = sess[:counter] + 1;
        var counter = sess[:counter];
        var expiresAt = vehicleClockNow(sess) + COMMAND_TTL;

        var metadata = TeslaCrypto.commandMetadata(
            TeslaCrypto.SIGNATURE_TYPE_HMAC_PERSONALIZED,
            domain,
            vinBytes(),
            sess[:epoch],
            expiresAt,
            counter,
            0 /* flags */);

        var tag = TeslaCrypto.commandTag(sess[:key], metadata, plaintext);
        var uuid = Cryptography.randomBytes(16);

        return TeslaProto.signedCommand(
            domain, plaintext, mPub, mRoutingAddr,
            sess[:epoch], counter, expiresAt, tag, uuid);
    }

    // Build the unsigned add-key (pairing) envelope.
    function buildAddKey(role) {
        return TeslaProto.addKeyEnvelope(mPub, role, TeslaProto.FORM_FACTOR_ANDROID);
    }
}
