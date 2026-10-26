using Toybox.Lang;

// Builders and parsers for the specific Tesla protobuf messages this app uses.
// Field numbers are taken directly from the vendored .proto files
// (universal_message.proto, signatures.proto, vcsec.proto, keys.proto).
module TeslaProto {

    // UniversalMessage.Domain
    const DOMAIN_VEHICLE_SECURITY = 2;
    const DOMAIN_INFOTAINMENT = 3;

    // VCSEC.RKEAction_E
    const RKE_UNLOCK = 0;
    const RKE_LOCK = 1;
    const RKE_AUTO_SECURE = 29;
    const RKE_WAKE = 30;

    // VCSEC.ClosureMoveType_E
    const CLOSURE_OPEN = 3;
    const CLOSURE_CLOSE = 4;

    // Keys.Role
    const ROLE_OWNER = 2;
    const ROLE_DRIVER = 3;

    // VCSEC.KeyFormFactor
    const FORM_FACTOR_ANDROID = 7;

    // VCSEC.SignatureType
    const VCSEC_SIG_PRESENT_KEY = 2;

    // ---- RoutableMessage builders -----------------------------------------

    // Destination { domain = 1 }
    function destDomain(domain) {
        return Pb.fieldVarint(1, domain);
    }

    // Destination { routing_address = 2 }
    function destRouting(addr) {
        return Pb.fieldBytes(2, addr);
    }

    // The session-info handshake request.
    function handshakeRequest(domain, ourPublicKey, routingAddr, challenge, uuid) {
        // SessionInfoRequest { public_key = 1, challenge = 2 }
        var sir = Pb.fieldBytes(1, ourPublicKey);
        sir.addAll(Pb.fieldBytes(2, challenge));

        var msg = []b;
        msg.addAll(Pb.fieldBytes(6, destDomain(domain)));      // to_destination
        msg.addAll(Pb.fieldBytes(7, destRouting(routingAddr))); // from_destination
        msg.addAll(Pb.fieldBytes(14, sir));                     // session_info_request
        msg.addAll(Pb.fieldBytes(51, uuid));                    // uuid
        return msg;
    }

    // A fully-signed command addressed to `domain`, authenticated with a
    // personalized HMAC tag.
    //   plaintext : the UnsignedMessage / Action protobuf bytes (P)
    function signedCommand(domain, plaintext, ourPublicKey, routingAddr,
                           epoch, counter, expiresAt, tag, uuid) {
        // HMAC_Personalized_Signature_Data
        //   epoch = 1, counter = 2, expires_at = 3 (fixed32), tag = 4
        var hmacData = []b;
        hmacData.addAll(Pb.fieldBytes(1, epoch));
        hmacData.addAll(Pb.fieldVarint(2, counter.toLong()));
        hmacData.addAll(Pb.fieldFixed32(3, expiresAt.toLong()));
        hmacData.addAll(Pb.fieldBytes(4, tag));

        // KeyIdentity { public_key = 1 }
        var signerIdentity = Pb.fieldBytes(1, ourPublicKey);

        // SignatureData { signer_identity = 1, HMAC_Personalized_data = 8 }
        var sigData = []b;
        sigData.addAll(Pb.fieldBytes(1, signerIdentity));
        sigData.addAll(Pb.fieldBytes(8, hmacData));

        var msg = []b;
        msg.addAll(Pb.fieldBytes(6, destDomain(domain)));       // to_destination
        msg.addAll(Pb.fieldBytes(7, destRouting(routingAddr))); // from_destination
        msg.addAll(Pb.fieldBytes(10, plaintext));               // protobuf_message_as_bytes
        msg.addAll(Pb.fieldBytes(13, sigData));                 // signature_data
        msg.addAll(Pb.fieldBytes(51, uuid));                    // uuid
        // flags left unset (0) -> plaintext response, no AES-GCM needed.
        return msg;
    }

    // ---- VCSEC UnsignedMessage payloads (P) -------------------------------

    // UnsignedMessage { RKEAction = 2 }
    function rkeAction(action) {
        return Pb.fieldVarint(2, action);
    }

    // UnsignedMessage { closureMoveRequest = 4 { <doorField> = moveType } }
    function closureMove(doorField, moveType) {
        var cmr = Pb.fieldVarint(doorField, moveType);
        return Pb.fieldBytes(4, cmr);
    }

