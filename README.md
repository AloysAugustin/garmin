# Tesla Key for Garmin Instinct 2

A Connect IQ watch app that turns a **Garmin Instinct 2 / 2S / 2X** into a
**standalone Bluetooth key for a Tesla** — no phone required once it's paired.

The watch talks to the car directly over Bluetooth Low Energy using Tesla's
**documented** [Vehicle Command protocol](https://github.com/teslamotors/vehicle-command)
(the same protocol the official Tesla app and `tesla-control` use). The watch
acts as a BLE *central* and connects to the vehicle's VCSEC service to unlock,
lock, open the trunk/frunk and wake the car.

> This app uses only Tesla's own published protocol and public test vectors. It
> enrolls **your own** key on **your own** vehicle, authorized by tapping an
> existing Tesla key card on the console — exactly like adding a phone key.

---

## What it does

| Action | Protocol message |
| ------ | ---------------- |
| Unlock | VCSEC `RKEAction = RKE_ACTION_UNLOCK` |
| Lock   | VCSEC `RKEAction = RKE_ACTION_LOCK` |
| Trunk  | VCSEC `ClosureMoveRequest { rearTrunk = OPEN }` |
| Frunk  | VCSEC `ClosureMoveRequest { frontTrunk = OPEN }` |
| Wake   | VCSEC `RKEAction = RKE_ACTION_WAKE_VEHICLE` |
| Pair   | Unsigned `WhitelistOperation` add-key request (needs NFC card tap) |

All commands are authenticated end-to-end; the watch holds a private key that
never leaves the device.

---

## How it works (crypto & protocol)

The app implements the client side of Tesla's protocol on top of Connect IQ's
`Toybox.Cryptography` module:

1. **Identity.** On first launch the app generates a NIST P-256 (secp256r1) key
   pair and stores it in the app's persistent storage. The **public key** is the
   identity the car whitelists.
2. **Handshake.** For each connection the app sends a `SessionInfoRequest` to the
   VCSEC domain. The car replies with its ephemeral public key, an anti-replay
   counter, its epoch and clock.
3. **Key agreement.** `K = SHA1(ECDH(ourPriv, carPub))[:16]` — a shared 128-bit
   key, exactly as specified.
4. **Response integrity.** The session-info reply is verified with
   `HMAC-SHA256(HMAC-SHA256(K,"session info"), metadata || sessionInfo)`.
5. **Command authentication.** Each command is signed with a *personalized HMAC*:
   `tag = HMAC-SHA256(HMAC-SHA256(K,"authenticated command"), metadata || command)`
   where `metadata` is the canonical TLV serialization of the signature type,
   domain, VIN, epoch, expiry and counter.

### Why HMAC instead of AES-GCM

Tesla vehicles accept **two** authentication methods: AES-GCM (encrypted) and
HMAC-SHA256 (plaintext). The official client prefers AES-GCM over BLE, but
Connect IQ's `Cipher` class only offers AES in CBC/ECB mode — **no GCM**. This
app therefore uses the documented **HMAC-SHA256** method, which needs only
primitives Connect IQ *does* provide (ECDH, SHA-1, SHA-256, HMAC-SHA256). The
`FLAG_ENCRYPT_RESPONSE` flag is intentionally left unset so the vehicle replies
in plaintext and no GCM is ever required.

### Verified against Tesla's test vectors

The protocol math is validated against the official test vectors in Tesla's
`protocol.md`, both as Connect IQ unit tests (`source/tests/CryptoTests.mc`,
runnable in the simulator) and independently. All checks pass: K derivation,
sub-key derivation, TLV metadata for both the session-info and command paths,
and the end-to-end session-info HMAC verification.

---

## Project layout

```
manifest.xml                 App manifest (Instinct 2/2S/2X, BLE permission)
monkey.jungle                Build configuration
resources/                   Strings, launcher icon, VIN setting
source/
  Pb.mc                      Minimal protobuf encoder/decoder
  TeslaCrypto.mc             ECDH / hashing / HMAC / TLV metadata
  TeslaProto.mc              Tesla protobuf message builders & parsers
  TeslaKey.mc                Key store, VIN, per-domain session state
  TeslaBleManager.mc         BLE scan / connect / chunked write / reassembly
  TeslaController.mc         Handshake -> command flow state machine
  TeslaKeyApp.mc             Application entry point
  ui/                        Menus and views
  tests/CryptoTests.mc       "Run No Evil" unit tests (test vectors)
```

---

## Building

You need the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
(4.1.7 or newer, which includes the Instinct 2 device) and a developer key.

```bash
# One-time: create a developer signing key
openssl genrsa -out certs/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
    -in certs/developer_key.pem -out certs/developer_key.der -nocrypt

# Build for the Instinct 2
monkeyc -f monkey.jungle -o bin/TeslaKey.prg -y certs/developer_key.der -d instinct2

# Build for the 2S or 2X instead
monkeyc -f monkey.jungle -o bin/TeslaKey.prg -y certs/developer_key.der -d instinct2s
```

### Run the unit tests (simulator, no vehicle needed)

```bash
monkeyc -f monkey.jungle -o bin/TeslaKey-test.prg -y certs/developer_key.der \
        -d instinct2 --unit-test
connectiq &                       # start the simulator
monkeydo bin/TeslaKey-test.prg instinct2 -t
```

### Install on the watch

Copy `bin/TeslaKey.prg` to the `GARMIN/APPS` folder of the watch over USB, or
sideload it from the Connect IQ simulator / VS Code extension.

---

## Setup & usage

1. **Set your VIN.** In the Garmin Connect mobile app, open the app's settings
   and enter your 17-character VIN. (The VIN is used to derive the car's BLE
   advertisement name and to personalize command signatures — it never leaves
   your Garmin account/watch.)
2. **Pair the watch.** Choose *Pair this watch → Driver* (or *Owner*). Within a
   few seconds, **tap an already-paired Tesla key card** on the center console
   reader and confirm on the car's screen. This enrolls the watch's public key,
   just like adding a phone key.
3. **Use it.** Walk up to the car and pick *Unlock*, *Lock*, *Trunk*, etc. The
   watch finds the car, performs the handshake and sends the command.

---

## Limitations & notes

- **Range / wake.** BLE range is short (a few metres). If the car is asleep, run
  *Wake* first; VCSEC stays reachable over BLE even when infotainment sleeps.
- **Connection slots.** A Tesla keeps only ~3 simultaneous BLE key connections;
  these are shared with phones and key fobs.
- **BLE chunking.** Connect IQ writes BLE characteristics in small chunks and one
  operation at a time; the app frames every message with the protocol's 2-byte
  length prefix and reassembles replies accordingly.
- **Authentication method.** Commands use the documented HMAC-SHA256 method (see
  above). This is a supported method for the VCSEC domain; the app does not
  implement AES-GCM because Connect IQ lacks a GCM cipher.
- **Not affiliated with Tesla or Garmin.** "Tesla" is a trademark of Tesla, Inc.
  Use on vehicles and keys you own, at your own risk.

---

## Security

- The watch's private key is generated on-device and stored in the app's private
  storage; it is never transmitted.
- Commands are bound to the VIN, epoch, counter and an expiry time, preventing
  replay and relay beyond a short window.
- Session-info responses from the car are integrity-checked before use.
- Never commit your `certs/` developer keys (see `.gitignore`).
