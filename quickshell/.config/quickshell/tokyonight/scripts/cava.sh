#!/bin/bash
# cava -> waybar visualizer.
# Reads cava's ASCII raw output ("0;3;5;...;" per frame) and renders the
# 8 bar values as block characters.
chars="▁▂▃▄▅▆▇█"

exec cava -p "$(dirname "$0")/cava.config" 2>/dev/null | while IFS= read -r line; do
    out=""
    for v in $(printf '%s' "$line" | tr ';' ' '); do
        v="${v:-0}"
        v=$((10#$v))                # parse as base-10 (handles "07", "0")
        [ "$v" -gt 7 ] && v=7
        out+="${chars:$v:1}"
    done
    printf '%s\n' "$out" 2>/dev/null || break     # exit when waybar goes away
done