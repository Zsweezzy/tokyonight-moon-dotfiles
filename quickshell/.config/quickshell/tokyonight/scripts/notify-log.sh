#!/bin/bash
# notify-log.sh — the notification centre's history file.
#
#   read        print the history, one notification per line, oldest first
#   add <json>  append one notification and trim to the newest $KEEP
#   clear       empty it
#
# The file is JSON Lines rather than one JSON array because this is an append-
# only log that a crash can truncate: the worst a half-written line can do is
# lose that one notification, whereas a truncated array loses every one. The
# QML side reads it with `read` and rebuilds the array, skipping any line that
# does not parse.
#
# Trimming here rather than in QML means the file cannot grow without bound even
# if the shell is killed before its own save.
set -u

state="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/tokyonight"
log="$state/notifications.json"
# 200 is a fortnight of ordinary noise. The centre only ever shows the newest
# screenful anyway; the rest is so "clear" is not the same as "lose".
keep=200

mkdir -p "$state" || exit 1

case "${1:-}" in
    read)
        [ -f "$log" ] && cat "$log"
        ;;
    add)
        json=${2:-}
        [ -n "$json" ] || { echo "notify-log.sh: add needs a json argument" >&2; exit 2; }
        # printf, not echo: a notification body can contain anything at all,
        # including backslashes and leading dashes, and echo would eat both.
        printf '%s\n' "$json" >>"$log"
        # Trim on a temp file and move it into place, so a reader never sees a
        # half-written log and the file is never momentarily empty.
        tmp=$(mktemp "$state/.notifications.XXXXXX") || exit 1
        tail -n "$keep" "$log" >"$tmp" && mv "$tmp" "$log" || rm -f "$tmp"
        ;;
    clear)
        : >"$log"
        ;;
    *)
        echo "usage: notify-log.sh read | add <json> | clear" >&2
        exit 2
        ;;
esac
