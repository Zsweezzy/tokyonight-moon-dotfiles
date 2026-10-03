// NotifyIcon.qml — one notification's icon, at the best size it can actually
// be.
//
// The toast this replaces drew the notification's image at a fixed 64px, and
// most apps send a 1x icon of 32-48px, so every one of them was being upscaled
// and looked soft. Three rules here, in order:
//
//   1. A real image — album art, a screenshot, an attachment — is shown, at its
//      own natural size if that is smaller than the box. An icon is never blown
//      up past the pixels it has; that is the whole of the blur.
//   2. Otherwise the icon is resolved by *name* through the store's theme map
//      (scripts/notify-icons.py), which holds the asset the freedesktop lookup
//      would pick for a 40px box: the exact-size PNG, else the scalable SVG.
//      Qt 6 no longer has a QML type for this — Qt.labs.platform's IconImage
//      was removed — so the map is built once at startup instead.
//   3. Otherwise a Nerd Font glyph for the app, which is crisp at any size
//      because it is drawn, not sampled.
//
// The `live` Notification is preferred over the stored record wherever there is
// one: it is the object the daemon still holds, and it may have been updated
// since (some apps rewrite a notification's body in place).
import QtQuick

Item {
    id: root

    /// a stored history entry, or a live Notification — both are read by field
    /// name and both have all of these except `live`
    property var source: null
    /// the side of the square this icon lives in
    property int size: 40
    /// the shell-wide store, for the icon-name map
    property var store: null

    // A square of `size`, always. Declared rather than left to the parent
    // because everything inside is positioned with anchors.centerIn and an
    // anchor with nothing to centre in collapses to the origin — which is what
    // made the icon render as a few stray pixels in the corner of the toast.
    width: root.size
    height: root.size

    readonly property string imageUri: root.source ? String(root.source.image || "") : ""
    readonly property string appIcon: root.source ? String(root.source.appIcon || "") : ""
    readonly property string desktopEntry: root.source
        ? String(root.source.desktopEntry || "") : ""
    readonly property string appName: root.source ? String(root.source.appName
                                                    || root.source.app || "") : ""

    /// An appIcon is a *name* unless it looks like a path. The two are told
    /// apart by shape because that is the only thing on the wire that tells
    /// them: "firefox" and "/usr/share/icons/hicolor/48x48/apps/firefox.png"
    /// arrive through the same field.
    readonly property bool appIconIsPath: root.appIcon.indexOf("/") >= 0

    /// The image_hint is usually not an image. `notify-send -i foot` sends
    /// "image://icon/foot" — a name in a URI, per the spec's icon form — and
    /// handing that straight to an Image leaves it to Qt's icon provider, which
    /// asks the platform theme and falls over on this system's (it logs "Icon
    /// theme 'Cosmic' not found" and hands back nothing). So the name is pulled
    /// out of the URI and resolved through the map below, which picks the asset
    /// itself. A URI that is not an icon form is a real image and is used as is.
    readonly property bool imageIsIconName: root.imageUri.indexOf("image://icon/") === 0
    readonly property string imageIconName: root.imageIsIconName
        ? decodeURIComponent(root.imageUri.substring(16)) : ""
    readonly property string realImage: root.imageIsIconName ? "" : root.imageUri

    /// What the map is asked for. desktopEntry is a .desktop id, which is the
    /// most reliable name on the wire when there is one — a client that sets it
    /// has looked itself up in the desktop database.
    readonly property string lookupName: root.desktopEntry !== ""
        ? root.desktopEntry
        : (root.appIconIsPath ? "" : root.appIcon)

    /// The map is asked for the .desktop id first, then the bare appIcon, then
    /// the name out of the image_hint URI. In practice a client sets at most one
    /// of them, and asking all three costs three dictionary lookups.
    readonly property string themePath: {
        if (root.store === null) return ""
        for (const name of [root.lookupName, root.appIcon, root.imageIconName]) {
            if (name === "" || root.appIconIsPath && name === root.appIcon) continue
            const hit = String(root.store.iconFor(name) || "")
            if (hit !== "") return hit
        }
        return ""
    }

    /// Whether the Image has something to draw. `status` and not a flag: a
    /// notification can name an icon from a package that has since been
    /// uninstalled, Image reports that as Error, and a glyph standing in is
    /// better than an empty 40px hole in the middle of the toast. Loading
    /// counts as drawable so the glyph does not flash before the real icon
    /// arrives.
    readonly property bool drawable: primary.status === Image.Ready
                                  || primary.status === Image.Loading

    /// The Nerd Font glyph for an app we have nothing better for. A handful of
    /// the ones that actually send notifications on a desktop this size; the
    /// rest fall through to the plain bell rather than to a wrong picture,
    /// which is what a wrong guess would look like.
    readonly property string fallbackGlyph: {
        const a = root.appName.toLowerCase()
        if (a.indexOf("cachy") >= 0 || a.indexOf("update") >= 0) return ""
        if (a.indexOf("mail") >= 0) return ""
        if (a.indexOf("calendar") >= 0) return ""
        if (a.indexOf("clock") >= 0) return ""
        if (a.indexOf("torrent") >= 0 || a.indexOf("transmission") >= 0) return ""
        if (a.indexOf("download") >= 0) return ""
        if (a.indexOf("bluetooth") >= 0) return ""
        if (a.indexOf("battery") >= 0 || a.indexOf("power") >= 0) return ""
        if (a.indexOf("volume") >= 0 || a.indexOf("audio") >= 0) return ""
        if (a.indexOf("disk") >= 0 || a.indexOf("drive") >= 0) return ""
        if (a.indexOf("plug") >= 0) return ""
        return ""
    }

    // ---------- 1. a real image, or 2. the theme, at its natural size ----------
    // One Image for both. They differ only in where `source` comes from, and
    // two Images meant two clamps to keep in step.
    Image {
        id: primary
        anchors.centerIn: parent
        visible: root.realImage !== "" || root.themePath !== ""
        source: root.realImage !== "" ? root.realImage
                                     : (root.themePath !== "" ? "file://" + root.themePath : "")
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit

        // Never upscale. Image will happily stretch a 32px PNG into a 40px box
        // because that is what it was told to do; clamping width/height to the
        // painted size is what stops it, and since fillMode is
        // PreserveAspectFit the smaller axis already fits inside the box.
        width: Math.min(root.size, Math.max(paintedWidth, 1))
        height: Math.min(root.size, Math.max(paintedHeight, 1))
    }

    // ---------- 3. a glyph ----------
    Text {
        anchors.centerIn: parent
        visible: !root.drawable
        text: root.fallbackGlyph
        color: Tokyo.cyan
        font { family: Tokyo.fontFamily; pixelSize: Math.round(root.size * 0.62) }
    }
}
