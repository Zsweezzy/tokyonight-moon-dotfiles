#!/bin/bash
# test-reload-check.sh — the guard against a silent config failure has to not
# lie, and it lied three ways.
#
# scripts/check-reload.sh is the only thing in this repo that answers "did my
# .qml edit actually load?". A failed reload leaves the OLD bar on screen, so
# the screen always looks fine and only the log tells you anything. That makes
# a verifier that lies worse than no verifier: it converts "I do not know" into
# "it worked", and the agent stops looking.
#
# It lied three ways, and each one is a test below:
#
#   1. It read a DEAD instance's log. `ls -t by-id/*/log.log` picks the newest
#      mtime on tmpfs, and a quickshell that was killed has the newest mtime
#      there because the last thing it ever wrote was its own death. This repo
#      manufactures exactly those corpses: the test probes run `quickshell -p
#      ...` offscreen and leave their by-id dirs behind. It reported the
#      probe's "Configuration Loaded" while the real bar was mid-reload.
#      Fixed by resolving the log through a RUNNING pid's fd table.
#
#   2. A reload IN FLIGHT read as success. It took the last TWO marker lines
#      and grepped the pair for "Configuration Loaded". A stale `Configuration
#      Loaded` followed by a fresh `Reloading configuration` still contains
#      that string, so it exited 0 with the config halfway through loading and
#      about to fail. Fixed by judging the LAST line only. Case 2 below.
#
#   3. Nothing checked that quickshell was running at all. With the bar dead it
#      happily reported on whatever log survived. Fixed with an explicit
#      not-running failure. Case 5 below.
#
# What is deliberately NOT tested against a live bar: this suite must be safe
# to run at any moment, including while the user is mid-edit, so every case
# builds its own fake config tree, its own fake log files and its own fake
# /proc. Nothing here reads the real /proc, the real by-id dirs, or the real
# .qml mtimes, and nothing here can kill anything.
#
# The script is tested through its documented environment seams
# (CHECK_RELOAD_PROC_ROOT, CHECK_RELOAD_PIDS, CHECK_RELOAD_LOG_OVERRIDE) plus
# a copied script inside a throwaway directory, so `CFG` — which the script
# derives from its own location — resolves to the fixture tree rather than the
# live config. That keeps the mtime comparison (the check that caught the
# `git revert` which rewrote Bar.qml and deleted a widget) exercised for real
# instead of stubbed.
#
# Run from anywhere: cd "$(dirname "$0")" first.
cd "$(dirname "$0")" || exit 1
ROOT=$(cd .. && pwd) || exit 1
SCRIPT=$ROOT/scripts/check-reload.sh

fail=0
ok()  { printf '  ok   %s\n' "$1" >&2; }
bad() { printf '  FAIL %s\n' "$1" >&2; fail=1; }

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Fixture builder.
#
# mkfixture <name> — echoes the fixture root. Creates:
#   $f/cfg/scripts/check-reload.sh   the real script, so CFG == $f/cfg
#   $f/cfg/*.qml                     the config the script compares mtimes against
#   $f/run/user/1000/quickshell/by-id/<id>/log.log
#   $f/proc/<pid>/fd/11 -> .../log.log
#   $f/proc/<pid>/stat               field 22 = starttime, for oldest-wins
# ---------------------------------------------------------------------------
mkfixture() {
    local f=$TMP/$1
    mkdir -p "$f/cfg/scripts" "$f/proc" "$f/run/user/1000/quickshell/by-id"
    cp "$SCRIPT" "$f/cfg/scripts/check-reload.sh"
    chmod +x "$f/cfg/scripts/check-reload.sh"
    # Base epoch: the .qml files start a day BEFORE the loads the fixtures
    # record, so "current" is the default and each case opts into staleness.
    touch -d '2026-01-01 00:00:00' "$f/cfg/Bar.qml" "$f/cfg/Tokyo.qml"
    echo "$f"
}

# logline <file> <id> <timestamp> <text...> — append one log line.
logline() {
    printf '%s  INFO: %s\n' "$3" "$4" >> "$1"
}

# mkpid <fixture> <pid> <starttime> <instance-id>
# A live process: its fd 11 is the open log, and its stat carries a starttime.
mkpid() {
    local f=$1 id=$4
    local dir=$f/run/user/1000/quickshell/by-id/$id
    mkdir -p "$dir" "$f/proc/$2/fd"
    : > "$dir/log.log"
    ln -sf "$dir/log.log" "$f/proc/$2/fd/11"
    # Fields 1..21 padded so that after the ")" the 20th field is starttime.
    printf '%s (quickshell) S %s %s\n' "$2" \
        "$(seq -s ' ' 2 21 | tr ' ' '\n' | head -20 | tr '\n' ' ')" "$3" \
        > "$f/proc/$2/stat"
}

