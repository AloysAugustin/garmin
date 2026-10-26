# Tesla Key for Garmin watches

A Connect IQ watch app that turns a **Garmin watch** (Instinct 2/3/E,
fēnix 5 Plus and later, epix, Forerunner 55–970, Venu, vívoactive 3 Music–6,
Enduro, MARQ, D2, Descent, Approach S50/S70; 118 models, listed below) into a
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

## Installation

### Option A — install a pre-built `.prg` (quickest)

Pre-built apps are published on the repo's
[**Releases**](https://github.com/AloysAugustin/garmin/releases) page, and are
also kept in the [`dist/`](dist/) folder:

<details><summary>Supported watches and their files (118)</summary>

<!-- BEGIN devices -->
| Watch | File |
| ----- | ---- |
| Approach® S50 | `TeslaKey-approachs50.prg` |
| Approach® S70 42mm | `TeslaKey-approachs7042mm.prg` |
| Approach® S70 47mm | `TeslaKey-approachs7047mm.prg` |
| Approach® S72 43mm | `TeslaKey-approachs7243mm.prg` |
| Approach® S72 47mm | `TeslaKey-approachs7247mm.prg` |
| Captain Marvel | `TeslaKey-legacyherocaptainmarvel.prg` |
| D2™ Air | `TeslaKey-d2air.prg` |
| D2™ Air X10 | `TeslaKey-d2airx10.prg` |
| D2™ Mach 1 | `TeslaKey-d2mach1.prg` |
| D2™ Mach 2 | `TeslaKey-d2mach2.prg` |
| D2™ Mach 2 Pro | `TeslaKey-d2mach2pro.prg` |
| Darth Vader™ | `TeslaKey-legacysagadarthvader.prg` |
| Descent™ G1 / G1 Solar | `TeslaKey-descentg1.prg` |
| Descent™ G2 | `TeslaKey-descentg2.prg` |
| Descent™ Mk2 / Mk2i | `TeslaKey-descentmk2.prg` |
| Descent™ Mk2 S | `TeslaKey-descentmk2s.prg` |
| Descent™ Mk3 43mm / Mk3i 43mm | `TeslaKey-descentmk343mm.prg` |
| Descent™ Mk3i 51mm | `TeslaKey-descentmk351mm.prg` |
| Enduro™ | `TeslaKey-enduro.prg` |
| Enduro™ 3 | `TeslaKey-enduro3.prg` |
| Enduro™ 4 | `TeslaKey-enduro4.prg` |
| epix™ (Gen 2) / quatix® 7 Sapphire | `TeslaKey-epix2.prg` |
| epix™ Pro (Gen 2) 42mm | `TeslaKey-epix2pro42mm.prg` |
| epix™ Pro (Gen 2) 47mm / quatix® 7 Pro | `TeslaKey-epix2pro47mm.prg` |
| epix™ Pro (Gen 2) 51mm / D2™ Mach 1 Pro / tactix® 7 – AMOLED Edition | `TeslaKey-epix2pro51mm.prg` |
| First Avenger | `TeslaKey-legacyherofirstavenger.prg` |
| Forerunner® 165 | `TeslaKey-fr165.prg` |
| Forerunner® 165 Music | `TeslaKey-fr165m.prg` |
| Forerunner® 170 | `TeslaKey-fr170.prg` |
| Forerunner® 170 Music | `TeslaKey-fr170m.prg` |
| Forerunner® 245 | `TeslaKey-fr245.prg` |
| Forerunner® 245 Music | `TeslaKey-fr245m.prg` |
| Forerunner® 255 | `TeslaKey-fr255.prg` |
| Forerunner® 255 Music | `TeslaKey-fr255m.prg` |
| Forerunner® 255s | `TeslaKey-fr255s.prg` |
| Forerunner® 255s Music | `TeslaKey-fr255sm.prg` |
| Forerunner® 265 | `TeslaKey-fr265.prg` |
| Forerunner® 265s | `TeslaKey-fr265s.prg` |
| Forerunner® 55 | `TeslaKey-fr55.prg` |
| Forerunner® 570 42mm | `TeslaKey-fr57042mm.prg` |
| Forerunner® 570 47mm | `TeslaKey-fr57047mm.prg` |
| Forerunner® 645 Music | `TeslaKey-fr645m.prg` |
| Forerunner® 70 | `TeslaKey-fr70.prg` |
| Forerunner® 745 | `TeslaKey-fr745.prg` |
| Forerunner® 945 | `TeslaKey-fr945.prg` |
| Forerunner® 945 LTE | `TeslaKey-fr945lte.prg` |
| Forerunner® 955 / Solar | `TeslaKey-fr955.prg` |
| Forerunner® 965 | `TeslaKey-fr965.prg` |
| Forerunner® 970 | `TeslaKey-fr970.prg` |
| fēnix® 5 Plus | `TeslaKey-fenix5plus.prg` |
| fēnix® 5S Plus | `TeslaKey-fenix5splus.prg` |
| fēnix® 5X Plus | `TeslaKey-fenix5xplus.prg` |
| fēnix® 6 / 6 Solar / 6 Dual Power | `TeslaKey-fenix6.prg` |
| fēnix® 6 Pro / 6 Sapphire / 6 Pro Solar / 6 Pro Dual Power / quatix® 6 | `TeslaKey-fenix6pro.prg` |
| fēnix® 6S / 6S Solar / 6S Dual Power | `TeslaKey-fenix6s.prg` |
| fēnix® 6S Pro / 6S Sapphire / 6S Pro Solar / 6S Pro Dual Power | `TeslaKey-fenix6spro.prg` |
| fēnix® 6X Pro / 6X Sapphire / 6X Pro Solar / tactix® Delta Sapphire / Delta Solar / Delta Solar - Ballistics Edition / quatix® 6X / 6X Solar / 6X Dual Power | `TeslaKey-fenix6xpro.prg` |
| fēnix® 7 / quatix® 7 | `TeslaKey-fenix7.prg` |
| fēnix® 7 Pro | `TeslaKey-fenix7pro.prg` |
| fēnix® 7 Pro - Solar Edition (no Wi-Fi) | `TeslaKey-fenix7pronowifi.prg` |
| fēnix® 7S | `TeslaKey-fenix7s.prg` |
| fēnix® 7S Pro | `TeslaKey-fenix7spro.prg` |
| fēnix® 7X / tactix® 7 / quatix® 7X Solar / Enduro™ 2 | `TeslaKey-fenix7x.prg` |
| fēnix® 7X Pro | `TeslaKey-fenix7xpro.prg` |
| fēnix® 7X Pro - Solar Edition (no Wi-Fi) | `TeslaKey-fenix7xpronowifi.prg` |
| fēnix® 8 43mm | `TeslaKey-fenix843mm.prg` |
| fēnix® 8 47mm / 51mm / tactix® 8 47mm / 51mm / quatix® 8 47mm / 51mm | `TeslaKey-fenix847mm.prg` |
| fēnix® 8 Pro 47mm / 51mm / MicroLED / quatix® 8 Pro 47mm / 51mm | `TeslaKey-fenix8pro47mm.prg` |
| fēnix® 8 Solar 47mm | `TeslaKey-fenix8solar47mm.prg` |
| fēnix® 8 Solar 51mm / tactix® 8 Solar 51mm | `TeslaKey-fenix8solar51mm.prg` |
| fēnix® 9 43mm | `TeslaKey-fenix943mm.prg` |
| fēnix® 9 47mm / 51mm | `TeslaKey-fenix947mm.prg` |
| fēnix® 9 Pro 43mm | `TeslaKey-fenix9pro43mm.prg` |
| fēnix® 9 Pro 47mm | `TeslaKey-fenix9pro47mm.prg` |
| fēnix® 9 Pro 51mm | `TeslaKey-fenix9pro51mm.prg` |
| fēnix® 9 Pro Solar 47mm | `TeslaKey-fenix9prosolar47mm.prg` |
| fēnix® 9 Pro Solar 51mm | `TeslaKey-fenix9prosolar51mm.prg` |
| fēnix® E | `TeslaKey-fenixe.prg` |
| Instinct® 2 / Solar / Dual Power / dēzl Edition | `TeslaKey-instinct2.prg` |
| Instinct® 2S / Solar / Dual Power | `TeslaKey-instinct2s.prg` |
| Instinct® 2X Solar | `TeslaKey-instinct2x.prg` |
| Instinct® 3 AMOLED 45mm | `TeslaKey-instinct3amoled45mm.prg` |
| Instinct® 3 AMOLED 50mm | `TeslaKey-instinct3amoled50mm.prg` |
| Instinct® 3 Solar 45mm / 50mm | `TeslaKey-instinct3solar45mm.prg` |
| Instinct® Crossover | `TeslaKey-instinctcrossover.prg` |
| Instinct® Crossover AMOLED | `TeslaKey-instinctcrossoveramoled.prg` |
| Instinct® E 40mm | `TeslaKey-instincte40mm.prg` |
| Instinct® E 45mm | `TeslaKey-instincte45mm.prg` |
| MARQ® (Gen 2) Athlete / Adventurer / Captain / Golfer / Carbon Edition / Commander - Carbon Edition | `TeslaKey-marq2.prg` |
| MARQ® (Gen 2) Aviator | `TeslaKey-marq2aviator.prg` |
| MARQ® (Gen 3) Athlete / Adventurer / Aviator / Commander / Golfer / Diver | `TeslaKey-marq3.prg` |
| MARQ® Adventurer | `TeslaKey-marqadventurer.prg` |
| MARQ® Athlete | `TeslaKey-marqathlete.prg` |
| MARQ® Aviator | `TeslaKey-marqaviator.prg` |
| MARQ® Captain / MARQ® Captain: American Magic Edition | `TeslaKey-marqcaptain.prg` |
| MARQ® Commander | `TeslaKey-marqcommander.prg` |
| MARQ® Driver | `TeslaKey-marqdriver.prg` |
| MARQ® Expedition | `TeslaKey-marqexpedition.prg` |
| MARQ® Golfer | `TeslaKey-marqgolfer.prg` |
| Rey™ | `TeslaKey-legacysagarey.prg` |
| Venu® | `TeslaKey-venu.prg` |
| Venu® 2 | `TeslaKey-venu2.prg` |
| Venu® 2 Plus | `TeslaKey-venu2plus.prg` |
| Venu® 2S | `TeslaKey-venu2s.prg` |
| Venu® 3 | `TeslaKey-venu3.prg` |
| Venu® 3S | `TeslaKey-venu3s.prg` |
| Venu® 4 41mm | `TeslaKey-venu441mm.prg` |
| Venu® 4 45mm / D2™ Air X15 | `TeslaKey-venu445mm.prg` |
| Venu® Mercedes-Benz® Collection | `TeslaKey-venud.prg` |
| Venu® Sq 2 Music | `TeslaKey-venusq2m.prg` |
| Venu® Sq. Music Edition | `TeslaKey-venusqm.prg` |
| Venu® X1 | `TeslaKey-venux1.prg` |
| vívoactive® 3 Music | `TeslaKey-vivoactive3m.prg` |
| vívoactive® 3 Music LTE | `TeslaKey-vivoactive3mlte.prg` |
| vívoactive® 4 | `TeslaKey-vivoactive4.prg` |
| vívoactive® 4S | `TeslaKey-vivoactive4s.prg` |
| vívoactive® 5 | `TeslaKey-vivoactive5.prg` |
| vívoactive® 6 | `TeslaKey-vivoactive6.prg` |
<!-- END devices -->

</details>

A watch is supported when its Connect IQ firmware has Bluetooth Low Energy
(central role) and `Cryptography.KeyPair` (ECDH P-256). Not supported:
Venu Sq / Sq 2 (no BLE API), fēnix 5/5S/5X, Forerunner 645/935, vívoactive 3
(non-Music), Instinct (1st gen), and older models. Only the Instinct 2 has
been tried by the author; the others are built and checked in the simulator.

1. **Download** the `.prg` that matches your watch (verify it against
   `dist/SHA256SUMS.txt` if you like).
2. **Connect the watch to your computer** with the USB cable. It mounts as a USB
   drive named `GARMIN`.
3. **Copy** the `.prg` into the **`GARMIN/APPS/`** folder on that drive.
4. **Eject** the drive and unplug. The app appears in your watch's app list
   (from the watch face: hold the middle/`MENU` button → look under Connect IQ
   apps / your activity-and-apps list).
5. Continue with **Setup & usage** below (set your VIN, then pair).

These binaries are signed with a project build key purely so they install; a
Connect IQ device runs any validly-signed sideloaded app. If you'd rather sign
with your own developer key, build from source.

### Option B — build from source

See [Building](#building) below.

### Updating / removing

Replace the `.prg` in `GARMIN/APPS/` with a newer one to update, or delete it to
remove the app. Your enrolled key stays in the car until you remove it in the
Tesla app (Controls → Locks → Keys).

---

## How it works (crypto & protocol)

The app implements the client side of Tesla's protocol on top of Connect IQ's
`Toybox.Cryptography` module:

1. **Identity.** On first launch the app generates a NIST P-256 (secp256r1) key
   pair and stores it in the app's persistent storage. The **public key** is the
   identity the car whitelists.
2. **Handshake.** For each connection the app sends a `SessionInfoRequest` to the
   VCSEC domain. The car replies with its ephemeral public key, an anti-replay
   counter, its epoch and clock. The reply's integrity tag is bound to the
   request's random `uuid`, so a replayed or forged reply is rejected.
3. **Key agreement.** `K = SHA1(ECDH(ourPriv, carPub))[:16]` — a shared 128-bit
   key, exactly as specified.
4. **Response integrity.** The session-info reply is verified with
   `HMAC-SHA256(HMAC-SHA256(K,"session info"), metadata || sessionInfo)`.
5. **Command authentication.** Each command is signed with a *personalized HMAC*:
   `tag = HMAC-SHA256(HMAC-SHA256(K,"authenticated command"), metadata || command)`
   where `metadata` is the canonical TLV serialization of the signature type,
   domain, VIN, epoch, expiry and counter.
6. **Reply handling.** VCSEC can send up to three replies per command. The app
   follows the reference client: a reply without `commandStatus` is final
   (empty = success, `nominalError` = refused, e.g. "door open"),
   `OPERATIONSTATUS_WAIT` means busy and is retried after 1 s, and
   counter/epoch/clock faults are retried after resyncing from the
   HMAC-verified session info the car attaches.

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
and the end-to-end session-info HMAC verification. The tests also pin the exact
bytes of the handshake, a signed unlock, trunk/frunk and add-key messages, and
the parsing of vehicle replies, against bytes produced from Tesla's official
`.proto` files.

---

## Project layout

```
manifest.xml                 App manifest (supported watches, BLE permission)
monkey.jungle                Build configuration
resources/                   Strings, VIN setting
resources-icons/<size>/      Launcher icon per size (generated)
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
(9.x) with the device files installed via the SDK Manager, and a developer
key. `tools/devices.py` decides which watches are supported from the device
files and regenerates the manifest, jungle, icons and the table above.

```bash
# One-time: create a developer signing key
openssl genrsa -out certs/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
    -in certs/developer_key.pem -out certs/developer_key.der -nocrypt

# Build for the Instinct 2
monkeyc -f monkey.jungle -o bin/TeslaKey.prg -y certs/developer_key.der -d instinct2

# Or any other supported watch, e.g.
monkeyc -f monkey.jungle -o bin/TeslaKey.prg -y certs/developer_key.der -d fenix7

# Release-build every supported watch into dist/ (+ SHA256SUMS.txt)
tools/build-dist.sh
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
  implement AES-GCM because Connect IQ lacks a GCM cipher. The protocol defines
  a `REQUIRES_RESPONSE_ENCRYPTION` fault; if a future firmware enforces it, the
  app shows "Car requires encrypted replies" and would need AES-GCM (buildable
  on top of Connect IQ's AES-ECB).
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

### Does using HMAC instead of AES-GCM weaken security?

**Not for authorization — only a minor privacy trade-off.**

- **Authorization / forgery / replay are unaffected.** Both HMAC and GCM
  authenticate commands with a tag derived from the ECDH shared key `K`, which
  only the holder of the enrolled private key can produce. The HMAC covers the
  full metadata (domain, VIN, epoch, counter, expiry) plus the command, so
  tampering, cross-vehicle reuse and replay are rejected identically. Dropping
  GCM does **not** let anyone control the car who couldn't already.
- **What you give up:** confidentiality of the command/response *contents* to a
  passive BLE sniffer physically in range (a few metres) — they could see
  *which* command was sent and the returned vehicle status. That's low-sensitivity
  metadata, not a control compromise. Encrypting responses (`FLAG_ENCRYPT_RESPONSE`)
  would require GCM to decrypt, which Connect IQ cannot do, so it is intentionally
  left off.

### The more relevant considerations

- **Key storage is not hardware-backed.** The P-256 private key lives in Connect
  IQ app storage, not a secure element. Someone with developer access to an
  unlocked watch could extract it (a phone key benefits from the phone's secure
  enclave; the watch has no equivalent). This is the most meaningful real-world
  weakness, and it is independent of the HMAC/GCM choice.
- **RNG.** Security rests on `Cryptography.randomBytes` being a proper CSPRNG
  (it generates the private key, challenge and routing address).
- **Revocation.** If the watch is lost, remove its key in the Tesla app
  (Controls → Locks → Keys), exactly as for a lost phone key.
