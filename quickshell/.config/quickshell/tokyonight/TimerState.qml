pragma Singleton
// TimerState.qml — every countdown in the shell, in one place.
//
// Singleton (like Tokyo.qml) because three surfaces read it: the bar pill, the
// timer's tooltip, and the timer panel. A service object threaded through
// Bar.qml would be the alternative; the singleton keeps that plumbing out of
// five call sites.
//
// Model: an immutable array of plain objects, reassigned on every mutation —
// Repeater binds to it exactly the way AudioFlyout binds to its node lists.
//   id        unique, never reused
//   totalMs   original length, for the progress bar
//   endsAt    epoch-ms deadline (wall clock, so a suspend that overshoots
//             simply fires on wake instead of silently losing the timer)
//   remaining frozen remainder while paused
//   paused    true between pause and resume
//   fired     true once it hit zero — kept in the list until dismissed, so a
//             finished timer never vanishes without a trace
//   firedAt   epoch ms of the finish, drives the pill's green flash
//
// IN-MEMORY BY DESIGN: a bar reload or restart clears every timer. Nothing is
// written to disk. A consequence while developing: any save to this config
// hot-reloads the bar and drops the running timers.
import QtQuick
import Quickshell

Singleton {
    id: root

    // ---------- bounds (shared by the panel and the pill) ----------
    readonly property int minMinutes: 1
    readonly property int maxMinutes: 30
    readonly property int minMs: minMinutes * 60000
    readonly property int maxMs: maxMinutes * 60000

    // ---------- state ----------
    property var timers: []
    readonly property bool active: root.timers.length > 0

    /// Ticks only while something is in the list, and views only ever READ it:
    /// every display derives from `now` instead of running its own timer, so
    /// the pill, the popup and the window cannot drift apart.
    property double now: Date.now()

    /// throttles the chime when several timers land on the same tick
    property double lastSoundAt: 0
    property int nextId: 1

    Timer {
        interval: 200
        repeat: true
        running: root.timers.length > 0
        onTriggered: root.advance()
    }

    // ---------------- reads ----------------

    function remainingMs(t) {
        if (!t) return 0
        if (t.fired) return 0
        if (t.paused) return t.remaining
        return Math.max(0, t.endsAt - root.now)
    }

    /// "MM:SS", or "H:MM:SS" past the hour
    function fmt(ms) {
        const total = Math.max(0, Math.round(ms / 1000))
        const h = Math.floor(total / 3600)
        const m = Math.floor((total % 3600) / 60)
        const s = total % 60
        // minutes are zero-padded in both cases so the seconds column of a
        // column-aligned list (tooltip/window) does not jump around
        return (h > 0 ? h + ":" : "") + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }

    function progress(t) {
        if (!t || !t.totalMs) return 0
        return Math.min(1, Math.max(0, 1 - root.remainingMs(t) / t.totalMs))
    }

    function byId(id) {
        return root.timers.find(t => t.id === id) || null
    }

    /// anything that can still be paused or resumed — everything but the fired
    readonly property var pausable: root.timers.some(t => !t.fired)

    /// running timers, soonest to finish first
    readonly property var running: root.runningList()
    function runningList() {
        return root.timers.filter(t => !t.fired && !t.paused).sort((a, b) => a.endsAt - b.endsAt)
    }

    /// what the pill shows. Precedence, highest first:
    ///   1. a timer that just fired (10 s window) — a finish must not pass
    ///      unnoticed just because something longer is still counting
    ///   2. the soonest running timer
    ///   3. the first paused one
    ///   4. the first finished one
    readonly property var nearest: {
        const fresh = root.timers.filter(t => t.fired && root.now - t.firedAt < 10000)
        if (fresh.length > 0) return fresh[fresh.length - 1]
        if (root.running.length > 0) return root.running[0]
        const paused = root.timers.filter(t => !t.fired && t.paused)
        if (paused.length > 0) return paused[0]
        return root.timers.length > 0 ? root.timers[0] : null
    }

    /// one line per timer, for the pill tooltip and the window's list
    function lines() {
        return root.timers.slice().sort((a, b) => {
            if (a.fired !== b.fired) return a.fired ? 1 : -1
            return root.remainingMs(a) - root.remainingMs(b)
        }).map(t => {
            if (t.fired) return "finished  " + root.fmt(t.totalMs)
            if (t.paused) return "paused    " + root.fmt(root.remainingMs(t))
            return root.fmt(root.remainingMs(t)) + "  of " + root.fmt(t.totalMs)
        })
    }

    // ---------------- writes ----------------

    /// start a timer of `ms` length; returns its id
    function start(ms) {
        const length = Math.max(1000, Math.min(root.maxMs, Math.round(ms)))
        // Refresh the display cache on the write, like every deadline writer.
        // `now` is a cache the 200 ms tick keeps fresh, but that tick only runs
        // while the list is non-empty, so the FIRST start() after an empty list
        // used to stamp its deadline from a `now` frozen since the shell last
        // had no timers: a 30-minute timer started after ten idle minutes came
        // back with twenty left. Rather than argue about which writers may get
        // away with a stale cache, every one of them (`start`, `scrub`,
        // `retime`, `togglePause`, `nudge`, `pauseAll`) refreshes `now` first,
        // so a deadline is always stamped off the real clock.
        root.now = Date.now()
        const t = {
            id: root.nextId++,
            totalMs: length,
            endsAt: root.now + length,
            remaining: length,
            paused: false,
            fired: false,
            firedAt: 0
        }
        root.timers = root.timers.concat([t])
        return t.id
    }

    function startMinutes(minutes) {
        return root.start(minutes * 60000)
    }

    function replace(id, patch) {
        root.timers = root.timers.map(t => (t.id === id ? Object.assign({}, t, patch) : t))
    }

    function togglePause(id) {
        const t = root.byId(id)
        if (!t || t.fired) return
        if (t.paused) {
            root.now = Date.now()
            root.replace(id, { paused: false, endsAt: root.now + t.remaining })
        } else {
            root.replace(id, { paused: true, remaining: root.remainingMs(t) })
        }
    }

    /// Move the playhead: say how much is left, WITHOUT touching the total.
    /// This is what dragging the progress bar calls.
    ///
    /// The bar is a playhead over the timer's own length, so `ms` is clamped
    /// into [0, totalMs]. A drag must never quietly lengthen or shorten a
    /// timer — changing a length is `retime()`'s job.
    ///
    /// A fired timer is locked: this returns and changes nothing, because the
    /// row's `+1` is the only route back from finished. A paused timer stores
    /// the new remainder and stays paused — scrubbing is not resuming. A
    /// running one gets a fresh deadline off the real clock, so a long press
    /// cannot carry the deadline backward by the 200 ms the display cache may
    /// be stale; it carries on counting from where the pointer left it.
    /// `ms = 0` needs no special case, because a deadline of "now" fires it on
    /// the next tick, which is what dragging the bar to its end should do.
    function scrub(id, ms) {
        const t = root.byId(id)
        if (!t || t.fired) return
        // `|| 0` is the NaN guard, not a default: Math.round(NaN) is NaN, and a
        // NaN `endsAt` is unrecoverable — remainingMs and progress both go NaN
        // and `endsAt <= root.now` is never true, so the timer could never fire
        // again. No caller can pass a non-number today; `scrub` is public API now.
        const left = Math.max(0, Math.min(t.totalMs, Math.round(ms) || 0))
        // cache refresh on the write, like every deadline writer, see `start`
        root.now = Date.now()
        if (t.paused) {
            root.replace(id, { remaining: left })
        } else {
            root.replace(id, { endsAt: root.now + left })
        }
    }

    /// The precise box's scrub: type how much is left, and when the number fits
    /// inside the timer's total it is exactly `scrub()` — playhead moves, total
    /// untouched. The difference is what `scrub()` must refuse: typing a length
    /// PAST the total lengthens the timer to that value, playhead at the top of
    /// the new length, counting down from the full amount. So the two-way rule
    /// (that exact value, or the whole existing length) is how a timer's length
    /// changes now; the drag stays a pure playhead.
    ///
    /// A paused timer gets the new total and stays paused — same rule as
    /// scrub, retiming is not resuming. A fired timer is locked. `ms = 0` is
    /// allowed: on a paused timer it parks the playhead at zero without firing,
    /// on a running one a deadline of "now" fires it on the next tick.
    function retime(id, ms) {
        const t = root.byId(id)
        if (!t || t.fired) return
        const value = Math.round(ms) || 0
        root.now = Date.now()
        if (value <= t.totalMs) {
            // within the total: a playhead move, identical to scrub
            if (t.paused) {
                root.replace(id, { remaining: value })
            } else {
                root.replace(id, { endsAt: root.now + value })
            }
        } else {
            const total = Math.min(root.maxMs, value)
            // past the total: the timer BECOMES that long, playhead at the top
            if (t.paused) {
                root.replace(id, { totalMs: total, remaining: total })
            } else {
                root.replace(id, { totalMs: total, endsAt: root.now + total })
            }
        }
    }

    /// ±1 minute. Also revives a finished timer, so the pill's controls are
    /// never dead ends.
    function nudge(id, minutes) {
        const t = root.byId(id)
        if (!t) return
        const delta = minutes * 60000
        if (t.fired) {
            if (delta <= 0) return
            const base = Math.min(root.maxMs, Math.max(60000, t.totalMs))
            root.now = Date.now()
            root.replace(id, {
                fired: false, firedAt: 0, paused: false,
                totalMs: base, endsAt: root.now + base, remaining: base
            })
            return
        }
        if (t.paused) {
            const left = Math.max(1000, Math.min(root.maxMs, t.remaining + delta))
            root.replace(id, { remaining: left, totalMs: Math.max(t.totalMs, left) })
        } else {
            const ends = t.endsAt + delta
            root.replace(id, { endsAt: ends, totalMs: Math.max(t.totalMs, ends - root.now) })
        }
    }

    function stop(id) {
        root.timers = root.timers.filter(t => t.id !== id)
    }

    function stopAll() {
        root.timers = []
    }

    /// One control for every timer, so running wins the precedence: while
    /// anything is counting, a press pauses the lot, and only when nothing is
    /// running does it resume what is paused. The other way round a global
    /// button would *start* a timer the user can see not running, which is a
    /// worse surprise than a pause that has to be pressed twice. Fired timers
    /// are skipped, so they are left exactly as they are.
    function pauseAll() {
        const resume = root.running.length === 0
        if (resume) root.now = Date.now()
        root.timers = root.timers.map(t => {
            if (t.fired || t.paused === !resume) return t
            return resume
                ? Object.assign({}, t, { paused: false, endsAt: root.now + t.remaining })
                : Object.assign({}, t, { paused: true, remaining: root.remainingMs(t) })
        })
    }

    // ---------------- the tick ----------------

    function advance() {
        root.now = Date.now()
        const due = root.timers.filter(t => !t.fired && !t.paused && t.endsAt <= root.now)
        if (due.length === 0) return
        const stamp = root.now
        root.timers = root.timers.map(t => (due.includes(t)
            ? Object.assign({}, t, { fired: true, firedAt: stamp, remaining: 0 })
            : t))
        root.alert(due)
    }

    function alert(due) {
        // One chime per burst: timers that finish on the same tick would stack
        // into a stutter, and the sound is punctuation, not data — the
        // notification carries the detail.
        if (root.now - root.lastSoundAt > 700) {
            root.lastSoundAt = root.now
            Quickshell.execDetached(["pw-play", "--volume=1.0", Tokyo.scriptDir + "/../assets/timer-done.wav"])
        }
        const body = due.length === 1
            ? root.fmt(due[0].totalMs) + " timer finished"
            : due.length + " timers finished ("
                + due.map(t => root.fmt(t.totalMs)).join(", ") + ")"
        // The icon is a file, not a theme name: the active theme (YAMIS) has
        // no timer/clock/alarm glyph at any size, so a name falls back to a
        // 48 px image stretched to ~200 px — the blur. The asset is rendered
        // by scripts/make-timer-icon.py from the same font the shell uses.
        Quickshell.execDetached([
            "notify-send", "-a", "tokyonight", "-u", "critical",
            "-i", Tokyo.scriptDir + "/../assets/timer-done.png",
            "Timer done", body
        ])
    }
}