# runcheck <fixture> <pid-list> [log-override] — runs the fixture script and
# captures stdout+stderr and the exit code into RUN_OUT / RUN_CODE.
runcheck() {
    local f=$1
    RUN_OUT=$(env CHECK_RELOAD_PROC_ROOT="$f/proc" CHECK_RELOAD_PIDS="$2" \
        ${3:+CHECK_RELOAD_LOG_OVERRIDE="$3"} \
        "$f/cfg/scripts/check-reload.sh" 2>&1)
    RUN_CODE=$?
}

expect() { # expect <want-code> <name> [<substring the output must contain>]
    local want=$1 name=$2 needle=${3-}
    if [ "$RUN_CODE" != "$want" ]; then
        bad "$name: exit $RUN_CODE, want $want"
        printf '       output: %s\n' "$RUN_OUT" >&2
        return 1
    fi
    if [ -n "$needle" ] && ! printf '%s' "$RUN_OUT" | grep -qF "$needle"; then
        bad "$name: exit $RUN_CODE but output lacks '$needle'"
        printf '       output: %s\n' "$RUN_OUT" >&2
        return 1
    fi
    ok "$name"
}

echo "reload check:"

# ---------- 1. loaded and current -> 0 ----------
f=$(mkfixture loaded)
mkpid "$f" 9001 100 alive
logline "$f/run/user/1000/quickshell/by-id/alive/log.log" alive \
    '2026-01-02 03:04:05.678' 'Configuration Loaded'
runcheck "$f" 9001
expect 0 "a finished load newer than the .qml files exits 0" \
    '2026-01-02 03:04:05.678  INFO: Configuration Loaded'

# ---------- 2. THE REGRESSION: reload in flight -> 1 ----------
# One stale success, then a fresh reload that has not finished. Judging the last
# TWO lines finds "Configuration Loaded" in the pair and calls it a pass.
f=$(mkfixture inflight)
mkpid "$f" 9002 100 alive
L=$f/run/user/1000/quickshell/by-id/alive/log.log
logline "$L" alive '2026-01-02 03:04:05.678' 'Configuration Loaded'
logline "$L" alive '2026-01-02 09:09:09.999' 'Reloading configuration...'
runcheck "$f" 9002
expect 1 "a reload in flight exits 1 (the last TWO lines bug)" 'IN FLIGHT'

# The in-flight message must not accuse the user of a broken config. It is not
# known to be broken yet, and saying so is how this script trained its reader
# to ignore it.
if printf '%s' "$RUN_OUT" | grep -q "your edit broke the config"; then
    bad "in-flight message blames a break that has not happened yet"
else
    ok "in-flight message does not claim the edit broke the config"
fi

