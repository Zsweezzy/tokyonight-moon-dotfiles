// NotificationStore.qml — the notification daemon, and the history behind the
// centre. One instance for the whole shell, created in shell.qml.
//
// Declaring a `NotificationServer` is what takes the org.freedesktop.Notifications
// bus name. While something else holds it — swaync, mako, dunst — this server
// simply never sees a notification, so this bar's toasts and its centre stay
// empty and the other daemon keeps the job. Only one daemon can be the daemon.
//
// The `NotificationServer` type is a PostReloadHook, so it survives a config
// reload with `keepOnReload: true`: without it every reload would tear the
// server down and a notification arriving in that window would be dropped by
// the client rather than arriving late.
//
// Quickshell 0.3.1 has no history of its own, so history is this file. The
// service hands out the live `Notification` objects; what gets written down is
// a plain record of them, because a Notification is gone once it is dismissed
// and cannot be re-read from anywhere.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// A Scope and not a QtObject: it holds a Poll and a NotificationServer as
// children, and QtObject has no default property to put them in.
Scope {
    id: root

    /// A notification has arrived, carrying the daemon's own object. The toasts
    /// listen to this rather than to `entries`, because a toast needs the live
    /// object to dismiss and to run its actions — the history entry is a plain
    /// record and the live one is not in it.
    signal newNotification(var n)

    // ---------- history ----------
    /// Newest first. Each entry is a plain object, not a Notification: see below.
    property var entries: []
    /// how many of the top entries have not been read. The bell lights on this.
    property int unread: 0

    /// Absolute timestamps, not "3 minutes ago" strings: a notification history
    /// is read days later, and a relative time written at capture time is wrong
    /// by exactly the time you spent not looking at it.
    readonly property string logPath: (Quickshell.env("XDG_STATE_HOME")
                                       || Quickshell.env("HOME") + "/.local/state")
                                    + "/quickshell/tokyonight/notifications.json"

    // ---------- icon names ----------
    /// icon name -> absolute path of the asset the theme would pick for a 40px
    /// box. Built once by scripts/notify-icons.py, which does the freedesktop
    /// lookup that Qt 6 no longer exposes to QML.
    property var icons: ({})

    /// A per-entry handle the delegate can hand back. `modelData` from a
    /// ListView is a V4ReferenceObject wrapper, not the object in `entries`, so
    /// `filter(e => e !== entry)` matches nothing and the row never goes away.
    /// Matching on this instead is what makes delete work at all.
    property int seq: 0

    function iconFor(name) {
        if (name === undefined || name === null || String(name) === "") return ""
        const hit = root.icons[String(name)]
        return hit !== undefined ? hit : ""
    }

    Poll {
        id: iconReader
        command: [Tokyo.scriptDir + "/notify-icons.py", "40"]
        interval: 600000
        onResult: line => {
            try {
                root.icons = JSON.parse(line)
            } catch (e) {
                root.icons = ({})
            }
        }
    }

    function record(n) {
        const entry = {
            id: n.id,
            app: n.appName,
            summary: n.summary,
            body: n.body,
            // `image` is a URI, `appIcon` a name or a path, `desktopEntry` the
            // .desktop id. All three are kept because the icon resolver needs
            // them in that order of preference and a Notification is not around
            // to ask later.
            image: n.image,
            appIcon: n.appIcon,
            desktopEntry: n.desktopEntry,
            urgency: n.urgency,
            time: Date.now(),
            // The live object, so a row that is still on screen can be
            // dismissed or can run one of its action buttons. Null once the
            // notification is gone, which is why the centre falls back to
            // launching the app by name when it is.
            live: n,
            read: false,
            // Monotonic, assigned here and nowhere else. `id` is the daemon's,
            // and it restarts from 1 with the shell, so it cannot key a list.
            key: ++root.seq,
        }
        root.entries = [entry].concat(root.entries)
        root.unread = root.unread + 1
        root.save()
        root.newNotification(n)
    }

    function save() {
        // Append only the new one. The log is append-only precisely so the hot
        // path — a notification arriving — is a single line write and nothing
        // else; anything that removes entries goes through rewrite() instead.
        const e = root.entries[0]
        if (e === undefined) return
        Quickshell.execDetached([
            Tokyo.scriptDir + "/notify-log.sh", "add", JSON.stringify({
                id: e.id, app: e.app, summary: e.summary, body: e.body,
                image: e.image, appIcon: e.appIcon, desktopEntry: e.desktopEntry,
                urgency: e.urgency, time: e.time, read: e.read,
            }),
        ])
    }

    // ---------- reading the history back ----------
    // A Process and not a Poll, because Poll parses stdout line by line and the
    // history is a file of many lines: with Poll the reader saw one notification
    // per result and the last one won, which is a history of exactly one. The
    // whole output is taken once, on exit, and split here.
    Process {
        id: reader
        command: ["cat", root.logPath]
        running: true
        stdout: StdioCollector {
            id: readerOut
            waitForEnd: true
        }
        onExited: root.load(readerOut.text)
    }

    /// Parse the log file's contents into `entries`. The file is JSON *Lines*,
    /// one object per line, so it is split and parsed a line at a time.
    ///
    /// A line that does not parse is skipped, not fatal: a crash between the
    /// write and the newline leaves half a line, and losing that one
    /// notification is the entire point of the format.
    function load(text) {
        const parsed = []
        for (const raw of String(text).split("\n")) {
            if (raw.trim() === "") continue
            try {
                const e = JSON.parse(raw)
                if (e !== null && typeof e === "object") parsed.push(e)
            } catch (err) {
                // deliberately ignored
            }
        }
        if (parsed.length === 0) return
        // Oldest first on disk, newest first in the model, and a live object is
        // null for everything that came back from the file — the daemon is not
        // holding those, so the centre offers app-launch rather than a button
        // that cannot do anything.
        root.entries = parsed.reverse().map(
            e => Object.assign({}, e, { live: null, key: ++root.seq }))
        root.unread = root.entries.filter(e => e.read !== true).length
    }

    // ---------- the daemon ----------
    NotificationServer {
        id: server
        // Hold on to notifications across a config reload, so a reload does not
        // silently drop whatever was on screen.
        keepOnReload: true
        // The caps are what this bar's toasts actually honour. Declaring a
        // capability the renderer ignores is worse than not declaring it: the
        // client picks its behaviour from what the server says it supports.
        persistenceSupported: false
        bodySupported: true
        bodyImagesSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false
        onNotification: n => root.record(n)
    }

    // ---------- what the centre calls ----------
    function markAllRead() {
        if (root.unread === 0) return
        root.entries = root.entries.map(e => Object.assign({}, e, { read: true }))
        root.unread = 0
        root.rewrite()
    }

    /// Close a notification on the daemon, if it is still open there.
    ///
    /// Wrapped because a Notification the daemon has already released throws on
    /// any property access, and an uncaught throw here would abort `dismiss()`
    /// before it removed the row — a delete button that deletes nothing exactly
    /// when the notification has expired. The row goes either way.
    function closeLive(n) {
        if (n === null || n === undefined) return
        try {
            n.dismiss()
        } catch (e) {
            // Already gone from the daemon's side; nothing to tell it.
        }
    }

    function dismiss(entry) {
        root.closeLive(entry.live)
        // On `key`, not on identity: the centre's delegate hands back a
        // V4ReferenceObject wrapper, never the object in `entries`, so an
        // identity filter removes nothing and the × appears inert.
        root.entries = root.entries.filter(e => e.key !== entry.key)
        if (entry.read !== true && root.unread > 0) root.unread = root.unread - 1
        root.rewrite()
    }

    function clearAll() {
        for (const e of root.entries) root.closeLive(e.live)
        root.entries = []
        root.unread = 0
        root.rewrite()
    }

    /// Overwrite the log with what is in memory. `save()` only appends, so
    /// anything that removes entries has to say so here instead. `$1` is the
    /// path and `$@` the lines, with the shift to keep them separate — the
    /// obvious `sh -c 'printf "$@" > "$1"'` would write the path into its own
    /// first line.
    function rewrite() {
        const wire = root.entries.map(e => ({
            id: e.id, app: e.app, summary: e.summary, body: e.body,
            image: e.image, appIcon: e.appIcon, desktopEntry: e.desktopEntry,
            urgency: e.urgency, time: e.time, read: e.read,
        }))
        Quickshell.execDetached([
            "sh", "-c",
            'log=$1; shift; if [ "$#" -eq 0 ]; then : > "$log"; else printf "%s\n" "$@" > "$log"; fi',
            "_", root.logPath,
        ].concat(wire.map(e => JSON.stringify(e))))
    }
}
