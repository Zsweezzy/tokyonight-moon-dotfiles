#!/bin/bash
# cachy-updates.sh — waybar widget: number of pending CachyOS/Arch updates.
# Hover shows the list (name  old -> new). A click on the widget in waybar
# forces an immediate re-check (sends this module's signal).
out=$(checkupdates 2>/dev/null)
n=$(printf '%s' "$out" | grep -c .)

if [ "$n" -eq 0 ]; then
    printf '{"text": "\\uf019 0", "class": "zero", "tooltip": "System up to date — no pending updates"}\n'
    exit 0
fi

list=$(printf '%s\n' "$out" | sed -n '1,40p' | sed 's/\t/ /g')
[ "$n" -gt 40 ] && list="$list
… and $((n - 40)) more"

esc=$(printf '%s' "$list" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
esc=${esc//$'\n'/\\n}   # literal \n so the JSON stays on one line

printf '{"text": "\\uf019 %d", "class": "pending", "tooltip": "CachyOS updates (%d)\\n%s"}\n' \
    "$n" "$n" "$esc"