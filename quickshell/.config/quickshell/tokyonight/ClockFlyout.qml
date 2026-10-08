// ClockFlyout.qml — left-clicking the clock pill opens this: a 1x2 pair of
// cards holding everything the bar used to spread over four separate pills.
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
// same 452 px on two rows of 214 while the timer form — the one card with
// something to type into — was squeezed into a square. Collapsing the three
// time-ish cards into a single stacked card buys the timers card a full-height
// half of the panel without widening the flyout at all.
//
// One instance per bar window (created in Bar.qml), so it always opens on the
// monitor you clicked. `grabFocus` dismisses it on any outside click.
//
// WHERE IT SITS. It is *not* anchored to the pill that opened it, and it never
// was meant to be more than an item in the bar: an xdg_popup cannot float free,
// so the bar hands it `clockAnchor` — a zero-size Item at the top centre of the
// bar — and the popup hangs from that. `Edges.Top` with no Left or Right is the
// whole trick: quickshell's positioner reads "centred" from the absence of a
// horizontal edge, so with a zero-size anchor the popup's *top* lands on the
// marker's top edge, its middle on the screen's middle, and gravity Bottom
// expands it downward from there. The marker's own top edge is the bar's top
// edge, and `anchor.margins.top` (see `topGap`) then pushes the whole panel down
// clear of the bar — the offset belongs to the placement, so it is applied here
// and not baked into the bar's geometry. No reserved strip, no second surface
// and nothing to measure: the pill is nowhere near the popup and the two never
// share a pixel, which is what lets the pill just sit there showing the time the
// whole time this is open.
//
// This is SysFlyout.qml's shape, because SysFlyout.qml's *look* was the point.
// The outer box is `bgDark` / `pillRadius` / a 1px `bgHighlight` border, the two
// cards inside it are `bg` on `bgHighlight`, the insets and the gap between the
// cards are SysFlyout's own 8, labels are 10 bold ls 1.5 and figures are 13
// bold.
//
// ONE PLACE IT DOES NOT COPY SysFlyout, and it is the user's call: SysFlyout has
// no reveal at all, opening on a bare `visible = true`. This one flies in and
// flies back out, and it does it the way SettingsFlyout.qml and
// NotificationCenter.qml do — one number, `t`, that the whole panel is a
// function of. `t` is the only thing either direction writes; it moves the
// panel down into place and back up as `content.y`, and fades it as
// `content.opacity`, both on an inner Item. The window's `implicitWidth` and
// `implicitHeight` are static bindings that never change, because resizing an
// xdg_popup is a compositor round-trip per frame. Nothing about the pill's own
// contents moves, ever: that was the morph and it is gone.
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
import Quickshell
import Quickshell.Io

