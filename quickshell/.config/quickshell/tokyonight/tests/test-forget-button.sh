#!/bin/bash
# test-forget-button.sh — the paired-row forget × in the bluetooth panel.
#
# DeviceRow is shared: the wifi list, the "Find new devices" button and the
# bluetooth device list are all the same component. So the × has to be opt-in,
# and the part that can rot silently is the layout — a forget button that
# measures width 0 or visible:false paints nothing and still looks "fine" in
# review, which is the toast and clock failure mode in this tree.
#
# Four layers, cheapest first:
#   1. static — the opt-in defaults off, only the bluetooth delegate sets it,
#      the × outranks the whole-row click area and does not toggle, and
#      Settings.qml actually runs `bt-dev.sh forget`
#   2. probe  — an offscreen render of the REAL DeviceRow, extracted from
#      SettingsFlyout.qml at run time (never a copy, so it cannot drift) reports
#      its geometry, and Qt's own hit test says who gets a click in the
#      right-hand slot
#   3. A/B    — the same rows measured out of the commit that introduced the
#      feature, so "the wifi rows did not move" is a number and not a promise
#   4. hover  — a REAL QQuickWindow driven with REAL synthetic mouse events,
#      because layers 2 and 3 assign `hovered` outright and therefore never
#      evaluate `hover.containsMouse` at all. The reveal binding, the flicker
#      bug that lived in it, and which signal a press produces can only be
#      measured by moving a pointer.
#
# Layer 4 is the one that matters and it is not optional: assigning a property
# that has a binding SEVERS that binding, so a probe that writes `hovered: true`
# proves nothing about hover. It is what let the × flicker under the cursor and
# fire the row toggle instead of forgetting, with the suite green throughout.
#
# Run from anywhere: cd "$(dirname "$0")/.." first.
cd "$(dirname "$0")" || exit 1
cd .. || exit 1
fail=0
ok()   { printf '  ok   %s\n' "$1" >&2; }
bad()  { printf '  FAIL %s\n' "$1" >&2; fail=1; }

echo "forget button:"

# ---------- 1. structure ----------
python3 - <<'PY' || fail=1
import re, sys

def code(text):
    """Comments stripped. A check for `dr.clicked()` must be satisfied by code
    and must not be broken by the prose warning against it — and brace matching
    is safer without them too."""
    return re.sub(r"//[^\n]*", "", text)

src = code(open("SettingsFlyout.qml").read())
pill = code(open("Settings.qml").read())

def block(text, start):
    """The text of the {…} that starts at or after `start`."""
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[start:j + 1]
    raise SystemExit("unbalanced braces")

def enclosing(text, marker):
    """The {…} whose header `marker` sits inside — `id:` names come after
    their object's opening brace, so this cannot use block()."""
    i = text.rindex("{", 0, text.index(marker))
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
    raise SystemExit("unbalanced braces")

