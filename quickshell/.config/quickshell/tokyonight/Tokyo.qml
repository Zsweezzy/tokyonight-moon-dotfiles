pragma Singleton
// Tokyo.qml — Tokyo Night Moon palette + bar geometry.
// Mirrors ~/.config/waybar/style.css (source of truth for pixel fidelity).
import QtQuick
import Quickshell

Singleton {
    // ---------- palette (tokyonight moon) ----------
    readonly property color bgDark: "#16161e"
    readonly property color bg: "#1e2030"
    readonly property color bgHighlight: "#2f334d"
    readonly property color fg: "#c8d3f5"
    readonly property color blue: "#82aaff"
    readonly property color cyan: "#86e1fc"
    readonly property color green: "#9ece6a"
    readonly property color yellow: "#e0af68"
    readonly property color magenta: "#bb9af7"
    readonly property color purple: "#9d7cd8"
    readonly property color teal: "#2ac3de"
    readonly property color pink: "#d6a6c8"
    // glyph color for TRAYED background apps — opened apps keep pink. This is
    // tokyonight's "comment" blue-gray: clearly distinct from pink, reads as
    // secondary/background, still bright enough for 14px glyphs.
    readonly property color trayGlyph: "#a9b1d6"

    // ---------- flyout surfaces ----------
    //
    // Opaque, every one of them. This block was built out of translucent
    // washes — the pane a thin blue film over the panel, the rules thin films of
    // the foreground — which meant the panel took its colour from whatever
    // happened to be behind it: the same pane measured #394161 over a terminal
    // and #394162 over a photo viewer, and the hairlines drifted with it. Fixed
    // values, so the panel is the panel.
    //
    // These are what those washes actually composited to, read off the screen
    // rather than computed: each surface over the one it really sits on. It was
    // two rules, not one, while the panel had a header — `headerRule` sat on the
    // panel's own fill rather than on a pane, and so a darker fixed value. The
    // header is gone and took its rule with it, so every rule in the flyout is
    // `hairline` on a pane again and one value does the lot.
    //
    // What they replaced, and why it was wrong: the panes were `bg` (#1e2030),
    // *darker* than the fill they cover, so each read as a near-black window
    // punched through the widget; and the borders and rules were `bgHighlight`
    // (#2f334d), the panel fill's own RGB — a divider drawn in the exact colour
    // of what it divides, 2-3 units apart per channel, i.e. nothing.
    readonly property color pane: "#394161"
    /// the pane's own edge, a step stronger than its interior rules: a card reads
    /// as a card because of its outline, and an outline at rule strength is lost
    /// in the fill on the far side of it
    readonly property color paneEdge: "#454c65"
    /// a rule *inside* a pane — over `pane`
    readonly property color hairline: "#485172"
    /// "dimmed", for the text that used to borrow the *surface* colour to say so.
    /// Lifted along with the surfaces: #2f334d lettering on a #394161 pane is not
    /// a de-emphasis, it is unreadable, and the zone abbreviations are the one
    /// place in these panes that was dimmed by borrowing the fill.
    readonly property color dim: "#7983a4"

    // The shape the morph grows — the panel's *own* fill, so the flyout draws
    // this and not `pillBg`, which the bar's pills still use.
    //
    // `pillBg` is rgba(47,51,77,0.9) and the bar's pill resolves to about
    // #2d3049 over the bar, so the panel is within a unit of its own widget at
    // rest either way. What is not negotiable is the *lit* widget, which is
    // opaque #2f334d: the widget does not go away when its panel opens, it sits
    // directly on the panel's top edge for the whole morph, and the joint puts
    // the two fills side by side. At #2c3149 that was a 3-unit step on two
    // touching surfaces — the one place a step this small is actually visible.
    // So the panel takes the pill's raw RGB and the step is gone.
    readonly property color panelFill: "#2f334d"
    // Its hover target, and it cannot be `bgHighlight` any more. `pillBg` and
    // `bgHighlight` are the same RGB differing only in alpha, so the morph's
    // hover tint was *purely* an alpha change (0.9 -> 1.0) over whatever was
    // behind — which a mix() between two opaque colours cannot express at all,
    // and an opaque fill is exactly two opaque colours. The highlight therefore
    // has to be a real step in RGB now. It is spent across the morph (see
    // `hoverTint`): a lift at t=0 fading to nothing, which is the whole "this
    // widget lit up and then became a panel" beat. It stays *below* `pane` on
    // purpose — a hover target above the pane would turn the two panes into
    // holes in a lit panel for the frames they are fading in over.
    //
    // #353a55, not the 30-unit #454c65 it was. The panel's own fill is now the
    // widget's lit colour, and the widget is on screen throughout the morph, so
    // the tint is a step between the widget directly above and the panel
    // directly below. 30 units there is a light panel sitting on a dark widget
    // for the first half of every open; 6 units is a lift and nothing more.
    readonly property color panelHover: "#353a55"

    // ---------- bar chrome ----------
    readonly property color barBg: Qt.rgba(0x1e / 255, 0x20 / 255, 0x30 / 255, 0.9)   // rgba(30,32,48,0.9)
    readonly property color pillBg: Qt.rgba(0x2f / 255, 0x33 / 255, 0x4d / 255, 0.9)  // rgba(47,51,77,0.9)
    // hover highlight for the apps-cluster cells. bgHighlight == pillBg, which
    // made the old hover invisible (it blended into the pill); a clearly
    // lighter indigo reads as "this cell is clickable".
    readonly property color cellHover: "#4a5278"
    readonly property color activeTint: Qt.rgba(0x82 / 255, 0xaa / 255, 0xff / 255, 0.2) // rgba(130,170,255,0.2)

    readonly property real barHeight: 34
    readonly property real barRadius: 10                          // 0 0 10px 10px
    readonly property real barBorderBottom: 2                     // 2px solid #2f334d
    // One radius for every surface in the shell: the bar's own bottom corners
    // are `decoration.rounding` (10) out of `~/.config/hypr/hyprland.lua`, and
    // the pills, panels, flyouts, tooltip, tray menu and clock panes all wear
    // that same number so a quickshell surface reads as a Hyprland window.
    // Only *surfaces* — a button or a slider track inside a panel is a
    // different scale of thing and keeps its own radius. The other half of that
    // rule is a ceiling, not a preference: a radius may not pass half the
    // element's height, because past it a bar stops being a bar and becomes a
    // lozenge. Three elements needed that and all three clamp —
    // `Workspaces`' 2 px active underline, `TimerPanel`'s 3 px progress bar and
    // `TrayMenu`'s 7 px separator rows.
    //
    // pillRadius and panelRadius are still two tokens even though they are both
    // 10: the morph's shape interpolates between them (see ClockFlyout), so
    // dialling one of them brings the corner run back. It used to be 8 and 16
    // for exactly that reason; at 10 and 10 the corner does not animate.
    readonly property int pillRadius: 10
    readonly property int panelRadius: 10
    readonly property real pillMarginV: 4
    readonly property real pillHeight: barHeight - pillMarginV * 2 // 26
    readonly property real pillHPad: 12                           // padding: 0 12px
    readonly property real wsPad: 10                              // workspaces button padding: 0 10px
    readonly property real moduleMarginH: 3                       // margin: 4px 3px
    readonly property real barSpacing: 6                          // waybar "spacing"
    readonly property real pillGap: barSpacing + moduleMarginH * 2 // 12 — GTK margins stack with box spacing

    // Distance from the monitor border to the outermost widgets. Must match the
    // hyprland window↔screen-edge gap (hyprland.lua: general.gaps_out = 6) so
    // the pills sit exactly as far from the border as the windows.
    readonly property real edgeGap: 6

    // Vertical offset that drops the pills below the monitor's top edge. Window
    // top = 42px (34px bar/exclusive zone + 6px gaps_out + 2px border); exact
    // midpoint 21 felt too close to the windows and 17 too close to the edge,
    // so the pills sit at 19 — slightly above the true middle, tuned by eye.
    readonly property real barShiftV: 2

    // ---------- typography ----------
    readonly property string fontFamily: "JetBrains Mono Nerd Font"
    readonly property real fontSize: 13

    // ---------- the bar's clock widget ----------
    /// What the clock pill shows: Font Awesome `clock-o` (nf-fa-clock_o), the
    /// only glyph in the set that is still a clock at 14px. It used to show
    /// HH:mm:ss over "Sat 27 Sep", which the flyout's CLOCK pane repeats at a
    /// size worth reading — the same time in two places, in two sizes, one
    /// click apart.
    ///
    /// Owned here rather than in `ClockFace` because the flyout measures this
    /// glyph too, for the closed end of its morph, and a second copy of the
    /// font spec is a second copy of the answer to "how wide is the pill".
    readonly property string clockGlyph: "\uf017"
    readonly property real clockGlyphSize: 14

    // ---------- script locations ----------
    /// scripts live with the config now (self-contained bar; waybar pkg removed)
    readonly property string scriptDir: Quickshell.env("HOME") + "/.config/quickshell/tokyonight/scripts"
    readonly property string shellDir: Quickshell.shellDir
}






