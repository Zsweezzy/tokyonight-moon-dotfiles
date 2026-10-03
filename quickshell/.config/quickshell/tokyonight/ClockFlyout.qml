// ClockFlyout.qml — left-clicking the clock pill opens this: a 1x2 pair of
// panes holding everything the bar used to spread over four separate pills.
//
//   +-------------------+-------------------+
//   | TIMERS            | CLOCK             |
//   | full timer panel  | TIME   local +    |
//   |                   |        other zones |
//   |                   | DATE   full date  |
//   |                   | UPTIME since boot |
//   +-------------------+-------------------+
//
// This started as a 2x2 grid of four cells. Four cells meant four titles, four
// rules and four sets of insets to keep in step, and the bar's centre spent the
// same 462 px on two rows of 214 while the timer form — the one pane with
// something to type into — was squeezed into a square. Collapsing the three
// time-ish panes into a single stacked pane buys the timers pane a full-height
// half of the panel without widening the flyout at all.
//
// One instance per bar window (created in Bar.qml), anchored to whichever pill
// was clicked, so it always opens on the monitor you clicked. `grabFocus`
// dismisses it on any outside click.
//
// THE MORPH. The pill and this panel are one rectangle, and `t` is the single
// number that says how far along the change from one to the other is: the
// shape's width, height, radius, fill and top edge are all read off it, and
// nothing here animates on a timer of its own. At t=0 the shape is a copy of
// the clock pill, on the pill's own pixels; at t=1 it is the `panelW`-wide,
// `pad * 2 + cellH`-tall panel hanging directly below that pill. Both edges
// travel: the bottom runs down `panelH - pillH` while the top walks down exactly
// the pill's height, so the panel finishes flush under the widget instead of
// having replaced its row. The sizes are the formulas rather than the numbers
// they come to: every absolute written in this file went stale the first time a
// constant moved under it.
//
// That top edge is the one part of the shape that is not a lerp between a
// pill's number and a panel's — it is `drop * min(1, t)`, capped rather than
// left to follow the 1.04 overshoot, so the joint never re-opens. See the
// comment on `shape.y` for why this used to be forbidden and what changed.
//
// The price is one thing, and it is the price: the panel's top is no longer the
// widget's own row. It used to be — the label was the panel's first `pillH` rows
// and the digits were the window's, so at rest the two were adjacent rather than
// coincident, and the label only ever came near them as the shape uncovered it.
// The widget's rows had to stay the widget's, and they could only stay them by
// the readings leaving the header: on the widget's own row a header repeating
// the time and the date is a third copy of it, two of them a click apart. Left
// with nothing to repeat, the header had nothing left to do but name the panes
// the CLOCK pane already names — so it was deleted, and what the panel has where
// the header was is `pad` of margin. The bar's widget keeps its own clock —
// `HH:mm:ss` over the date, becoming a clock glyph while the panel is up — and
// the panel's silence is what makes opening it read as the widget going quiet
// rather than as the clock having moved somewhere else.
//
// That is possible because a PopupWindow is an xdg_popup — a *child* surface of
// the bar's own, composited above it by protocol. The window is anchored with
// its top edge on the pill's top edge and hangs down over the bar and past it,
// so the shape can start as an exact copy of the widget that was clicked and
// grow out of it with no seam and no second surface. (Caelestia gets the same
// read with BlobRect/BlobGroup: one shape shared by the button and the popout.
// Here it is one Rectangle, and the shape spanning the two is the whole trick.)
// The window is the shape's *final* size plus a transparent margin, not its
// animated size — resizing a surface every frame is a compositor round-trip
// per frame, and the margin is what gives `t`'s overshoot somewhere to go.
//
// WHERE THE DATA COMES FROM, and why it is uneven:
//   - local time/date, and the boot timestamp, are plain JS Date arithmetic on
//     the `now` tick below: one in-process tick per second, no subprocess.
//   - the other timezones and the uptime seconds come from
//     `scripts/clock-panel.sh`, because quickshell's JS engine has no `Intl`
//     and no `TimeZone` QML type (verified on 0.3.1 / Qt 6.11) and
//     `toLocaleTimeString` silently *ignores* a `timeZone` option instead of
//     failing — every city would show local time under its own name.
//   - the timers come straight from the TimerState singleton, so this panel
//     and the SUPER + SHIFT + T window cannot disagree.
//
// The script poll is bound to `visible`, so a closed flyout forks nothing, and
// opening one refreshes immediately instead of waiting out the interval.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io

