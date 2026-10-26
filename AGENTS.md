# AGENTS.md — working notes for this repo

Context for anyone (human or AI) picking this project up. This is a **Connect IQ
watch app** that makes a Garmin Instinct 2 act as a standalone BLE key for a
Tesla, speaking Tesla's documented Vehicle Command protocol directly.

## What this project is

- Language: **Monkey C** (Garmin Connect IQ).
- Target devices: **118 watches** — every Garmin wearable whose device files
  have BLE + `Cryptography.KeyPair` etc. (`tools/devices.py`). Developed on
  the Instinct 2.
- Protocol: Tesla `vehicle-command` (BLE to the VCSEC service). See README for
  the full design.

## How to build (verified working)

The build needs the Connect IQ SDK **and** the per-device files, which the Garmin
SDK Manager normally downloads from `developer.garmin.com`.

Run `tools/ciq-setup.sh` first (SDK 9.3.0 + device files + fonts from Garmin).
Both the normal build and the `--unit-test` build compile cleanly for
`instinct2`, `instinct2s` and `instinct2x`, and all 15 unit tests pass in the
simulator on each. `tools/build-dist.sh` release-builds (`-r`) every manifest
product into `dist/` and rewrites `dist/SHA256SUMS.txt`:

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

- `native` is also reserved (fails as a parameter name with a confusing
  "expecting 'function'" parse error); avoid `from` too.
- **Compiling proves little.** Before 2026-10-26 the app compiled cleanly yet
  every crypto call crashed or produced wrong bytes at runtime (byte order,
  Array vs ByteArray). Always run the unit tests in the simulator.
- `hidden` is only allowed inside classes, not modules. Functions take at most
  **9 arguments** (pass a dictionary instead).
- Test-only modules (`(:test) module X`) are stripped from normal builds, so
  any non-test code referring to them breaks the app build: mark the whole
  test module `(:test)` (see `GcmTests`). Test hooks in app classes use
  `(:debug)` (stripped from `-r` release builds).
- `:private` and `:public` are **reserved words** — they cannot be used as symbol
  literals / dictionary keys. Use other names (we use `:priv` / `:pub`).
- `ByteArray.add` / `addAll` mutate in place and do **not** reliably return the
  array — don't chain on their return value. Build into a `var`, then `return` it.
- Byte-array literals from a **variable** (`[someVar]b`) are fragile; build with
  `var a = []b; a.add(x);` instead (see `Pb.oneByte`).
- `monkeyc -o dir/x.prg` also writes `x.prg.debug.xml`, `*-settings.json`,
  `external-mir/`, `internal-mir/` and `gen/` into `dir/`. Never point `-o` at
  `dist/` directly; `tools/build-dist.sh` builds in a temp dir.
- The launcher icon must match the device's size (`launcherIcon` in its
  `compiler.json`; 26x26 to 70x70, one is 40x33) or you get a scaling warning.
  Icons live in `resources-icons/<WxH>[-mono]/` and each device's
  `<id>.resourcePath` in `monkey.jungle` picks one.
- The manifest validates **every** `<iq:product>` against the SDK, even when
  building for just one device. An unknown product id (e.g. `instinct2x` on an
  older SDK) fails the whole build.
- `project.typecheck = 0` in `monkey.jungle`: the protobuf codec and session
  state use dynamically-typed dictionaries/byte arrays, and some SDK API type
  stubs are over-narrow (`Cryptography.createPublicKey`, BLE iterator element
  types), so gradual typing throws false positives. Syntax/semantic compilation
  is unaffected. Re-checked with SDK 9.3.0: `typecheck = 1` gives 5 errors —
  4 fixable (timer `method()` callbacks need `as Void`, the scan iterator
  element type), but the `createPublicKey` stub still declares its first
  parameter as `HashAlgorithm`, so it stays at 0.

## Connect IQ crypto capability notes (important for the protocol)

- `Toybox.Cryptography` provides: ECDH on **secp256r1**
  (`KEY_PAIR_ELLIPTIC_CURVE_SECP256R1`, `KEY_AGREEMENT_ECDH`), `HASH_SHA1`,
  `HASH_SHA256`, HMAC-SHA256, and `randomBytes`.
- **No AES-GCM** — `Cipher` only supports AES in `MODE_CBC` / `MODE_ECB`. The
  default stays Tesla's documented **HMAC-SHA256** method
  (`SIGNATURE_TYPE_HMAC_PERSONALIZED`, no `FLAG_ENCRYPT_RESPONSE`). The
  `encrypt` app setting (property, default false) switches to AES-GCM
  commands + encrypted replies, implemented in `TeslaGcm.mc` on AES-ECB.
