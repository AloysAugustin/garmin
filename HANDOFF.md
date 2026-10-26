# Handoff — next session (written 2026-10-26)

Read `AGENTS.md` first: build mechanics, Monkey C / Connect IQ gotchas, and
the Docker simulator recipe. This file covers what's next.

## Where things stand

- App in `source/` builds for `instinct2` / `instinct2s` / `instinct2x` with
  SDK **9.3.0** and Garmin's current device files (`tools/ciq-setup.sh`).
  **All 15 unit tests pass in the simulator on all three** (Docker recipe in
  AGENTS.md).
- Protocol code was checked against the current `teslamotors/vehicle-command`
  and fixed: handshake challenge = request uuid, mandatory session-info tag,
  verified/monotonic session refresh, VCSEC multi-reply handling with
  retries, pairing status, BLE framing guards, safer advert matching.
- Running the tests for the first time showed the original crypto never
  worked on Connect IQ (EC keys/secret are little-endian; `toUtf8Array()` is
  not a ByteArray). Fixed and covered by tests.
- `dist/` holds release builds (`tools/build-dist.sh`) for every manifest
  product from the fixed source, signed
  with a throwaway developer key (the original key was never committed; no
  permanent key exists yet).
- **Not verified:** the UI in the simulator (no device fonts until Garmin
  access works) and anything on real hardware or a real car.

## Garmin access: the `CIQ_TOKEN` secret

Device files and fonts need a Garmin account. The owner (whose account has
SMS 2FA) created an OAuth token with `lindell/connect-iq-sdk-manager-cli`
via its browser login flow, and stored the **contents of `token.json`** as
the environment secret **`CIQ_TOKEN`**. It works (tested 2026-10-26; refresh
token valid until 2027-10-26).

```bash
tools/ciq-setup.sh            # writes the token, installs the CLI, accepts the
                              # agreement, sets SDK >=9, downloads the manifest's
                              # devices + fonts into ~/.Garmin/ConnectIQ
```

If the token has expired (`refreshTokenExpiresIn` in the JSON), ask the
owner to redo the login; don't ask for the password. The 2FA-compatible
procedure is: run the CLI's `login` in a container, `curl` its
`/login` URL from inside the container to get the Garmin SSO link, sign in in
a browser, then `curl` the resulting `http://localhost:<port>/done?ticket=…`
URL from inside the container. (Password login can't do 2FA. The installer
also needs `touch <bindir>/connect-iq-sdk-manager` first, or it refuses to
install without sudo.)

Device files and fonts are Garmin-licensed: keep them out of git.

## Next tasks, in order

1. ~~Run `tools/ciq-setup.sh`~~ — done 2026-10-26 (fixed the CLI install).
2. ~~Re-enable the Instinct 2X~~ — done 2026-10-26; tests pass on it.
3. **Check the UI in the simulator** now that fonts exist (Menu2 menus,
   `StatusView`, `InfoView`). Screenshots via `import -window root` in the
   container (install `imagemagick`).
4. **Multi-device support** (owner's goal: as many Garmin watches as
   possible). About 125 watches have both `BluetoothLowEnergy` and
   `Cryptography.KeyPair` per the SDK 9.3.0 docs: roughly everything since
   ~2019 (fēnix 6+, epix, FR 245–970, Venu 2/3/4, vívoactive 4–6,
   Instinct 2/3/Crossover/E, Enduro, MARQ, D2, Descent). Not supported: Venu
   Sq/Sq 2 (no BLE API), fēnix 5, FR 645/935, Instinct 1, vívosmart/Lily.
   - Add those products to the manifest (check `minApiLevel`).
   - Per-resolution launcher icons (the current one is 62×62 for Instinct).
   - Check layouts on round, rectangular and Instinct screens in the simulator.
   - Run the unit tests on a few representative devices.
5. **Permanent signing key:** create once, store outside the repo (store
   updates must use the same key forever). Ask the owner where to keep it.
6. **AES-GCM (recommended before a public release):** Tesla recommends
   `FLAG_ENCRYPT_RESPONSE`, and fault `REQUIRES_RESPONSE_ENCRYPTION` (28)
   exists; if firmware enforces it, every user breaks. GCM can be built on
   Connect IQ's AES-ECB (CTR + GHASH). Test against Go-generated vectors.
7. **Store package:** `monkeyc -e -o dist/TeslaKey.iq ...`. A Connect IQ
   Store submission needs the owner's developer account, a description,
   screenshots, a privacy statement, and a name that doesn't present the app
   as official (no Tesla logo).

## Needs hardware (owner)

Sideload, set the VIN in Garmin Connect, pair with an NFC key-card tap, then
test unlock/lock/trunk/frunk/wake on the car. Bluetooth behaviour varies by
watch model, so test on several.
