#!/usr/bin/env bash
# Drive the Connect IQ simulator (running in the `ciqsim` container, see
# AGENTS.md) by clicking the device's buttons, then screenshot the watch.
#
# Usage: tools/sim-shot.sh <device> <out.png> [button...]
#   buttons are key ids from the device's simulator.json: enter, esc, up, down
#   (menu is a long-press and is not supported). Example:
#   tools/sim-shot.sh instinct2 /tmp/menu.png down down enter
# Needs xdotool and imagemagick in the container.
set -euo pipefail
dev=$1; out=$2; shift 2
sim="$HOME/.Garmin/ConnectIQ/Devices/$dev/simulator.json"
# The watch image is drawn at (1, 26) in the simulator window at (0, 0).
for k in "$@"; do
  xy=$(python3 -c "
import json, sys
for b in json.load(open(sys.argv[1]))['keys']:
    if b['id'] == sys.argv[2] and not b.get('isHold'):
        l = b['location']; print(l['x'] + l['width'] // 2 + 1, l['y'] + l['height'] // 2 + 26); break
" "$sim" "$k")
  [ -n "$xy" ] || { echo "no button '$k' for $dev" >&2; exit 1; }
  docker exec -e DISPLAY=:99 ciqsim xdotool mousemove $xy click 1
  sleep 1.2
done
sleep 1
geom=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))['display']['location']
print('%dx%d+%d+%d' % (d['width'], d['height'], d['x'] + 1, d['y'] + 26))" "$sim")
docker exec -e DISPLAY=:99 ciqsim sh -c "import -window root -crop $geom +repage /tmp/shot.png"
docker cp -q ciqsim:/tmp/shot.png "$out"
