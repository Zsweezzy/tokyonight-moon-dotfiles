// Tray.qml — the tray pill: StatusNotifierItem background apps, one pill.
//
//   tray cells (theme icon, else glyph)
//
// One cell per SNI item — the background apps that register a
// StatusNotifierItem on the desktop portal (Steam, NordVPN, ...). The list is
// global and spans every workspace. An app with no tray support registers no
// SNI item and so never appears here: that is the whole contract of this pill.
// It is the tray, not a taskbar — an app shows up only while it is running
// with a tray icon, and it stays put as its windows come and go.
//
// A cell is ICON-FIRST: the app's own icon — whatever URL iconUrl() resolves,
// be that a theme name, an absolute path, or an image:// provider URL —
// whenever that resolves; only when it does not does a mapped nerd-font glyph
// stand in, and the generic wrench when nothing is mapped either. That order
// is not a decision the cell makes — it is what the glyph Text's `visible`
// binding enforces, since that binding paints only while the icon is Null (no
// source) or Error (undecodable). So a mapped glyph can go completely unpainted
// for any app that has an icon at all: Steam maps to nf-fa-steam, and its SNI
// hands over an icon URL, so you will not see that glyph for as long as it
// loads.
// Most apps have no glyph worth hand-mapping, and a hand-picked glyph is only
// ever a guess at a logo — the theme's icon is the better one when it has one,
// which is exactly why the icon wins. The tradeoff is that native icons are
// artwork, so an icon cell is full-colour and only glyph cells take the muted
// blue-gray tint.
//
// Every cell is its own click target (≥24 px, ~12 px gaps between cells, and
// icons are a px bigger than the other pills' labels so they're easy to hit):
//   left-click  restores the window this icon covers — a window parked on
//               Hyprland's hidden special:tray workspace moves back onto the
//               active one — or activates the app when it covers none.
//   right-click opens the app's own SNI menu when it has one.
//
// The pill collapses to nothing when there is no SNI item and reappears when
// one returns. A window hidden to special:tray has no cell of its own: it is
// represented by its app's tray icon, if it has one.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Rectangle {
    id: root

    /// shared tooltip popup (passed from Bar.qml)
    property var tooltipHost: null

    implicitHeight: Tokyo.pillHeight
    // the contents are anchor-filled, so they don't feed the parent's implicit
    // size themselves — implicitWidth is driven by the inner row instead.
    implicitWidth: contentRow.implicitWidth + Tokyo.pillHPad * 2
    radius: Tokyo.pillRadius
    color: Tokyo.pillBg
    visible: root.hasTrayContent

    // ---------- content state ----------
    // NOTE: quickshell 0.3.1's ObjectModel does NOT expose .count — only
    // .values, so gate on values.length (SystemTray.items.count is undefined).
    readonly property bool hasTrayContent: SystemTray.items.values.length > 0

    // ---------- tray sizing (the other pills keep Tokyo.fontSize) ----------
    // "a tiny bit bigger" than the other pills' labels.
    readonly property real iconSize: Tokyo.fontSize + 1
    // last-resort glyph: only painted when the app has neither a mapped
    // nerd-font glyph nor an icon in the current theme. \uf0ad is fa-wrench;
    // \uf0c8 is fa-square, which just reads as an empty box.
    readonly property string genericGlyph: "\uf0ad"
    // cell width = the wider of glyph and icon + 12 px spacing (6 px pad each
    // side → ~12 px visual gap between cells), min 24 px so each icon is a
    // comfortable click target. The icon belongs in the formula because the
    // cell IS the hover rect: a glyph narrower than the icon would otherwise
    // size the cell under the icon and leave the overhang outside the
    // highlighted, clickable area. iconSize is a constant, so this is about the
    // resting width — nothing here resizes when the icon arrives.
    readonly property real appCellPad: 12
    readonly property real appCellMin: 24

    // every window currently parked on Hyprland's hidden special:tray workspace
    property var _rawClients: []

    // ---------- hidden-window discovery (tray) ----------
    // This answers exactly one question, and only on click: does this tray icon
    // cover a window hidden in special:tray? A one-second poll for a question
    // asked at most once per click is wasted work, so the timer is off and the
    // cell re-runs the poll when the cursor arrives (onEntered ->
    // trayPoll.refresh()) — a fraction of a second before the click it feeds.
    // Poll.qml's `active` gates the timer only, not refresh(), and it fires one
    // ungated run from its own Component.onCompleted: that is what fills this
    // list on startup.
    Poll {
        id: trayPoll
        // "clients -j" alone prints PRETTY-PRINTED json (1 line per field), and
        // Poll's SplitParser fires onRead per line -> JSON.parse would fail on
        // every fragment. Compact it with jq -c so each poll run is one line.
        command: ["sh", "-c", "hyprctl clients -j | jq -c ."]
        active: false
        onResult: output => {
            try {
                const arr = JSON.parse(output)
                const inTray = arr
                    .filter(c => {
                        const ws = c.workspace
                        return ws !== null && ws !== undefined && String(ws.name) === "special:tray"
                    })
                    .map(c => ({
                        address: c.address,
                        class: c.class,
                        title: c.title,
                        pid: c.pid,
                    }))
                root._rawClients = inTray
            } catch (e) {
                // transient parse failure — keep the previous list
            }
        }
    }

    // does any SNI item represent this window's app? (no pid on TrayItem in
    // quickshell, so we match lowercased title/id against the window class)
    function _sniCovers(items, client) {
        const cls = String(client.class || "").toLowerCase()
        if (!cls) return false
        for (const it of items) {
            const t = String(it.title || it.id || "").toLowerCase()
            if (!t) continue
            if (t === cls || t.startsWith(cls) || t.endsWith(cls)) return true
        }
        return false
    }

    // the tray'd window (if any) that this SNI item represents. When found, a
    // left click on the tray cell restores that window onto the active
    // workspace; otherwise we'd only surface the special-workspace overlay
    // (Hyprland keeps the window in special:tray, which is confusing).
    function _coveredTrayWindow(item) {
        for (const c of root._rawClients) {
            if (root._sniCovers([item], c)) return c
        }
        return null
    }

    // nerd-font glyph for a tray app, or "" when nothing is mapped — the generic
    // wrench is the only other thing this feeds (the cell's glyph Text binds
    // `glyphFor(...) || root.genericGlyph`). What this RETURNS is not what you
    // see first: the cell's own icon is painted in preference to it, and this
    // glyph only shows once that icon fails to load. openRGB is deliberately
    // absent: the sliders glyph (\uf1de, was \uf1fb) was a stand-in for its
    // logo, and its own icon is the better one where the theme has it.
    function glyphFor(name) {
        const n = String(name || "").toLowerCase()
        if (n.indexOf("steam") !== -1) return "\uf1b6"    // nf-fa-steam
        if (n.indexOf("nordvpn") !== -1) return "\uf023"  // nf-fa-lock (was \uf132 shield — read as a generic blob at 14 px)
        if (/firefox|chromium|brave|zen|webkit/.test(n)) return "\uf269"   // browser
        if (/kitty|alacritty|wezterm|foot|konsole|ghostty|urxvt|xterm/.test(n)) return "\uf120"  // terminal
        if (/kate|kwrite|sublime|code|vim|nvim|emacs|zed/.test(n)) return "\uf044"  // editor
        if (/dolphin|nautilus|thunar|pcmanfm|nemo/.test(n)) return "\uf07b"  // file manager
        return ""
    }

    // whatever URL the Image can load for an app, or "" when nothing resolves.
    // An absolute path is taken as one. A path that no longer exists on disk
    // still goes to the Image, which fails it and hands the cell back to its
    // glyph — there is no existence check here to fall back from (QML has no
    // equivalent of the old resolver's `[ -f "$name" ]`).
    function iconUrl(name) {
        const n = String(name || "").trim()
        if (n === "") return ""
        // an SNI icon is not always a bare theme name: Steam hands over a
        // complete provider URL (image://icon/steam_tray_mono?path=...), others
        // a generated one (image://qspixmap/...). Those are already URLs, and
        // iconPath() cannot resolve them — hand them to the Image as they are.
        if (n.indexOf("://") !== -1) return n
        // iconPath() is case-SENSITIVE while theme names on disk are lower-
        // case, and window classes are often reverse-DNS (org.kde.kate -> kate)
        // with the app name in TitleCase at the end (org.samrewritten.
        // SamRewritten, whose icon is samrewritten.png). So try the name, then
        // its last dotted segment, then that segment lower-cased. Lower case
        // comes last on purpose: org.openrgb.OpenRGB resolves in its own casing
        // and not in lower case.
        const last = n.split(".").pop()
        for (const cand of [n, last, last.toLowerCase()]) {
            const p = Quickshell.iconPath(cand, true)
            if (p !== "") return p
        }
        // nothing in the theme: an absolute path the app gave us
        if (n.indexOf("/") === 0) return "file://" + n.replace(/ /g, "%20")
        return ""
    }

    // display a tray item's own SNI menu (Steam's Exit/Library, ...) as a
    // themed flyout (TrayMenu.qml) anchored below its cell — same flyout
    // language as the audio flyout, same position the platform menu had.
    // The menu is populated from item.menu (a QsMenuHandle) by QsMenuOpener;
    // grabFocus dismisses it on any outside click.
    function showTrayMenu(item, cell) {
        if (!item || !item.menu) return
        root.cancelTooltip()
        trayMenu.menuHandle = item.menu
        trayMenu.showFor(cell, "below")
    }

    // ---------- delayed tooltip ----------
    // Don't pop the tooltip the instant the cursor enters a cell: popping it
    // immediately while scanning across the cluster disturbed hover handling
    // and made the highlight look like it "fades out". Now the tooltip appears
    // only after the cursor rests on a cell for ~0.5 s. One shared timer means
    // only the last-scheduled cell wins. The highlight itself is position-
    // tracked (containsMouse), so resting on a cell keeps it lit regardless.
    Timer {
        id: tooltipTimer
        interval: 500
        repeat: false
        property var pendingCell: null
        property string pendingText: ""
        onTriggered: {
            if (root.tooltipHost !== null && tooltipTimer.pendingCell !== null)
                root.tooltipHost.showFor(tooltipTimer.pendingCell, tooltipTimer.pendingText)
        }
    }

    function scheduleTooltip(cell, tip) {
        tooltipTimer.pendingCell = cell
        tooltipTimer.pendingText = tip
        tooltipTimer.restart()
    }

    function cancelTooltip() {
        tooltipTimer.stop()
        if (root.tooltipHost !== null) root.tooltipHost.hide()
    }

    // move a tray'd window back onto the currently active workspace and focus it.
    // Uses the Lua DSL form of the dispatcher: hyprctl dispatch evaluates its
    // argument as Lua, so bare "movetoworkspacesilent 1,address:0x..." is a
    // syntax error. workspace + window selection need { workspace=..., window=... }.
    function restoreWindow(c) {
        const addr = String(c.address || "")
        if (!addr) return
        Quickshell.execDetached(["bash", "-c",
            "a=$1; ws=$(hyprctl activeworkspace -j | jq -r .name); hyprctl dispatch \"hl.dsp.window.move({workspace=\\\"$ws\\\", window=\\\"address:$a\\\", follow=true})\"",
            "tray-restore", addr])
    }

    // ---------- the pill ----------
    Row {
        id: contentRow
        anchors { fill: parent; leftMargin: Tokyo.pillHPad; rightMargin: Tokyo.pillHPad }
        spacing: 0

        // ---------- tray background apps ----------
        Row {
            id: trayRow
            spacing: 0

            // SNI items (background apps with a StatusNotifierItem)
            Repeater {
                model: SystemTray.items

                delegate: Rectangle {
                    required property var modelData
                    readonly property var item: modelData

                    id: sniCell
                    // sizing (root.appCellPad/Min): the wider of glyph/icon +
                    // 12 px spacing, min 24 px.
                    width: Math.max(Math.max(root.iconSize, glyph.implicitWidth) + root.appCellPad, root.appCellMin)
                    height: Tokyo.pillHeight
                    radius: 6
                    // no fade: an instant highlight means two adjacent cells can
                    // never both look "lit" during a transition (a 150 ms fade
                    // left the previous cell fading out while the next faded in,
                    // and jiggling between the tray icons made both look focused)
                    color: mouse.containsMouse ? Tokyo.cellHover : "transparent"

                    // the app's own icon, and the cell's FIRST choice: it paints
                    // whenever it resolves, and the glyph Text beside it stays
                    // hidden until this Image reports Null or Error. So
                    // glyphFor() is a fallback for a missing icon, not a
                    // preferred brand mark — a mapped glyph for an app that has
                    // an icon at all is never painted.
                    // item.icon is what the SNI hands us (a theme name, a path,
                    // or a whole image:// URL), so try it first and fall back to
                    // the SNI id.
                    // openRGB is the case this exists for: it runs
                    // --startminimized and lives here as an SNI cell, and the
                    // sliders glyph it used to be given is only a guess at its
                    // logo — so it takes whatever the theme resolves for its
                    // icon/id, and the generic wrench if that misses too.
                    Image {
                        id: icon
                        anchors.centerIn: parent
                        width: root.iconSize
                        height: root.iconSize
                        fillMode: Image.PreserveAspectFit
                        // rasterize at the target size: without these the
                        // image:// provider hands back a 200x200 pixmap and Qt
                        // scales it down (blurry SVG at 14 px); with them the SVG
                        // rasterizes at 14.
                        sourceSize.width: root.iconSize
                        sourceSize.height: root.iconSize
                        source: sniCell.item ? (root.iconUrl(sniCell.item.icon) || root.iconUrl(sniCell.item.id)) : ""
                    }

                    Text {
                        id: glyph
                        anchors.centerIn: parent
                        // item can be momentarily undefined while the Repeater
                        // rebuilds on reload — guard so it doesn't warn.
                        text: sniCell.item ? (root.glyphFor(sniCell.item.title + " " + sniCell.item.id + " " + sniCell.item.icon) || root.genericGlyph) : ""
                        // tray/background apps use a muted blue-gray, distinct
                        // from the pink the other pills' glyphs wear.
                        color: Tokyo.trayGlyph
                        font { family: Tokyo.fontFamily; pixelSize: root.iconSize; letterSpacing: 0.2 }
                        // the glyph stands in for a cell with no icon to paint,
                        // and a cell has none two ways: the source was empty
                        // (status Null) or the provider could not decode it
                        // (status Error — a stale path, a broken SVG). Judged on
                        // the status enum, not on `source === ""`: source is
                        // url-typed, so that comparison is never true and every
                        // blank cell would lose its glyph. Loading stays hidden
                        // so the two are never painted at once.
                        visible: icon.status === Image.Null || icon.status === Image.Error
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onEntered: {
                            // the click handler below reads _rawClients, so this
                            // is the one place it has to be current.
                            trayPoll.refresh()
                            if (root.tooltipHost !== null) {
                                const tip = sniCell.item.tooltipTitle !== "" ? sniCell.item.tooltipTitle : sniCell.item.title
                                if (tip !== "") root.scheduleTooltip(sniCell, tip)
                            }
                        }
                        onExited: root.cancelTooltip()
                        onClicked: m => {
                            // right-click: the app's own menu (Library/Exit/etc.)
                            if (m.button === Qt.RightButton && sniCell.item.hasMenu) {
                                root.showTrayMenu(sniCell.item, sniCell)
                                return
                            }
                            // left-click: if this icon covers a window hidden in
                            // the tray, restore that window; otherwise activate.
                            const covered = root._coveredTrayWindow(sniCell.item)
                            if (covered !== null) root.restoreWindow(covered)
                            else sniCell.item.activate()
                        }
                    }
                }
            }
        }
    }

    // SNI right-click menus: a themed flyout (TrayMenu.qml) in the audio
    // flyout's visual language, populated from the tray item's QsMenuHandle by
    // QsMenuOpener. menu + anchor item are set per right-click by
    // showTrayMenu(). Kept at the root so it survives cell rebuilds.
    TrayMenu {
        id: trayMenu
    }
}