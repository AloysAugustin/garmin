#!/usr/bin/env bash
# Release-build TeslaKey-<device>.prg for every product in manifest.xml into
# dist/, and write dist/SHA256SUMS.txt.
#
# Usage: tools/build-dist.sh [signing_key.der]   (default certs/developer_key.der)
# Needs monkeyc on PATH (see tools/ciq-setup.sh).
set -euo pipefail
key=${1:-certs/developer_key.der}
devices=$(grep -o '<iq:product id="[^"]*"' manifest.xml | cut -d'"' -f2)
rm -f dist/*.prg dist/SHA256SUMS.txt
mkdir -p dist
for d in $devices; do
  echo "== $d"
  monkeyc -f monkey.jungle -o "dist/TeslaKey-$d.prg" -y "$key" -d "$d" -r 2>&1 \
    | grep -v '^Picked up JAVA_TOOL_OPTIONS' | grep -v '^BUILD SUCCESSFUL' || true
  [ -s "dist/TeslaKey-$d.prg" ] || { echo "build failed for $d" >&2; exit 1; }
done
(cd dist && sha256sum TeslaKey-*.prg > SHA256SUMS.txt)
echo "Built $(echo $devices | wc -w) devices into dist/"