# ---------- 3. a dead instance's log is newer; the live one must win ----------
# Reproduces the real failure: a corpse left by an offscreen probe has the
# newest mtime on tmpfs and its own "Configuration Loaded", so `ls -t` picks
# it and reports success no matter what the real bar is doing.
f=$(mkfixture corpse)
mkpid "$f" 9003 100 alive
A=$f/run/user/1000/quickshell/by-id/alive/log.log
logline "$A" alive '2026-01-02 03:04:05.678' 'Configuration Loaded'
# The corpse: no proc entry at all, so no fd table — only files on disk.
D=$f/run/user/1000/quickshell/by-id/dead
mkdir -p "$D"
logline "$D/log.log" dead '2026-01-02 23:59:59.000' 'Configuration Loaded'
# Pin both mtimes by hand, so "the corpse is newest" is a property of the
# fixture rather than of whatever second the suite happened to run in. This is
# exactly the ordering a real kill produces: the corpse's last write was its
# own death, so it is always the freshest log on tmpfs.
touch -d '2026-01-02 03:04:05' "$A"
touch -d '2026-01-02 23:59:59' "$D/log.log"
if ls -t "$f"/run/user/1000/quickshell/by-id/*/log.log | head -1 | grep -q '/dead/'; then
    ok "fixture: the corpse's log is the newest, so ls -t would pick it"
else
    bad "fixture: corpse log is not the newest; case 3 proves nothing"
fi
runcheck "$f" 9003
# Exit code aside, what matters here is WHICH log was read, and the two logs
# disagree about it: the corpse says loaded at 23:59:59, the live bar says
# loaded at 03:04:05. Whichever timestamp comes back names the source.
expect 0 "the live instance's log wins over a newer dead one" \
    '2026-01-02 03:04:05.678  INFO: Configuration Loaded'
if printf '%s' "$RUN_OUT" | grep -q '23:59:59'; then
    bad "the dead instance's log was read (23:59:59 leaked into the output)"
else
    ok "nothing from the dead instance's log reaches the output"
fi

# ---------- 4. a .qml newer than the last load -> 1 ----------
# The watcher never fired. This check earned its place: it caught a git revert
# that rewrote Bar.qml and deleted a widget while the log showed a load from a
# quarter of an hour earlier. Do not weaken it.
f=$(mkfixture stale)
mkpid "$f" 9004 100 alive
logline "$f/run/user/1000/quickshell/by-id/alive/log.log" alive \
    '2026-01-02 03:04:05.678' 'Configuration Loaded'
touch -d '2026-01-03 00:00:00' "$f/cfg/Bar.qml"
runcheck "$f" 9004
expect 1 "a .qml newer than the last load exits 1" 'watcher never saw your save'

# And it must name the file that is ahead, or the message is not actionable.
if printf '%s' "$RUN_OUT" | grep -q 'Bar.qml'; then
    ok "the stale message names the file that is ahead"
else
    bad "the stale message does not name Bar.qml"
    printf '       output: %s\n' "$RUN_OUT" >&2
fi

# ---------- 5. no quickshell running -> 1 ----------
f=$(mkfixture nobody)
mkpid "$f" 9005 100 alive
logline "$f/run/user/1000/quickshell/by-id/alive/log.log" alive \
    '2026-01-02 03:04:05.678' 'Configuration Loaded'
runcheck "$f" ""
expect 1 "no quickshell process exits 1" 'no quickshell is running'

# Same, but with the pid list overridden to a pid whose fd table is empty —
# running, but not something we can read a log from. Must not fall through to
# whatever log happens to be lying around on disk.
f=$(mkfixture nolog)
mkdir -p "$f/proc/9006/fd"
D=$f/run/user/1000/quickshell/by-id/orphan
mkdir -p "$D"
logline "$D/log.log" orphan '2026-01-02 23:59:59.000' 'Configuration Loaded'
touch -d '2026-01-02 23:59:59' "$D/log.log"
runcheck "$f" 9006
expect 1 "a pid with no open log exits 1 instead of reading a stale one"
if printf '%s' "$RUN_OUT" | grep -q '23:59:59'; then
    bad "it fell back to an orphan log on disk"
else
    ok "no fallback to an unrelated log when the live one is unreadable"
fi

# ---------- 6. no reload recorded at all -> 1 ----------
f=$(mkfixture norecord)
mkpid "$f" 9007 100 alive
logline "$f/run/user/1000/quickshell/by-id/alive/log.log" alive \
    '2026-01-02 03:04:05.678' 'Launching config: "/somewhere/shell.qml"'
runcheck "$f" 9007
expect 1 "a log with no reload marker exits 1" 'no reload recorded yet'

# ---------- 7. two live instances: warn, and use the oldest ----------
# A second instance fights the first over the same window, so it is reported
# rather than silently absorbed. The oldest wins because that is the instance
# the user has been watching.
f=$(mkfixture two)
mkpid "$f" 9009 500 young
mkpid "$f" 9008 100 old
logline "$f/run/user/1000/quickshell/by-id/young/log.log" young \
    '2026-01-02 22:22:22.222' 'Configuration Loaded'
logline "$f/run/user/1000/quickshell/by-id/old/log.log" old \
    '2026-01-02 03:04:05.678' 'Configuration Loaded'
runcheck "$f" "9008 9009"
expect 0 "two instances: warns and reads the oldest" '2 quickshell instances are running'
if printf '%s' "$RUN_OUT" | grep -q '03:04:05'; then
    ok "two instances: the oldest instance's log is the one reported"
else
    bad "two instances: reported the younger instance's log"
    printf '       output: %s\n' "$RUN_OUT" >&2
fi

# ---------- 8. CHECK_RELOAD_LOG_OVERRIDE is honoured ----------
# The documented escape hatch, and the one a human debugging by hand uses.
f=$(mkfixture override)
L=$f/hand-picked.log
logline "$L" x '2026-01-02 03:04:05.678' 'Configuration Loaded'
runcheck "$f" 9009 "$L"
expect 0 "CHECK_RELOAD_LOG_OVERRIDE is read when set" '03:04:05.678'

# ---------------------------------------------------------------------------
# The "last line is neither marker" guard.
#
# This branch is defence in depth, not a state the two-marker grep can produce:
# whatever `last` matched, it matched one of the two markers, so the
# "refusing to call it a pass" line is unreachable at runtime today. It is
# asserted structurally rather than pretended into a passing fixture, because
# a test that cannot fail is the exact thing this file exists to prevent.
# ---------------------------------------------------------------------------
if grep -q 'neither marker' "$SCRIPT"; then
    ok "the neither-marker guard is present in the script"
else
    bad "the neither-marker guard has been dropped from check-reload.sh"
fi
if grep -q 'tail -1' "$SCRIPT" && ! grep -qE 'grep -E "Reloading configuration\|Configuration Loaded" \| tail -2' "$SCRIPT"; then
    ok "markers are read with tail -1, not tail -2"
else
    bad "the marker selection is not tail -1 — defect 2 may be back"
fi

# ---------- tabs ----------
for f in "$ROOT/scripts/check-reload.sh" "$ROOT/tests/test-reload-check.sh"; do
    n=$(grep -cP '\t' "$f" || true)
    [ "$n" = "0" ] && ok "${f#$ROOT/} has no tabs" || bad "${f#$ROOT/} has $n tab line(s)"
done

[ $fail -eq 0 ] && echo "reload check tests passed" \
                 || { echo "reload check tests FAILED"; exit 1; }