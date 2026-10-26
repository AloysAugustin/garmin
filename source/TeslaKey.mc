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

    // applySessionInfo() results.
    enum {
        SESSION_OK,
        SESSION_NOT_PAIRED,
        SESSION_INVALID
    }

    hidden var mPriv;        // ByteArray, 32 bytes
    hidden var mPub;         // ByteArray, 65 bytes (0x04||X||Y)
    hidden var mVin;         // String (17 chars) or null

    // Per-domain session state, keyed by domain Number.
    //   { :key, :vehiclePub, :epoch, :counter, :clockTime, :timerMs, :verified,
    //     :challenge (uuid of the last request, used to verify session info) }
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

    // True if a vehicle reply is addressed to this connection. Replies carry
    // our routing address in to_destination; anything else is not for us.
    function isForUs(routable) {
        if (!routable.hasKey(:toAddress)) {
            return true;
        }
        return TeslaCrypto.constantTimeEquals(routable[:toAddress], mRoutingAddr);
    }

    // --- Handshake ----------------------------------------------------------

    // Build the handshake request for a domain. The request uuid doubles as
    // the challenge the vehicle binds into its session-info HMAC.
    function buildHandshake(domain) {
        var uuid = Cryptography.randomBytes(16);
        mSessions[domain] = {
            :challenge => uuid,
            :verified => false
        };
        return TeslaProto.handshakeRequest(domain, mPub, mRoutingAddr, uuid);
    }

    // The challenge a session-info reply was tagged with: the request_uuid the
    // vehicle echoed if any (VCSEC usually omits it), else the uuid we sent.
    hidden function replyChallenge(sess, routable) {
        if (routable.hasKey(:requestUuid) && routable[:requestUuid].size() > 0) {
            return routable[:requestUuid];
        }
        return sess[:challenge];
    }

    // Consume a handshake response (parsed RoutableMessage dict). Derives the
    // shared key, verifies the session-info HMAC, and records session state.
    // Returns SESSION_OK, SESSION_NOT_PAIRED or SESSION_INVALID.
    function applySessionInfo(domain, routable) {
        var sess = mSessions[domain];
        if (sess == null || !routable.hasKey(:sessionInfo)) {
            return SESSION_INVALID;
        }
        var encoded = routable[:sessionInfo];
        var info = TeslaProto.parseSessionInfo(encoded);
        if (info[:status] == TeslaProto.SESSION_INFO_STATUS_KEY_NOT_ON_WHITELIST) {
            return SESSION_NOT_PAIRED;
        }
        if (info[:publicKey] == null || info[:epoch] == null) {
            return SESSION_INVALID;
        }

        var key = TeslaCrypto.deriveSharedKey(mPriv, info[:publicKey]);

        // The integrity tag is mandatory: session info without a valid tag
        // must be discarded (protocol.md "Session state").
        if (!routable.hasKey(:sessionInfoTag)) {
            return SESSION_INVALID;
        }
        if (!TeslaCrypto.verifySessionInfo(key, vinBytes(), replyChallenge(sess, routable),
                encoded, routable[:sessionInfoTag])) {
            return SESSION_INVALID;
        }

        mSessions[domain] = {
            :key => key,
            :vehiclePub => info[:publicKey],
            :epoch => info[:epoch],
            :counter => info[:counter],
            :clockTime => info[:clockTime],
            :timerMs => System.getTimer(),
            :verified => true,
            :challenge => sess[:challenge]
        };
        return SESSION_OK;
    }

    // Resync from session info the vehicle attached to an error reply (used to
    // recover from counter/epoch/time faults before retrying). The info is only
    // applied if its HMAC verifies against the request it answers. Following
    // protocol.md, the counter never rolls back unless the epoch changes, and
    // clock time never goes backwards within an epoch.
    function refreshFromResponse(domain, routable) {
        if (!routable.hasKey(:sessionInfo) || !routable.hasKey(:sessionInfoTag)
                || !hasSession(domain)) {
            return false;
        }
        var sess = mSessions[domain];
        var encoded = routable[:sessionInfo];
        if (!TeslaCrypto.verifySessionInfo(sess[:key], vinBytes(), replyChallenge(sess, routable),
                encoded, routable[:sessionInfoTag])) {
            return false;
        }
        var info = TeslaProto.parseSessionInfo(encoded);
        if (info[:epoch] == null
                || (info[:publicKey] != null
                    && !TeslaCrypto.constantTimeEquals(info[:publicKey], sess[:vehiclePub]))) {
            return false;
        }
        var newEpoch = !TeslaCrypto.constantTimeEquals(info[:epoch], sess[:epoch]);
        if (newEpoch) {
            sess[:epoch] = info[:epoch];
            sess[:counter] = info[:counter];
        } else if (info[:clockTime] < sess[:clockTime]) {
            return false; // stale
        } else if (info[:counter] > sess[:counter]) {
            sess[:counter] = info[:counter];
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
        sess[:challenge] = uuid;

        return TeslaProto.signedCommand(
            domain, plaintext, mPub, mRoutingAddr,
            sess[:epoch], counter, expiresAt, tag, uuid);
    }

    // Build the unsigned add-key (pairing) envelope.
    function buildAddKey(role) {
        return TeslaProto.addKeyEnvelope(mPub, role, TeslaProto.FORM_FACTOR_ANDROID);
    }
}
