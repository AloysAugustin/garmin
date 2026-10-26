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
#   or `--download-all` (large).
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

if [ ! -x "$BIN_DIR/connect-iq-sdk-manager" ] || [ ! -s "$BIN_DIR/connect-iq-sdk-manager" ]; then
  # Download a pinned release directly: the upstream install.sh looks up the
  # tag through api.github.com, which the cloud proxy blocks (403), while
  # github.com release downloads work.
  ver=0.8.4
  name="connect-iq-sdk-manager-cli_${ver}_Linux_x86_64.tar.gz"
  url="https://github.com/lindell/connect-iq-sdk-manager-cli/releases/download/v${ver}"
  tmp=$(mktemp -d)
  curl -sSfL -o "$tmp/$name" "$url/$name"
  curl -sSfL -o "$tmp/checksums.txt" "$url/checksums.txt"
  (cd "$tmp" && grep " $name\$" checksums.txt | sha256sum -c -)
  tar -xzf "$tmp/$name" -C "$tmp" connect-iq-sdk-manager
  install -m 755 "$tmp/connect-iq-sdk-manager" "$BIN_DIR/connect-iq-sdk-manager"
  rm -rf "$tmp"
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