- **Connect IQ AES-ECB `encrypt()` only processes the first 16-byte block** of
  its input; the remaining output bytes are zeros (seen in the simulator, SDK
  9.3.0). Encrypt one block per call (`TeslaGcm.aesEcb`).
- **GCM speed:** GHASH is the whole cost (AES blocks are native, ~0.02 ms).
  The first version (bit-by-bit with Long words) took 5.6 ms per GF(2^128)
  multiply / 17 ms per command in the simulator; Shoup's 4-bit table with
  32-bit Numbers (table cached per key) takes 0.34 ms / ~2 ms
  (`source/tests/GcmBench.mc`). Longs are boxed objects in Monkey C, so
  avoid them in hot loops. Watches run the VM much slower than the
  simulator. The watchdog limit is `watchdogCount` in each device's
  `simulator.json` (Instinct 2: 120,000; most recent watches: 240,000), and
  the unit-test runner does **not** enforce it, so tests can't measure that
  headroom.
- GCM replies: `TeslaKey.openReply` decrypts in place and drops replies whose
  tag fails or whose counter was already seen; the request hash is
  `sigType || tag` (17 bytes for VCSEC); response metadata always includes
  flags and the fault (protocol.md "Response metadata", Go `peer.go`).
- **Connect IQ EC keys are little-endian and have no `0x04` prefix** (see the
  `KeyAgreement` example in the SDK docs; confirmed in the simulator): private
  key = 32-byte scalar reversed; `getPublicKey().getBytes()` = reverse(X) ||
  reverse(Y) (64 bytes); `createPublicKey` expects the same; and
  `generateSecret()` returns **reverse(Sx)**. Tesla uses big-endian and 65-byte
  `0x04||X||Y`. `TeslaCrypto` converts at the boundary (`publicFromNative`,
  `publicToNative`, `reverseBytes`); private keys are stored natively.
- `String.toUtf8Array()` returns an **Array of Numbers, not a ByteArray**, and
  `Hash`/`HMAC` reject it ("Expected ByteArray, given Array"). Use
  `TeslaCrypto.strBytes`.
- Confirmed from the instinct2 device VM that it ships both `BluetoothLowEnergy`
  and the `Cryptography` classes (KeyPair/KeyAgreement/Hash/HMAC).

## Validation approach (how to be confident without a car)

- Unit tests in `source/tests/CryptoTests.mc` encode Tesla's **official
  `protocol.md` test vectors** (K derivation, sub-keys, session + command
  metadata TLV, end-to-end session-info HMAC), plus exact message bytes
  (handshake, signed unlock, closures, add-key) and reply parsing, generated by
  serializing with the official `.proto` files via protobuf-python. Run in the
  simulator: `monkeydo bin/TeslaKey-test.prg instinct2 -t`.
- The session-info HMAC challenge is the **request `uuid`** (protocol.md
  "Handshake"; Go verifies against `request_uuid`), not
  `SessionInfoRequest.challenge`. The app leaves `challenge` unset, as the
  reference client does.
- Compare behaviour with the reference client in
  `github.com/teslamotors/vehicle-command`: `pkg/vehicle/vcsec.go` (VCSEC
  reply handling), `internal/dispatcher/` (session refresh),
  `pkg/protocol/error.go` (which faults are retryable).
- AES-GCM vectors: `tools/vectors/gcm_vectors.py` (NIST + random, checked with
  pyca/cryptography and PyCryptodome) and `tools/vectors/tesla_gcm_vectors.py`
  (Tesla's published example + encrypted command/replies from the official
  `.proto` files) write `source/tests/*Vectors.mc`.
  `tools/vectors/tesla_gcm_vectors.go` runs inside a vehicle-command checkout
  (copy to `cmd/ciqvectors/main.go`, `go run ./cmd/ciqvectors`): Tesla's
  vehicle-side `Verifier` must accept our encrypted command, and it encrypts
  replies for us to decrypt (`TeslaGoVectors.mc`; new random epoch each run).
  The owner allowed running Tesla's Go code (2026-10-26); the auto-mode
  classifier blocks it otherwise. Go serializes oneof fields last, so the
  test compares decoded fields, not raw bytes.
- If you change anything in `TeslaCrypto.mc` / `Pb.mc` / `TeslaProto.mc` / `TeslaGcm.mc`,
  re-run the tests **in the simulator** (a Python reimplementation cannot catch
  Connect IQ API quirks like the byte-order issue above).