PopupWindow {
    id: root

    visible: false
    grabFocus: true
    color: "transparent"

    // ---------------- the morph ----------------

    /// True from the click that opens the panel until the frame its surface is
    /// torn down. The bar's pill stays on screen for all of it and is on
    /// different pixels by the end — see the long comment in `toggleFor`.
    property bool open: false
    /// Set while the close animation runs, so a second click cannot restart it
    /// halfway and strand the shape at some `t` between 0 and 1.
    property bool closing: false
    /// 0 = pill, 1 = panel. `openAnim` takes it to 1.04 before settling on 1:
    /// a spatial spring overshoots, and the overshoot is most of the difference
    /// between "grew" and "was replaced".
    property real t: 0
    /// The bar's Clock, so the closed end of the morph is the pill's *measured*
    /// width rather than a second guess at it.
    property var pill: null
    /// The hover the bar's pill was carrying at the instant of the click, latched
    /// in `toggleFor`. See `hoverTint` for why it cannot be read live off this
    /// window's own MouseArea.
    property bool hoverCarry: false

    /// Whether the bar's pill should be painted lit. This window's surface is
    /// drawn *on top of* the pill, so while the popup holds the pointer the bar's
    /// MouseArea hears nothing and the pill would cool off under the cursor at
    /// the exact moment its panel appeared. The pill binds this as
    /// `hoveredExtra` — it is a sibling, not a child, so nothing binds the
    /// other way, but a binding can still cross *into* it.
    readonly property bool pillLit: root.open
        && (root.hoverCarry || pillMouse.containsMouse)

    /// How far the widget's contents have gone from the readings to the glyph.
    ///
    /// Owned here and read by both copies of the face — this window's, drawn on
    /// the shape, and the bar's, under it — because during the morph both are on
    /// screen at the same pixels and a frame where they disagree is a frame
    /// where the hand-over is visible. The bar's copy reads it through
    /// `Clock.flyoutHost`; this window's reads it directly.
    ///
    /// `/ 0.7` is a ~50 ms fade on a ~300 ms morph (`t` is a spatial value on an
    /// `Easing.OutQuart` curve, so it is most of the way there by 20 ms — hence
    /// the divisor rather than a duration in milliseconds). Long enough not to
    /// pop, short enough to be over before the shape's top edge has travelled far:
    /// the glyph is 14 rows centred in a 26-row pill, so it does not reach the
    /// edge until `t` = 0.77, and a fade still running then would be a face
    /// half-readings, half-glyph on the only part of it anyone sees.
    readonly property real glyphMix: Math.min(1, root.t / 0.7)

    readonly property real room: 18          // transparent margin for the overshoot
    readonly property real pad: 12
    readonly property real cellGap: 10
    readonly property real cellW: 214
    /// Where on the morph the panel's own content starts to appear — `panel`'s
    /// opacity is `max(0, min(1, (t - contentIn) / 0.5))`, and it is named
    /// rather than left as a literal in that one place because a second thing has
    /// to agree on it: `pillMouse` has to be down to `pad` by then, so the
    /// click-to-close strip is never sitting over a row the panes can be pressed
    /// on. See there.
    readonly property real contentIn: 0.35
    // The pill's *implicit* width, not its `width`. The bar's layout is free to
    // leave whatever it likes in `width`, and the shape's closed end has to be
    // the pill's own idea of how wide it is rather than one layout pass's idea.
    // The implicit width is a binding on the face's font metrics, so the shape
    // and the face are both cut from the same number. The fallback is for a
    // standalone preview, where no bar handed a pill over at all.
    readonly property real pillW: pill !== null ? pill.implicitWidth : face.faceW
    readonly property real pillH: Tokyo.pillHeight
    readonly property real panelW: pad * 2 + cellW * 2 + cellGap
    /// How far the shape's top edge travels, from the pill's top edge to the
    /// pill's *bottom* edge — so the open panel hangs flush under the widget
    /// instead of taking its place.
    ///
    /// Exactly the pill's height, because the window's top edge is the pill's
    /// top edge (see `magnet` in Clock.qml) and nothing above that moves. The
    /// panel's top row therefore lands on the bar's lower half of padding, which
    /// is empty: the pills either side of this one are at the two ends of a
    /// 462-wide gap, so there is nothing for the overlap to land on.
    readonly property real drop: root.pillH
    /// The fillet at the joint: how far the panel's top edge sweeps up the
    /// widget's side before it becomes the widget's side. Bounded by the
    /// widget's own straight left side — a `pillRadius` round rect of height
    /// `drop` has straight sides only from `pillRadius` to `drop - pillRadius`,
    /// and the arc's tangent point has to land in that run or it starts on a row
    /// that is already curving and kinks. `drop - pillRadius` is therefore the
    /// largest arc that fits, and at its tangent point the fillet meets the
    /// widget's own corner exactly where that corner becomes vertical, so the
    /// two arcs join without a break.
    ///
    /// Capped by the shape's own top edge, and that cap is the whole trick: the
    /// arc is drawn tangent to the *live* edge rather than to the edge's final
    /// resting place, so the widget's side, the fillet and the top edge are one
    /// continuous outline at every value of `t` and not only at t=1. A fillet
    /// pinned to the resting place and faded in at the end is the same silhouette
    /// for the 150ms in between, hanging above an edge that is still six rows
    /// below where it will end up. The cap degenerates the fillet to a point at
    /// t=0, so it needs no opacity of its own, and 0.1 rather than 0 because an
    /// SVG arc with a zero radius is not a legal path.
    readonly property real fillet: Math.max(0.1, Math.min(root.drop - Tokyo.pillRadius, shape.y))
    /// How far the shape's top edge has come down over the widget's own bottom
    /// corner, 0..1 — which is how much of the corner is uncovered and so how
    /// much of the patch that squares it has to be at full strength. Reads the
    /// edge rather than `t`, for the reason `fillet` does.
    readonly property real patchMix: Math.max(0, Math.min(1, (shape.y - root.drop + Tokyo.pillRadius) / Tokyo.pillRadius))
    /// One row of two, so the panel is only as tall as its content. Nothing sets
    /// this number: it is *measured* off the clock pane's three stacked blocks
    /// (see `clockTail`), because the block heights are font metrics and the
    /// zone count — three of them — is data. A hand-written constant here would
    /// be wrong the moment a zone is added, and a wrong constant is not a
    /// cosmetic bug: the bottom of the UPTIME block would be cut off.
    ///
    /// 55 = QuadCell's chrome, item by item: 10 pad + 14 title row + 12 gap
    /// down to the rule (`gap`, plus the 4 by which the title row's 22 px
    /// buttons overhang a 14 px row, see QuadCell) + 1 rule, + 8 gap down to the
    /// body, + 10 pad under it. Was 51 before that 4 was spent.
    ///
    /// It is a frame constant, not the pane's height: cellH is this chrome plus
    /// `clockTail`, so the body the panes actually get is the tail either way and
    /// raising the chrome does not shrink the clock pane's content. That is also
    /// what keeps the two panes the same height while their frame grows under
    /// them, and why `listCap` does not move. Re-derive both sides together —
    /// QuadCell's comment above its rule carries the same arithmetic.
    readonly property real cellH: 55 + clockPane.clockTail
    /// The cells, with `pad` above and `pad` below. Written as `pad * 2` rather
    /// than as a sum of two literals so the two margins cannot drift apart: the
    /// top one has to stay equal to the bottom one, because `pillMouse` is sized
    /// off the strip the top one leaves (see there) and a bare `pad` in each
    /// place is two chances to be wrong.
    ///
    /// The header band this replaced was `pillH` of rows plus a `headerGap`; both
    /// are gone, and the only thing above the panes now is the margin.
    readonly property real panelH: pad * 2 + cellH

    implicitWidth: panelW + room * 2
    // The panel plus its overshoot margin, plus `drop` for the top edge's
    // journey down to under the widget. At t=0 all of that is empty bar: the
    // window is `panelH + room + drop` tall with `pillH` of them painted, and the
    // rest is the margin the shape grows into.
    implicitHeight: panelH + room + drop

    // ---------------- data ----------------

    /// local wall clock. Drives every date/time line and the boot timestamp.
    property var now: new Date()

    /// [{ label, clock, delta, abbrev }] — the extra zones, from clock-panel.sh
    property var zones: []
    /// seconds since boot, from the same script
    property int upSecs: 0

    // One tick for the whole flyout. A timer per block would let the clock, the
    // date and the uptime disagree about what time it is for up to a second.
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    // clock-panel.sh prints "<uptime-secs>|<CityCode>\tHH:MM:SS\t<delta>\t<abbrev>|…"
    // on a single line, so SplitParser hands the whole thing over at once.
    Poll {
        id: clockPoll
        command: [Tokyo.scriptDir + "/clock-panel.sh"]
        interval: 1000
        active: root.open             // a closed flyout must cost nothing
        onResult: output => root.parse(output)
    }

    function parse(output) {
        const parts = String(output).split("|")
        if (parts.length < 2) return
        const secs = parseInt(parts[0], 10)
        if (!isNaN(secs)) root.upSecs = secs

        const list = []
        for (let i = 1; i < parts.length; i++) {
            const f = parts[i].split("\t")
            if (f.length < 4) continue
            list.push({ label: f[0], clock: f[1], delta: f[2], abbrev: f[3] })
        }
        root.zones = list
    }

    /// "3d 04h 12m" / "4h 07m" / "42m". Units are dropped from the top only, and
    /// what is left is zero-padded, so the number does not change width as the
    /// minutes tick over.
    function uptimeText() {
        const s = Math.max(0, root.upSecs)
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (d > 0) return d + "d " + String(h).padStart(2, "0") + "h " + String(m).padStart(2, "0") + "m"
        if (h > 0) return h + "h " + String(m).padStart(2, "0") + "m"
        return m + "m"
    }

    readonly property int upDays: Math.floor(Math.max(0, root.upSecs) / 86400)

    /// When the machine came up, derived rather than read: boot = now - uptime.
    readonly property var booted: root.upSecs > 0
        ? new Date(root.now.getTime() - root.upSecs * 1000)
        : null

    // ---------------- date helpers ----------------

    /// ISO 8601 week number (the "calendar week"): week 1 is the week that
    /// contains the first Thursday, and weeks run Monday to Sunday. Qt's
    /// formatDateTime has no token for it — the date line was rendering the
    /// literal "ww" — so the number is computed here.
    function weekNumber(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        const dow = t.getUTCDay() || 7
        t.setUTCDate(t.getUTCDate() + 4 - dow)
        const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
        return Math.ceil((((t - yearStart) / 86400000) + 1) / 7)
    }

    /// The 8 moon phases, glyph only. A local estimate, not an almanac:
    /// days since a known new moon (2000-01-06 18:14 UTC) modulo the mean
    /// synodic month (29.53 d), split into 8 slices. Right to within hours
    /// of a phase boundary — enough to name today's phase, not to plan an
    /// eclipse watch. The glyphs are the Weather Icons moon set in the
    /// bundled Nerd Font (verified present in the font file).
    function moonPhase(d) {
        const synodic = 29.530588853
        const knownNewMoon = Date.UTC(2000, 0, 6, 18, 14)
        let age = ((d.getTime() - knownNewMoon) / 86400000) % synodic
        if (age < 0) { age += synodic }
        const slice = Math.floor((age / synodic) * 8 + 0.5) % 8
        const glyphs = [
            "\uE38D", "\uE390", "\uE394", "\uE396",
            "\uE39B", "\uE39D", "\uE3A2", "\uE3A4"
        ]
        return glyphs[slice]
    }

    // ---------------- window / anchoring ----------------

    /// `pill` is the bar's Clock, for its measured width. `magnet` is that pill's
    /// 1x1 anchor dot, and it — not the pill — is what the window is anchored to:
    /// see the comment on `magnet` in Clock.qml.
    function toggleFor(pill, magnet) {
        if (root.open) {
            root.close()
            return
        }
        root.pill = pill
        root.anchor.item = magnet
        root.anchor.edges = Edges.Top
        root.anchor.gravity = Edges.Bottom
        // No margins, and the half-pill correction that used to live here is
        // gone on purpose.
        //
        // `Edges.Top` with no Left/Right edge puts the window's middle on the
        // anchor's middle, which is what a morph wants: the anchor is a 1x1 dot on
        // the pill's centre line (see Clock.qml's `magnet`), so the panel's
        // centre lands on the pill's centre however the bar lays itself out.
        // Measured with the shape's fill made opaque for the measurement: the
        // open panel spans 728.50..1190.50, centre 959.50, which is the closed
        // pill's own centre to the pixel.
        //
        // There was a `margins.left = -pillW` here for a day and a half, undoing
        // a half-pill error that was not in quickshell at all: it was this
        // config's own doing. Bar.qml hid the pill while the flyout was open —
        // first with `visible: false`, then with `opacity: 0` — and a hidden item
        // is skipped by the layout that positions it, so the popup's anchor was
        // read at an instant when the pill's geometry was mid-flight and the
        // panel landed up to half a pill off in whichever direction that pass
        // happened to fall. Opacity fixed the layout; not hiding the pill at all
        // fixed the rest. The panel now hangs *under* the widget rather than
        // taking its place, so there is nothing to hide — the two are on
        // different pixels, and the shape slides off the pill to get there.
        //
        // `pillW` is an implicit width rather than a laid-out one for the same
        // reason it was before: a hidden item's width is not a number to design
        // a shape from, and the implicit width is the same binding on every
        // layout pass.
        root.closing = false
        root.t = 0
        // Read the bar's hover flag *here*, while the bar's MouseArea is still
        // the one under the pointer: the click that opens this arrives through
        // it, and a frame later the popup owns the pointer and the bar hears
        // nothing more.
        root.hoverCarry = root.pill !== null && root.pill.hovered
        root.open = true
        root.visible = true
        // Do not wait out the poll interval for data that is already stale.
        clockPoll.refresh()
        openAnim.restart()
    }

    function close() {
        if (!root.open || root.closing) return
        root.closing = true
        closeAnim.restart()
    }

    /// Tear the surface down once the shape is a pill again. `open` goes first,
    /// so the bar's pill has stopped being lit from here before this surface
    /// stops being the thing drawing over it.
    function hide() {
        root.closing = false
        root.open = false
        root.visible = false
    }

    // A flyout dismissed by an outside click never reaches `hide()`: the
    // compositor closes an xdg_popup itself, and the surface is already gone by
    // the time we hear about it. So there is nothing left to animate — just drop
    // `open`, which unlights the pill, and forget the morph.
    onVisibleChanged: {
        if (visible) return
        if (root.open) {
            openAnim.stop()
            closeAnim.stop()
            root.closing = false
            root.open = false
            root.t = 0
        }
        // A dismissed flyout must not come back with the last half-typed timer
        // still in the form.
        timerPanel.reset()
    }

    // One curve, both directions. The fly-in is the fly-out played backwards:
    // OutQuart over 200 ms, which is exactly the time-reverse of the InQuart
    // 200 ms below. The panel therefore looks the same going up as coming down
    // — the same motion, reversed — instead of opening on a springy overshoot
    // that the close never had, which read as the panel being *placed* rather
    // than *drawn out of the pill*.
    SequentialAnimation {
        id: openAnim
        NumberAnimation {
            target: root; property: "t"
            from: 0; to: 1
            duration: 200
            easing.type: Easing.OutQuart
        }
    }

    // Exits are quicker than entrances. No `from`: the animation starts from
    // wherever `t` actually is, which is the only way a close can interrupt a
    // half-finished open without a jump.
    SequentialAnimation {
        id: closeAnim
        NumberAnimation {
            target: root; property: "t"
            to: 0
            duration: 200
            easing.type: Easing.InQuart
        }
        ScriptAction { script: root.hide() }
    }

    // Escape closes, which has to be a `Shortcut` rather than a `Keys` handler.
    // A `Keys` attached property only sees the key if some item in the window
    // holds the focus, and with the timer form empty and the form's field
    // unfocused, nothing in this popup does — so `Keys.onEscapePressed` further
    // down (which is still right, and is what catches Escape once the field has
    // focus) never ran. A window shortcut is matched against the window, and a
    // popup holding the keyboard grab *is* the active window. It also beats the
    // field: Qt resolves shortcuts before ordinary key propagation, so Escape
    // closes the panel instead of being swallowed by a text field that ignores
    // it. `ApplicationShortcut` would be wrong — that is for shortcuts that must
    // work while *another* window is focused, which is not what this is.
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: root.close()
    }

    // ---------------- the shape ----------------

    /// How much of the pill's hover highlight the shape is still carrying.
    /// `Module` paints a hovered pill `hoverBg` rather than `pillBg`, and the
    /// click lands while the pointer is sitting on it — so at t=0 the shape has
    /// to *be* the hovered pill, or the widget visibly cools off under the
    /// cursor on the very click that opens it. Faded out by t, because a
    /// `panelW` x `panelH` panel does not go hover-highlighted, and back in on
    /// the way down so the pill that reappears under the pointer still looks
    /// hovered.
    ///
    /// It reads `hoverCarry`, not `pillMouse.containsMouse`, and the reason is
    /// the one thing a MouseArea's hover state cannot do: report a pointer it
    /// never heard about. `containsMouse` only changes on a *motion* event, and
    /// the common case here is a popup mapping under a pointer that has not
    /// moved since it arrived on the pill — so the fresh read is "not hovered",
    /// the shape starts its 300 ms life one shade off the widget it just
    /// replaced, and the glyph on it comes up in the resting colour instead of
    /// the cyan the bar was showing a frame earlier.
    ///
    /// So the hover the bar's pill was carrying is latched at the click, from
    /// the bar's own flag, and `pillMouse` is only there for the pointer that
    /// does wander into the panel's top margin while the panel is open.
    ///
    /// This is a fade, not a switch: at t=0 the shape is fully
    /// `Tokyo.panelHover` and by t=1 it is `Tokyo.panelFill`, which is what
    /// spends a highlight the bar's pill is still carrying and lets the panel be
    /// a panel by the time the panes have faded in. Measured with the animation
    /// slowed down, before the fill went opaque: the shape came up #2f334d
    /// where the resting pill is #2c3149. It is a bigger step now — the highlight
    /// is 30 units of RGB rather than 0.1 of alpha — and it is worth knowing
    /// that the shape is therefore *lighter* than the hovered bar pill for its
    /// first frames. That was read as the widget lighting up when the bar's pill
    /// vanished under the shape; it is less certain now that the pill is still
    /// there beside it, and `Tokyo.panelHover` is the one value here that is a
    /// taste call rather than a measurement. `panelFill` is the dial-down if the
    /// two shapes read as a seam.
    ///
    /// The bar's pill is *also* lit while this is open, via `pillLit`, so the
    /// widget stays highlighted the way it was at the click. The fill fade and
    /// that flag are not the same job: this one is the shape, that one is the
    /// pill underneath it.
    readonly property real hoverTint: (root.hoverCarry || pillMouse.containsMouse)
        ? Math.max(0, 1 - root.t) : 0

    /// Linear mix of two colours. Clamped because `t` overshoots to 1.04 on
    /// purpose and Qt.alpha, handed 1.008, does not clip it — it complains, once
    /// per frame, for every frame of the settle.
    function mix(a, b, f) {
        f = Math.max(0, Math.min(1, f))
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f,
                       a.b + (b.b - a.b) * f, a.a + (b.a - a.a) * f)
    }

    // Declared first so it sits *under* everything: a click that the panel's own
    // controls did not take should close the panel, and a click in the window's
    // transparent margin should too. Over the panel itself it does nothing.
    MouseArea {
        anchors.fill: parent
        onClicked: m => {
            if (m.x < shape.x || m.y < shape.y
                || m.x > shape.x + shape.width
                || m.y > shape.y + shape.height)
                root.close()
        }
    }

    // ---------------- the joint ----------------
    //
    // The widget's bottom edge and the panel's top edge are the same line, and
    // both of them round it away: the widget in the bar's window, the panel in
    // this one. The two roundings meet at a cusp — the widget's corner arc
    // arrives at the joint travelling rightwards and the panel's top edge
    // leaves it travelling leftwards, so the outline doubles back on itself and
    // the widget's corner tapers to a point resting on a flat line. That cusp
    // is the whole seam, and neither half can be given up: the widget's corner
    // belongs to the widget, the panel's to the panel, and they are painted by
    // two components in two windows.
    //
    // So the corner is added back here, in this window, over the bar: the
    // widget's own corner squared off in its own colour, and a fillet sweeping
    // the panel's top edge up into the widget's side. Both are cuts from the
    // outline rather than a shape of their own, and what is left of the joint
    // is one arc — the widget's side, the fillet, the panel's top edge — with
    // the same vertical tangent at one end and the same horizontal tangent at
    // the other, and no corner anywhere along it.
    //
    // Neither piece is faded in, and that is the part that took the thinking.
    // The joint's resting place is a constant and the morph moves the top edge
    // for 150ms, so anything drawn at the resting place and faded in at the end
    // spends those 150ms hovering above an edge that is still six rows short of
    // it — the shoulder comes in as a wedge hanging in the bar, which is the
    // silhouette this whole arrangement exists to lose, only fainter. Tied to
    // the edge instead, both pieces are simply *at* the joint in every frame:
    // the fillet's radius is the edge's own distance from the widget's top (see
    // `fillet`), and the patch is as strong as the part of the corner the shape
    // has uncovered (see `patchMix`).
    Item {
        // The joint is the top strip of the window: the widget's own rows, which
        // the shape's top edge spends the morph uncovering.
        width: root.implicitWidth
        height: root.drop

        // Below `shape`, so the shape's own top edge is what reveals these,
        // edge-first, exactly as it reveals the panel. In front, the fillet
        // would hang over the bar as a wedge of panel colour with the shape's
        // fill behind it.

        // The fillet: the corner cut out from between the widget's side and the
        // panel's top edge, in the shape's own fill, so the panel's top edge
        // runs up and over into the widget's side instead of stepping out to
        // it. The path is that corner minus a quarter disc of radius `fillet`,
        // which is the only arc tangent to both edges — hence the same
        // `fillet` twice, and `shape.y` twice as the tangent edge.
        //
        // The colour is read off `shape` rather than rebuilt from Tokyo, so the
        // shoulder is never a shade behind the panel it is part of.
        //
        // `strokeWidth: 0` on both paths is load-bearing, not tidiness: a
        // ShapePath left at its defaults strokes itself, and the stroke this Qt
        // build reaches for is a two-pixel band of opaque white. Measured here
        // on the left fillet, which carries the explicit zero: no white pixel
        // anywhere along 44 rows; the mirrored path without it, 155.
        Shape {
            anchors.fill: parent
            ShapePath {
                fillColor: shape.color
                strokeWidth: 0
                PathSvg {
                    path: `M ${face.x} ${shape.y - root.fillet} A ${root.fillet} ${root.fillet} 0 0 1 ${face.x - root.fillet} ${shape.y} L ${face.x} ${shape.y} Z`
                }
            }
            ShapePath {
                fillColor: shape.color
                strokeWidth: 0
                PathSvg {
                    path: `M ${face.x + root.pillW} ${shape.y - root.fillet} A ${root.fillet} ${root.fillet} 0 0 0 ${face.x + root.pillW + root.fillet} ${shape.y} L ${face.x + root.pillW} ${shape.y} Z`
                }
            }
        }

        // The widget's own bottom corner, squared off, and *after* the fillet so
        // that the fillet's inner edge lands on the widget's fill rather than on
        // this patch's. A rect and not a path: the corner is a `pillRadius`
        // square, and the crescent of that square the widget already paints is
        // the widget's own colour, so filling the square squares the corner and
        // touches nothing else.
        //
        // `pill.color`, not a Tokyo token, so it follows the widget through its
        // own hover state — the panel is open, so the widget is lit, and a
        // patch in the resting colour is a step in the widget's own corner. The
        // fallback is a standalone preview, which has no bar to ask.
        //
        // `patchMix` on both, because until the shape's edge is level with the
        // widget's bottom the shape is painting over this corner in its own fill
        // and the patch would be double-covering it: at full strength from the
        // first frame it is a lit square sitting on top of the panel's own rows
        // for two thirds of the morph.
        Rectangle {
            x: face.x
            y: root.drop - Tokyo.pillRadius
            width: Tokyo.pillRadius
            height: Tokyo.pillRadius
            opacity: root.patchMix
            color: root.pill !== null ? root.pill.color : Tokyo.pillBg
        }
        Rectangle {
            x: face.x + root.pillW - Tokyo.pillRadius
            y: root.drop - Tokyo.pillRadius
            width: Tokyo.pillRadius
            height: Tokyo.pillRadius
            opacity: root.patchMix
            color: root.pill !== null ? root.pill.color : Tokyo.pillBg
        }
    }

    Rectangle {
        id: shape
        // Centred in the window, and the window is centred on the pill, so the
        // shape's centre is the pill's centre at every value of `t`: the growth
        // is symmetric, and the face — drawn outside the clip, below — never
        // moves by so much as a pixel. Verified by screenshot, on a freshly
        // launched process driven by a real click: the open panel's fill spans
        // 728.50..1190.50 and the closed pill's 914.50..1004.50 — centres 959.50
        // both, in every frame of the burst, the 1.04 overshoot included.
        x: (root.implicitWidth - width) / 2
        // The one thing here that is a function of `t` and not a lerp between a
        // pill's number and a panel's: the top edge walks down exactly as far as
        // the pill is tall, so the open panel hangs *under* the widget rather
        // than taking the widget's row for itself. At t=0 this is 0, which is the
        // pill's top edge, so the shape is still the pill's rect on the frame the
        // click lands.
        //
        // Capped at t=1 and not left to follow the 1.04 overshoot, deliberately:
        // an overshooting top edge would push the panel's top row back up into
        // the bar's padding, which is a joint re-opening. The bottom edge
        // overshoots instead, so the panel still breathes past its resting size.
        //
        // This *is* the top edge sliding down out of the bar, and it was tried
        // once and thrown out — but that was a different shape: a narrow tab
        // bridging a gap, with the panel a second rectangle below it. That had
        // two joints to be wrong about, one of which (the tab's square top
        // corners) existed only because the pill whose rounded bottom they used
        // to be was no longer drawn. This is one rectangle with both edges
        // moving, and the widget it comes off is still drawn the whole way.
        //
        // What did have to go, and was the reason it could not be done before:
        // the panel's top is no longer the widget's own row. The label was the
        // panel's first `pillH` rows and the digits the window's, so at rest the
        // two were adjacent rather than coincident, and the label only ever came
        // near them as the shape uncovered it. There is nothing left up there to
        // replace — it is `pad` of margin now, and the reading is the widget's
        // alone. The widget reads the clock, the panel is where the clock is read.
        y: root.drop * Math.min(1, root.t)
        // Capped against the window's own height, so the settle's overshoot
        // cannot push the last fraction of a pixel off the surface.
        width: Math.min(root.implicitWidth, root.pillW + (root.panelW - root.pillW) * root.t)
        height: Math.min(root.implicitHeight, root.pillH + (root.panelH - root.pillH) * root.t)
        // The pill's corner at t=0, the panel's at t=1: the same corner opening
        // out as the shape grows, so the shape reads as one thing resizing
        // rather than a rectangle that was edited. All four corners move
        // together, including the two at the top, which are the widget's own —
        // so the widget's outline rounds out as it opens instead of popping.
        // Both tokens are 10 (the Hyprland window radius), so this is a
        // constant today and the corner does not animate; the growth and the
        // joint carry the morph instead. Dial one token and the run returns.
        radius: Tokyo.pillRadius + (Tokyo.panelRadius - Tokyo.pillRadius) * root.t
        // The pill's own background, for the whole morph and not just at t=0 —
        // plus whatever hover highlight the pill was carrying, which the morph
        // spends. `panelFill`/`panelHover` rather than `pillBg`/`bgHighlight`:
        // the panel is the pill, grown, so the fill is pinned to the colour the
        // lit bar pill actually is (opaque #2f334d) and the highlight to a real
        // step in RGB, because an opaque fill cannot express the old alpha-only
        // difference. See both in Tokyo.qml.
        color: root.mix(Tokyo.panelFill, Tokyo.panelHover, root.hoverTint)
        // No border, and that is load-bearing twice over. A Rectangle's border
        // is drawn *inside* its rect, so a 1px stroke would shrink the fill: at
        // t=0 the shape would be a pixel narrower and shorter than the pill it
        // is standing in for, and the stroke itself would sit one pixel above
        // the clock's cap height — a hairline ruled across the top of the
        // digits, which is what a border there reads as. Without one the rect
        // *is* the painted area: t=0 is the pill's rect exactly, and the
        // content below is laid out against the same edges with nothing
        // clipped.
    }

    // Everything that is *panel* rather than *pill*: clipped to the shape and
    // faded in behind it. The clock face is deliberately not in here — it has to
    // hold still on the widget's own pixels while the shape grows away from
    // under it, and a clip that moves with the shape would drag it sideways for
    // the length of the animation.
    //
    // This item is the shape's own rect, so the clip *is* the shape: the panel
    // gets revealed edge-first as the blob widens, the way the pill's own
    // corners opened in Caelestia. What is inside it is laid out at its final
    // size and never resized — an earlier version had the grid track the shape's
    // width, which meant the two cells were squeezed to 69px and back for
    // 300ms, re-wrapping every label and reflowing the timer list on each frame.
    // A morph that reflows its own contents reads as a layout bug, not a blob.
    Item {
        id: panel
        x: shape.x
        y: shape.y
        width: shape.width
        height: shape.height
        clip: true
        opacity: Math.max(0, Math.min(1, (root.t - root.contentIn) / 0.5))

        // The panel's own coordinate space: the *final* `panelW` x `panelH`
        // rectangle, in
        // window coordinates, so nothing inside it moves by so much as a pixel
        // while the shape grows around it. `x` is the final shape's left edge
        // expressed in the shape's own — still moving — coordinates. The two are
        // easy to confuse: `panel` is already offset by `shape.x`, so a child
        // placed in window coordinates lands `room` to the right of where it
        // belongs, which is how the panes ended up shoved off-centre and the
        // right-hand one clipped by the shape.
        Item {
            id: panelSpace
            x: (shape.width - root.panelW) / 2
            y: 0
            width: root.panelW
            height: root.panelH

            // The timers form takes a text field, and the popup holds the keyboard
            // (grabFocus) rather than a layer panel, so the field only needs an
            // explicit focus — no compositor trickery. Escape arrives here by
            // propagating up the item chain from the field, which ignores it; the
            // handler has to sit on an Item, not on the Window, to be in that chain.
            //
            // That chain only exists while something in the popup *has* focus,
            // though, and with the form empty nothing in here does — so this
            // handler, on its own, was dead code: Escape did nothing at all with
            // the panel open (verified with a temporary IPC read-out of
            // `open`/`visible`/`t`: the press left every one of them untouched),
            // and neither does an xdg_popup get dismissed by the compositor on
            // Escape, so there was no second route. `Shortcut` below is the one
            // that works: it is matched against the window rather than against a
            // focus item, and a popup with a keyboard grab is the active window.
            Keys.onEscapePressed: root.close()

            // The panel used to open with a `time and date` label on the pill's
            // own 26 rows and a 1 px rule under it. Both are gone, and what is
            // left above the panes is `pad` — the same margin the panel already
            // had on its other three sides, so 12 is this panel's margin and no
            // new constant is warranted.
            //
            // It is not a `pad` for looks. Flush was tried and it broke two
            // things at once: `pillMouse` is a later sibling of `panel` and so
            // topmost, and a `pillH` strip off the shape covers cell y 0..26 —
            // the whole of `headerRow`, from QuadCell's `pad` 10 to
            // `pad` + `headerH` 24, and the top 20 of the 22 the `PillButton`s
            // are — so pressing either one closed the flyout. And a pane flush
            // with the panel's own edge does not read as a bordered card:
            // `paneEdge` is drawn, but with no air on its outside it is the
            // panel's outline rather than the pane's. One inset fixes both, and
            // the strip it leaves is bare panel fill — which is what a
            // click-to-close target wants to be.
            GridLayout {
                id: grid
                x: root.pad
                y: root.pad
                width: root.panelW - root.pad * 2
                columns: 2
                columnSpacing: root.cellGap

                // ================= 1. timers =================
                QuadCell {
                    title: "TIMERS"
                    accent: Tokyo.magenta
                    Layout.preferredWidth: root.cellW
                    Layout.preferredHeight: root.cellH

                    // The two bulk controls ride in the title row, the one place a
                    // cell gets for something that is not the cell's own content.
                    // The pair is a pause/resume toggle plus a stop — the same two
                    // controls every row already carries one at a time, so the
                    // title row reads as their row-level version rather than a new
                    // vocabulary.
                    //
                    // The glyph is the *state*, not the action, exactly as a row's
                    // is: play while something is running, pause once nothing is.
                    // Reading it the other way round — showing what the press will
                    // do — would make one glyph mean "running" in a row and
                    // "paused" in the title row of the same pane. `pausable` greys
                    // the toggle out when the list is nothing but finished timers,
                    // since a control that would do nothing is worse than none.
                    //
                    // Glyph-only because the labels do not fit: the title row is
                    // 194 px and "PAUSE ALL" + "STOP ALL" measure ~165 px between
                    // them before the pane title, so the title would be the thing
                    // that has to go. Both glyphs are already on every timer row,
                    // so nothing new has to be learned to read them.
                    headerExtra: Row {
                        spacing: 6
                        visible: TimerState.active

                        PillButton {
                            glyph: TimerState.running.length > 0 ? "\uf04c" : "\uf04b"
                            accent: Tokyo.yellow
                            enabled: TimerState.pausable
                            onClicked: TimerState.pauseAll()
                        }
                        PillButton {
                            glyph: "\uf068"        // times
                            accent: Tokyo.magenta
                            onClicked: TimerState.stopAll()
                        }
                    }

                    // The full panel, not a summary: this is where a timer is
                    // actually set. The list runs down to the slider and the form is
                    // pinned to the bottom of the pane, so what is running and what
                    // to set are the two ends of one pane.
                    //
                    // The pane is as tall as the *clock* pane's three stacked
                    // blocks. Rather than centring the whole thing — which put the
                    // form in the middle of nowhere — the form is pinned to the
                    // bottom, and the row cap is left to `TimerPanel` to derive from
                    // the space between them. It used to be a hard-coded two rows,
                    // which was right for the old square cell and left a 160 px hole
                    // in a pane twice that size.
                    TimerPanel {
                        id: timerPanel
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        pinFormToBottom: true
                        onFieldActivated: timerPanel.focusField()
                    }
                }

                // ================= 2. clock / date / uptime =================
                QuadCell {
                    id: clockPane
                    title: "CLOCK"
                    accent: Tokyo.blue
                    Layout.preferredWidth: root.cellW
                    Layout.preferredHeight: root.cellH

                    // Three blocks stacked in one pane, in the order they are asked
                    // for: what time is it (here and elsewhere), what day is it,
                    // how long has this been up.
                    //
                    // The three old cell titles survive as 9 px block labels in
                    // their original accent colours. Losing them would leave the
                    // pane reading as one undifferentiated column — and the colour
                    // coding is the only thing that says which number is a
                    // timezone and which is a boot time at a glance.
                    Item {
                        id: clockBody
                        anchors { left: parent.left; right: parent.right; top: parent.top }

                        // ---------- block 1: local time + other zones ----------
                        Item {
                            id: timeBlock
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            // measured off the last child, never an implicit height:
                            // the blocks are plain Items, so an unset `height` would
                            // make `bottom` collapse onto `top` and the next block
                            // would land on top of this one
                            readonly property real tail: zonesArea.y + zonesArea.height
                            height: tail

                            Text {
                                id: timeLabel
                                anchors { left: parent.left; top: parent.top }
                                text: "TIME"
                                color: Tokyo.blue
                                font { family: Tokyo.fontFamily; pixelSize: 9; bold: true; letterSpacing: 1.5 }
                            }

                            Text {
                                id: localClock
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: timeLabel.bottom; topMargin: 5
                                }
                                text: Qt.formatDateTime(root.now, "HH:mm:ss")
                                color: Tokyo.fg
                                font { family: Tokyo.fontFamily; pixelSize: 28; bold: true; letterSpacing: 0.5 }
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                id: rule
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: localClock.bottom; topMargin: 6
                                }
                                height: 1
                                color: Tokyo.hairline
                            }

                            // A plain Item, not a Column: the rows are placed
                            // by hand (fixed columns, see the delegate below),
                            // because a positioner nested in a positioner is
                            // exactly what leaves children stacked at y=0 when
                            // Qt polishes the outer one first (see TimerCreator.qml).
                            Item {
                                id: zonesArea
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: rule.bottom; topMargin: 8
                                }
                                readonly property real rowH: 22
                                height: root.zones.length > 0
                                    ? root.zones.length * rowH
                                    : waiting.implicitHeight

                                Repeater {
                                    model: root.zones
                                    delegate: Item {
                                        id: zoneRow
                                        required property var modelData
                                        required property int index

                                        readonly property var zone: modelData
                                        readonly property bool ahead: String(zoneRow.zone.delta).charAt(0) === "+"
                                        readonly property bool behind: String(zoneRow.zone.delta).charAt(0) === "-"

                                        width: zonesArea.width
                                        height: zonesArea.rowH
                                        y: index * zonesArea.rowH

                                        // Fixed columns, driven from the left, so the abbreviation column
                                        // falls under itself on every row. The old
                                        // layout anchored the abbrev to the delta's
                                        // *implicit* width, and "same" (4 glyphs) is
                                        // 6 logical px wider than "+1d" (3), so a zone
                                        // on another calendar day had its abbreviation
                                        // one notch to the right of the others.
                                        Text {
                                            id: city
                                            anchors {
                                                left: parent.left
                                                verticalCenter: parent.verticalCenter
                                            }
                                            width: 32
                                            text: zoneRow.zone.label
                                            color: Tokyo.trayGlyph
                                            font { family: Tokyo.fontFamily; pixelSize: 11 }
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            id: abbrev
                                            anchors {
                                                left: city.right; leftMargin: 8
                                                verticalCenter: parent.verticalCenter
                                            }
                                            width: 24
                                            text: zoneRow.zone.abbrev
                                            color: Tokyo.dim
                                            font { family: Tokyo.fontFamily; pixelSize: 9 }
                                        }
                                        // Accented only when that zone is on another
                                        // calendar day, which is the entire point of
                                        // the column: "is it tomorrow over there?"
                                        // Right-aligned in a fixed slot so "same" and
                                        // "+1d" share a right edge and the columns on
                                        // either side of it never move.
                                        Text {
                                            id: delta
                                            anchors {
                                                left: abbrev.right; leftMargin: 8
                                                verticalCenter: parent.verticalCenter
                                            }
                                            width: 30
                                            text: zoneRow.zone.delta === "0" ? "same" : zoneRow.zone.delta + "d"
                                            color: zoneRow.ahead ? Tokyo.green
                                                : (zoneRow.behind ? Tokyo.magenta : Tokyo.dim)
                                            font { family: Tokyo.fontFamily; pixelSize: 10 }
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text {
                                            id: zoneClock
                                            anchors {
                                                right: parent.right
                                                verticalCenter: parent.verticalCenter
                                            }
                                            text: zoneRow.zone.clock
                                            color: Tokyo.fg
                                            font { family: Tokyo.fontFamily; pixelSize: 13; letterSpacing: 0.5 }
                                        }
                                    }
                                }

                                // Shown only until the first script run lands, so the
                                // block is never blank while its data is in flight.
                                Text {
                                    id: waiting
                                    anchors { left: parent.left; top: parent.top }
                                    visible: root.zones.length === 0
                                    text: "reading timezones…"
                                    color: Tokyo.trayGlyph
                                    font { family: Tokyo.fontFamily; pixelSize: 10 }
                                }
                            }
                        }

                        // ---------- block 2: the full date ----------
                        Item {
                            id: dateBlock
                            anchors {
                                left: parent.left; right: parent.right
                                top: timeBlock.bottom; topMargin: 14
                            }
                            readonly property real tail: isoDate.y + isoDate.height
                            height: tail

                            Text {
                                id: dateLabel
                                anchors { left: parent.left; top: parent.top }
                                text: "DATE"
                                color: Tokyo.yellow
                                font { family: Tokyo.fontFamily; pixelSize: 9; bold: true; letterSpacing: 1.5 }
                            }

                            Text {
                                id: weekday
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: dateLabel.bottom; topMargin: 5
                                }
                                text: Qt.formatDateTime(root.now, "dddd")
                                color: Tokyo.fg
                                font { family: Tokyo.fontFamily; pixelSize: 24; bold: true }
                                elide: Text.ElideRight
                            }

                            Text {
                                id: fullDate
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: weekday.bottom; topMargin: 3
                                }
                                text: Qt.formatDateTime(root.now, "dd MMMM yyyy")
                                color: Tokyo.fg
                                font { family: Tokyo.fontFamily; pixelSize: 14 }
                                elide: Text.ElideRight
                            }

                            // The one-line date, compact: the format asked for
                            // (dd.mm.yyyy), the ISO calendar week number, and
                            // the current moon phase (glyph only).
                            Text {
                                id: isoDate
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: fullDate.bottom; topMargin: 3
                                }
                                text: Qt.formatDateTime(root.now, "dd.MM.yyyy")
                                    + "  ·  week " + root.weekNumber(root.now)
                                    + "  ·  " + root.moonPhase(root.now)
                                color: Tokyo.trayGlyph
                                font { family: Tokyo.fontFamily; pixelSize: 10 }
                                elide: Text.ElideRight
                            }
                        }

                        // ---------- block 3: uptime ----------
                        Item {
                            id: uptimeBlock
                            anchors {
                                left: parent.left; right: parent.right
                                top: dateBlock.bottom; topMargin: 14
                            }
                            readonly property real tail: daysLine.y + daysLine.height
                            height: tail

                            Text {
                                id: uptimeLabel
                                anchors { left: parent.left; top: parent.top }
                                text: "UPTIME"
                                color: Tokyo.teal
                                font { family: Tokyo.fontFamily; pixelSize: 9; bold: true; letterSpacing: 1.5 }
                            }

                            Text {
                                id: uptime
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: uptimeLabel.bottom; topMargin: 5
                                }
                                text: root.uptimeText()
                                color: Tokyo.fg
                                font { family: Tokyo.fontFamily; pixelSize: 28; bold: true; letterSpacing: 0.5 }
                                elide: Text.ElideRight
                            }

                            // When it was read, and how much of it there is: the
                            // uptime number alone does not say whether a reboot is
                            // 20 minutes or 20 hours old.
                            Text {
                                id: bootedLine
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: uptime.bottom; topMargin: 3
                                }
                                // Re-worded, never hidden: an anchor bound to a
                                // conditional keeps the value it was first given
                                // (the rule above the timer creator froze on its
                                // idle value for the same reason), and the pane's
                                // height is measured off this block — so hiding it
                                // would both freeze `daysLine` and make the whole
                                // panel jump 18 px when the script's first result
                                // landed.
                                text: root.booted === null
                                    ? "reading boot time…"
                                    : "booted " + Qt.formatDateTime(root.booted, "ddd dd MMM HH:mm")
                                color: Tokyo.trayGlyph
                                font { family: Tokyo.fontFamily; pixelSize: 11 }
                                elide: Text.ElideRight
                            }

                            Text {
                                id: daysLine
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: bootedLine.bottom
                                    topMargin: 3
                                }
                                text: root.upDays > 0
                                    ? root.upDays + (root.upDays === 1 ? " full day" : " full days")
                                        + " since boot"
                                    : "first day up"
                                color: Tokyo.trayGlyph
                                font { family: Tokyo.fontFamily; pixelSize: 10 }
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // What the pane actually needs, measured bottom-up off the last
                    // block. `cellH` adds QuadCell's own chrome to this; nothing
                    // reads a positioner's implicit height, because a positioner
                    // can be polished before its children exist and never polished
                    // again (see TimerCreator.qml) — and this stack is exactly the
                    // shape of thing that ends up a block too short.
                    readonly property real clockTail: uptimeBlock.y + uptimeBlock.tail
                }
            }
        }
    }

    // The widget's face, on the widget's own pixels, for as long as the shape's
    // top edge is still below it. Its x is written out longhand rather than
    // derived from `shape` on purpose: the widget does not move during the
    // morph, and the shape's width and y are both changing underneath it.
    //
    // This copy is not here because the bar's copy stands down — the bar's copy
    // never stands down any more. It is here because the shape *covers* the bar's
    // copy until its top edge has walked down past it, and a widget that loses
    // its clock on the click that opens it is the one pop this morph cannot
    // afford. Both copies are driven by one `glyphMix` and read one `now`, so
    // they are the same face at the same pixels in the same colour and which one
    // is drawing is not a thing you can see.
    //
    // Nothing fades it out at the end of the morph. It used to, over the last
    // fifth of `t`, to hand over to the bar's copy — which needed the shrink
    // with it, and the shrink was the tell, because a copy of a stationary thing
    // shrinking is a stationary thing changing size twice. The hand-over no
    // longer needs either: the two copies agree, so the only thing a fade bought
    // was one fewer redundant draw.
    ClockFace {
        id: face
        x: (root.implicitWidth - root.pillW) / 2
        y: 0
        width: root.pillW
        height: root.pillH
        now: root.pill !== null ? root.pill.now : root.now
        glyphMix: root.glyphMix
        // The same latched hover the shape's fill uses, for the same reason: the
        // face is cyan on the hovered pill in the bar, and it must not come back
        // in the resting colour for the frames it is still on screen.
        hovered: root.hoverCarry || pillMouse.containsMouse
    }

    MouseArea {
        id: pillMouse
        // On `shape`, not on `face`, because the thing to click is not the
        // widget any more — by the time the panel is open, the shape *is* the
        // panel's rect, so this one area covers the widget at t=0 and the panel
        // at t=1 without a second MouseArea, sliding down with the joint in
        // between.
        //
        // Its height is the part that has to be right, and it is not one number:
        // it is `pillH` closed, so the widget's own row is still clickable, and
        // `pad` open, so it is only the bare strip the top margin leaves. Left at
        // `pillH` it would still be 26 rows, and past the 12 rows of top margin
        // that is 14 rows into the cells: `headerRow` starts at QuadCell's `pad`
        // (10), so 4 of the 14 are title row, and the `PillButton`s start 4 above
        // that and are 22 tall, so 8 of the 14 are button. `pillMouse` is a later
        // sibling of `panel` and so topmost in the input stack, and a press up
        // there closed the flyout instead of pausing the timers.
        //
        // The ramp is `contentIn` and not `t`, and what decides it is the panes
        // rather than the strip. Ramped on `t` the strip is still over the
        // buttons' rows until `t` is 0.57, by which point the content is 44%
        // opaque, so a press in the opening frames would land on a button that
        // was on screen. On `t / contentIn` the strip is already down to `pad` on
        // the frame the content starts to fade in, so it is never over a row
        // anyone can see. Below `contentIn` the panes have no opacity at all, and
        // the strip is still the widget's own row there, which closed the panel
        // anyway.
        //
        // `min(1, ...)`, like `shape.y` above it: the burst overshoots to 1.04
        // and an unclamped strip would dip under `pad` on the settle, which is
        // the wrong side to be wrong on and buys nothing.
        //
        // `shape.x`/`shape.y`, not `shape.left`/`shape.top`: those are anchor
        // *lines* (QQuickAnchorLine) on any item Qt has anchored, and assigning
        // one to a qreal is 0 with no warning at all. `shape` is positioned by
        // hand rather than by anchors, so its `x` and `y` are the plain
        // coordinates they look like. This MouseArea once read `face.x` and
        // `face.y` off a face that *was* anchored, and sat at the window's left
        // edge, 202px from the thing it was meant to cover.
        x: shape.x
        y: shape.y
        // The shape's width, so the strip is as wide as whatever it is covering:
        // the pill's at t=0, the panel's at t=1. Also what `hoverTint` samples,
        // since the popup's surface sits over this rect and the bar's own
        // MouseArea goes quiet the moment the popup grabs the pointer.
        width: shape.width
        height: root.pillH + (root.pad - root.pillH) * Math.min(1, root.t / root.contentIn)
        hoverEnabled: true
        // The strip closes. It is what the panel is for and the strip is what
        // you reach for, and the toggle has to be reversible from the panel as
        // well as from the bar. (The widget's own row closes it too, by falling
        // outside the shape and hitting the catch-all above.) A click during the
        // close is a no-op: `close()` ignores it, which is what keeps the shape
        // from being re-run backwards halfway down.
        onClicked: root.close()
    }
}