    function openTrunk() {
        return closureMove(5, CLOSURE_OPEN); // rearTrunk
    }

    function openFrunk() {
        return closureMove(6, CLOSURE_OPEN); // frontTrunk
    }

    // ---- Add-key (pairing) envelope ---------------------------------------

    // ToVCSECMessage carrying an unsigned WhitelistOperation to enroll our
    // public key. This is sent directly over BLE (not wrapped in a
    // RoutableMessage) with signatureType = PRESENT_KEY; the user authorizes it
    // by tapping an already-paired NFC key card on the center console.
    function addKeyEnvelope(ourPublicKey, role, formFactor) {
        // PublicKey { PublicKeyRaw = 1 }
        var pubKey = Pb.fieldBytes(1, ourPublicKey);

        // PermissionChange { key = 1, keyRole = 4 }
        var perm = []b;
        perm.addAll(Pb.fieldBytes(1, pubKey));
        perm.addAll(Pb.fieldVarint(4, role));

        // KeyMetadata { keyFormFactor = 1 }
        var keyMeta = Pb.fieldVarint(1, formFactor);

        // WhitelistOperation { addKeyToWhitelistAndAddPermissions = 5,
        //                      metadataForKey = 6 }
        var wl = []b;
        wl.addAll(Pb.fieldBytes(5, perm));
        wl.addAll(Pb.fieldBytes(6, keyMeta));

        // UnsignedMessage { WhitelistOperation = 16 }
        var unsigned = Pb.fieldBytes(16, wl);

        // SignedMessage { protobufMessageAsBytes = 2, signatureType = 3 }
        var signed = []b;
        signed.addAll(Pb.fieldBytes(2, unsigned));
        signed.addAll(Pb.fieldVarint(3, VCSEC_SIG_PRESENT_KEY));

        // ToVCSECMessage { signedMessage = 1 }
        return Pb.fieldBytes(1, signed);
    }

    // ---- Response parsing --------------------------------------------------

    // Parse a RoutableMessage. Returns a dictionary with any of:
    //   :sessionInfo (ByteArray), :sessionInfoTag (ByteArray),
    //   :fault (Number MessageFault_E), :operationStatus (Number),
    //   :payload (ByteArray, the plaintext protobuf_message_as_bytes)
    function parseRoutable(bytes) {
        var f = Pb.decode(bytes);
        var result = {};

        var si = Pb.firstBytes(f, 15);
        if (si != null) {
            result[:sessionInfo] = si;
        }

        var payload = Pb.firstBytes(f, 10);
        if (payload != null) {
            result[:payload] = payload;
        }

        // signature_data (13) -> session_info_tag (6) -> tag (1)
        var sigData = Pb.firstBytes(f, 13);
        if (sigData != null) {
            var sd = Pb.decode(sigData);
            var sit = Pb.firstBytes(sd, 6);
            if (sit != null) {
                var sitd = Pb.decode(sit);
                var tag = Pb.firstBytes(sitd, 1);
                if (tag != null) {
                    result[:sessionInfoTag] = tag;
                }
            }
        }

        // signedMessageStatus (12) -> MessageStatus { operation_status=1, fault=2 }
        var status = Pb.firstBytes(f, 12);
        if (status != null) {
            var st = Pb.decode(status);
            var op = Pb.firstInt(st, 1);
            var fault = Pb.firstInt(st, 2);
            if (op != null) {
                result[:operationStatus] = op.toNumber();
            }
            if (fault != null) {
                result[:fault] = fault.toNumber();
            }
        }

        return result;
    }

    // Parse a SessionInfo message. Returns a dictionary:
    //   :counter (Number), :publicKey (ByteArray), :epoch (ByteArray),
    //   :clockTime (Number), :status (Number)
    function parseSessionInfo(bytes) {
        var f = Pb.decode(bytes);
        var result = {};
        var counter = Pb.firstInt(f, 1);
        result[:counter] = counter == null ? 0 : counter.toNumber();
        result[:publicKey] = Pb.firstBytes(f, 2);
        result[:epoch] = Pb.firstBytes(f, 3);
        var clock = Pb.firstInt(f, 4);
        result[:clockTime] = clock == null ? 0 : clock.toNumber();
        var status = Pb.firstInt(f, 5);
        result[:status] = status == null ? 0 : status.toNumber();
        return result;
    }
}