## This cloud environment's constraints (so you don't rediscover them)

- Network policy varies by session. With full network access,
  `developer.garmin.com` works and the **SDK** downloads without login
  (`https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json` lists
  them; 9.3.0 was current on 2026-10-26). **Device files do not**: the
  device catalogue (`api.gcs.garmin.com/ciq-product-onboarding/...`) needs a
  Garmin account token (401 without one), and no public Docker image ships
  `instinct2x`. Older sessions saw all `*.garmin.com` hosts blocked (403).
- **Garmin login for device files/fonts:** the `CIQ_TOKEN` environment secret
  holds an OAuth `token.json` for `lindell/connect-iq-sdk-manager-cli`;
  `tools/ciq-setup.sh` installs it and downloads the SDK (into
  `~/.Garmin/ConnectIQ/Sdks/`), devices and fonts (**verified working
  2026-10-26**, ~1 min). Afterwards:
  `export PATH=$(connect-iq-sdk-manager sdk current-path --bin):$PATH`
  (the CLI is in `~/.local/bin`). The refresh token expires 2027-10-26
  (`refreshTokenExpiresIn`). Other devices:
  `connect-iq-sdk-manager device download -d a,b,c --include-fonts`. See
  HANDOFF.md for how the token was created (owner's account uses SMS 2FA).
- `api.github.com` is blocked by the proxy (403), but `github.com` release
  downloads and git clones of public repos work. That is why the setup script
  downloads a pinned CLI release instead of using upstream `install.sh`.
- **Docker works** (start the daemon with `dockerd &` if the socket is missing).
  Docker Hub blobs are reachable; **ghcr.io blobs are blocked** (403).
  Docker Hub often answers **429** (anonymous pull limit); pull through
  Google's mirror instead: `mirror.gcr.io/yulrizka/connectiq:latest`,
  `mirror.gcr.io/library/ubuntu:22.04` (works; `public.ecr.aws` did not).
- Before `CIQ_TOKEN` existed, the device files came from the Docker Hub image
  `piccobit/docker-connectiq:4.1.7-2022-11-21-562b8a195` (SDK 4.1.7). No
  longer needed. Inspect images with `docker create` + `docker export`
  (copying files out), which avoids executing image code.
- The compiler is Java: run `monkeybrains.jar` with
  `com.garmin.monkeybrains.Monkeybrains`. Device files must be at
  `$HOME/.Garmin/ConnectIQ/Devices/<device>` (the path is effectively hard-coded;
  running as root with devices under `/root/.Garmin/...` works).
- The **GUI simulator cannot run on the host** (it links the EOL
  `webkit2gtk-4.0`; the host is Ubuntu 24.04). **It runs in Docker** (verified
  2026-10-26): `yulrizka/connectiq:latest` is Ubuntu 22.04 with the WebKit 4.0
  libs; add Xvfb and mount the SDK, `~/.Garmin` and the repo:

  ```bash
  P=$HTTPS_PROXY   # agent proxy; CONNECT only, so apt must use https mirrors
  docker run -d --name ciqsim --network host --user root -e HOME=/root \
    -e https_proxy=$P -e HTTPS_PROXY=$P \
    -v /root/.ccr/ca-bundle.crt:/usr/local/share/ca-certificates/ccr.crt:ro \
    -v /root/.Garmin:/root/.Garmin -v <sdk>:/sdk -v $PWD:/proj \
    --entrypoint sleep mirror.gcr.io/yulrizka/connectiq:latest infinity
  docker exec ciqsim sh -c 'update-ca-certificates; sed -i "s#http://#https://#" /etc/apt/sources.list; apt-get update; apt-get install -y xvfb'
  docker exec -d ciqsim sh -c "Xvfb :99 -screen 0 1280x1024x24 >/tmp/xvfb.log 2>&1"
  docker exec -d -e DISPLAY=:99 -w /sdk/bin ciqsim sh -c "./simulator >/tmp/sim.log 2>&1"
  sleep 15
  docker exec -e DISPLAY=:99 -w /proj ciqsim /sdk/bin/monkeydo bin/TeslaKey-test.prg instinct2 -t
  ```

  If it says "Unable to connect to simulator", `docker restart ciqsim` and
  start Xvfb + simulator again (a killed simulator leaves state that makes the
  next one exit 255). Docker Hub may rate-limit pulls (429).
- Device fonts come with `tools/ciq-setup.sh` (`--include-fonts`); without
  them launching the app UI fails with "Invalid Font Specified".
- **Driving the UI:** launch with
  `docker exec -d -e DISPLAY=:99 -w /proj ciqsim sh -c "/sdk/bin/monkeydo bin/app.prg instinct2 >/tmp/run.log 2>&1"`
  (wait ~12 s), then `tools/sim-shot.sh <device> out.png [enter|esc|up|down...]`
  clicks the device's buttons (positions from its `simulator.json`) and
  crops a screenshot of the display. Needs `xdotool imagemagick` installed in
  the container. Keyboard input via xdotool does **not** reach the simulator;
  mouse clicks on the button images do. Screenshots include Garmin's device
  artwork if not cropped; don't commit them.
- Running binaries extracted from a container can be gated by the auto-mode
  safety classifier ("Code from External"); the user may need to grant
  permission to run the SDK/compiler.

## Multi-device support

- `tools/devices.py` reads `~/.Garmin/ConnectIQ/Devices/*/<id>.api.debug.xml`
  (each device's exact API surface) and `compiler.json`, and lists devices
  in the "Watches/Wearables" group that have every class/function the app
  calls (BLE delegate/registerProfile/setScanState/pairDevice,
  KeyPair/KeyAgreement/Hash/HMAC, createPublicKey, randomBytes, Menu2) at
  API >= `minApiLevel`. `tools/devices.py update` regenerates the manifest
  products, the jungle block (icon folder, `excludeAnnotations = color` for
  1-bit screens), missing icons and the README table. If you add an API
  call, add it to `REQUIRED_*` there and re-run `update`.
- Needs all device files: `connect-iq-sdk-manager device download --download-all`
  (~380 MB, 179 devices, ~2 min). Fonts only for devices you run in the
  simulator: `... device download -d a,b --include-fonts`.
- `minApiLevel` is **3.1.0** (was 3.3.0 for no recorded reason): that adds
  vívoactive 3 Music/LTE, FR 645 Music and D2 Air, whose last firmware is
  API 3.1–3.2 but has every API used. Tests pass on vívoactive 3 Music.
- Unit tests (25 since AES-GCM) pass on instinct2, fenix7 and venu3 (23 of
  them also on instinct2x, venusq2m and vivoactive3m); the earlier 15 also on fr55, instinctcrossover,
  instincte40mm and instinct3amoled45mm. A GCM command + reply takes ~40 ms
  in the simulator. `tools/build-dist.sh` builds all 118 (~8 min, 3.8 MB).
- Simulator quirk: `BluetoothLowEnergy.registerProfile` fails with a fatal
  "System Error" (not the catchable `ProfileRegistrationException`) on about
  the 4th app launch in one simulator session — profiles are never released
  between runs (limit 3). **Restart the simulator every ~3 launches.**
  `docker restart` leaves a stale `/tmp/.X99-lock`; delete it before Xvfb.
- Touch watches: the simulator's Enter button doesn't select Menu2 items on
  Venu; tap them (`tools/sim-shot.sh <dev> out.png tap:X,Y`, swipe with
  `drag:...`). vívoactive 3 has no Back button in the simulator (swipe right).
- Instinct Crossover: the simulator draws the physical hands over the app;
  nothing to fix in the app. Instinct 3 AMOLED and Instinct E also report a
  subscreen, so `Layout` handles them like the Instinct 2.

## UI / layout notes (checked in the simulator 2026-10-26)

- `source/ui/Layout.mc` does the screen-shape work: titles go in the strip
  left of the Instinct **subscreen** (`WatchUi.getSubscreen()`, with ~8 px
  extra below it for the physical ring), body text is wrapped by pixel width
  (`getTextWidthInPixels`), round screens use the chord width, and the
  largest of SMALL/TINY/XTINY that fits is chosen.
- Instinct 2/2S/2X/E/Crossover are **1-bit** displays (`bitsPerPixel: 1` in
  the device's `compiler.json`): `COLOR_RED`/`GREEN` draw as **black**, i.e.
  invisible on black. `Layout.resultColor` has `(:color)`/`(:mono)` variants;
  1-bit devices get `<id>.excludeAnnotations = color` in `monkey.jungle`
  (generated; base excludes `mono`).
- Menu2's title on Instinct only fits one short word beside the subscreen
  ("Tesla"); the subscreen shows the launcher icon in menus.

## Repo conventions

- Development branch: `claude/garmin-instinct-tesla-key-jlvhkd`.
- `bin/` and `certs/` are gitignored — never commit build output or signing keys.
- Keep the crypto/protocol code in sync with the test vectors; they are the
  safety net for a device nobody can easily hardware-test in CI.
