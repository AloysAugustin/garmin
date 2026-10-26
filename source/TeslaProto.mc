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
    const RKE_REMOTE_DRIVE = 20; // keyless driving for two minutes
    const RKE_AUTO_SECURE = 29;
    const RKE_WAKE = 30;

    // VCSEC.ClosureMoveType_E
    const CLOSURE_OPEN = 3;
    const CLOSURE_CLOSE = 4;

    // VCSEC.ClosureMoveRequest door fields
    const DOOR_FRONT_DRIVER = 1;
    const DOOR_FRONT_PASSENGER = 2;
    const DOOR_REAR_DRIVER = 3;
    const DOOR_REAR_PASSENGER = 4;

    // Keys.Role
    const ROLE_OWNER = 2;
    const ROLE_DRIVER = 3;

    // VCSEC.KeyFormFactor
    const FORM_FACTOR_ANDROID = 7;

    // VCSEC.SignatureType
    const VCSEC_SIG_PRESENT_KEY = 2;

    // OperationStatus_E (same values in UniversalMessage and VCSEC)
    const OPSTATUS_OK = 0;
    const OPSTATUS_WAIT = 1;
    const OPSTATUS_ERROR = 2;

    // Signatures.Session_Info_Status
    const SESSION_INFO_STATUS_KEY_NOT_ON_WHITELIST = 1;

    // VCSEC.WhitelistOperation_information_E values we report specially
    const WL_INFO_NONE = 0;
    const WL_INFO_WHITELIST_FULL = 4;
    const WL_INFO_ALREADY_ON_WHITELIST = 13;
    const WL_INFO_UI_DENIED = 24;
    const WL_INFO_TIMED_OUT_WAITING_FOR_TAP = 25;
    const WL_INFO_TIMED_OUT_WAITING_FOR_UI_ACK = 26;
    const WL_INFO_CANCELLED = 28;

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
    //
    // The vehicle authenticates its reply with TAG_CHALLENGE = this message's
    // `uuid` (protocol.md "Handshake"), so the caller must keep `uuid` to verify
    // the response. Like the reference client, we leave
    // SessionInfoRequest.challenge unset so there is only one candidate value.
    function handshakeRequest(domain, ourPublicKey, routingAddr, uuid) {
        // SessionInfoRequest { public_key = 1 }
        var sir = Pb.fieldBytes(1, ourPublicKey);

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

    // An AES-GCM encrypted command (protocol.md "AES-GCM encryption").
    //   ciphertext : P encrypted under K with AAD = SHA256(metadata)
    //   sig        : { :epoch, :nonce, :counter, :expiresAt, :tag }
    //   flags      : RoutableMessage.flags (also authenticated in the metadata)
    function encryptedCommand(domain, ciphertext, ourPublicKey, routingAddr, sig, uuid, flags) {
        // AES_GCM_Personalized_Signature_Data
        //   epoch = 1, nonce = 2, counter = 3, expires_at = 4 (fixed32), tag = 5
        var gcmData = []b;
        gcmData.addAll(Pb.fieldBytes(1, sig[:epoch]));
        gcmData.addAll(Pb.fieldBytes(2, sig[:nonce]));
        gcmData.addAll(Pb.fieldVarint(3, sig[:counter].toLong()));
        gcmData.addAll(Pb.fieldFixed32(4, sig[:expiresAt].toLong()));
        gcmData.addAll(Pb.fieldBytes(5, sig[:tag]));

        // SignatureData { signer_identity = 1, AES_GCM_Personalized_data = 5 }
        var sigData = []b;
        sigData.addAll(Pb.fieldBytes(1, Pb.fieldBytes(1, ourPublicKey)));
        sigData.addAll(Pb.fieldBytes(5, gcmData));

        var msg = []b;
        msg.addAll(Pb.fieldBytes(6, destDomain(domain)));       // to_destination
        msg.addAll(Pb.fieldBytes(7, destRouting(routingAddr))); // from_destination
        msg.addAll(Pb.fieldBytes(10, ciphertext));              // protobuf_message_as_bytes
        msg.addAll(Pb.fieldBytes(13, sigData));                 // signature_data
        msg.addAll(Pb.fieldBytes(51, uuid));                    // uuid
        if (flags != 0) {
            msg.addAll(Pb.fieldVarint(52, flags));              // flags
        }
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

    // Experimental: the door fields exist in vcsec.proto, but Tesla's
    // reference client never sends them, so whether (and on which models) the
    // car acts on them is unverified. `door` is one of DOOR_*.
    function openDoor(door) {
        return closureMove(door, CLOSURE_OPEN);
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

    // Field numbers that only occur at the top level of a RoutableMessage. A
    // FromVCSECMessage (the legacy reply to a raw ToVCSECMessage) uses 1, 4,
    // 16, 17 and 46 instead, so the two can be told apart.
    function isRoutable(bytes) {
        var f = Pb.decode(bytes);
        var keys = [6, 7, 10, 12, 13, 14, 15, 50, 51, 52];
        for (var i = 0; i < keys.size(); i++) {
            if (f.hasKey(keys[i])) {
                return true;
            }
        }
        return false;
    }

    // Parse a RoutableMessage. Returns a dictionary with any of:
    //   :sessionInfo (ByteArray), :sessionInfoTag (ByteArray),
    //   :fault (Number MessageFault_E), :operationStatus (Number),
    //   :payload (ByteArray, the plaintext protobuf_message_as_bytes),
    //   :toAddress (ByteArray, to_destination.routing_address),
    //   :fromDomain (Number, from_destination.domain),
    //   :requestUuid (ByteArray), :flags (Number),
    //   :gcmResponse ({:nonce, :counter, :tag}: AES_GCM_Response_data, present
    //                 when :payload is encrypted)
    function parseRoutable(bytes) {
        var f = Pb.decode(bytes);
        var result = {};

        // to_destination (6) -> routing_address (2)
        var to = Pb.firstBytes(f, 6);
        if (to != null) {
            var addr = Pb.firstBytes(Pb.decode(to), 2);
            if (addr != null) {
                result[:toAddress] = addr;
            }
        }

        // from_destination (7) -> domain (1)
        var fromDest = Pb.firstBytes(f, 7);
        if (fromDest != null) {
            var dom = Pb.firstInt(Pb.decode(fromDest), 1);
            if (dom != null) {
                result[:fromDomain] = dom.toNumber();
            }
        }

        var flags = Pb.firstInt(f, 52);
        if (flags != null) {
            result[:flags] = flags.toNumber();
        }

        var reqUuid = Pb.firstBytes(f, 50);
        if (reqUuid != null) {
            result[:requestUuid] = reqUuid;
        }

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
            // AES_GCM_Response_data (9) { nonce = 1, counter = 2, tag = 3 }
            var gcm = Pb.firstBytes(sd, 9);
            if (gcm != null) {
                var g = Pb.decode(gcm);
                var counter = Pb.firstInt(g, 2);
                result[:gcmResponse] = {
                    :nonce => Pb.firstBytes(g, 1),
                    :counter => counter == null ? 0 : counter.toNumber(),
                    :tag => Pb.firstBytes(g, 3)
                };
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

    // Parse a VCSEC.FromVCSECMessage (the application-layer reply from VCSEC).
    // Returns a dictionary with any of:
    //   :nominalError (Number GenericError_E; present => command refused)
    //   :opStatus (Number, commandStatus.operationStatus; present => has commandStatus)
    //   :whitelistInfo (Number, commandStatus.whitelistOperationStatus
    //                   .whitelistOperationInformation; present => whitelist op status)
    //   :signedStatus (true when commandStatus.signedMessageStatus is present)
    //   :empty (true when the message has no fields at all)
    function parseFromVcsec(bytes) {
        var f = Pb.decode(bytes);
        var result = {};
        if (f.size() == 0) {
            result[:empty] = true;
        }

        // nominalError (46) -> genericError (1)
        var ne = Pb.firstBytes(f, 46);
        if (ne != null) {
            var code = Pb.firstInt(Pb.decode(ne), 1);
            result[:nominalError] = code == null ? 0 : code.toNumber();
        }

        // commandStatus (4) { operationStatus = 1, signedMessageStatus = 2,
        //                     whitelistOperationStatus = 3 }
        var cs = Pb.firstBytes(f, 4);
        if (cs != null) {
            var c = Pb.decode(cs);
            var op = Pb.firstInt(c, 1);
            result[:opStatus] = op == null ? OPSTATUS_OK : op.toNumber();
            if (c.hasKey(2)) {
                result[:signedStatus] = true;
            }
            var wl = Pb.firstBytes(c, 3);
            if (wl != null) {
                var info = Pb.firstInt(Pb.decode(wl), 1);
                result[:whitelistInfo] = info == null ? WL_INFO_NONE : info.toNumber();
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
