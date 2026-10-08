#!/bin/bash
# procs.sh — the heaviest processes running right now, one row per PID, for the
# pc-stats flyout (Sys.qml / SysFlyout.qml).
#
# Rows are per-PID and NOT merged by name (mem.sh merges, which is right for a
# memory summary): a row here is killable, and a kill needs one specific pid.
#
# NOTE: output must fit on ONE line — Poll.qml's SplitParser emits one event per
# stdout line, so a multiline script would overwrite the list with its last line.
# Fields are pipe-delimited:
#   1:    header/count   "TOP 12"
#   2..N: rows           "pid|name|cpuPct|ramMB"
set -euo pipefail

prev="/tmp/opencode/quickshell-procs-prev"
# utime/stime are in clock ticks and the tick size is a kernel constant, not a
# promise: getconf reads it rather than assuming the usual 100.
hz=$(getconf CLK_TCK)

# `ps` is read into a variable first, not piped from: as a pipeline its own
# process is in the table it is printing and shows up in the list. $$ and $PPID
# drop this script and the `sh -c` wrapper Poll.qml runs it under.
table=$(ps -eo pid=,rss=,comm=)

awk -v prevfile="$prev" -v self="$$" -v ppid="$PPID" -v hz="$hz" -v now="$(date +%s)" '
# utime (14) + stime (15) out of /proc/<pid>/stat, in ticks. NOT `ps -o time`:
# that column is whole seconds, so over a 1s poll every rate quantises to 0 or
# 100 and the column is useless. The ticks are 10ms here, which is why it is.
function cputicks(   sl, f, nf, path) {
    path = "/proc/" pid "/stat"
    if ((getline sl < path) > 0) {
        close(path)
        # comm is parenthesised and may contain both spaces and ")", so cut at
        # the LAST ")" and the trailing blanks. What is left starts at field 3
        # (state), which puts utime at element 12 and stime at element 13.
        sub(/^.*\) */, "", sl)
        nf = split(sl, f, " ")
        if (nf >= 13) return f[12] + f[13]
    } else {
        close(path)
    }
    return -1
}
function take(   i, j, b, t) {
    for (i = 1; i <= TOP && i <= n; i++) {
        b = i
        for (j = i + 1; j <= n; j++)
            if (rcpu[ord[j]] > rcpu[ord[b]] ||
                (rcpu[ord[j]] == rcpu[ord[b]] && rram[ord[j]] > rram[ord[b]])) b = j
        if (b != i) { t = ord[i]; ord[i] = ord[b]; ord[b] = t }
    }
    printf "TOP %d", (n < TOP ? n : TOP)
    for (i = 1; i <= TOP && i <= n; i++)
        printf "|%d|%s|%.1f|%.0f", rpid[ord[i]], rname[ord[i]], rcpu[ord[i]], rram[ord[i]]
}
BEGIN {
    TOP = 12
    while ((getline l < prevfile) > 0) {
        if (l == "") continue
        nf = split(l, f, " ")
        if (f[1] == "T") { pe = f[2] + 0; continue }
        if (nf >= 2) prevcpu[f[1] + 0] = f[2] + 0
    }
    close(prevfile)
    dt = now - pe
    if (dt <= 0) dt = 0
}
{
    pid = $1 + 0
    if (pid <= 1 || pid == self || pid == ppid) next
    name = $3
    for (i = 4; i <= NF; i++) name = name "_" $i
    # Kernel threads are printed bracketed ("[kworker/0:1]"). They have nothing
    # worth showing and cannot usefully be killed.
    if (name == "" || substr(name, 1, 1) == "[") next
    rss = $2 + 0
    if (rss <= 0) next

    t = cputicks()
    if (t < 0) next
    # A pid absent from the previous snapshot — just started, or a recycled pid —
    # has no delta and reads 0 this round. NOT `t - prevcpu[pid]`: that is an
    # uninitialised "" coerced to 0, which turns the delta into the whole
    # lifetime CPU time and ranks a process as if it were the busiest thing on
    # the machine. No clamping to 100 either: a process using several threads
    # legitimately exceeds 100, which is exactly what top and htop show.
    if (dt > 0 && pid in prevcpu && t >= prevcpu[pid]) {
        c = 100 * (t - prevcpu[pid]) / (hz * dt)
        if (c < 0) c = 0
    } else {
        c = 0
    }

    n++
    rpid[n] = pid; rname[n] = name; rcpu[n] = c; rram[n] = rss / 1024; rtime[n] = t
}
END {
    for (i = 1; i <= n; i++) ord[i] = i
    take()

    # Every pid, not just the ones that made the list: a process that turns heavy
    # between rounds is in the previous snapshot then, so its first appearance in
    # the list carries a real rate instead of a 0 that only fixes itself next
    # poll. Same /tmp snapshot idiom cpu.sh keeps for /proc/stat.
    printf "T %d\n", now > prevfile
    for (i = 1; i <= n; i++) printf "%d %d\n", rpid[i], rtime[i] >> prevfile
    close(prevfile)
}
' <<< "$table"