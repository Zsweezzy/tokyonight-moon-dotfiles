#!/usr/bin/env bash
# Move the focused window in a direction (left|right|up|down).
# Works even while the window is fullscreen: temporarily exits fullscreen,
# moves the window, then re-enters fullscreen in the same mode.
# Called from SUPER + SHIFT + arrows in hyprland.lua.
#
# Mode detection via `hyprctl activewindow -j .fullscreen`:
#   0 = not fullscreen, 1 = maximized (Super+F), 2 = plain fullscreen (Super+Shift+F)

dir="${1:?usage: move-fullscreen.sh <left|right|up|down>}"

meta=$(hyprctl activewindow -j)
addr=$(printf '%s' "$meta" | jq -r '.address // empty')

# No focused window (e.g. cursor on wallpaper) -> nothing to do
[ -n "$addr" ] || exit 0

fs=$(printf '%s' "$meta" | jq -r '.fullscreen // 0')

# Turn fullscreen off using the toggle that matches the current mode
if [ "$fs" = "1" ]; then
	hyprctl dispatch 'hl.dsp.window.fullscreen({mode="maximized"})'
elif [ "$fs" = "2" ]; then
	hyprctl dispatch 'hl.dsp.window.fullscreen()'
fi

# Move the window
hyprctl dispatch "hl.dsp.window.move({direction=\"$dir\"})"

# Restore fullscreen in the same mode it was before
if [ "$fs" = "1" ]; then
	hyprctl dispatch 'hl.dsp.window.fullscreen({mode="maximized"})'
elif [ "$fs" = "2" ]; then
	hyprctl dispatch 'hl.dsp.window.fullscreen()'
fi