PopupWindow {
    id: root

    visible: false
    grabFocus: true
    color: "transparent"

    // ---------------- geometry ----------------

    // SysFlyout.qml:25-26 and :31, unchanged. This was 12/10 on the argument
    // that these cards are 62px wider than SysFlyout's and so want a looser
    // inset — the ratio says otherwise (12/214 against 8/132), and the user
    // looking at both panels side by side read it as thicker, not looser. One
    // figure for the family beats a defensible per-file one.
    readonly property real pad: 8
    readonly property real cellGap: 8
    readonly property real cellW: 214
    readonly property real panelW: pad * 2 + cellW * 2 + cellGap
    /// One row of two, so the panel is only as tall as its content. Nothing sets
    /// this number: it is *measured* off the clock card's three stacked blocks
    /// (see `clockTail`), because the block heights are font metrics and the
    /// zone count — three of them — is data. A hand-written constant here would
    /// be wrong the moment a zone is added, and a wrong constant is not a
    /// cosmetic bug: the bottom of the UPTIME block would be cut off.
    ///
    /// `chrome` is QuadCell's own figure, read rather than re-derived here. An
    /// earlier version spelled it out as the literal 55, which was a second copy
    /// of QuadCell's arithmetic living in a file that does not own it: editing
    /// either side alone still compiled, still loaded, and still rendered — it
    /// just quietly cut the bottom off the UPTIME block. There is nothing to keep
    /// in sync now.
    ///
    /// `chrome` is a frame constant, not the card's height: cellH is chrome plus
    /// `clockTail`, so the body the cards actually get is the tail either way and
    /// raising the chrome does not shrink the clock card's content. That is also
    /// what keeps the two cards the same height while their frame grows under
    /// them.
    readonly property real cellH: clockPane.chrome + clockPane.clockTail
    /// The cards, with `pad` above and `pad` below. Written as `pad * 2` rather
    /// than as a sum of two literals so the two margins cannot drift apart.
    readonly property real panelH: pad * 2 + cellH

    /// The window is the panel. No transparent margin around it and no strip
    /// reserved below it: it opens already placed (see `topGap`), and there is
    /// nothing inside the window for a margin to be room for.
    implicitWidth: root.panelW
    implicitHeight: root.panelH

    // ---------------- anchoring ----------------

    /// The bar's zero-size screen-top-centre marker (Bar.qml: clockAnchor)
    property var anchorItem: null

    /// How far below the bar the panel hangs. It lives here, not as a margin on
    /// `clockAnchor`, because it is a property of the *placement* and not of the
    /// marker: the marker says where on screen the panel is centred, and the gap
    /// below the bar is this panel's business. Putting it on the marker instead
    /// made a figure that tunes this popup look like it belonged to the bar's
    /// layout, so tidying it to 0 produced no error and the panel jumped up under
    /// the bar's pills — and a bar moved to the bottom of the screen would have
    /// opened it mid-screen.
    readonly property real topGap: Tokyo.barHeight + Tokyo.edgeGap

    /// The bar's Clock, read for its `now` so the panel's seconds and the pill's
    /// seconds are the same Date. May be null in previews — see `clock`.
    property var pill: null

    // `Top` alone on both edges and `Bottom` for gravity is the reading that hangs
    // the panel from the marker's top edge while leaving its horizontal placement
    // centred — quickshell centres when no Left or Right edge is named.
    //
    // `PopupAdjustment.None`, not Toast.qml's `All`. `All` is Flip | Slide |
    // Resize, and FlipY inverts the vertical gravity: if the panel ever grew past
    // the space below `topGap`, the compositor would flip it to hang UPWARD off
    // the top of the screen. That is not hypothetical here — `cellH` is measured
    // off font metrics and `clockTail` grows by a whole 22px row per timezone
    // added, so the height is data, not a constant. The horizontal axis does not
    // have that problem: the panel is centred on a full-width bar, so a
    // horizontally flipped or slid popup could never be the lesser evil, and
    // `None` keeps the placement above exactly as written instead of letting the
    // compositor reinterpret it on a monitor it thinks is too small.
    Component.onCompleted: {
        root.anchor.item = root.anchorItem
        root.anchor.edges = Edges.Top
        root.anchor.gravity = Edges.Bottom
        root.anchor.margins.top = root.topGap
        root.anchor.adjustment = PopupAdjustment.None
    }

    // ---------------- data ----------------

    /// Local wall clock, and the fallback for `clock` when no bar handed over a
    /// pill. Reads it directly and nothing else should: its timer only runs in
    /// that case, so outside a standalone preview this value never advances.
    property var now: new Date()

    /// [{ label, clock, delta, abbrev }] — the extra zones, from clock-panel.sh
    property var zones: []
    /// seconds since boot, from the same script
    property int upSecs: 0

    // One tick for the whole flyout. A timer per block would let the clock, the
    // date and the uptime disagree about what time it is for up to a second.
    // Only while it is actually the source of truth, though — see `clock`.
    Timer {
        interval: 1000
        repeat: true
        running: root.pill === null
        onTriggered: root.now = new Date()
    }

    /// The one clock this panel reads, for every date and time line in it. The
    /// bar's pill owns the tick whenever there is one, so the fallback timer above
    /// does not run in the real shell at all.
    readonly property var clock: root.pill !== null ? root.pill.now : root.now

    // clock-panel.sh prints "<uptime-secs>|<CityCode>\tHH:MM:SS\t<delta>\t<abbrev>|…"
    // on a single line, so SplitParser hands the whole thing over at once.
    Poll {
        id: clockPoll
        command: [Tokyo.scriptDir + "/clock-panel.sh"]
        interval: 1000
        active: root.visible          // a closed flyout must cost nothing
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
        ? new Date(root.clock.getTime() - root.upSecs * 1000)
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

    // ---------------- open / close ----------------

    /// Three states, not two, because the close is now a gesture and a gesture
    /// takes time: open, shut, and closing. That middle state is the only reason
    /// `closing` exists — without it a second click during the exit restarts the
    /// close from wherever `t` had got to and the panel visibly stutters.
    ///
    /// `t = 0` before the reveal starts because a property animation applies
    /// `from` on its first update, and that update is the frame *after* the window
    /// is already up: without this line the panel shows at rest for one frame and
    /// then yanks itself up 10px and back down, which reads as a glitch rather
    /// than as an animation.
    ///
    /// `root.pill` is read again on every toggle, because the pill is the bar's
    /// own widget and `clock` reads its `now` through it. `refresh()` before the
    /// surface goes up, not after: a zone row showing the sample from up to a
    /// second before the click is a row showing a lie.
    function toggleFor(pill) {
        root.pill = pill
        if (!root.visible) clockPoll.refresh()
        // Re-assert the anchor on every open, as SysFlyout does. 0.3.1 only
        // computes the position when the window is first shown, so a marker that
        // has moved since construction would place the panel from a stale
        // rectangle. `clockAnchor` is pinned to static bar geometry so this is
        // belt-and-braces, not a live bug — but it is one line, and it is the
        // self-healing the pre-morph code had.
        root.anchor.item = root.anchorItem
        if (root.closing) {
            // A close is in flight: this click reverses it rather than opening a
            // second panel, which is what a plain visible toggle would do.
            closeAnim.stop()
            root.closing = false
            root.t = 0
            openAnim.start()
            return
        }
        if (root.visible) {
            root.closing = true
            closeAnim.start()
            return
        }
        root.visible = true
        root.t = 0
        openAnim.start()
    }

    /// Escape and the outside click both land here. `closing` goes true first so
    /// a second Escape cannot restart the exit mid-flight; `closeAnim` runs `t`
    /// back to 0 and calls `hide()` itself, so nothing here touches `visible` —
    /// setting it here would cut the panel off mid-slide and leave `t` stranded
    /// above 0 for the next open.
    function close() {
        if (root.closing) return
        root.closing = true
        closeAnim.start()
    }

    // A flyout dismissed by an outside click never runs anything of ours: the
    // compositor closes an xdg_popup itself, and the surface is already gone by
    // the time we hear about it. So there is nothing to animate — but `t` and
    // `closing` still have to go back to their start values, or the next open
    // begins halfway through a reveal that is no longer running, and `closing`
    // stays latched so the first Escape after it does nothing at all.
    onVisibleChanged: {
        if (visible) return
        openAnim.stop()
        closeAnim.stop()
        root.closing = false
        root.t = 0
        timerPanel.reset()
    }

    // Escape closes, and it is a `Shortcut` and nothing else. A `Keys` attached
    // property only sees the key if some item in the window holds the focus, and
    // with the timer form empty nothing in this popup does — so a `Keys` handler
    // is dead exactly when the panel has just opened. A window shortcut is matched
    // against the window instead, and a popup holding the keyboard grab *is* the
    // active window. It also beats the field: Qt resolves shortcuts before
    // ordinary key propagation, so Escape closes the panel rather than being
    // swallowed by a text field that ignores it — which means a `Keys` fallback
    // for the focused-field case would never run anyway, and there is only one
    // path to reason about. `ApplicationShortcut` would be wrong — that is for
    // shortcuts that must work while *another* window is focused.
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: root.close()
    }

    // ---------------- the surface ----------------

    /// How far above its resting place the panel sits while it is shut. Big
    /// enough to read as movement rather than as a dissolve, small enough that
    /// the whole panel is still mostly on screen while it happens.
    readonly property real slideFrom: 10

    // ---------------- the reveal ----------------
    // The same one-number reveal SettingsFlyout.qml and NotificationCenter.qml
    // use, down to the figures, because the user asked for this panel's fly-in to
    // be the same gesture as theirs "just backwards" — and SettingsFlyout's
    // comment above its own animation already claimed the clock flyout as the
    // source of the curve, which quietly stopped being true when the morph took
    // the fly-in away with it. Copying it back makes that comment true again.
    //
    // `t` is 0 shut and 1 open, and everything the panel does on the way in or
    // the way out is a function of this one number, so the whole thing moves as a
    // single gesture rather than several items each running their own tween.
    // Nothing here writes `implicitWidth` or `implicitHeight`: resizing an
    // xdg_popup is a compositor round-trip per frame, and the window is exactly
    // the panel at both ends of the travel.
    property real t: 0
    /// Set while the close runs, so a second click cannot restart it halfway and
    /// strand the panel at some `t` between 0 and 1.
    property bool closing: false

    // No `stagger()` here, and that is a decision rather than an omission.
    // SettingsFlyout and NotificationCenter stagger their rows because they have
    // six of them and a flat sheet that size arrives as a single slab; their own
    // comment sets the ceiling — "a stagger you notice as 'slow' is worse than no
    // stagger at all". This panel is two cards that move as one gesture, which is
    // what the user asked for: more displacement, not more time, and a stagger
    // across two items is a delay nobody can see a reason for. Copied here once
    // and left unwired it would have been dead code with a sibling's figures on
    // it, which is worse than not having it.

    // OutQuart in, InQuart out — one curve in both directions, which is what
    // "just backwards" means. The panel decelerates into place instead of
    // arriving at speed and stopping dead, and it never travels past its mark:
    // on a panel this size a bounce reads as a wobble.
    SequentialAnimation {
        id: openAnim
        NumberAnimation {
            target: root; property: "t"
            from: 0; to: 1
            duration: 260
            easing.type: Easing.OutQuart
        }
    }

    // The exit is quicker than the entrance (200 against 260), as in both
    // siblings: a panel you are closing is a panel you have already decided
    // about, and making it wait makes the next click feel late. No `from:` — the
    // animation starts from wherever `t` actually is, which is the only way a
    // close can interrupt a half-finished open without a jump.
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

    function hide() {
        root.closing = false
        root.visible = false
    }

    // The one thing that moves, and the only reason `box` has a parent to sit in
    // at all. A plain Item, sized to the window and offset from the top-left, so
    // `y` is a free number here rather than something an anchor recomputes: an
    // anchored item has its `y` rewritten on every anchoring pass, and a binding
    // or a tween writing to an anchored `y` is the classic way to get a reveal
    // that runs to completion and moves nothing.
    //
    // It slides DOWN out of the window's own top edge rather than up into a
    // reserved strip above it, which is why there is no strip: a strip is
    // transparent window area, and an xdg_popup's grab region is its whole
    // window, so a strip is a grab region larger than the panel you can see. The
    // cost is that the panel's top edge is clipped for the first part of the
    // fade, where it is at its faintest anyway.
    Item {
        id: content
        x: 0
        y: (1 - root.t) * -root.slideFrom
        width: parent.width
        height: parent.height
        opacity: root.t

        // The panel's own surface. Fills `content`, which fills the window, which
        // is exactly `panelW` x `panelH` — so there is nothing below it and
        // nothing around it.
        Rectangle {
            id: box
            anchors.fill: parent
            color: Tokyo.bgDark
            radius: Tokyo.pillRadius
            border.color: Tokyo.bgHighlight
            border.width: 1

            // The cards sit at `pad` from the surface's own edge, and that inset is
            // load-bearing: a card flush with the surface reads as the surface's own
            // outline rather than as a card on it. `pad` and `cellGap` are
            // SysFlyout's 8 (see the geometry block above) — the whole point of
            // matching that file's look is not to leave one figure behind.
            GridLayout {
                id: grid
                anchors {
                    left: parent.left; right: parent.right; top: parent.top
                    leftMargin: root.pad; rightMargin: root.pad; topMargin: root.pad
                }
                columns: 2
                columnSpacing: root.cellGap
                // ================= 1. timers =================
                QuadCell {
                    title: "TIMERS"
                    accent: Tokyo.magenta
                    Layout.preferredWidth: root.cellW
                    Layout.preferredHeight: root.cellH

                    // The two bulk controls ride in the title row, the one place a
                    // card gets for something that is not the card's own content.
                    // The pair is a pause/resume toggle plus a stop — the same two
                    // controls every row already carries one at a time, so the
                    // title row reads as their row-level version rather than a new
                    // vocabulary.
                    //
                    // The glyph is the *state*, not the action, exactly as a row's
                    // is: play while something is running, pause once nothing is.
                    // Reading it the other way round — showing what the press will
                    // do — would make one glyph mean "running" in a row and
                    // "paused" in the title row of the same card. `pausable` greys
                    // the toggle out when the list is nothing but finished timers,
                    // since a control that would do nothing is worse than none.
                    //
                    // Glyph-only because the labels do not fit: the title row is
                    // 194 px and "PAUSE ALL" + "STOP ALL" measure ~165 px between
                    // them before the card title, so the title would be the thing
                    // that has to go. Both glyphs are already on every timer row,
                    // so nothing new has to be learned to read them.
                    headerExtra: Row {
                        spacing: 6
                        visible: TimerState.active

                        PillButton {
                            glyph: TimerState.running.length > 0 ? "\uF04C" : "\uF04B"
                            accent: Tokyo.yellow
                            enabled: TimerState.pausable
                            onClicked: TimerState.pauseAll()
                        }
                        PillButton {
                            glyph: "\uF068"        // times
                            accent: Tokyo.magenta
                            onClicked: TimerState.stopAll()
                        }
                    }

                    // The full panel, not a summary: this is where a timer is
                    // actually set. The list runs down to the slider and the form is
                    // pinned to the bottom of the card, so what is running and what
                    // to set are the two ends of one card.
                    //
                    // The card is as tall as the *clock* card's three stacked blocks.
                    // Rather than centring the whole thing — which put the form in
                    // the middle of nowhere — the form is pinned to the bottom, and
                    // the row cap is left to `TimerPanel` to derive from the space
                    // between them. It used to be a hard-coded two rows, which was
                    // right for the old square cell and left a 160 px hole in a card
                    // twice that size.
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

                    // Three blocks stacked in one card, in the order they are asked
                    // for: what time is it (here and elsewhere), what day is it,
                    // how long has this been up.
                    //
                    // The three old cell titles survive as block labels in their
                    // original accent colours. Losing them would leave the card
                    // reading as one undifferentiated column — and the colour coding
                    // is the only thing that says which number is a timezone and
                    // which is a boot time at a glance.
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
                                font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
                            }

                            Text {
                                id: localClock
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: timeLabel.bottom; topMargin: 5
                                }
                                text: Qt.formatDateTime(root.clock, "HH:mm:ss")
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
                                            font { family: Tokyo.fontFamily; pixelSize: 13; bold: true }
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
                                font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
                            }

                            Text {
                                id: weekday
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: dateLabel.bottom; topMargin: 5
                                }
                                text: Qt.formatDateTime(root.clock, "dddd")
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
                                text: Qt.formatDateTime(root.clock, "dd MMMM yyyy")
                                color: Tokyo.fg
                                font { family: Tokyo.fontFamily; pixelSize: 14 }
                                elide: Text.ElideRight
                            }

                            // The one-line date, compact: the format asked for
                            // (dd.mm.yyyy), the ISO calendar week number, and the
                            // current moon phase.
                            Text {
                                id: isoDate
                                anchors {
                                    left: parent.left; right: parent.right
                                    top: fullDate.bottom; topMargin: 3
                                }
                                text: Qt.formatDateTime(root.clock, "dd.MM.yyyy")
                                    + "  ·  week " + root.weekNumber(root.clock)
                                    + "  ·  " + root.moonPhase(root.clock)
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
                                font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
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
                                // idle value for the same reason), and the card's
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

                    // What the card actually needs, measured bottom-up off the last
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
}

