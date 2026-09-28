#!/usr/bin/env bash
# rofi-outside-click.sh
# Close rofi when clicking outside its window.
# Bound to plain LMB/RMB in hyprland.lua with non_consuming (clicks still
# reach the surface under the cursor). Kills rofi only when the click landed
# outside the rofi window rect; clicks inside pass through untouched.
#
# Note: rofi's own -click-to-exit doesn't work under the Wayland backend
# (rofi only creates its own small layer surface, so outside clicks never
# reach it). This script fills that gap at the compositor level.

pgrep -x rofi >/dev/null 2>&1 || exit 0

hyprctl cursorpos 2>/dev/null | tr -d ' ' | python3 -c '
import json, subprocess, sys

raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)  # no cursor position -> do nothing

cx, cy = map(int, raw.split(","))

try:
    layers = json.loads(subprocess.run(["hyprctl", "layers", "-j"], capture_output=True, text=True, timeout=3).stdout)
    mons   = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=3).stdout)
except Exception:
    sys.exit(0)

monmap = {m["name"]: m for m in mons}

for mon, data in layers.items():
    m = monmap.get(mon)
    if not m:
        continue
    s = m["scale"]
    px, py = m["x"], m["y"]
    for lev_lst in data.get("levels", {}).values():
        for l in lev_lst:
            if l.get("namespace") == "rofi":
                # layer coords: x/y = monitor physical origin + local logical offset;
                # w/h already logical. Convert to global logical space.
                gx = (l["x"] - px) + px / s
                gy = (l["y"] - py) + py / s
                w, h = l["w"], l["h"]
                if gx <= cx <= gx + w and gy <= cy <= gy + h:
                    sys.exit(0)   # inside rofi -> let the click through
                sys.exit(1)       # outside rofi -> close it
sys.exit(1)  # rofi process alive but no window found -> close it
'
rc=$?
if [ "$rc" -eq 1 ]; then
    pkill -x rofi 2>/dev/null
fi
exit 0