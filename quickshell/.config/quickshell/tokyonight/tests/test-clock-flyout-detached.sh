#!/bin/bash
# test-clock-flyout-detached.sh — the clock flyout is a detached SysFlyout-shaped
# popup and the morph is gone.
#
# Three layers, cheapest first:
#
#   1. static — the popup is anchored to the BAR's screen-top marker rather than
#      to the clock pill, opens and closes on one assignment with no tween, the
#      surface is the SysFlyout token set, the data sources are still the script
#      and the singleton, and every identifier the morph was built out of is
#      absent from all three files — comments included, because a comment that
#      still explains `glyphMix` is how the next reader believes it is there.
#   2. probe, faces — the REAL ClockFace, symlinked (never transcribed, so it
#      cannot drift), rendered offscreen against a spread of timestamps. What
#      layer 1 cannot see is the thing the morph was actually about: a face whose
#      width moved once a second, and a face whose contents travelled.
#      `contentW` has to be one number across every time there is, the face has
#      to have exactly one child, nothing may stick out of it at *any* depth,
#      and hovering has to change the ink and nothing else.
#   3. probe, the popup itself — the REAL ClockFlyout, instantiated next to a
#      stand-in for the bar's marker. Layers 1 and 2 both pass on a popup whose
#      cards are 50 px too short, whose padding is zero, or whose anchor margin
#      throws it off-screen, because none of them ever execute the widget that
#      owns those numbers. This layer does. Every figure asserted here is read
#      off the live object, not restated from the source: that is the point.
#
# The whole config directory is symlinked into the probe directory, so the popup
# is measured together with the real QuadCell, TimerPanel, TimerCreator,
# PillButton and TimerState it composes, and a break injected anywhere in that
# tree is a break this suite sees.
#
# No A/B-against-a-commit layer here, deliberately. There is no "before" worth
# preserving — the whole point of the change is that the old geometry is wrong —
# so a baseline could only ever compare the file against itself, and that is the
# trap test-forget-button.sh documents at length: the guard that has to protect
# the shipped code dies the moment it is committed.
#
# Run from anywhere: cd "$(dirname "$0")/.." first.
cd "$(dirname "$0")" || exit 1
cd .. || exit 1
fail=0
ok()   { printf '  ok   %s\n' "$1" >&2; }
bad()  { printf '  FAIL %s\n' "$1" >&2; fail=1; }

echo "clock flyout (detached, SysFlyout-styled):"

# ---------- 1. static ----------
python3 - <<'PY' || fail=1
import re, sys

FILES = ["ClockFlyout.qml", "ClockFace.qml", "Clock.qml"]
raw = {f: open(f).read() for f in FILES}
# Bar.qml, QuadCell.qml, Tokyo.qml and Module.qml are read here too: each carries
# part of the change (the anchor marker, the cell's new fill and its published
# chrome figure, the dead glyph token and the dead hover flag), and each is
# asserted on below.
raw["Bar.qml"] = open("Bar.qml").read()
raw["Tokyo.qml"] = open("Tokyo.qml").read()
raw["Module.qml"] = open("Module.qml").read()
raw["QuadCell.qml"] = open("QuadCell.qml").read()

fails = []


