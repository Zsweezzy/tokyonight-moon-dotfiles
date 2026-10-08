#!/bin/bash
# test-settings-scripts.sh — the settings flyout's scripts, checked without a
# phone or a second network in range.
#
# The interesting part of each script is its parsing, and each of those has a
# specific way of being wrong that only shows up on a real machine:
#
#   wifi-list.sh  nmcli answers `enabled`, not `yes`, for `nmcli radio` — and
#                the ACTIVE,SSID column is the network, while DEVICE is just
#                wlan0 on every row, so reading the wrong one reports the
#                interface as the SSID.
#   bt-state.sh   `bluetoothctl devices` prefixes every line with the literal
#                word "Device", so a naive `read mac` yields "Device" as a MAC.
#   both          must emit exactly one line of valid JSON, which is all Poll
#                can read.
#
# Run from anywhere: cd "$(dirname "$0")/.." first.
cd "$(dirname "$0")/.." || exit 1
fail=0
ok()   { printf '  ok   %s\n' "$1" >&2; }
bad()  { printf '  FAIL %s\n' "$1" >&2; fail=1; }

# One line, and it parses. The JSON goes to stdout, the pass/fail line to
# stderr, so the caller can slurp one without swallowing the other.
one_json() {
    local name=$1 out lines
    out=$(bash "scripts/$name" 2>/dev/null)
    lines=$(printf '%s' "$out" | grep -c '')
    if [ "$lines" -ne 1 ]; then
        printf '  FAIL %s: emitted %s lines, want exactly 1\n' "$name" "$lines" >&2
        return 1
    fi
    if ! printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        printf '  FAIL %s: stdout is not valid JSON\n' "$name" >&2
        return 1
    fi
    printf '  ok   %s: one line, valid JSON\n' "$name" >&2
    printf '%s' "$out"
}

echo "settings scripts:"

out=$(one_json wifi-list.sh) || exit 1
python3 - "$out" <<'PY' || fail=1
import json, sys
o = json.loads(sys.argv[1])
assert isinstance(o["radio"], bool), "radio must be a bool"
assert isinstance(o["active"], str), "active must be a string"
assert isinstance(o["networks"], list), "networks must be a list"
# the one thing that made the SSID column wrong: DEVICE is the interface
assert o["active"] != "wlan0", f"active is the interface, not the SSID: {o['active']!r}"
# one entry per ssid — nmcli lists one row per access point
ssids = [n["ssid"] for n in o["networks"]]
assert len(ssids) == len(set(ssids)), f"duplicate ssids: {ssids}"
for n in o["networks"]:
    assert isinstance(n["signal"], int) and 0 <= n["signal"] <= 100, n
    assert isinstance(n["secure"], bool) and isinstance(n["active"], bool), n
    # `known` is what the flyout filters on to hide networks this machine has
    # never joined, so it has to exist and be a bool on every row
    assert isinstance(n["known"], bool), f"missing known flag: {n}"
# the joined network is by definition known — if it ever is not, the flyout
# would hide the one network the user is actually on
for n in o["networks"]:
    if n["active"]:
        assert n["known"], "the active network must be known"
print("  ok   wifi-list.sh: radio is a bool, active is an SSID, one row per network")
print("  ok   wifi-list.sh: every row has a known flag, the active one is known")
PY

out=$(one_json bt-state.sh) || exit 1
python3 - "$out" <<'PY' || fail=1
import json, sys
o = json.loads(sys.argv[1])
assert isinstance(o["powered"], bool), "powered must be a bool"
assert isinstance(o["devices"], list), "devices must be a list"
for d in o["devices"]:
    # "Device" is the literal first column, not a MAC
    assert ":" in d["mac"], f"mac column was not parsed: {d['mac']!r}"
    assert isinstance(d["connected"], bool), d
print("  ok   bt-state.sh: powered is a bool, macs are macs")
PY

# speedtest.sh spends the user's bandwidth to do its job, so the test hands it
# 200 KB instead of 80 MB: what has to hold is the line and the two numbers in
# it, not the measurement. It is also the only script here that can fail
# without being broken (no route, endpoint down), so a bad run marks the suite
# instead of stopping it.
export SPEEDTEST_DOWN_BYTES=200000 SPEEDTEST_UP_BYTES=100000
out=$(one_json speedtest.sh) || fail=1
unset SPEEDTEST_DOWN_BYTES SPEEDTEST_UP_BYTES
python3 - "$out" <<'PY' || fail=1
import json, sys
o = json.loads(sys.argv[1])
for k in ("down", "up"):
    assert isinstance(o[k], float), f"{k} must be a number: {o[k]!r}"
    assert o[k] >= 0, o
