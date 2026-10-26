#!/usr/bin/env bash
# Release-build TeslaKey-<device>.prg for every product in manifest.xml into
# dist/, and write dist/SHA256SUMS.txt.
#
# Usage: tools/build-dist.sh [signing_key.der]   (default certs/developer_key.der)
# Needs monkeyc on PATH (see tools/ciq-setup.sh).
set -euo pipefail
key=${1:-certs/developer_key.der}
devices=$(grep -o '<iq:product id="[^"]*"' manifest.xml | cut -d'"' -f2)
# monkeyc writes debug/mir/gen side files next to the output; build in a
# scratch dir and copy only the .prg into dist/.
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for d in $devices; do
  echo "== $d"
  monkeyc -f monkey.jungle -o "$out/$d/TeslaKey-$d.prg" -y "$key" -d "$d" -r 2>&1 \
    | grep -v '^Picked up JAVA_TOOL_OPTIONS' | grep -v '^BUILD SUCCESSFUL' || true
  [ -s "$out/$d/TeslaKey-$d.prg" ] || { echo "build failed for $d" >&2; exit 1; }
done
rm -rf dist
mkdir -p dist
cp "$out"/*/TeslaKey-*.prg dist/
(cd dist && sha256sum TeslaKey-*.prg > SHA256SUMS.txt)
echo "Built $(echo $devices | wc -w) devices into dist/"
