#!/usr/bin/env bash
# Drive the Connect IQ simulator (running in the `ciqsim` container, see
# AGENTS.md) by clicking the device's buttons, then screenshot the watch.
#
# Usage: tools/sim-shot.sh <device> <out.png> [action...]
#   action: a key id from the device's simulator.json (enter, esc, up, down;
#   menu is a long-press and is not supported), tap:X,Y (display pixels) or
#   drag:X1,Y1,X2,Y2 (a swipe on touch screens). Example:
#   tools/sim-shot.sh instinct2 /tmp/menu.png down down enter
# Needs xdotool and imagemagick in the container.
set -euo pipefail
dev=$1; out=$2; shift 2
sim="$HOME/.Garmin/ConnectIQ/Devices/$dev/simulator.json"
# The watch image is drawn at (1, 26) in the simulator window at (0, 0).
disp=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))['display']['location']
print(d['x'] + 1, d['y'] + 26)" "$sim")
read dx dy <<<"$disp"
x11() { docker exec -e DISPLAY=:99 ciqsim xdotool "$@"; }
for k in "$@"; do
  case "$k" in
    tap:*)
      IFS=, read x y <<<"${k#tap:}"
      x11 mousemove $((dx + x)) $((dy + y)) click 1; sleep 1.2; continue;;
    drag:*)
      IFS=, read x1 y1 x2 y2 <<<"${k#drag:}"
      x11 mousemove $((dx + x1)) $((dy + y1)) mousedown 1
      for i in 1 2 3 4 5 6 7 8; do
        x11 mousemove $((dx + x1 + (x2 - x1) * i / 8)) $((dy + y1 + (y2 - y1) * i / 8)); sleep 0.05
      done
      x11 mouseup 1; sleep 1.5; continue;;
  esac
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
