#!/usr/bin/env bash
# Set up the Connect IQ SDK, device files and fonts in a cloud session.
#
# Needs the CIQ_TOKEN secret: the contents of token.json written by
# `connect-iq-sdk-manager login` (lindell/connect-iq-sdk-manager-cli),
# obtained via Garmin's browser login (supports 2FA). See AGENTS.md.
#
# Usage: tools/ciq-setup.sh [manifest.xml]
#   Downloads the devices listed in the manifest. For other devices use
#   `connect-iq-sdk-manager device download -d <id>[,<id>] --include-fonts`
#   or `--download-all` (large). Untested as of 2026-10-26: CIQ_TOKEN was
#   added after the session that wrote this started.
set -euo pipefail
manifest=${1:-manifest.xml}
CIQ_ROOT="$HOME/.Garmin/ConnectIQ"
BIN_DIR="$HOME/.local/bin"

if [ -z "${CIQ_TOKEN:-}" ]; then
  echo "CIQ_TOKEN is not set (add it as an environment secret; new sessions pick it up)." >&2
  exit 1
fi

mkdir -p "$CIQ_ROOT" "$BIN_DIR"
umask 077
printf '%s' "$CIQ_TOKEN" > "$CIQ_ROOT/token.json"
umask 022

if ! command -v connect-iq-sdk-manager >/dev/null; then
  # The installer refuses to write a binary that doesn't exist yet unless it
  # can sudo; pre-creating the file works around that.
  touch "$BIN_DIR/connect-iq-sdk-manager"
  curl -sSfL https://raw.githubusercontent.com/lindell/connect-iq-sdk-manager-cli/master/install.sh \
    | sh -s -- -b "$BIN_DIR"
fi
export PATH="$BIN_DIR:$PATH"

# Without --agreement-hash this records acceptance of the current agreement
# (the owner already accepted it when creating the token).
connect-iq-sdk-manager agreement accept
connect-iq-sdk-manager sdk set ">=9.0.0"
connect-iq-sdk-manager device download --manifest="$manifest" --include-fonts

echo
echo "SDK bin: $(connect-iq-sdk-manager sdk current-path --bin)"
echo "Devices: $(ls "$CIQ_ROOT/Devices" | wc -l) in $CIQ_ROOT/Devices"
