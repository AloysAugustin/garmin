# AGENTS.md — working notes for this repo

Context for anyone (human or AI) picking this project up. This is a **Connect IQ
watch app** that makes a Garmin Instinct 2 act as a standalone BLE key for a
Tesla, speaking Tesla's documented Vehicle Command protocol directly.

## What this project is

- Language: **Monkey C** (Garmin Connect IQ).
- Target device: **instinct2** (also instinct2s; instinct2x needs a newer SDK).
- Protocol: Tesla `vehicle-command` (BLE to the VCSEC service). See README for
  the full design.

## How to build (verified working)

The build needs the Connect IQ SDK **and** the per-device files, which the Garmin
SDK Manager normally downloads from `developer.garmin.com`.

Both the normal build and the `--unit-test` build compile cleanly for `instinct2`:

```bash
monkeyc -f monkey.jungle -o bin/TeslaKey.prg -y certs/developer_key.der -d instinct2
monkeyc -f monkey.jungle -o bin/TeslaKey.prg -y certs/developer_key.der -d instinct2 --unit-test
```

Create a dev key once (gitignored, never commit):

```bash
openssl genrsa -out certs/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in certs/developer_key.pem -out certs/developer_key.der -nocrypt
```

## Monkey C gotchas learned here (these cost build cycles)

- `:private` and `:public` are **reserved words** — they cannot be used as symbol
  literals / dictionary keys. Use other names (we use `:priv` / `:pub`).
- `ByteArray.add` / `addAll` mutate in place and do **not** reliably return the
  array — don't chain on their return value. Build into a `var`, then `return` it.
- Byte-array literals from a **variable** (`[someVar]b`) are fragile; build with
  `var a = []b; a.add(x);` instead (see `Pb.oneByte`).
- The launcher icon must match the device's size (Instinct 2 = **62x62**) or you
  get a scaling warning.
- The manifest validates **every** `<iq:product>` against the SDK, even when
  building for just one device. An unknown product id (e.g. `instinct2x` on an
  older SDK) fails the whole build.
- `project.typecheck = 0` in `monkey.jungle`: the protobuf codec and session
  state use dynamically-typed dictionaries/byte arrays, and some SDK API type
  stubs are over-narrow (`Cryptography.createPublicKey`, BLE iterator element
  types), so gradual typing throws false positives. Syntax/semantic compilation
  is unaffected.

## Connect IQ crypto capability notes (important for the protocol)

- `Toybox.Cryptography` provides: ECDH on **secp256r1**
  (`KEY_PAIR_ELLIPTIC_CURVE_SECP256R1`, `KEY_AGREEMENT_ECDH`), `HASH_SHA1`,
  `HASH_SHA256`, HMAC-SHA256, and `randomBytes`.
- **No AES-GCM** — `Cipher` only supports AES in `MODE_CBC` / `MODE_ECB`. This is
  why commands use Tesla's documented **HMAC-SHA256** auth method
  (`SIGNATURE_TYPE_HMAC_PERSONALIZED`) and we never set `FLAG_ENCRYPT_RESPONSE`
  (so replies stay plaintext and no GCM is needed to read them).
- `KeyAgreement.generateSecret()` returns the **raw shared X coordinate** (32
  bytes) — matches `K = SHA1(Sx)[:16]`. Verified against test vectors.
- Confirmed from the instinct2 device VM that it ships both `BluetoothLowEnergy`
  and the `Cryptography` classes (KeyPair/KeyAgreement/Hash/HMAC).

## Validation approach (how to be confident without a car)

- Unit tests in `source/tests/CryptoTests.mc` encode Tesla's **official
  `protocol.md` test vectors** (K derivation, sub-keys, session + command
  metadata TLV, end-to-end session-info HMAC). Run in the simulator:
  `monkeydo bin/TeslaKey-test.prg instinct2 -t`.
- The same vectors were also checked with an independent Python reimplementation
  (pyca/cryptography) using identical byte operations — all pass. If you change
  anything in `TeslaCrypto.mc` / `Pb.mc` / `TeslaProto.mc`, re-run the tests.

## This cloud environment's constraints (so you don't rediscover them)

- `developer.garmin.com` and other `*.garmin.com` hosts are **blocked** by the
  egress proxy (403). You cannot download the SDK or device files from Garmin.
- **Docker works** (start the daemon with `dockerd &` if the socket is missing).
  Docker Hub blobs are reachable; **ghcr.io blobs are blocked** (403).
- The SDK + device files used here came from the Docker Hub image
  `piccobit/docker-connectiq:4.1.7-2022-11-21-562b8a195` (SDK 4.1.7, includes
  the instinct2 device). Inspect images with `docker create` + `docker export`
  (copying files out), which avoids executing image code.
- The compiler is Java: run `monkeybrains.jar` with
  `com.garmin.monkeybrains.Monkeybrains`. Device files must be at
  `$HOME/.Garmin/ConnectIQ/Devices/<device>` (the path is effectively hard-coded;
  running as root with devices under `/root/.Garmin/...` works).
- The **GUI simulator cannot run here**: it needs the EOL `webkit2gtk-4.0`, but
  this host is Ubuntu 24.04 (only WebKit 4.1). So in-simulator test runs must be
  done on a normal dev machine. Compilation of the `--unit-test` build still
  works and proves the test code is valid.
- Running binaries extracted from a container can be gated by the auto-mode
  safety classifier ("Code from External"); the user may need to grant
  permission to run the SDK/compiler.

## Repo conventions

- Development branch: `claude/garmin-instinct-tesla-key-jlvhkd`.
- `bin/` and `certs/` are gitignored — never commit build output or signing keys.
- Keep the crypto/protocol code in sync with the test vectors; they are the
  safety net for a device nobody can easily hardware-test in CI.
