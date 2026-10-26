# Handoff — tasks needing Garmin server access

This note is for an agent/developer running in an environment that **can reach
Garmin's servers** (`developer.garmin.com`, the Connect IQ SDK Manager, device
downloads). The app is complete and compiles; the items below are the things
that were blocked in the environment where it was built (Garmin hosts returned
403 there, so the SDK and device files had to be extracted from a Docker image).

Read `AGENTS.md` first for build mechanics and Monkey C gotchas. This file only
covers what Garmin access additionally unlocks.

## Current state (already done)

- Full Connect IQ app in `source/`; compiles cleanly for `instinct2` and
  `instinct2s` with SDK **4.1.7**.
- Pre-built binaries committed in `dist/` (`TeslaKey-instinct2.prg`,
  `TeslaKey-instinct2s.prg`, `SHA256SUMS.txt`).
- Crypto/protocol verified against Tesla's official `protocol.md` test vectors
  (unit tests in `source/tests/CryptoTests.mc`, plus an independent cross-check).
- `instinct2x` is intentionally **not** in `manifest.xml` — it postdates SDK
  4.1.7 and that SDK's compiler rejects the unknown product id.

## Tasks to do with Garmin access

### 1. Install the current official SDK + device files

Use the SDK Manager (or the CLI SDK download) to get the latest SDK and the
device bundles for `instinct2`, `instinct2s`, **and `instinct2x`**. Device files
install under `~/.Garmin/ConnectIQ/Devices/<device>/`.

### 2. Re-enable the Instinct 2X

In `manifest.xml`, add it back to `<iq:products>`:

```xml
<iq:product id="instinct2x"/>
```

(The manifest already has a comment marking where it goes.)

### 3. Build release binaries for all three devices

```bash
# one-time signing key (keep it OUT of git; see .gitignore)
openssl genrsa -out certs/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
    -in certs/developer_key.pem -out certs/developer_key.der -nocrypt

for d in instinct2 instinct2s instinct2x; do
  monkeyc -f monkey.jungle -o dist/TeslaKey-$d.prg -y certs/developer_key.der -d $d
done
(cd dist && sha256sum *.prg > SHA256SUMS.txt)
```

Then commit the refreshed `dist/` (binaries are tracked; `bin/` and `certs/`
are not).

Optional: with a newer SDK you may be able to relax `project.typecheck = 0` in
`monkey.jungle` back to gradual typing if the SDK's API type stubs for
`Cryptography.createPublicKey` / BLE iterators are no longer over-narrow. Rebuild
and confirm no new errors before changing it.

### 4. Run the unit tests in the simulator

This needs a **GUI-capable** environment (the simulator links `webkit2gtk`;
it could not run on the headless Ubuntu 24.04 box used earlier):

```bash
monkeyc -f monkey.jungle -o bin/TeslaKey-test.prg -y certs/developer_key.der \
        -d instinct2 --unit-test
connectiq &                 # start the simulator
monkeydo bin/TeslaKey-test.prg instinct2 -t
```

All six tests in `CryptoTests.mc` should pass (they assert against Tesla's
published test vectors).

### 5. (Optional) Build a store package and/or cut a GitHub release

- Store/sideload-everywhere package: `monkeyc -e -o dist/TeslaKey.iq ...` (export).
- GitHub release (needs valid GitHub auth in that environment):

  ```bash
  gh release create v0.1.0 dist/*.prg dist/SHA256SUMS.txt \
     --title "Tesla Key v0.1.0" \
     --notes "Standalone Tesla BLE key for Garmin Instinct 2 / 2S / 2X."
  ```

## Things Garmin access does NOT fix

- The GitHub **release** limitation is about GitHub auth, not Garmin.
- Real-vehicle testing still requires hardware: sideload, set the VIN in Garmin
  Connect, pair with an NFC key-card tap, and test unlock/lock on the car.