print("  ok   speedtest.sh: one line, down/up as Mbit/s numbers")
PY

# bt-scan is the slow one (it listens), so only the shape is checked and the
# listen window is one second
out=$(bash scripts/bt-scan.sh 1 2>/dev/null)
printf '%s' "$out" | python3 -c '
import json,sys
o=json.load(sys.stdin)
assert isinstance(o["devices"], list)
for d in o["devices"]:
    assert ":" in d["mac"] and isinstance(d["paired"], bool), d
' 2>/dev/null && ok "bt-scan.sh: one line, valid JSON" || bad "bt-scan.sh: bad output"

# the action scripts must not run for real here, so only their argument
# handling is checked: a bad verb exits non-zero and touches nothing
for s in bt-radio.sh wifi-radio.sh eth-radio.sh; do
    bash "scripts/$s" sideways >/dev/null 2>&1 && bad "$s: accepted a bad verb" \
        || ok "$s: rejects a bad verb"
done
bash scripts/bt-dev.sh connect 2>/dev/null && bad "bt-dev.sh: accepted a missing mac" \
    || ok "bt-dev.sh: rejects a missing mac"
bash scripts/wifi-connect.sh join 2>/dev/null && bad "wifi-connect.sh: accepted a missing ssid" \
    || ok "wifi-connect.sh: rejects a missing ssid"

# notify-log.sh is the notification centre's history, so its whole contract is
# that a body with quotes, backslashes, tabs and non-ASCII in it survives a
# round trip through a line of JSON. Bodies are arbitrary application text; if
# any of those is mangled the history reads back wrong and nothing complains.
# The path is fixed by XDG_STATE_HOME, which is what makes it testable at all.
t=$(mktemp -d); XDG_STATE_HOME="$t" bash scripts/notify-log.sh add \
    '{"summary":"a \"quoted\" \\ body"}'
XDG_STATE_HOME="$t" bash scripts/notify-log.sh add '{"summary":"back\\slash"}'
XDG_STATE_HOME="$t" bash scripts/notify-log.sh add '{"summary":"tab\tinside"}'
XDG_STATE_HOME="$t" bash scripts/notify-log.sh add '{"summary":"ünïcödé ✓"}'
# Checked by parsing each line back, not by counting: a mangled escape is still
# a line, it is just a line that no longer says what it said when it went in.
got=$(XDG_STATE_HOME="$t" bash scripts/notify-log.sh read | python3 -c '
import json,sys
want = ["a \"quoted\" \\ body", "back\\slash", "tab\tinside", "ünïcödé ✓"]
got = [json.loads(l)["summary"] for l in sys.stdin if l.strip()]
assert got == want, (got, want)
print("ok")' 2>&1 | tail -1)
[ "$got" = "ok" ] && ok "notify-log.sh: quotes, backslashes, tabs and UTF-8 round-trip" \
                 || bad "notify-log.sh: round trip mangled: $got"
# clear has to empty the file, not delete it: a missing file is a different
# failure to the reader than an empty one.
XDG_STATE_HOME="$t" bash scripts/notify-log.sh clear
left=$(XDG_STATE_HOME="$t" bash scripts/notify-log.sh read | wc -c)
[ "$left" = "0" ] && ok "notify-log.sh: clear empties the log" \
                  || bad "notify-log.sh: clear left $left bytes"
XDG_STATE_HOME="$t" bash scripts/notify-log.sh add >/dev/null 2>&1 \
    && bad "notify-log.sh: accepted a missing json" \
    || ok "notify-log.sh: rejects a missing json"
XDG_STATE_HOME="$t" bash scripts/notify-log.sh sideways >/dev/null 2>&1 \
    && bad "notify-log.sh: accepted a bad verb" \
    || ok "notify-log.sh: rejects a bad verb"
rm -rf "$t"

[ $fail -eq 0 ] && echo "settings tests passed" || { echo "settings tests FAILED"; exit 1; }
