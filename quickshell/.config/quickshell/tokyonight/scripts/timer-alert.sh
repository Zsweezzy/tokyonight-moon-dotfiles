#!/usr/bin/env bash
# timer-alert.sh — play the "timer finished" chime.
#
# Called by TimerState.qml through Quickshell.execDetached, so it must never
# block the bar: pw-play streams in the background and is killed by the script
# on exit. $TIMER_SOUND overrides the bundled asset (point it at your own wav
# if you dislike the generated one).
#
# pw-play first, paplay as the fallback: pipewire-pulse's player is the native
# one here, but paplay covers the case where only the pulse shim is running.
set -u

dir="$(dirname "$(readlink -f "$0")")"
sound="${TIMER_SOUND:-$dir/../assets/timer-done.wav}"

[ -r "$sound" ] || exit 0    # missing asset: stay silent rather than spam the bar

# Three attempts, ~0.45 s apart: a long drain or a second start-up race should
# not swallow the alert.
for attempt in 1 2 3; do
    if command -v pw-play >/dev/null 2>&1; then
        pw-play --volume=1.0 "$sound" 2>/dev/null && exit 0
    fi
    if command -v paplay >/dev/null 2>&1; then
        paplay "$sound" 2>/dev/null && exit 0
    fi
    sleep 0.45
done

exit 0
