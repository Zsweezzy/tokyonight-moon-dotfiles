#!/usr/bin/env bash
# duplicate-window.sh
# Launch a second instance of the app in the focused window, on the current
# workspace, leaving the original exactly where it is. Bound to SUPER + D in
# hyprland.lua, which is why Steam moved off that chord to SUPER + T.
#
# The app is identified by the focused window's own /proc/<pid>/cmdline instead
# of by its class name, because class is a label the app chose for itself and
# says nothing about how the binary was launched -- matching on it would need a
# per-app table that goes stale the first time an app changes its name. Re-
# running the real command line is the one thing that works for every app with
# no lookup at all, and it is also what makes single-instance apps (Discord,
# Slack) hand off to the window they already have rather than failing outright.
#
# argv[0] is refused when the host cannot back it up, and the refusal is silent
# because a keystroke that does nothing beats a wrong window. A name with no
# slash is the common case -- /proc/<pid>/cmdline records the argv the caller
# passed, not the resolved binary, so a kitty started as "kitty" is recorded as
# "kitty" -- but that branch is a PATH lookup, so it only finds what the bind's
# own PATH can see, and command -v also accepts shell builtins. Anything with a
# slash in it is taken literally instead, which is what catches Steam's
# ./steamwebhelper (exists only inside the pressure-vessel sandbox) and a
# container's /app/bin/... (not on the host at all). No app is special-cased.
#
# ponytail: Steam and Flatpak windows therefore refuse to duplicate silently,
# as a side effect of that guard rather than as a rule in it. Upgrade if that
# ever annoys: notify-send on both refuse paths -- not a per-app allowlist,
# which would only relocate the same guess to another table.

set -u

meta=$(hyprctl activewindow -j)
pid=$(printf '%s' "$meta" | jq -r '.pid // empty')

# pid 0 is what the compositor reports for a window it has no process for; -ge 2
# rejects pid 1 too, which is never a window either
[ -n "$pid" ] && [ "$pid" -ge 2 ] || exit 0

# A pid that died between the two calls makes the open fail. Bash reports that
# but does not treat it as fatal, so argv keeps the value declared below and
# the length check is the dead-pid guard. 2>/dev/null has to come before the
# redirect: with the reverse order the open's own error reaches real stderr.
argv=()
mapfile -d '' -t argv 2>/dev/null < "/proc/$pid/cmdline"
[ "${#argv[@]}" -gt 0 ] || exit 0

case "${argv[0]}" in
    */*) [ -x "${argv[0]}" ] || exit 0 ;;
    *) command -v -- "${argv[0]}" >/dev/null || exit 0 ;;
esac

# The array is handed straight to setsid, which execs it: nothing re-splits it
# into words and nothing re-quotes it, so an element holding spaces or a control
# character stays one argument. Joining it into a string for sh -c instead would
# need quoting that a second parser has to understand, and printf %q emits a
# bash $'...' form a dash /bin/sh would mangle into the wrong argument silently.
# setsid puts the app in a new session, so job-control signals aimed at the
# bind's process group do not reach it; it is still a descendant in the tree.
setsid -- "${argv[@]}" &
