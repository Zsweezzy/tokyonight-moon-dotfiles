#!/bin/bash
# procs-kill.sh — SIGTERM one PID shown in the PROCESSES list of the pc-stats
# flyout (SysFlyout.qml). Called as: procs-kill.sh <pid> <name-as-shown>
#
# The name is not decoration: pids get recycled, and between the poll that drew
# the row and the click that lands on it the pid can already belong to something
# else. Requiring the name to still match turns that into a refusal instead of
# killing an unrelated program.
#
# SIGTERM only, no fallback to SIGKILL: the program gets to clean up its own
# windows/sockets, and if it does not, SIGTERM usually arrives again via the
# normal session teardown.
set -euo pipefail

fail() {
    printf "refused: %s\n" "$1"
    exit 1
}

pid=${1:-}
shown=${2:-}

[[ $pid =~ ^[0-9]+$ ]] || fail "not a pid: '${pid}'"
(( pid > 1 )) || fail "pid $pid is off limits"
(( pid != $$ && pid != $PPID )) || fail "pid $pid is this script's own shell"
[[ -r /proc/$pid/comm ]] || fail "pid $pid is gone"

# comm is capped at 15 chars by the kernel and ps truncates to the same 15, so
# the two agree. procs.sh rewrites the spaces ps splits on into "_" — do the
# same here or every multi-word process fails the match below.
comm=$(tr -d '\n' < "/proc/$pid/comm" 2>/dev/null) || fail "pid $pid is gone"
name=${comm// /_}
[[ -n $name ]] || fail "pid $pid has no name"

# Kernel threads have no cmdline at all, and procs.sh already leaves them out of
# the list (stock procps brackets their comm; this system's ps does not, but they
# all report rss 0, which procs.sh's `rss <= 0` guard drops). This is the check
# that actually catches one, so it is the one kept here.
# NOTE: the emptiness test reads the bytes, it does NOT use `[[ -s /proc/$pid/cmdline ]]`
# — cmdline is a seq_file and stat() reports it as 0 bytes for every process,
# live ones included, so -s is always false and would refuse everything.
cmdline=$(tr -d '\0' < "/proc/$pid/cmdline" 2>/dev/null) || fail "pid $pid is gone"
[[ -n $cmdline ]] || fail "pid $pid has no command line (kernel thread)"

# The shell owns this UI. Killing it takes the whole bar down with it, so it is
# refused here rather than merely omitted from the list.
case $name in
    quickshell*) fail "pid $pid is quickshell" ;;
esac

[[ -n $shown ]] || fail "no expected name given"
[[ $shown == "$name" ]] || fail "pid $pid is now '$name', not '$shown'"

kill -TERM "$pid"
printf "SIGTERM -> %s (%s)\n" "$pid" "$name"