def need(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        fails.append(msg)


def code(text):
    return re.sub(r"//[^\n]*", "", text)


scrub = {f: code(raw[f]) for f in raw}


def block(text, start):
    """The text of the {…} whose header begins at `start`."""
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


# ---- criterion 6: the morph's own identifiers, raw text, comments included ----
# Plain substrings, not word boundaries: the ticket greps are `grep -n`, so a
# comment saying "no overshoot" is a hit and has to be a hit here too.
dead = ["glyphMix", "settleAt", "openExp", "swapTravel", "magnetItem",
        "contentIn", "overshoot"]
for name in dead:
    hits = {f: raw[f].count(name) for f in FILES}
    need(all(v == 0 for v in hits.values()),
         "criterion 6: `%s` is absent from all three files (%s)"
         % (name, ", ".join("%s:%d" % kv for kv in hits.items())))

# `tt` was the eighth term in the morph's easing chain and is the one that cannot
# be grepped as a plain substring: `letterSpacing` contains it, and it appears in
# this suite's own sibling checks. Word boundaries only, and on scrubbed code so a
# comment cannot trip it.
need(not re.search(r"\btt\b", "\n".join(scrub[f] for f in FILES)),
     "criterion 6: `tt` is absent from all three files (word-boundary match)")

# ---- criterion 2: nothing that could draw the open-state look ----
# `glyph` is gone from the two faces entirely. One exception has to be carved out
# first, and only one: `Tokyo.trayGlyph` is the *colour* of tray-icon ink, defined
# in Tokyo.qml and read by seven files here — it names an ink, not a drawn icon,
# and renaming a shared token is not this ticket's business. It is stripped before
# the word is counted, so a *new* mention anywhere still bites.
def unink(text):
    return text.replace("trayGlyph", "trayInk")


for f in ("ClockFace.qml", "Clock.qml"):
    n = len(re.findall(r"glyph", unink(raw[f]), re.I))
    need(n == 0,
         "criterion 2: %s draws no glyph at all (%d mention(s))" % (f, n))

# The word `glyph` cannot be banned outright: the timers card's title row draws
# two Font Awesome icons through `PillButton.glyph`, and the date line ends in a
# moon-phase character — both predate this change and both stay. What must not
# come back is the *clock* glyph, and the token that fed it is now gone from
# Tokyo.qml, so there is nothing left to reinvent: any mention of it in the three
# files is the morph's second look reaching for a character that no longer exists.
need("clockGlyph" not in raw["Tokyo.qml"] and "clockGlyph" not in raw["Module.qml"],
     "criterion 2: Tokyo.qml no longer defines clockGlyph — there is no clock "
     "glyph left in this config to draw")
for f in FILES:
    n = raw[f].count("clockGlyph")
    need(n == 0, "criterion 2: %s draws no clock glyph (%d)" % (f, n))

for f in FILES:
    n = len(re.findall(r"magnet", unink(raw[f]), re.I))
    need(n == 0,
         "criterion 1: %s is anchored to the bar, not to a pill dot (%d)" % (f, n))

need("hoveredExtra" not in raw["Clock.qml"] and "pillLit" not in raw["Clock.qml"],
     "criterion 2: the pill no longer borrows the popup's hover state")
need("hoveredExtra" not in raw["Module.qml"],
     "criterion 2: Module.hoveredExtra is gone — nothing latched hover any more")
need(re.search(r"readonly\s+property\s+bool\s+lit\s*:\s*hovered\s*$",
               scrub["Module.qml"], re.M) is not None,
     "criterion 2: Module.lit collapsed to hovered, its only remaining reader")

# ---- the travelling machinery ----
# The parking clip and both Transforms existed only to hide a look that was
# parked outside the face. With one look there is nothing parked.
for f in FILES:
    need("transform:" not in scrub[f],
         "criterion 3: %s has no entrance transform" % f)
need("clip" not in scrub["ClockFace.qml"],
     "criterion 3: the face has no parking clip — it has one look")
need("QtQuick.Shapes" not in raw["ClockFace.qml"],
     "criterion 6: ClockFace.qml no longer imports QtQuick.Shapes")

# ---- criterion 3: what animation is allowed, and what it may touch ----
# The morph is gone. The open is not: the panel slides down into place and fades
# up, on an inner Item, in 150 ms. That is one deliberate exception, and it is
# pinned by target and property rather than permitted by type — "no
# NumberAnimation anywhere in the flyout" is the rule that has to be relaxed to
# allow this one, and relaxing a ban list by type is precisely how the slide (and
# then the morph behind it) comes back.
#
# Still banned in every file, by capability rather than by name: `states`, and
# `Transition`, and anything that is not the one allowed tween. Those three are
# how a morph gets written when nobody is thinking about the ban list — a state
# machine with a spring under it is the same slide, wearing a different hat.
#
# Still banned in the faces, without exception: any animation that is not a
# colour tween. A face must never move. A `ColorAnimation` on anything but
# `color` could, which is why the `Behavior on` property is checked by name.
for f in FILES:
    need("Transition" not in scrub[f],
         "criterion 3: %s has no Transition — a state machine is how the morph "
         "comes back" % f)
    need(re.search(r"^\s*states\s*:", scrub[f], re.M) is None,
         "criterion 3: %s has no states block" % f)
    need(re.search(r"Behavior on (?!color)\w+", scrub[f]) is None,
         "criterion 3: every remaining Behaviour in %s is on color" % f)

for f in ("ClockFace.qml", "Clock.qml"):
    every = re.findall(r"\w*Animation", scrub[f])
    colours = re.findall(r"\bColorAnimation\b", scrub[f])
    need(len(every) == len(colours),
         "criterion 3: every animation in %s is a colour tween (%d of type(s), "
         "%d ColorAnimation; %s)"
         % (f, len(every), len(colours),
            ", ".join(sorted(set(every) - set(colours))) or "none"))

# ---- criterion 3: whatever Behaviour is left, and its figure ----
# `Behavior on color` is allowed (hovering a face changes the ink in 120 ms), but
# a geometry or opacity Behaviour is the morph by another name and the duration
# has to stay at or under SysFlyout's 120.
behaviours = []
for f in FILES:
    for m in re.finditer(r"Behavior on (\w+)\s*\{", scrub[f]):
        body = block(scrub[f], m.start())
        dur = re.search(r"duration:\s*(\d+)", body)
        behaviours.append((f, m.group(1), int(dur.group(1)) if dur else None))
need(all(p == "color" for _, p, _ in behaviours),
     "criterion 3: every remaining Behaviour is on color (%s)"
     % ", ".join("%s:%s" % (p, d) for _, p, d in behaviours) or "none")
over = [b for b in behaviours if b[2] is None or b[2] > 120]
need(not over,
     "criterion 3: no Behaviour over 120ms (%s)"
     % ", ".join("%s %sms" % (f, d) for f, _, d in over) or "none")

# ---- criterion 3: the reveal, pinned by target, property and figure ----
# One number drives everything: `t` runs 0 shut to 1 open, and the Item's `y` and
# `opacity` are both expressions of it. So the panel slides and fades as one
# gesture, and there is exactly one animation per direction rather than two that
# could disagree about where the panel is. The figures are the sibling panels'
# (SettingsFlyout.qml:83-106), which is what "just backwards" means — InQuart is
# OutQuart run in reverse, over a shorter window.
fl = scrub["ClockFlyout.qml"]
tweens = re.findall(r"NumberAnimation\s*\{([^{}]*)\}", fl)
kinds = set(re.findall(r"\w*Animation", fl))
need(kinds <= {"NumberAnimation", "SequentialAnimation"},
     "criterion 3: the flyout's only animation types are NumberAnimation and the "
     "container that runs them in turn (%s)"
     % (", ".join(sorted(kinds)) or "none"))
need(len(tweens) == 2,
     "criterion 3: one tween per direction — the open and the close (%d)"
     % len(tweens))

pairs = []
for t in tweens:
    tgt = re.search(r"target:\s*(\w+)", t)
    prop = re.search(r'property:\s*"([\w.]+)"', t)
    pairs.append("%s.%s" % (tgt.group(1), prop.group(1))
                 if tgt and prop else "unreadable")
need(pairs == ["root.t", "root.t"],
     "criterion 3: both tweens drive `root.t` and nothing else (%s)"
     % ", ".join(pairs))


def easing(t):
    m = re.search(r"easing\.type:\s*Easing\.(\w+)", t)
    return m.group(1) if m else None


def dur(t):
    m = re.search(r"duration:\s*(\d+)", t)
    return int(m.group(1)) if m else None


opens = [t for t in tweens if easing(t) == "OutQuart"]
closes = [t for t in tweens if easing(t) == "InQuart"]
need(len(opens) == 1 and len(closes) == 1,
     "criterion 3: exactly one OutQuart open and one InQuart close (%d/%d)"
     % (len(opens), len(closes)))

if opens:
    o = opens[0]
    need(dur(o) == 260,
         "criterion 3: the open is 260ms — the sibling panels' figure (%s)"
         % dur(o))
    need(re.search(r"from:\s*0\s*;", o) is not None
         and re.search(r"to:\s*1\b", o) is not None,
         "criterion 3: the open runs t 0 -> 1, with `from:` stated rather than "
         "inherited")
if closes:
    c = closes[0]
    need(dur(c) == 200,
         "criterion 3: the close is 200ms — quicker than the entrance (%s)"
         % dur(c))
    need(re.search(r"to:\s*0\b", c) is not None,
         "criterion 3: the close runs t back to 0")
    # Load-bearing, and the reason the close is allowed to interrupt an open.
    need(re.search(r"\bfrom\s*:", c) is None,
         "criterion 3: the close states no `from:` — it must start from wherever "
         "`t` actually is, or a close landing mid-open jumps")
if opens and closes:
    need(dur(opens[0]) > dur(closes[0]),
         "criterion 3: the exit is quicker than the entrance — a panel you are "
         "closing is one you have already decided about")

need(re.search(r"property real t:\s*0\b", fl) is not None,
     "criterion 3: `t` is the panel's single progress number, and starts shut")
need("ScriptAction { script: root.hide() }" in fl,
     "criterion 3: the close hides the window itself, by calling hide() once the "
     "slide is finished — not from the toggle")
need(re.search(r"property bool closing:\s*false", fl) is not None,
     "criterion 3: there is a `closing` flag — the exit is animated, so a second "
     "click can land while it is still in flight")

hide_fn = re.search(r"function hide\(\)\s*\{([^{}]*)\}", fl)
need(hide_fn is not None
     and "root.visible = false" in hide_fn.group(1)
     and "root.closing = false" in hide_fn.group(1),
     "criterion 3: hide() clears `closing` and takes the window down")
close_fn = re.search(r"function close\(\)\s*\{([^{}]*)\}", fl)
need(close_fn is not None
     and "closeAnim.start()" in close_fn.group(1)
     and "root.visible" not in close_fn.group(1),
     "criterion 3: close() starts the exit and never touches `visible` itself — "
     "cutting it here would strand `t` above 0 for the next open")

# The animated Item must be free to move. An anchored item has its `y` rewritten
# on every anchoring pass, so a tween writing to an anchored `y` runs to
# completion and moves nothing — which reads on screen as "the animation stopped
# working" with nothing in the log to explain it. Sized from the window's own
# numbers instead, and offset rather than anchored.
citem = re.search(r"Item\s*\{\s*\n\s*id:\s*content\b", fl)
need(citem is not None, "criterion 3: there is an inner Item `content` to move")
if citem:
    cbody = block(fl, citem.start())
    # `content`'s OWN declarations, not its descendants'. `grid` inside it is
    # anchored to `box`, which is correct and has nothing to do with whether the
    # animated Item may be moved — so this reads only the lines at the Item's own
    # indent level.
    pad = re.match(r"[ ]*", cbody.split("\n", 1)[1]).group(0)
    own = [ln for ln in cbody.split("\n")
           if ln.startswith(pad) and not ln.startswith(pad + " ")]
    need(not any("anchor" in ln for ln in own),
         "criterion 3: `content` is not anchored — an anchored y is rewritten "
         "under the tween, so the panel would sit still and the tween would "
         "still run to 0 (%s)"
         % "; ".join(ln.strip() for ln in own if "anchor" in ln))
    need(any(re.search(r"width:\s*parent\.width", ln) for ln in own)
         and any(re.search(r"height:\s*parent\.height", ln) for ln in own),
         "criterion 3: `content` takes the window's own size")
    # The bug this line exists for: a `content` Item that does not actually wrap
    # the surface compiles, loads, and animates an empty box of nothing.
    need("id: box" in cbody,
         "criterion 3: the surface `box` is inside `content`, so the slide moves "
         "the panel and not an empty Item")
    # Both properties read `t`, so the slide and the fade cannot fall out of step
    # with each other — and neither can quietly go missing on its own.
    need(any(re.search(r"y:\s*\(1\s*-\s*root\.t\)\s*\*\s*-root\.slideFrom", ln)
             for ln in own),
         "criterion 3: `content.y` is a function of `t`")
    need(any(re.search(r"opacity:\s*root\.t\s*$", ln) for ln in own),
         "criterion 3: `content.opacity` is `t` — a panel that slides without "
         "fading is not the reveal either")

# What must never be tweened is the window. A change to implicitWidth or
# implicitHeight is a compositor round-trip per frame, so `t` may drive the panel's
# position and opacity but never its size.
need(not re.search(r'target:\s*root\s*;\s*property:\s*'
                   r'"(width|height|implicitWidth|implicitHeight)"', fl),
     "criterion 3: nothing tweens the window's size — an xdg_popup resize is a "
     "compositor round-trip per frame")
need(not re.search(r"target:\s*(box|grid)\b", fl),
     "criterion 3: no tween targets the surface or the grid directly")
need(not re.search(r"implicit(?:Width|Height)\s*:[^;]*\bt\b", fl),
     "criterion 3: the window's own dimensions do not read `t`")

# Movement is displacement, not duration: the slide is 6-14px and the fade rides
# the same number, so a longer or shorter `slideFrom` is the dial, not the curve.
m = re.search(r"readonly property \w+ slideFrom:\s*(\d+)", fl)
v = int(m.group(1)) if m else None
need(v is not None and 6 <= v <= 14,
     "criterion 2: slideFrom is 6-14 — movement is displacement, not duration "
     "(got %s)" % v)

# ---- criterion 3: the toggle opens, closes, and reverses a close in flight ----
toggle_m = re.search(r"function toggleFor\([^)]*\)\s*\{", fl)
if toggle_m:
    tb = block(fl, toggle_m.start())
    anim_ids = re.findall(r"\w*Animation\s*\{\s*id:\s*(\w+)", fl)
    need(set(anim_ids) == {"openAnim", "closeAnim"},
         "criterion 3: the flyout declares one open and one close animation (%s)"
         % ", ".join(sorted(anim_ids)))
    # Order matters and the reason is a frame: `openAnim.start()` applies
    # `from:` on its first animation tick, so a reveal started before the window
    # is up can finish against a window that is not showing yet. `t = 0` is also
    # written by hand, because a tween that only learned `from:` on its first tick
    # would show the panel at rest for one frame and then yank it up and back.
    if "root.visible = true" in tb and "openAnim.start()" in tb:
        need(tb.index("root.visible = true") < tb.rindex("openAnim.start()"),
             "criterion 3: the window is shown before the reveal starts")
    else:
        need(False, "criterion 3: the window is shown before the reveal starts")
    need(re.search(r"root\.t\s*=\s*0", tb) is not None,
         "criterion 3: the toggle parks `t` at 0 before the reveal runs")
    need(re.search(r"closeAnim\.start\(\)", tb) is not None,
         "criterion 3: the toggle closes as well as opens")
    # The panel is dismissed by the animation, not by the click: setting visible
    # from the toggle would cut it off mid-slide.
    need(re.search(r"root\.visible\s*=\s*false", tb) is None,
         "criterion 3: the toggle never sets visible false — closeAnim owns the "
         "dismissal, so the panel is not cut off mid-slide")
    need("root.visible = !root.visible" not in fl,
         "criterion 3: open and close are no longer one bare toggle — each branch "
         "parks `t` and starts its own animation")
    # A click during the exit reverses it. Without this the close runs to 0 on a
    # panel the user has just reopened.
    need(re.search(r"if \(root\.closing\)", tb) is not None
         and "closeAnim.stop()" in tb,
         "criterion 3: a click during the exit stops the close and reopens")

need("relativeX" not in fl and "relativeY" not in fl,
     "criterion 1: no relativeX/relativeY (deprecated in 0.3.1)")

# The toggle takes the pill and stores the pill. Half-migrated — a parameter left
# named `host`, with `host.anchor` reaching for the magnet the popup no longer
# follows — compiles, loads and opens the panel, just not from the right state.
toggle = re.search(r"function toggleFor\(([^)]*)\)\s*\{", fl)
need(toggle is not None and toggle.group(1).strip() == "pill",
     "criterion 3: toggleFor takes the pill and nothing else (got %s)"
     % (("`%s`" % toggle.group(1).strip()) if toggle else "no toggleFor"))
if toggle:
    body = block(fl, toggle.start())
    need(re.search(r"root\.pill\s*=\s*pill\b", body) is not None,
         "criterion 3: the toggle stores the argument it was given, untouched")
    need("anchor" not in body.split("root.anchor")[0].replace("anchorItem", ""),
         "criterion 3: the toggle does not re-derive what the pill is")

# ---- criterion 1: anchored to the bar's screen-top marker ----
# Anchored to the END of the line, all three. `Edges.Top | Edges.Right` contains
# the string `anchor.edges = Edges.Top`, so a substring test passes the exact
# regression criterion 1 exists to stop: a popup in the corner rather than
# centred. Same for a gravity that adds an edge, and same for `panelH + 18`
# passing a `panelH` pattern — a reserved strip is the other thing this file
# used to do with its height.
def edge_line(prop, value):
    m = re.search(r"^.*\b%s\s*=\s*%s\s*$" % (prop, value), fl, re.M)
    return m.group(0).strip() if m else None


need("anchor.item = root.anchorItem" in fl,
     "criterion 1: the window is anchored to the host-supplied marker")
need(edge_line(r"anchor\.edges", r"Edges\.Top") is not None,
     "criterion 1: anchored by its top edge, and nothing else — Top only, no "
     "Left/Right, so the popup centres (%s)" % (edge_line(r"anchor\.edges", r"Edges\.Top") or "no such line"))
need(edge_line(r"anchor\.gravity", r"Edges\.Bottom") is not None,
     "criterion 1: gravity Bottom, so the popup hangs below that top edge (%s)"
     % (edge_line(r"anchor\.gravity", r"Edges\.Bottom") or "no such line"))

# `PopupAdjustment.None`, not Toast.qml's `All`. `All` is Flip | Slide | Resize
# and FlipY inverts the vertical gravity: if the panel ever outgrew the space
# below the bar, the compositor would flip it to hang off the top of the screen
# instead. `cellH` is measured off font metrics and `clockTail` grows a whole row
# per timezone added, so the height is data rather than a constant — this is a
# constraint that can be reached, not a theoretical one.
need(re.search(r"^.*\banchor\.adjustment\s*=\s*PopupAdjustment\.None\s*$", fl, re.M)
     is not None,
     "criterion 1: PopupAdjustment.None — All's FlipY would flip the panel "
     "upward off the top of the screen once the panel outgrows the space below "
     "the bar (%s)" % (edge_line(r"anchor\.adjustment", r"PopupAdjustment\.\w+") or "unset"))

# The gap below the bar belongs to the placement, not to the bar. On the marker it
# read as bar layout: tidying it to 0 compiles, renders, and drops the panel up
# under the pills; moving the bar to the bottom of the screen would open it
# mid-screen.
need(re.search(r"^.*\banchor\.margins\.top\s*=\s*root\.topGap\s*$", fl, re.M) is not None,
     "criterion 1: the offset below the bar is applied through anchor.margins.top")
need(re.search(r"topGap:\s*Tokyo\.barHeight\s*\+\s*Tokyo\.edgeGap", fl) is not None,
     "criterion 1: topGap is the bar's own height plus its edge gap — one "
     "figure, named in the file that places the panel")

need(re.search(r"^\s*implicitWidth:\s*root\.panelW\s*$", fl, re.M) is not None
     and re.search(r"^\s*implicitHeight:\s*root\.panelH\s*$", fl, re.M) is not None,
     "criterion 1: the window is exactly the panel — no overshoot margin, no "
     "reserved strip")
for gone in ("room", "root.gap"):
    need(gone not in fl, "criterion 1: no `%s` term in the flyout's geometry"
         % gone)
need("property var anchorItem" in fl,
     "criterion 1: the flyout takes the marker as a property, like Toast.qml")

bar = raw["Bar.qml"]
bs = code(bar)
have = "id: clockAnchor" in bar
need(have and bar.index("id: clockAnchor") < bar.index("ClockFlyout {"),
     "criterion 1: Bar.qml declares clockAnchor BEFORE ClockFlyout")
if have:
    # From the `Item {` that owns the id, not from the id itself: the token after
    # `id: clockAnchor` is `anchors {`, so anchoring the search on the id measures
    # the anchors block — which is where `width: 0` is not.
    at = bs.index("id: clockAnchor")
    anchor = block(bs, bs.rindex("Item {", 0, at))
    need(re.search(r"width:\s*0", anchor) is not None
         and re.search(r"height:\s*0", anchor) is not None,
         "criterion 1: clockAnchor is zero-sized, so nothing is drawn at it")
    need("horizontalCenter: parent.horizontalCenter" in anchor
         and "top: parent.top" in anchor,
         "criterion 1: clockAnchor is centred horizontally at the bar's top edge")
    need(re.search(r"topMargin", anchor) is None,
         "criterion 1: clockAnchor carries no offset — the gap below the bar is "
         "the popup's own placement, not bar geometry")
flyout_block = block(bs, bs.index("ClockFlyout {"))
need("anchorItem: clockAnchor" in flyout_block,
     "criterion 1: the flyout is handed clockAnchor")
need("magnet" not in bar and "hidden while the flyout" not in bar,
     "criterion 1: no stale pill-anchor prose left in Bar.qml")

# ---- criterion 4: the SysFlyout surface ----
need(re.search(r"color:\s*Tokyo\.bgDark", fl) is not None,
     "criterion 4: the popup surface is Tokyo.bgDark")
need(re.search(r"radius:\s*Tokyo\.pillRadius", fl) is not None,
     "criterion 4: the popup surface is Tokyo.pillRadius")
need(re.search(r"border\.color:\s*Tokyo\.bgHighlight", fl) is not None
     and re.search(r"border\.width:\s*1", fl) is not None,
     "criterion 4: the popup surface has a 1px Tokyo.bgHighlight border")

qcell = open("QuadCell.qml").read()
qc = code(qcell)
need(re.search(r"color:\s*Tokyo\.bg\b", qc) is not None
     and re.search(r"border\.color:\s*Tokyo\.bgHighlight", qc) is not None,
     "criterion 4: the inner cells are Tokyo.bg with a Tokyo.bgHighlight border")
need("Tokyo.pane" not in qc and "Tokyo.paneEdge" not in qc,
     "criterion 4: the cells no longer use the older pane pair")
title = block(qc, qc.index("root.title"))
need(re.search(r"pixelSize:\s*10", title) is not None
     and "bold: true" in title and "letterSpacing: 1.5" in title,
     "criterion 4: cell titles are 10px bold, ls 1.5")

# The cell publishes its own chrome. The flyout sizes a cell to its content by
# *reading* that figure; when it used to spell the same arithmetic out as a
# literal, the two copies could drift and nothing said so — the card simply
# rendered with its bottom block cut off, which is not a crash and not a warning.
need(re.search(r"readonly\s+property\s+real\s+chrome\s*:", qc) is not None,
     "criterion 4: QuadCell publishes the chrome its body sits inside")
need(re.search(r"cellH:\s*clockPane\.chrome\s*\+\s*clockPane\.clockTail", fl)
     is not None,
     "criterion 4: cellH reads QuadCell's chrome instead of restating it — one "
     "source for the figure, so it cannot be half-updated")

# The flyout's own block labels, one per block, and the zone figure
for label in ('text: "TIME"', 'text: "DATE"', 'text: "UPTIME"'):
    i = fl.index(label)
    b = block(fl, i - 200 if i > 200 else 0)
    seg = b[b.index("Text {"):]
    need(re.search(r"pixelSize:\s*10", seg) is not None and "bold: true" in seg
         and "letterSpacing: 1.5" in seg,
         "criterion 4: the %s label is 10px bold, ls 1.5"
         % label.split('"')[1])
need(re.search(r"pixelSize:\s*13;\s*bold:\s*true", fl) is not None,
     "criterion 4: the zone clock figures are 13px bold")

# ---- criterion 5 + 7: content live, poll off when closed ----
need("clock-panel.sh" in fl and "TimerPanel" in fl and "TimerState" in fl,
     "criterion 5: zones/uptime from clock-panel.sh, timers from the singleton")
need(re.search(r"active:\s*root\.visible", fl) is not None,
     "criterion 7: the script poll is bound to visible")
need("TimerState.active" in fl and "pinFormToBottom: true" in fl
     and "onFieldActivated" in fl,
     "criterion 5: the full timer panel still rides the timers cell")
for helper in ("function uptimeText", "function weekNumber", "function moonPhase"):
    need(helper in fl, "criterion 5: %s survives" % helper)

# ---- one Escape path, and it is not annotated as dead code ----
# A `Keys` handler beside a working `Shortcut` reads as "one of these is
# redundant, guess which" — and the guess is wrong, because Qt resolves shortcuts
# before ordinary key propagation, so the fallback never fires.
need("Keys.onEscapePressed" not in fl,
     "criterion 3: one Escape path — the window Shortcut, no Keys fallback "
     "annotated as dead code")
need(re.search(r"Shortcut\s*\{[^}]*sequence:\s*\"Escape\"[^}]*"
               r"context:\s*Qt\.WindowShortcut", scrub["ClockFlyout.qml"], re.S)
     is not None,
     "criterion 3: Escape is a Qt.WindowShortcut, so it fires without a focused item")

sys.exit(1 if fails else 0)
PY

# ---------- 2 + 3. the real face and the real popup, rendered ----------
if ! command -v quickshell >/dev/null; then
    # Loudly, and not `exit $fail`. A layer that cannot run is a failure.
    bad "quickshell is not on PATH — layers 2 and 3 cannot run"
    echo "clock flyout tests FAILED"
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
probe="$tmp/q"
mkdir -p "$probe"
# The WHOLE directory, symlinked. One file at a time was how the suite came to be
# green on a popup that had never been executed: it measured ClockFace, which knows
# nothing about padding, card heights or anchor margins, and every number those
# three assertions read from the source was a number nothing ever computed.
# Symlinked rather than copied so there is still exactly one copy of the truth:
# Tokyo is a pragma Singleton and both widgets under test are the live files.
for f in *.qml; do ln -sf "$PWD/$f" "$probe/$f"; done

cat > "$probe/probe.qml" <<'QML'
import QtQuick
import Quickshell

// GENERATED by tests/test-clock-flyout-detached.sh — do not edit.
// Every widget below is a SYMLINK to the live config.
ShellRoot {
    id: sr

    // One face per timestamp, spanning the digit shapes: 0 and 8 are the widest
    // advances in this font, and Qt rounds each glyph's advance separately, so a
    // face sized off its own live text is a pill that resizes once a second.
    readonly property var stamps: [
        "2026-09-27T08:08:08", "2026-09-27T00:00:00", "2026-09-27T23:59:59",
        "2026-01-01T11:11:11", "2026-12-31T19:07:43", "2026-03-03T03:03:03",
        "2026-06-06T06:06:06", "2026-09-09T09:09:09", "2026-11-11T11:11:11",
        "2026-02-02T22:22:22"
    ]

    /// the face the hover round-trip is measured on
    property var probeFace: null

    Item {
        id: host
        width: 400
        height: 300

        Column {
            id: stack
            Repeater {
                model: sr.stamps
                delegate: ClockFace {
                    required property int index
                    required property string modelData
                    width: 200
                    height: 26
                    now: new Date(modelData)
                    objectName: "face" + index
                }
            }
        }
    }

    // ---- the popup, instantiated for real, never shown ----
    // Stand-in for Bar.qml's clockAnchor: zero-sized, horizontally offset from
    // the origin so an accidentally-centring assertion has something to catch.
    Item {
        id: marker
        x: 100
        y: 0
        width: 0
        height: 0
    }

    ClockFlyout {
        id: fly
        anchorItem: marker
    }

    function r1(v) { return Math.round(v * 10) / 10 }

    function readingsOf(face) {
        return face.children.length > 0 && face.children[0].children !== undefined
            ? face.children[0] : null
    }

    function geom(item, ref) {
        if (item === null) return ""
        var a = item.mapToItem(ref, 0, 0)
        return [r1(a.x), r1(a.y), r1(item.width), r1(item.height)].join(",")
    }

    // Every descendant, not just the direct children. The face's one child is
    // `readings`, so a look parked inside the readings — which is where the morph
    // put it — was never in this walk at all, and the probe reported a clean face
    // over a broken one. Depth is the whole point: `mapToItem` needs a QQuickItem
    // on both ends, so anything that is not one is skipped rather than crashed on.
    function walk(item, out) {
        if (item === null || item.children === undefined) return out
        for (var i = 0; i < item.children.length; i++) {
            var c = item.children[i]
            if (c.mapToItem === undefined) continue
            out.push(c)
            walk(c, out)
        }
        return out
    }

    // How many descendants stick out of the face *once their transforms are
    // applied*. Through `mapToItem`, not x/y: a `Translate` is not geometry, so a
    // parked second look sat a whole pill above or below a 26-row face while still
    // reporting x/y that fit inside it — which is exactly the bug, and a stray
    // count reading x/y reports it as clean.
    function strays(face) {
        var n = 0
        var all = walk(face, [])
        for (var i = 0; i < all.length; i++) {
            var c = all[i]
            var a = c.mapToItem(face, 0, 0)
            var b = c.mapToItem(face, c.width, c.height)
            if (a.x < -0.5 || a.y < -0.5
                || b.x > face.width + 0.5 || b.y > face.height + 0.5) n++
        }
        return n
    }

    // Pure reader. `hovered` is set by the pass that owns the tick, never here:
    // setting it in the same statement as the read makes every reading the
    // *previous* value, which is how a probe reports the un-hovered colour under
    // the label `hover` and then passes a direction-blind `!=` on the pair.
    function measure(face, label) {
        var rd = readingsOf(face)
        var time = rd ? rd.children[0] : null
        var date = rd ? rd.children[1] : null
        var c = time === null ? "" : String(time.color)
        return "cfprobe " + label + " " + JSON.stringify({
            now: face.now.toISOString(),
            contentW: r1(face.contentW),
            children: face.children.length,
            strays: strays(face),
            depth: walk(face, []).length,
            readings: rd === null ? "absent" : rd.children.length,
            timeText: time === null ? "" : time.text,
            timeGeom: time === null ? "" : geom(time, face),
            timeAlign: time === null ? -1 : time.horizontalAlignment,
            timeColor: c,
            isCyan: c === String(Tokyo.cyan),
            isFg: c === String(Tokyo.fg),
            dateGeom: date === null ? "" : geom(date, face),
            dateAlign: date === null ? -1 : date.horizontalAlignment,
            dateColor: date === null ? "" : String(date.color),
            faceGeom: geom(face, host),
            readingsGeom: rd === null ? "" : geom(rd, face)
        })
    }

    // The popup's own figures, read off the live object. `cells` are located by
    // shape — anything publishing QuadCell's `chrome` — and the clock card is the
    // one that also publishes `clockTail`, because those are public properties of
    // real widgets rather than a private contract invented for this probe.
    //
    // Note what is NOT read here: the height the *layout* assigned to the cards,
    // and the grid's implicitHeight. Qt only re-runs a layout for an item tree
    // that is in a live scene, so offscreen — where nothing in this config is
    // ever shown — every layout is frozen at whatever it computed on its first
    // pass and then ignores later changes. Measured: with three zone rows the
    // real `cellH` is 401 and the card still reports 349, and forcing the zone
    // count 0 → 3 → 6 moves the property 349 → 401 → 467 while the card stays at
    // 349. In a visible window the same layout tracks its preferred height
    // correctly, so that gap is the offscreen harness, not the widget — and an
    // assertion built on it would be asserting a harness artefact. What is read
    // instead are the bindings that decide the height, which are live everywhere.
    function measureFly() {
        var all = walk(fly.contentItem, [])
        var cells = []
        for (var i = 0; i < all.length; i++)
            if ("chrome" in all[i]) cells.push(all[i])
        var clock = null
        for (var j = 0; j < cells.length; j++)
            if ("clockTail" in cells[j]) clock = cells[j]
        var grid = clock === null ? null : clock.parent
        return "cfprobe fly " + JSON.stringify({
            implicitW: r1(fly.implicitWidth),
            implicitH: r1(fly.implicitHeight),
            panelW: r1(fly.panelW),
            panelH: r1(fly.panelH),
            cellW: r1(fly.cellW),
            cellH: r1(fly.cellH),
            pad: r1(fly.pad),
            cellGap: r1(fly.cellGap),
            cells: cells.length,
            chrome: clock === null ? -1 : r1(clock.chrome),
            clockTail: clock === null ? -1 : r1(clock.clockTail),
            gridX: grid === null ? -1 : r1(grid.x),
            gridY: grid === null ? -1 : r1(grid.y),
            anchorIsMarker: fly.anchor.item === marker,
            anchorTopMargin: r1(fly.anchor.margins.top),
            topGap: r1(fly.topGap),
            barHeight: r1(Tokyo.barHeight),
            zoneRows: fly.zones.length
        })
    }

    // Four chained passes rather than handlers reading and writing in one tick.
    // Two separate things need a tick of their own here: the hover round-trip,
    // because `time` has a `Behavior on color` (120 ms) and a colour read on the
    // frame the assignment lands is the old colour; and the popup, which has to
    // finish polishing its GridLayout and shaping its fonts before any of its
    // geometry means anything. 400 ms is comfortably past the settle of a 120 ms
    // curve.
    Timer {
        id: pass1
        running: true
        interval: 200
        onTriggered: {
            for (var i = 0; i < stack.children.length; i++) {
                var f = stack.children[i]
                // QQuickRepeater is a QQuickItem, so a Repeater sitting inside a
                // Column is one of its `children` and comes LAST. A loop that
                // assumes otherwise prints every real face and then dies on the
                // repeater — which is exactly how this probe read "9 good lines,
                // then silence" for an hour. Skipped by shape, not by index.
                if (!("contentW" in f)) continue
                if (sr.probeFace === null) sr.probeFace = f
                print(measure(f, "face" + i))
                // If a mix property is still there, drive it to 1 and measure
                // again: parked looks sit at mix 0 *inside* the face — that is
                // what "parked" means — so a probe that only ever reads the
                // resting state measures a clean face and calls it a pass.
                if ("glyphMix" in f) {
                    f.glyphMix = 1
                    print(measure(f, "face" + i + "Open"))
                    f.glyphMix = 0
                }
            }
            pass2.start()
        }
    }
    Timer {
        id: pass2
        interval: 400
        onTriggered: {
            // The write, in its own tick. pass3 reads.
            sr.probeFace.hovered = true
            pass3.start()
        }
    }
    Timer {
        id: pass3
        interval: 400
        onTriggered: {
            print(measure(sr.probeFace, "hover"))
            sr.probeFace.hovered = false
            pass4.start()
        }
    }
    Timer {
        id: pass4
        interval: 400
        onTriggered: {
            print(measure(sr.probeFace, "unhover"))
            print(sr.measureFly())
            Qt.exit(0)
        }
    }
}
QML

# quickshell prefixes every line (` DEBUG qml: cfprobe …`), so match the payload.
got=$(timeout 25 env QT_QPA_PLATFORM=offscreen quickshell -p "$probe/probe.qml" 2>&1 \
    | sed 's/\x1b\[[0-9;]*m//g' | grep -o 'cfprobe .*') || true

if [ -z "$got" ]; then
    bad "probe produced no measurements (probe harness broken, not the feature)"
    echo "clock flyout tests FAILED"
    exit 1
fi
echo "$got" >&2

python3 - "$got" <<'PY' || fail=1
import json, re, sys

fails = []


def need(cond, msg):
    print(("  ok   " if cond else "  FAIL ") + msg)
    if not cond:
        fails.append(msg)


m = {}
for line in sys.argv[1].splitlines():
    label, payload = line.split(" ", 2)[1], line.split(" ", 2)[2]
    m[label] = json.loads(payload)

if "fly" not in m:
    print("  FAIL the popup was never measured — the probe did not reach it")
    sys.exit(1)

faces = [v for k, v in sorted(m.items()) if k.startswith("face")]
need(len(faces) >= 10, "every timestamp was rendered (%d faces)" % len(faces))

# The one the morph broke: Qt rounds each glyph's advance separately and this
# font's digits are not all the same width, so a face sized off its own live
# text is a pill that resizes once a second.
widths = {f["contentW"] for f in faces}
need(len(widths) == 1,
     "criterion 2: contentW is one number across every time there is (%s)"
     % ", ".join(str(w) for w in sorted(widths)))
need(all(w > 0 for w in widths), "criterion 2: contentW is non-zero (%s)"
     % ", ".join(str(w) for w in sorted(widths)))
# Whole pixels, not just one number. A fractional width centres the 13px digits
# on a half pixel and re-renders every one of them, and `timeWorst` exists
# precisely because this font's advances are whole. The value itself is not
# pinned — that would be pinning the font, not the invariant.
need(all(float(w).is_integer() for w in widths),
     "criterion 2: contentW is a whole number of pixels (%s)"
     % ", ".join(str(w) for w in sorted(widths)))

# One look, permanently: nothing parked off-frame and clipped back into view, at
# any depth. `depth` is printed so a walk that silently found nothing cannot pass
# by accident — an empty walk finds zero strays.
need(all(f["strays"] == 0 for f in faces),
     "criterion 2: nothing is parked outside the face, at any depth — the second "
     "look is gone, not clipped (%s)"
     % ", ".join("%d over %d descendants" % (f["strays"], f["depth"]) for f in faces))
need(all(f["depth"] >= 2 for f in faces),
     "criterion 2: the stray walk reaches below the face's own child (%d "
     "descendants)" % faces[0]["depth"])
need(all(f["readings"] == 2 for f in faces),
     "criterion 5: the readings are still both lines (%s)"
     % ", ".join(str(f["readings"]) for f in faces))
need(all(re.fullmatch(r"\d\d:\d\d:\d\d", f["timeText"]) for f in faces),
     "criterion 5: the top line is HH:mm:ss on every face (%s)"
     % ", ".join(f["timeText"] for f in faces))

# The box is as wide as the *widest* of the looks and the readings fill it, so
# the date has to be centred or it sits a few px left of the time above it.
# Text.AlignHCenter is 4 — AlignLeft is 1, which is the number a wrong guess
# lands on, so it is worth spelling out rather than assuming 1.
need(all(f["timeAlign"] == 4 and f["dateAlign"] == 4 for f in faces),
     "criterion 5: both lines stay centred in the face (%s)"
     % ", ".join("%s/%s" % (f["timeAlign"], f["dateAlign"]) for f in faces))

# Criterion 2: hovering changes the ink and nothing else. This is the assertion
# that would have caught the slide, and it is the only one that can — a static
# grep for `Translate` cannot tell a parked look from a static one.
#
# Direction matters and is asserted, not inferred: a bare `h != u` passes just as
# happily on a face whose time turned *invisible* on hover, and the probe's own
# bug was to hand it two identical readings under different labels. So both ends
# are pinned to the token ClockFace actually branches on, in the file, in QML —
# where Tokyo.cyan and Tokyo.fg are readable and a guess about which is which is
# impossible.
h, u = m["hover"], m["unhover"]
same_geom = all(h[k] == u[k] for k in
                ("timeGeom", "dateGeom", "faceGeom", "readingsGeom"))
need(same_geom, "criterion 2: hovering moves nothing — geometry is identical "
                "(time %s / %s, face %s / %s)"
     % (h["timeGeom"], u["timeGeom"], h["faceGeom"], u["faceGeom"]))
need(u["isFg"] and not u["isCyan"],
     "criterion 2: at rest the time is Tokyo.fg, not Tokyo.cyan (%s, cyan=%s)"
     % (u["timeColor"], u["isCyan"]))
need(h["isCyan"] and not h["isFg"],
     "criterion 2: hovered, the time is Tokyo.cyan — not merely *different* (%s, "
     "fg=%s)" % (h["timeColor"], h["isFg"]))
need(h["dateColor"] == u["dateColor"],
     "criterion 2: the date does not follow the hover, as before (%s)"
     % u["dateColor"])

# ================= the popup itself =================
p = m["fly"]

# The window is the panel and nothing else. A popup larger than its content shows
# a margin of background around it; smaller clips the card.
need(p["implicitW"] == p["panelW"] and p["implicitH"] == p["panelH"],
     "criterion 1: the window is exactly panelW x panelH (%s x %s vs %s x %s)"
     % (p["implicitW"], p["implicitH"], p["panelW"], p["panelH"]))

# Anchored to the marker the host handed it, not to something it went and found.
need(p["anchorIsMarker"],
     "criterion 1: the popup is anchored to the host's marker, and to that one")

# The offset below the bar, read off the live anchor rather than trusted from the
# source. `-2000` here is the whole panel off the top of the screen, which is not
# a crash and not a warning.
need(p["anchorTopMargin"] == p["topGap"],
     "criterion 1: anchor.margins.top is topGap (%s vs %s)"
     % (p["anchorTopMargin"], p["topGap"]))
need(p["topGap"] == p["barHeight"] + 6 and p["topGap"] > p["barHeight"],
     "criterion 1: the gap clears the bar (%s below the top edge, bar is %s)"
     % (p["topGap"], p["barHeight"]))

# The card is sized to its content: chrome plus the measured tail, with the tail
# measured off the real font metrics of the real blocks. A hand-written constant
# here compiles, loads, renders, and quietly cuts the bottom block off. This is
# the identity that makes it fit, asserted on live values — see the note in the
# probe about why the layout-assigned height is not one of the readings.
need(p["chrome"] > 0, "criterion 4: the cell publishes a real chrome figure (%s)"
     % p["chrome"])
need(p["cells"] == 2, "criterion 4: both cards are really in the panel (%d)"
     % p["cells"])
need(p["clockTail"] > 0,
     "criterion 4: the clock card actually has content to fit (tail %s over %s "
     "zone rows)" % (p["clockTail"], p["zoneRows"]))
need(abs(p["cellH"] - (p["chrome"] + p["clockTail"])) <= 0.5,
     "criterion 4: the card is chrome plus exactly the measured content — tail %s "
     "+ chrome %s is %s, and cellH is %s"
     % (p["clockTail"], p["chrome"],
        round(p["chrome"] + p["clockTail"], 1), p["cellH"]))

# The inset is load-bearing: a card flush with the surface reads as the surface's
# own outline. Asserted as measured geometry rather than as `pad > 0` alone,
# because the arithmetic identities are what a wrong `pad` actually breaks.
need(p["gridX"] == p["pad"] and p["gridY"] == p["pad"],
     "criterion 4: the cards sit pad in from the surface's own edge (%s / %s, pad %s)"
     % (p["gridX"], p["gridY"], p["pad"]))
need(p["pad"] >= 1,
     "criterion 4: the inset is non-zero — a card flush with the surface is a "
     "defect, not a style (pad %s)" % p["pad"])
need(abs(p["panelW"] - (p["pad"] * 2 + p["cellW"] * 2 + p["cellGap"])) <= 0.5,
     "criterion 4: panelW is the two cards, the gap and the insets (%s)" % p["panelW"])
need(abs(p["panelH"] - (p["pad"] * 2 + p["cellH"])) <= 0.5,
     "criterion 4: panelH is the card plus the insets above and below (%s = 2 x %s "
     "+ %s)" % (p["panelH"], p["pad"], p["cellH"]))

sys.exit(1 if fails else 0)
PY

# ---------- tabs ----------
for f in ClockFlyout.qml ClockFace.qml Clock.qml Bar.qml QuadCell.qml \
         Tokyo.qml Module.qml tests/test-clock-flyout-detached.sh; do
    n=$(grep -cP '\t' "$f" || true)
    [ "$n" = "0" ] && ok "$f has no tabs" || bad "$f has $n tab line(s)"
done

[ $fail -eq 0 ] && echo "clock flyout tests passed" \
                 || { echo "clock flyout tests FAILED"; exit 1; }
