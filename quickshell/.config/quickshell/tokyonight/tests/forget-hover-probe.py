#!/usr/bin/env python3
"""Layer 4 of test-forget-button.sh: drive the REAL DeviceRow with REAL mouse
events in a REAL QQuickWindow.

Layers 2 and 3 assign `hovered: true` outright. Assigning a property that has
a binding SEVERS that binding, so `hover.containsMouse` is never evaluated
anywhere in those layers — which is exactly the half where the shipped bug
lived. Nothing short of moving a pointer measures it.

What it prints, one line per fact, all prefixed `forgethover `:
    trace <V|./- string>   forgetHit.visible at each 1px column across the row
    drops <n> <cols...>    columns inside the plate where it was NOT visible
    press <jitters> <visible> <FORGET|TOGGLE|none>
    rowpress <x> <FORGET|TOGGLE|none>
    offrow <true|false>    visible with the pointer off the row entirely
    hover <true|false>     visible after entering the row from the left

usage: forget-hover-probe.py <DeviceRow.inc> [outdir]
`DeviceRow.inc` is the component text cut out of SettingsFlyout.qml by the
caller, so this never carries its own copy of the component.
"""
import os
import sys
import tempfile

inc_path = sys.argv[1]
out_dir = sys.argv[2] if len(sys.argv) > 2 else tempfile.mkdtemp(prefix="fh.")
comp = open(inc_path).read()

# DeviceRow reads exactly these five members of the Tokyo singleton. Hover
# mechanics do not depend on their values, so a stub exercises the same code
# path and lets this run under plain Qt instead of quickshell.
TOKYO = """
pragma Singleton
import QtQuick
QtObject {
    readonly property color dim: "#7983a4"
    readonly property color pane: "#1a1b26"
    readonly property color bgHighlight: "#292e42"
    readonly property color yellow: "#e0af68"
    readonly property string fontFamily: "sans"
}
"""

ROWS = """
import QtQuick
import QtQuick.Shapes
Item {
    id: host
    width: 260; height: 30
    property string lastSignal: "none"

%s

    // A paired bluetooth row, the only shape that may forget.
    DeviceRow {
        id: paired
        objectName: "paired"
        x: 0; y: 2; width: 200; height: 26
        name: "Xbox Wireless Controller"; status: "PAIRED"
        forgetable: true
        onClicked:   { host.lastSignal = "TOGGLE" }
        onForgotten: { host.lastSignal = "FORGET" }
    }

    // A wifi row in its real shape: signal glyph, so the name hangs off the
    // glyph, and a real status word. forgetable is left off.
    DeviceRow {
        id: wifi
        objectName: "wifi"
        x: 0; y: 2; width: 200; height: 26
        visible: false
        name: "Fujitsu-SSID"
        glyph: "4"
        status: "CONNECTED"
        onClicked:   { host.lastSignal = "TOGGLE" }
        onForgotten: { host.lastSignal = "FORGET" }
    }
}
""" % comp

os.makedirs(out_dir, exist_ok=True)
open(os.path.join(out_dir, "Tokyo.qml"), "w").write(TOKYO)
open(os.path.join(out_dir, "hoverprobe.qml"), "w").write(ROWS)

os.environ["QT_QPA_PLATFORM"] = "offscreen"
from PySide6.QtCore import QEventLoop, QPoint, Qt, QUrl, QObject   # noqa: E402
from PySide6.QtGui import QGuiApplication                           # noqa: E402
from PySide6.QtQuick import QQuickView                              # noqa: E402
from PySide6.QtTest import QTest                                    # noqa: E402

# QQuickView aborts inside its constructor without a QGuiApplication; with the
# offscreen platform the real display is not otherwise needed.
app = QGuiApplication([])
view = QQuickView()
view.setSource(QUrl.fromLocalFile(os.path.join(out_dir, "hoverprobe.qml")))
if view.rootObject() is None:
    sys.exit("forgethover LOAD FAILED: "
             + "; ".join(e.toString() for e in view.errors()))
root = view.rootObject()
view.resize(260, 30)
view.show()
QTest.qWaitForWindowExposed(view)
QTest.qWait(60)

out = []


def emit(line):
    out.append("forgethover " + line)


def settle(n=3):
    for _ in range(n):
        app.processEvents(QEventLoop.AllEvents)
        QTest.qWait(1)


def move(x, y):
    QTest.mouseMove(view, QPoint(int(x), int(y)), 1)
    settle()


def click(x, y):
    root.setProperty("lastSignal", "none")
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier,
                     QPoint(int(x), int(y)))
    settle()
    return str(root.property("lastSignal"))


def probe(which):
    return root.findChild(QObject, which)


def plate(row):
    return (row.property("x") + row.findChild(QObject, "forgetHit").property("x"),
            row.findChild(QObject, "forgetHit").property("width"))


def walk(row, y, emit_drops=True, label=None):
    """1px steps left to right across the row, recording forgetHit.visible."""
    px, pw = plate(row)
    hit = row.findChild(QObject, "forgetHit")
    trace, drops = [], []
    for x in range(4, 198):
        move(x, y)
        if hit.property("visible"):
            trace.append("V")
        else:
            trace.append(".")
            if x >= px:
                drops.append(x)
    if label:
        emit("trace-%s %s" % (label, "".join(trace)))
    if emit_drops:
        emit("drops-%s %d %s" % (label, len(drops),
                                 ",".join(str(d) for d in drops)))
    return drops


# ---- a paired row -----------------------------------------------------------
paired = probe("paired")
px, pw = plate(paired)
mid = paired.property("y") + paired.property("height") / 2

move(4, int(mid))
emit("hover %s" % ("true" if paired.findChild(QObject, "forgetHit")
                  .property("visible") else "false"))
d = walk(paired, mid, label="paired")
emit("plateleft %d" % px)

# off the row entirely: the window is 260 wide, the row 200.
move(230, int(mid))
emit("offrow %s" % ("true" if paired.findChild(QObject, "forgetHit")
                    .property("visible") else "false"))

# Press inside the plate after N extra sub-pixel moves. A real hand always
# emits more than one move before a press, so offset 0 is the least likely
# real case, not the most likely.
for n in range(4):
    move(4, int(mid))                    # leave the row
    move(px + pw / 2, int(mid))          # land inside the plate
    for k in range(n):
        move(px + pw / 2 + (0.5 if k % 2 == 0 else -0.5), int(mid))
    vis = "true" if paired.findChild(QObject, "forgetHit").property("visible") \
        else "false"
    emit("press %d %s %s" % (n, vis, click(px + pw / 2, mid)))

# The left of the row must still toggle — the × did not swallow the row.
move(40, int(mid))
emit("rowpress 40 %s" % click(40, mid))

# ---- a wifi row, same treatment -------------------------------------------
# `dr.forgetable &&` gates the reveal, so the extra `|| forgetMouse...` term
# must not leak the × onto a row that never asked for one.
wifi = probe("wifi")
wifi.setProperty("visible", True)
settle()
wmid = wifi.property("y") + wifi.property("height") / 2
move(4, int(wmid))
emit("wifhover %s" % ("true" if wifi.findChild(QObject, "forgetHit")
                      .property("visible") else "false"))
wd = walk(wifi, int(wmid), label="wifi")
wpx, wpw = plate(wifi)
move(wpx + wpw / 2, int(wmid))
emit("wifpress %s" % click(wpx + wpw / 2, int(wmid)))

print("\n".join(out))
