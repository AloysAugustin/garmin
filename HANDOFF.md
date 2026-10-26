# Handoff — next session (written 2026-10-26)

Read `AGENTS.md` first: build mechanics, Monkey C / Connect IQ gotchas, and
the Docker simulator recipe. This file covers what's next.

## Where things stand

- App in `source/` builds for 118 watches with SDK **9.3.0** and Garmin's
  current device files (`tools/ciq-setup.sh`). **All 15 unit tests pass in
  the simulator** on the Instinct 2 family and 8 representative watches
  (Docker recipe in AGENTS.md).
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
- **118 watches** supported (was Instinct 2 family only); UI checked in the
  simulator on Instinct 2/2S/E/Crossover/3 AMOLED, fēnix 7, FR 55, Venu 3,
  Venu Sq 2 and vívoactive 3 Music.
- **Not verified:** anything on real hardware or a real car.

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
3. ~~Check the UI in the simulator~~ — done 2026-10-26. Fixed: invisible
   status title on the 1-bit Instinct display, titles under the subscreen,
   clipped/overflowing text. See AGENTS.md "UI / layout notes".
4. ~~Multi-device support~~ — done 2026-10-26: 118 watches (all wearables
   with the needed APIs, per `tools/devices.py`), icons per size, layouts
   checked on round / rectangular / Instinct screens, tests pass on 8
   representative devices. See AGENTS.md "Multi-device support".
   Follow-ups:
   - Only the Instinct 2 family and the 8 devices above were run in the
     simulator; the rest are build-checked only.
   - The launcher icon is a generated key glyph (not the Tesla logo); a
     designer might want to redo it.
   - Approach S50/S70/S72 (golf watches) and the "Legacy Hero/Saga" editions
     stay in: the owner decided to keep them (2026-10-26).
5. **Permanent signing key:** create once, store outside the repo (store
   updates must use the same key forever). Ask the owner where to keep it.
6. ~~AES-GCM~~ — done 2026-10-26 as an opt-in app setting ("Encrypt
   commands (AES-GCM, beta)", default off = HMAC as before). 25 tests pass in
   the simulator (NIST, two Python libraries, Tesla's published example,
   protocol vectors from the official .proto files, and Tesla's Go Verifier
   accepting our command and producing replies we decrypt). Follow-up: try
   the setting on the car (see "Needs hardware").
7. **Store package:** `monkeyc -e -o dist/TeslaKey.iq ...`. A Connect IQ
   Store submission needs the owner's developer account, a description,
   screenshots, a privacy statement, and a name that doesn't present the app
   as official (no Tesla logo).

## Needs hardware (owner)

Sideload, set the VIN in Garmin Connect, pair with an NFC key-card tap, then
test unlock/lock/trunk/frunk/wake on the car. Also try **Doors**
(experimental, added 2026-10-26): it sends `ClosureMoveRequest` with a door
field set to OPEN, which Tesla's reference client never does. Note what the
car does (opens, unlatches, ignores, or returns an error) and on which model.
Try **Drive** (keyless driving, added 2026-10-26): enable *Allow keyless
driving* and set a *Drive PIN* in the app settings, pick *Drive*, enter the
PIN, and see whether the car can be driven within 2 minutes. Note: whether it
works with a Driver-role key or only Owner; whether PIN to Drive (if enabled
on the car) is still asked for.
Then turn on **Encrypt commands (AES-GCM, beta)** in the app settings, check
*Vehicle* on the watch says "Encryption on", and repeat unlock/lock. A
"Reply failed verification" result would point at the GCM reply path. Bluetooth behaviour varies by
watch model, so test on several.