def need(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        sys.exit(1)

comp = block(src, src.index("component DeviceRow: Item"))
# every `DeviceRow {` that is not the component declaration. One call site is
# written `delegate: DeviceRow {`, so this cannot key on the line start.
sites = [block(src, m.start()) for m in re.finditer(r"DeviceRow \{", src)
         if not src[:m.start()].endswith("component ")]
need(len(sites) == 3, "DeviceRow has 3 call sites: wifi, scan button, bt list")
wifi = next(s for s in sites if "ssid" in s)
scan = next(s for s in sites if "Find new devices" in s)
bt = next(s for s in sites if "modelData.paired" in s)

# the opt-in itself
need("property bool forgetable: false" in comp,
     "forget is opt-in: forgetable defaults to false")
need("signal forgotten()" in comp,
     "DeviceRow signals forgotten() rather than reaching for the pill itself")

# the risk the ticket calls out: the whole-row MouseArea is declared last in
# the base component, so the × has to out-rank it in BOTH declaration order and
# z — with the hover area on top the click forgets nothing and toggles instead.
need(comp.index("id: forgetHit") > comp.index("id: hover"),
     "the × is declared after the whole-row click area")
hit = enclosing(comp, "id: forgetHit")
need('objectName: "forgetHit"' in hit,
     "the × names its own hit plate so it can be found from a test")
z = re.search(r"(?m)^\s*z:\s*(-?\d+)", hit)
need(z is not None and int(z.group(1)) > 0,
     "the × carries an explicit z above the whole-row click area (z: %s)"
     % (z.group(1) if z else "none"))
need("dr.forgotten()" in hit and "dr.clicked()" not in hit,
     "clicking the × forgets only — it never fires the row toggle")

# the reveal condition, and that it replaces the word rather than joining it
need(re.search(r"property bool forgetShown:\s*dr\.forgetable", comp) is not None,
     "the × only exists on a row that asked for it and is hovered")
# …and that it keeps itself up while the pointer is ON the plate. The row
# MouseArea and the ×'s MouseArea are siblings, and Qt delivers hover to the
# deepest item under the cursor and then to its ancestors only — never
# sideways — so `dr.hovered` alone goes false the instant the pointer arrives,
# and the × hides itself from under the cursor. Layer 4 measures the
# consequence; this catches the revert without needing a window.
reveal = re.search(r"readonly property bool forgetShown:(.*?)\n\s*signal", comp,
                   re.S)
need(reveal is not None and "dr.hovered" in reveal.group(1)
     and "forgetMouse.containsMouse" in reveal.group(1),
     "the reveal holds while the pointer is on the × itself, not just on the "
     "row behind it")
need(re.search(r"property bool forgetable:\s*false", comp) is not None
     and comp.index("dr.forgetable") < comp.index("||"),
     "…without letting the × leak onto a row that did not opt in")
word = enclosing(comp, "id: stateText")
need(re.search(r"(?m)^\s*visible:.*forgetShown", word) is not None,
     "the status word hides while the × is shown (one slot, one piece of state)")

# the call sites
need("forgetable" not in wifi and "forgotten" not in wifi,
     "wifi rows are untouched: no forget affordance")
need("forgetable" not in scan and "forgotten" not in scan,
     "the scan button is untouched: no forget affordance")
need("forgetable: modelData.paired" in bt,
     "only PAIRED bluetooth rows opt in — a NEW row cannot forget")
need("onForgotten:" in bt and "forgetDevice(modelData.mac)" in bt,
     "the × calls forgetDevice for that device's own mac")

# the script side
fn = block(pill, pill.index("function forgetDevice"))
need('"forget"' in fn and "mac" in fn,
     "forgetDevice runs bt-dev.sh forget <mac>")
need("confirm.start()" in fn,
     "forgetDevice starts the confirming poll, so the row leaves the list")
PY

# ---------- 2 + 3. the real component, rendered ----------
if ! command -v quickshell >/dev/null; then
    # LOUDLY, and not `exit $fail`. Skipping the render + A/B layer used to
    # exit 0 with nine geometry assertions and the whole A/B never run, so the
    # suite reported success for a component it had not looked at. A layer that
    # cannot run is a failure, not a pass.
    bad "quickshell is not on PATH — layers 2, 3 and 4 cannot run"
    echo "forget button tests FAILED"
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
probe="$tmp/q"
mkdir -p "$probe"
# Tokyo is a pragma Singleton, so it resolves from the probe's own directory.
ln -sf "$PWD/Tokyo.qml" "$probe/"

# The A/B baseline is the parent of the commit that introduced `forgetable` —
# NOT HEAD. HEAD is the trap: while the change is uncommitted HEAD *is* the
# pre-change file, so the comparison is real; the moment it is committed HEAD
# *becomes* the change, the comparison degenerates into the file against itself,
# and the guard that has to protect the shipped code is the one that dies.
# `-S` finds every commit that changed the occurrence count, tail -1 is the
# oldest of them, i.e. the one that introduced the feature. An empty search
# means the feature exists in no commit yet (suite run against a working tree),
# so fall back to HEAD, which is the correct baseline in that case.
# Git paths are relative to the toplevel, not to $PWD. Here the toplevel IS
# the config dir, but in the mirror repo it is two levels up, and a bare
# `SettingsFlyout.qml` then names a file that does not exist — `git show`
# exits 128 and every A/B row fails. `--show-prefix` is that same offset
# (empty in this tree), so one expression is correct in both.
rel=$(git rev-parse --show-prefix)
intro=$(git log --format=%H -S 'forgetable' -- "$rel"SettingsFlyout.qml | tail -1)
base_rev=${intro:+${intro}^}
base_rev=${base_rev:-HEAD}
# The path belongs on the ref, not only in the line above: `git show <sha>^`
# with no path prints the commit's diff, not the file, and the diff has no
# `component DeviceRow` in it to extract.
base_ref=$base_rev:"$rel"SettingsFlyout.qml
printf '  ..   A/B baseline: %s\n' "$base_ref" >&2

# The shipped component, cut out once and handed to BOTH render layers, so
# there is a single extraction to trust.
python3 - "$tmp/DeviceRow.inc" <<'PY' || fail=1
import sys

def code(text):
    return __import__("re").sub(r"//[^\n]*", "", text)

def block(text, start):
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[start:j + 1]
    raise SystemExit("unbalanced braces")

src = code(open("SettingsFlyout.qml").read())
open(sys.argv[1], "w").write(block(src, src.index("component DeviceRow: Item")))
PY

python3 - "$probe" "$base_ref" "$tmp/DeviceRow.inc" <<'PY' || fail=1
import sys

def code(text):
    return __import__("re").sub(r"//[^\n]*", "", text)

out = sys.argv[1]

def block(text, start):
    i = text.index("{", start)
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[start:j + 1]
    raise SystemExit("unbalanced braces")

import subprocess
comp_new = open(sys.argv[3]).read()
base = subprocess.run(["git", "show", sys.argv[2]],
                      capture_output=True, text=True, check=True).stdout
comp_base = block(code(base), code(base).index("component DeviceRow: Item"))

# Deliberately not an f-string: QML is mostly braces.
HEAD = """import QtQuick
import QtQuick.Shapes
import Quickshell

// GENERATED by tests/test-forget-button.sh — do not edit.
// The component below is cut out of the real SettingsFlyout.qml at run time, so
// what is measured here is what ships, not a transcription of it.
ShellRoot {
%s

%s
    Item {
        width: 200
        height: 26
%s
    }

    // Which subtree owns the click at the right-hand slot. childAt walks down
    // too, so this resolves the × glyph as well as the area behind it.
    // Matched on objectName, never on `text`: the scan button's status is ""
    // and the glyph Text's text is also "", so matching by value reports on
    // the glyph instead of the status word — silently, and only on the one
    // shape where the two coincide.
    function ownerOf(it) {
        while (it) {
            if (it.objectName === "forgetHit") return "forget"
            // "row" and not "other": a bare other cannot tell a working row
            // from a dead right-hand slot, so narrowing the row MouseArea to
            // rightMargin: 60 — 20px of nothing that steals no click — would
            // still read as a pass.
            if (it.objectName === "rowHit") return "row"
            it = it.parent
        }
        return "none"
    }
    // The pre-feature component carries no objectNames at all, so an
    // objectName-only lookup reports every baseline row as -1 and the A/B
    // below compares numbers against nothing. Fall back to declaration order,
    // which the component has never changed: glyph, name, status word.
    function byName(r, n) {
        var named = r.children.filter(function (k) {
            return k.objectName === n
        })[0]
        if (named) return named
        var texts = r.children.filter(function (k) { return k.text !== undefined })
        return n === "rowName" ? texts[1]
             : n === "stateWord" ? texts[2]
             : undefined
    }
    function measure(r, label) {
        var f = byName(r, "forgetHit")
        var w = byName(r, "stateWord")
        var n = byName(r, "rowName")
        var hit = r.childAt(r.width - 8, r.height / 2)
        var r1 = function (v) { return Math.round(v * 10) / 10 }
        return "forgetprobe " + label + " "
            + JSON.stringify({
                forgetW: f === undefined ? -1 : r1(f.width),
                forgetH: f === undefined ? -1 : r1(f.height),
                forgetVisible: f === undefined ? "absent" : String(f.visible),
                wordVisible: w === undefined ? "absent" : String(w.visible),
                nameLeft: n === undefined ? -1 : r1(n.x),
                nameW: n === undefined ? -1 : r1(n.width),
                hitOwner: hit === null ? "none" : ownerOf(hit)
            })
    }
    Timer {
        running: true
        interval: 80
        onTriggered: {
%s
            Qt.exit(0)
        }
    }
}
"""

def rows(body):
    """`body` is indented to sit inside the Item above."""
    return "\n".join(body)

new_rows = rows([
    '        DeviceRow {',
    '            id: pairedOff',
    '            width: 200; height: 26',
    '            name: "Studio Headset"; status: "PAIRED"',
    '            forgetable: true',
    '        }',
    '        DeviceRow {',
    '            id: pairedOn',
    '            width: 200; height: 26',
    '            name: "Studio Headset"; status: "PAIRED"',
    '            forgetable: true',
    '            hovered: true',
    '        }',
    '        // The REAL wifi shape, not a bluetooth row wearing its name. The',
    '        // call site always sets a signal glyph, so the glyph Text is',
    '        // visible and the name hangs off g.right — measured nameLeft 6.0',
    '        // for a glyphless probe row against 56.6 for the real thing, and a',
    '        // whole layout branch that no assertion ever reached.',
    '        DeviceRow {',
    '            id: wifiRow',
    '            width: 200; height: 26',
    '            name: "Fujitsu-SSID"',
    '            glyph: "4"',
    '            status: "CONNECTED"',
    '        }',
    '        // The other real wifi shape: secured with no saved profile, so the',
    '        // glyph carries a padlock (wider, so the name starts later) and the',
    '        // status is a bare percentage rather than a word.',
    '        DeviceRow {',
    '            id: wifiLock',
    '            width: 200; height: 26',
    '            name: "FRITZ!Box 7590"',
    '            glyph: "2 \uf023"',
    '            status: "42%"',
    '        }',
    '        // a discovered-only bluetooth row',
    '        DeviceRow {',
    '            id: unpaired',
    '            width: 200; height: 26',
    '            name: "AirPods"; status: "NEW"',
    '        }',
    '        // the scan button, mid-scan',
    '        DeviceRow {',
    '            id: scanning',
    '            width: 200; height: 26',
    '            name: "Find new devices"; status: ""',
    '            busy: true',
    '        }',
])
new_prints = "\n".join([
    '            print(measure(pairedOff, "pairedOff"))',
    '            print(measure(pairedOn, "pairedOn"))',
    '            print(measure(wifiRow, "wifiRow"))',
    '            print(measure(wifiLock, "wifiLock"))',
    '            print(measure(unpaired, "unpaired"))',
    '            print(measure(scanning, "scanning"))',
])
open(out + "/probe.qml", "w").write(HEAD % (comp_new, "", new_rows, new_prints))

# The A/B half: the same rows out of the pre-feature commit, with only the
# properties they had then. Built with the SAME real wifi shapes, or the
# comparison would be one probe shape against another and always agree.
base_rows = rows([
    '        DeviceRow {',
    '            id: baseWifi',
    '            width: 200; height: 26',
    '            name: "Fujitsu-SSID"',
    '            glyph: "4"',
    '            status: "CONNECTED"',
    '        }',
    '        DeviceRow {',
    '            id: baseWifiLock',
    '            width: 200; height: 26',
    '            name: "FRITZ!Box 7590"',
    '            glyph: "2 \uf023"',
    '            status: "42%"',
    '        }',
])
base_prints = "\n".join([
    '            print(measure(baseWifi, "baseWifi"))',
    '            print(measure(baseWifiLock, "baseWifiLock"))',
])
open(out + "/baseprobe.qml", "w").write(
    HEAD % (comp_base, "", base_rows, base_prints))
PY

# quickshell prefixes every line (` DEBUG qml: forgetprobe …`), so match the
# payload rather than the line start.
run() { timeout 25 env QT_QPA_PLATFORM=offscreen quickshell -p "$probe/$1" 2>&1 \
        | sed 's/\x1b\[[0-9;]*m//g' | grep -o 'forgetprobe .*' ; }

got=$(run probe.qml) || true
base=$(run baseprobe.qml) || true

if [ -z "$got" ] || [ -z "$base" ]; then
    bad "probe produced no measurements (probe harness broken, not the feature)"
    echo "forget button tests FAILED"
    exit 1
fi
echo "$got" >&2
echo "$base" >&2

python3 - "$got" "$base" <<'PY' || fail=1
import json, sys

def parse(blob):
    out = {}
    for line in blob.splitlines():
        label, payload = line.split(" ", 2)[1], line.split(" ", 2)[2]
        out[label] = json.loads(payload)
    return out

m = parse(sys.argv[1])
base = parse(sys.argv[2])
fails = []

def need(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        fails.append(msg)

# 1. hovering a paired row shows the × in the right-hand slot
p = m["pairedOn"]
need(p["forgetVisible"] == "true" and p["forgetW"] >= 12,
     "hovering a paired row shows the × (%s x %s)"
     % (p["forgetW"], p["forgetH"]))
need(p["wordVisible"] == "false",
     "the × replaces the PAIRED/CONNECTED word, it does not sit beside it")
need(p["nameW"] == m["pairedOff"]["nameW"],
     "the row's name does not reflow when the × replaces the word (%s)"
     % p["nameW"])
# the × outranks the whole-row click area, so the toggle cannot also fire
need(p["hitOwner"] == "forget",
     "the × owns the click in the right-hand slot (toggle cannot eat it)")

# 2. every other shape is untouched. The × keeps its 20x20 geometry when
# hidden — that width IS the click target, so collapsing it to 0 would be the
# bug, not the fix. What must be true is that it is not visible (paints
# nothing) and not in the hit test (cannot steal the row's click).
for label, why in (("pairedOff", "a paired row not hovered"),
                   ("wifiRow", "a wifi row"),
                   ("wifiLock", "a secured wifi row with no saved profile"),
                   ("unpaired", "a NEW, unpaired bluetooth row"),
                   ("scanning", "the scan button")):
    r = m[label]
    need(r["forgetVisible"] == "false",
         "no × at all on %s (visible %s)" % (why, r["forgetVisible"]))
    need(r["hitOwner"] == "row",
         "the row's own click area still owns the right slot on %s (got %s)"
         % (why, r["hitOwner"]))

# the wifi rows did not move. Both real shapes, and nameLeft as well as nameW:
# the glyph is what decides which of two layout branches the name sits in, so
# a nameW-only comparison can agree while the name has moved.
# `forgetW == -1` is the proof the baseline really is pre-change — if it ever
# reads 20 the baseline has drifted onto the changed file and every comparison
# below it is the file against itself.
for label, blabel, why in (("wifiRow", "baseWifi", "a connected wifi row"),
                           ("wifiLock", "baseWifiLock",
                            "a secured wifi row with no saved profile")):
    b = base[blabel]
    need(b["forgetW"] == -1,
         "the A/B baseline really predates the feature (no × in %s, got %s)"
         % (blabel, b["forgetW"]))
    need(m[label]["nameLeft"] == b["nameLeft"],
         "%s starts its name where it did before the change (%s vs %s)"
         % (why, m[label]["nameLeft"], b["nameLeft"]))
    need(m[label]["nameW"] == b["nameW"],
         "%s renders exactly as it did before the change (%s vs %s)"
         % (why, m[label]["nameW"], b["nameW"]))
    need(m[label]["wordVisible"] == b["wordVisible"],
         "%s still draws its status word, as before the change" % why)

sys.exit(1 if fails else 0)
PY

# ---------- 4. real mouse events in a real window ----------
# The reveal binding cannot be reached any other way: assigning `hovered`
# severs it. PySide6 rather than quickshell because quickshell's offscreen
# probe has no input delivery to borrow — it renders and quits.
if ! python3 -c "import PySide6.QtTest" 2>/dev/null; then
    bad "PySide6.QtTest is missing — layer 4 cannot run, and layer 4 is the
         only layer that evaluates hover.containsMouse"
    echo "forget button tests FAILED"
    exit 1
fi

hover=$(python3 tests/forget-hover-probe.py "$tmp/DeviceRow.inc" "$tmp/h" 2>&1) || {
    bad "hover probe failed to run"
    printf '%s\n' "$hover" | sed 's/^/       /' >&2
    echo "forget button tests FAILED"
    exit 1
}
[ -n "$(printf '%s' "$hover" | grep -c .)" ] || {
    bad "hover probe produced no measurements (harness broken, not the feature)"
    echo "forget button tests FAILED"
    exit 1
}
printf '%s\n' "$hover" >&2

python3 - "$hover" <<'PY' || fail=1
import sys

fails = []

def need(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        fails.append(msg)

rows = {}
for line in sys.argv[1].splitlines():
    if line.startswith("forgethover "):
        parts = line.split()
        rows.setdefault(parts[1], []).append(parts[2:])

def one(key):
    got = rows.get(key)
    return got[0] if got and len(got) == 1 else None

def all_of(key):
    return rows.get(key) or []

# entering a paired row from the left reveals the ×
need(one("hover") == ["true"],
     "moving onto a paired row reveals the × (real hover event, not an "
     "assigned property)")

# THE flicker guard. `hover` and the ×'s MouseArea are siblings and Qt never
# delivers hover sideways, so a reveal reading only `hover.containsMouse`
# hides the × the instant the pointer reaches the plate — and a hidden × is
# out of the hit test, so the press then toggles the connection instead.
# Shipped, walking in 1px steps: VVVVVV.V.V.V.V.V.V.V.V.
paired_drops = one("drops-paired")
need(paired_drops is not None and int(paired_drops[0]) == 0,
     "the × never blinks out while the pointer crosses it (%s drops)"
     % (paired_drops[0] if paired_drops else "?"))

# moving off the row hides it again
need(one("offrow") == ["false"],
     "moving off the row hides the × again")

# THE wrong-action guard: a real hand always emits extra moves before a press,
# and on the shipped build one extra move was the difference between forgetting
# a device and toggling its connection.
presses = all_of("press")
need(len(presses) == 4, "the plate was pressed at 4 different jitter offsets")
bad_press = [p for p in presses if p[2] != "FORGET"]
need(not bad_press,
     "every press on the × forgets, at any jitter offset (%s)"
     % (", ".join("%s->%s" % (p[0], p[2]) for p in presses) or "none"))
need(all(p[1] == "true" for p in presses),
     "the × was still visible at every one of those presses")

# the × must not have swallowed the rest of the row
need(one("rowpress") is not None and one("rowpress")[1] == "TOGGLE",
     "the left of the row still toggles — the × took only its own 20x20")

# the extra `|| forgetMouse.containsMouse` term is inside a shared binding, so
# it must not leak the × onto rows that never opted in.
need(one("wifhover") == ["false"],
     "a wifi row never reveals the ×, hovered")
wiftrace = one("trace-wifi")
need(wiftrace is not None and "V" not in wiftrace[0],
     "a wifi row shows no × at any point across the row")
need(one("wifpress") is not None and one("wifpress")[0] == "TOGGLE",
     "a wifi row's right-hand slot still toggles")

sys.exit(1 if fails else 0)
PY

[ $fail -eq 0 ] && echo "forget button tests passed" \
                 || { echo "forget button tests FAILED"; exit 1; }
