#!/usr/bin/env bash
# rofi-toggle.sh
# Toggle the rofi app launcher: close it if it is already open, otherwise open
# it. Bound to the bare SUPER release bind in hyprland.lua.
#
# The rofi command line lives here rather than being passed in as an argument.
# Hyprland's exec dispatcher does not reliably keep a multi-word argument
# intact on its way to the script: with the command appended unquoted, the
# script was reached with only "rofi" and the mode flags were dropped, which
# rofi reports as "rofi is unsure what to show". Owning the command here means
# the toggle cannot depend on how that tokenizing behaves. If the launcher ever
# needs different flags, edit ROFI_CMD below (and nothing else).
#
# Closes with pkill -x rofi, the same way rofi-outside-click.sh does, so the
# ways of dismissing the launcher cannot disagree about what "rofi is open"
# means. Escape and the outside-click bind still work; this only adds a third
# way in, plus it stops a second rofi being stacked on the first.

set -u

# Always opens on the main center monitor DP-1, matching what the launcher did
# when it was bound straight to `menu` in the config's MY PROGRAMS block.
ROFI_CMD="rofi -monitor DP-1 -show drun"

if pgrep -x rofi >/dev/null 2>&1; then
    pkill -x rofi 2>/dev/null
    exit 0
fi

# shellcheck disable=SC2086  # ROFI_CMD is a command line, meant to word-split
exec $ROFI_CMD
