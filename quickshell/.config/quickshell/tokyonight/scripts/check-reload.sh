#!/usr/bin/env bash
# Did my .qml edit actually load? Prints ONLY the last reload attempt.
#
# Why this exists: `quickshell -c tokyonight log` replays the WHOLE journal
# since the instance started. Grepping it for "Configuration Loaded" matches
# stale lines from hours ago and fakes a successful reload. A failed reload
# leaves the OLD bar on screen, so the screen never tells you either.
#
# It also checks that the last load is NEWER than every .qml on disk. Without
# that second check the script answers "loaded" for a save that produced no
# reload at all, which is not hypothetical: a `git revert` that rewrote Bar.qml
# and deleted a widget printed a successful load from a quarter of an hour
# earlier, exit 0, and the stale bar kept rendering the deleted widget. A
# reload that never happened and a reload that happened last week look
# identical if you only ask "was the last one successful?".
#
# The log it reads is resolved through a RUNNING process's file descriptors.
# `ls -t by-id/*/log.log` picks the newest mtime on tmpfs, and a quickshell
# that was killed has the newest mtime there because the last thing it ever
# wrote was its own death — so it reports on corpses. In this repo the test
# probes (`quickshell -p ...`, offscreen) leave exactly such corpses behind,
# and one of them answered "Configuration Loaded" while the real bar was
# reloading. The pid's fd table is the only source that cannot name a process
# that is not running.
#
# Usage: scripts/check-reload.sh     (run right after saving a .qml change)
# Exit:  0 = current config is loaded, 1 = broke / never reloaded / watcher dead.
#
# Test seams (tests/test-reload-check.sh). Unset, they change nothing:
#   CHECK_RELOAD_PROC_ROOT      where pids live              (default /proc)
#   CHECK_RELOAD_PIDS           pid list, space separated    (default pgrep -x)
#   CHECK_RELOAD_LOG_OVERRIDE   log path, skips discovery
set -o pipefail

CFG=$(cd "$(dirname "$0")/.." && pwd)
PROC_ROOT=${CHECK_RELOAD_PROC_ROOT:-/proc}

# The log this pid currently has open, straight out of its fd table. Matching
# the log.log target rather than the by-id directory is deliberate: the live
# instance holds log.log, log.qslog and instance.lock open, and only one of
# them is the log.
resolve_log() {
    ls -l "$PROC_ROOT/$1/fd" 2>/dev/null | grep -o '/[^ ]*/log\.log$' | sort -u | head -1
}

# Field 22 of /proc/pid/stat is starttime in jiffies since boot. Used to pick
# the oldest of several live instances.
start_time() {
    awk '{ n = index($0, ")"); split(substr($0, n + 2), f, " "); print f[20] }' \
        "$1/stat" 2>/dev/null
}

if [ -n "$CHECK_RELOAD_LOG_OVERRIDE" ]; then
    LOG=$CHECK_RELOAD_LOG_OVERRIDE
else
    # -x, not -f: `pgrep -f quickshell` matches this script's own command line
    # and every shell that mentions the word, which is how a check ends up
    # reporting on something that is not a quickshell at all.
    #
    # `${VAR-...}`, not `${VAR:-...}`: the override is allowed to be set-and-
    # empty, which means "no processes". With `:-` an empty override silently
    # fell back to the real pgrep and the test consulted the live bar.
    PIDS=${CHECK_RELOAD_PIDS-$(pgrep -x quickshell)}
    if [ -z "$PIDS" ]; then
        echo "check-reload: no quickshell is running — the bar is down, so there is nothing to check." >&2
        exit 1
    fi

    count=0
    for p in $PIDS; do count=$((count + 1)); done
    if [ "$count" -gt 1 ]; then
        echo "check-reload: $count quickshell instances are running; using the oldest (pid $(for p in $PIDS; do echo "$(start_time "$PROC_ROOT/$p") $p"; done | sort -n | head -1 | cut -d' ' -f2))." >&2
        echo "check-reload: a second instance is its own problem — it will fight over the same window." >&2
        PIDS=$(for p in $PIDS; do echo "$(start_time "$PROC_ROOT/$p") $p"; done | sort -n | cut -d' ' -f2)
    fi

    LOG=""
    for p in $PIDS; do
        l=$(resolve_log "$p")
        if [ -n "$l" ] && [ -r "$l" ]; then
            LOG=$l
            break
        fi
    done
    if [ -z "$LOG" ]; then
        echo "check-reload: quickshell is running (pid $PIDS) but none of them has a readable log open" >&2
        exit 1
    fi
fi

clean=$(sed 's/\x1b\[[0-9;]*m//g' "$LOG")

# The LAST marker line, never the last two. Two lines are how this lied: a
# stale `Configuration Loaded` followed by a fresh `Reloading configuration`
# still contains the words "Configuration Loaded", so a grep over the pair
# found it and exited 0 while the config was mid-reload and about to fail.
last=$(printf '%s\n' "$clean" | grep -E "Reloading configuration|Configuration Loaded" | tail -1)
if [ -z "$last" ]; then
    echo "check-reload: no reload recorded yet — the watcher has not seen your save" >&2
    exit 1
fi
echo "$last"

if printf '%s\n' "$last" | grep -q "Reloading configuration"; then
    echo "check-reload: a reload is IN FLIGHT — the last line is 'Reloading configuration', so the load has not finished." >&2
    echo "check-reload: this is not yet a verdict either way. Wait a moment and run it again." >&2
    exit 1
fi

if ! printf '%s\n' "$last" | grep -q "Configuration Loaded"; then
    echo "check-reload: the last reload line is neither marker — refusing to call it a pass: $last" >&2
    exit 1
fi

# The bar is only running what is in the directory if the last successful load
# postdates every .qml. `touch` is a fine way to trip this: it changes the mtime
# without writing, so it never triggers a reload, which is the situation worth
# catching. Epochs are compared numerically on purpose — `find -newermt` does not
# accept the `@<epoch>` form and silently matches nothing, which looks exactly
# like "everything is current".
loaded=$(echo "$clean" | grep "Configuration Loaded" | tail -1 | awk '{print $1, $2}' \
  | xargs -I{} date -d "{}" +%s 2>/dev/null)
newest=$(find "$CFG" -name '*.qml' -printf '%T@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)
newest_file=$(find "$CFG" -name '*.qml' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "$loaded" ] && [ -n "$newest" ] && [ "$newest" -gt "$loaded" ]; then
    echo "check-reload: last load $(date -d "@$loaded" '+%T'), but ${newest_file#$CFG/} changed at $(date -d "@$newest" '+%T')." >&2
    echo "check-reload: the watcher never saw your save — the bar is running stale config." >&2
    echo "check-reload: restart it with 'quickshell -c tokyonight kill && quickshell -c tokyonight'" >&2
    exit 1
fi