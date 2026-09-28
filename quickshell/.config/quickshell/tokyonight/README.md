# tokyonight — Quickshell bar (Waybar clone)

Pixel-faithful port of your Waybar config (Tokyo Night Moon) to Quickshell 0.3.1.
The bar is fully self-contained: all scripts live in `scripts/` inside this
directory. The original `~/.config/waybar/` is preserved untouched as the
design reference / rollback backup (also backed up to GitHub:
`Zsweezzy/waybar-dotfiles`).

## Run

```
quickshell -c tokyonight
```

Hot-reloads on save (default). To find the config while iterating:

```
quickshell -c tokyonight -v
```

Launched at session start by `hyprland.lua` line 66
(`hl.exec_cmd("quickshell -c tokyonight")`).

## Module map

| waybar module          | file          | source                           |
|------------------------|---------------|----------------------------------|
| hyprland/workspaces    | Workspaces    | Quickshell.Hyprland IPC          |
| custom/cava            | Cava          | `scripts/cava.sh` (+ `cava.config`) |
| custom/openapps        | OpenApps      | `scripts/openapps.sh`             |
| custom/uptime          | ClockFlyout   | `scripts/clock-panel.sh` (+ `/proc/uptime`) |
| clock#date + clock     | Clock         | Qt `Date` (no script)            |
| custom/wifi            | Wifi          | `scripts/wifi.sh` / `wifi-toggle.sh` |
| custom/ethernet        | Ethernet      | `scripts/ethernet.sh`            |
| network metrics        | Wifi/Ethernet | `NetworkMonitor.qml` + `scripts/network-monitor.sh` |
| pulseaudio             | Audio         | Quickshell.Services.Pipewire     |
| custom/gpu             | Gpu           | `scripts/gpu.sh`                 |
| cpu                    | Cpu           | `scripts/cpu.sh` (new)           |
| memory                 | Mem           | `scripts/mem.sh` (new)           |
| custom/updates         | Updates       | `scripts/cachy-updates.sh`       |
| tray (merged into OpenApps) | OpenApps | Quickshell.Services.SystemTray + `special:tray` |
| (no waybar equivalent)  | Brightness    | `scripts/brightness.sh` (ddcutil, DDC/CI VCP 0x10) |
| (no waybar equivalent)  | ClockFlyout   | `TimerState.qml` + `scripts/timer-alert.sh` |

The bar's centre is **one** pill now, not four. `ClockDate.qml`, `ClockTime.qml`,
`Uptime.qml` and `TimerPill.qml` are gone; what they showed lives in
`ClockFlyout.qml`, which the pill **morphs into** behind a single left-click (see
"Clock" below), and the retired `scripts/uptime.sh` / `scripts/tz-times.sh` were
replaced by `scripts/clock-panel.sh`. The pill still reads the time and the date;
it just stops reading them out loud while it is open, going to a clock glyph for
the duration of the panel (see "Clock" below). The `HH:mm` ↔ `HH:mm:ss`
right-click toggle that the old `ClockTime.qml` had stays retired — the pill
shows seconds either way, and the toggle's other half had nowhere left to go.

CPU/RAM were Waybar built-ins (no script to reuse), so two tiny scripts were
added to `scripts/`; they use the same sysfs/proc reads as Waybar. All scripts
resolve their helpers via `$(dirname "$0")` (e.g. `wifi.sh` sources
`net-common.sh` from the same directory), and `Tokyo.scriptDir` points every
module at `scripts/`.

## Behavior parity notes

- **Waybar `signal`/RTMIN refresh has no Quickshell equivalent.** Replaced by:
  - wifi toggle → re-runs `wifi.sh` 800 ms after the toggle click
  - openapps → re-runs the script on Hyprland open/close window events (plus the 5 s poll)
  - updates middle-click → immediate re-run (the config already treats middle-click
    as "refresh", so its `pkill -RTMIN+9` is equivalent to a restored poll)
- Tooltips are custom popups styled after the waybar `tooltip` CSS rule; GTK's
  500 ms hover delay (and the old `libtooltip-delay.so` shim) does not apply.
- The memory tooltip lists the top-10 processes by RAM (RSS merged by process
  name, sorted descending, `name SIZE %of_total` per line) from `scripts/mem.sh`.
- The existing Wi‑Fi and Ethernet tooltips retain their SSID/IP/netmask/DNS/MAC
  details and append per-adapter upload/download rates plus the `1.1.1.1` ping
  time. DNS and MAC lines are omitted for adapters that do not expose those
  values. `NetworkMonitor.qml` refreshes one shared snapshot every second; all
  non-loopback adapters are represented, with non-Wi‑Fi adapters grouped under
  the Ethernet tooltip.
- Clicking the audio pill opens a flyout (`AudioFlyout.qml`) with per-application
  volume sliders + mute toggles and click-to-switch output/input devices
  (defaults set via `Pipewire.preferredDefaultAudioSink/Source`). It replaces
  the old `audio-popup.py` on left-click; right/middle click still launches it.
- Clicking the cpu / gpu / mem pills opens `btop` in a kitty window
  (`Quickshell.execDetached`, replacing waybar's on-click).
- **Apps cluster / "minimize to tray"** (`OpenApps.qml`, the dropped waybar tray
  merged into the open-apps pill, shown on the left):
  - One pill holds both: pink glyphs of foreground open apps, an 8 px gap, then
    muted blue-gray glyphs of tray background apps — StatusNotifierItems (Steam,
    NordVPN, …) and windows hidden with `SUPER + SHIFT + C` onto Hyprland's hidden
    `special:tray` workspace (the app keeps running, invisible — Hyprland has no
    native minimize; this is the hide-and-keep-running trick). `openapps.sh`
    excludes `special:tray` windows so tray'd apps only appear in the tray
    section. Opened vs trayed apps are color-coded (`Tokyo.pink` vs
    `Tokyo.trayGlyph`, the muted "comment" blue-gray).
  - Every icon is its own clickable cell (≥ 24 px wide, ~12 px gaps between
    glyphs, glyphs one px larger than the other pills' labels) — taskbar-style:
    clicking an open-app cell focuses that app's window
    (`hl.dsp.focus({ window = "class:…" })`; the old cycle-through-apps
    behavior and `openapps-focus.sh` are retired).
  - Tray glyphs are mapped per app (`glyphFor` mirrors the `openapps.sh` map):
    Steam gets its logo `\uf1b6`, NordVPN a padlock `\uf023`, and
    browser/terminal/editor/file-manager classes match their open-apps glyphs.
    Unmapped apps (OpenRGB among them — it used to be a `\uf1de` sliders glyph)
    get an **empty** glyph and fall back to **their own icon from the active
    icon theme**, so a cell shows: mapped glyph → the app's theme icon →
    the generic wrench `\uf0c8`. `Quickshell.iconPath(name, true)` does the
    lookup (and the active theme is picked up automatically); window classes
    that are reverse-DNS are retried on their last dotted segment
    (`org.kde.kate` → `kate`). An SNI `icon` is not always a bare theme name —
    Steam hands over a whole `image://icon/steam_tray_mono?path=…` URL and
    others a generated `image://qspixmap/…`, so `iconUrl()` passes any `://`
    string through untouched (`iconPath()` cannot resolve one) and only wraps
    `file://` around a name that really starts with `/`. A URL the image
    provider can't load lands back on the glyph rather than an empty cell.
    Accepted tradeoff: native icons are artwork, so they render full-colour —
    the pink / muted blue-gray split only tints the cells still showing a glyph.
    Icons are rasterized at `sourceSize` (14 px); without it the `image://`
    provider hands back a 200×200 pixmap that Qt then scales down.
  - Every cell hover-highlights; the highlight is tracked from the cursor
    position itself (`containsMouse`) and the 5 s `openapps.sh` poll reuses the
    same array when nothing changed — so the highlight stays lit exactly as long
    as the mouse is over the icon instead of blinking out mid-hover. The hover
    fill is `Tokyo.cellHover`, a clearly lighter indigo than the pill bg
    (`bgHighlight` == `pillBg` made the original hover invisible). Tooltips
    appear after a 500 ms delay (shared timer) rather than instantly on enter.
  - Tray cells hover-highlight. Left-click restores the app's window if one is
    currently hidden in the tray, otherwise it activates the app; right-click
    opens the app's own SNI menu (e.g. Steam's Exit/Library) when it has one —
    rendered as a themed flyout (`TrayMenu.qml`) in the audio flyout's visual
    language (bgDark panel, `pillRadius`, `bgHighlight` border and row hover,
    green check marks) instead of a native platform menu. (The clock flyout is
    the one deliberate exception: it is a bar pill that grew, so it keeps
    `pillBg` and no border — see "The morph".) It's populated from
    the item's `QsMenuHandle` by `QsMenuOpener`, anchored below the cell
    (bottom-edge-anchored, ~8 px gap so the tray glyph stays visible), rows
    with children open a nested flyout to the right, and `grabFocus` dismisses
    the whole stack on an outside click. (No platform menus are used for the
    tray anymore, so the `//@ pragma UseQApplication` in `shell.qml` is no
    longer needed for this; it's kept as harmless insurance.)
  - Windows tray'd that have **no** SNI icon get a placeholder glyph (same
    per-app mapping); clicking it restores the window to the current workspace
    and focuses it. Placeholders are suppressed when an SNI item covers the app
    (title/class match) — the SNI cell's left-click takes over the restore.
  - The pill collapses to nothing when there's no content (no open apps, no SNI
    items, no tray'd windows).
- **Monitor brightness** (right/middle-click or scroll on a workspace pill —
  no waybar equivalent, this bar only):
  - **Left-click is untouched** and still switches workspace. Right- or
    middle-clicking any pill opens `BrightnessFlyout.qml`; the scroll wheel
    over a pill nudges that monitor by ±5 without opening anything. The pill
    is the natural anchor because the bar is per-monitor already, so the
    flyout is always created on the screen you clicked.
  - Brightness is **real hardware DDC/CI** (VCP code 0x10, luminance) via
    `ddcutil`, *not* `brightnessctl`: this machine has no internal panel
    (`/sys/class/backlight` is empty), so `brightnessctl` has nothing to
    write, and there is no `gammastep`/`wlr-gamma-control` for a software
    fallback either. All three external displays answer VCP 0x10.
  - `scripts/brightness.sh` owns the Hyprland→`ddcutil` translation.
    ddcutil 3.x only takes an *integer* display number, and that number is
    just the position in `ddcutil detect` — unrelated to the Hyprland
    monitor id. The two are matched by **EDID serial number** (identical
    strings in `ddcutil detect` and `hyprctl monitors -j`), falling back to
    the DRM connector name and then the model. Serial is the only key that
    stays unique if two GPUs each expose an identically named connector.
  - `Brightness.qml` is a single shared service (like `NetworkMonitor` in
    `shell.qml`) because I2C is slow: ~0.4 s per read, ~0.5 s per write, and
    seconds for a `detect`. It therefore builds the display map **once** and
    caches it, keeps the last level per monitor, and updates it
    *optimistically* so the slider follows the pointer instead of stalling.
    A 180 ms debounce collapses a whole drag into one write, which is then
    re-read once to confirm — so a monitor that refuses a value snaps the
    handle back instead of lying.
  - Writes are clamped to each monitor's *own* maximum (not a hardcoded 100),
    because `ddcutil` prints "Verification failed for feature 10" but still
    exits 0 — an out-of-range write looks like success while changing nothing.
  - A monitor with no DDC/CI luminance gets a disabled slider and an explicit
    "no DDC/CI" label rather than a control that silently does nothing.
- The bar has no background: the waybar bg strip + bottom border band are
  dropped, so the pills float over the wallpaper and everything between them
  is transparent.
- Qt/vs GTK text rendering can shift baselines by a pixel or two.

## Clock

The centre of the bar used to be four pills — uptime, `clock#date`, `clock`, and
a timer countdown. It is now **one** pill (`Clock.qml`) and a **1×2 flyout**
(`ClockFlyout.qml`). Everything still asked the same question ("what time is it,
and how long have you been here"), so it is one click away instead of four.

- **The pill reads the time and the date, and becomes a clock glyph while the
  panel is open** — `HH:mm:ss` (13 px) stacked over `ddd dd MMM` (9 px), and
  `\uf017` (Font Awesome `clock-o`, U+F017) at 14 px for as long as the flyout is
  up. The readings are the resting state because a bar with no clock on it is a
  bar you have to click to know what time it is; the glyph is what it is while
  open because the panel is showing the same two numbers three lines down, in a
  bigger font, and two clocks one click apart is the thing this widget spent a
  while trying not to be. The glyph and its size live in `Tokyo.qml`
  (`clockGlyph`, `clockGlyphSize`).

  Both looks are in one file, `ClockFace.qml` — frameless, owning the fonts, the
  metrics and the padding arithmetic, taking `hovered`, `now` and `glyphMix`.
  One definition of the face, whichever end of the morph is on screen:
  `Clock.qml` is the bar's thin `Module` wrapper around it, and the flyout hosts
  the second copy. The face does not own a clock: `Clock.qml` does, and the
  flyout's copy reads *that* one (`root.pill.now`), because two faces with two
  `Timer`s started at two instants are two clocks that can disagree about the
  seconds digit by one for as long as both are on screen.

  `glyphMix` is one number, owned by the flyout (`min(1, t / 0.7)`, a ~50 ms
  fade) and read by *both* copies — the bar's through `Clock.flyoutHost`, the
  flyout's directly. They are on the same pixels for the whole morph, so a frame
  where they disagree is a frame where the hand-over is visible. It is short on
  purpose: the glyph is 14 rows centred in a 26-row pill, so it does not reach
  the shape's top edge until `t` = 0.77, and a fade still running then would be
  a face half-readings, half-glyph on the only part of it anyone sees.

  **The pill does not change width between the two looks**, and that is forced,
  not tidy: the shape's closed end is a copy of the pill's rect measured *before*
  the click, so a pill that narrowed on the click would leave the shape hanging
  over a narrower pill and open the joint on the wrong edges. So the width is the
  readings' — `contentW` is the widest thing the face can draw, and the glyph is
  nowhere near as wide as eight digits — and the open pill is a wide button with
  a lone icon in it.

  Measured: pill fill at device 1834..2005 × 12..63 (86 × 26 logical), time ink
  at 1861..1982 × 17..34 in eight cells with the two colons 4 and 3 device px
  wide, the date a dimmer line below it; opened, the same rect in the lit fill
  (47, 51, 77) with cyan glyph ink at 1905..1934, dead centre on 1919.5.

  The centring rule this file used to need is back with the second line. It was
  there because a QML `Column` puts a child narrower than itself at x=0, i.e.
  left-aligned, so two lines with separate measured widths left the date hanging
  4.75 px off the middle of the pill. Both lines are now one `Item` of
  `contentW` with the text centred in it, so the two cannot disagree — the
  mistake is made structurally impossible rather than compensated for.
- **Left-click *morphs* the pill into the panel** — one shape growing into another,
  not a panel appearing next to a pill — and the panel ends up **flush under the
  widget** rather than on the widget's own row. See "The morph" below. One
  `ClockFlyout` per bar window, so it always opens on the monitor you clicked.
  The bar's `Clock` stays on screen the whole time: there is nothing to hide,
  because the two are on different pixels by the end of the morph.

  What that cost, and why it is still the right trade: the panel's top is no
  longer the widget's own row. It used to be — the `time and date` label was the
  panel's first `pillH` rows and the digits were the window's, so at rest the two
  were adjacent rather than coincident, and the label slid in below the digits as
  the shape uncovered it rather than over them. That is what the move bought: the
  widget's own rows stayed the widget's. A panel *below* the widget has nothing to
  inherit, so the header was an ordinary header: the panel's own title, naming
  the panes rather than repeating them. It has since
  been deleted outright, which is that same conclusion taken one step further —
  the CLOCK pane carries both readings already, at a size worth reading, so the
  only thing the band was left doing was describing what was underneath it. What
  the panel has where the header was is `pad` of margin, the same margin it has
  on its other three sides. It could not be done while the header *was* a reading
  of the clock, because with the panel on the widget's own row a header
  repeating the time and the date is a third copy of it — two of them a click
  apart. The readings had to leave the header, not the widget, and the widget
  keeping them is what makes the panel's silence read as the widget going quiet.

  The widget also stays **lit** while its panel is up. The popup's own surface is
  drawn on top of the pill, so the bar's `MouseArea` hears nothing at all once
  the panel opens — without help the widget cools off under the cursor at the
  exact moment its panel appeared. `Module` grew a `hoveredExtra` flag (OR'd into
  a new readonly `lit`, which the paint reads and nothing else should) and the
  clock pill *binds* it to the flyout's latched `pillLit`. A binding cannot cross
  from child to parent, but it can cross the other way, into a sibling, and a
  binding is the right shape for a flag that moves every frame: no handler to
  miss an edge case where the value is already what it was set to, and no
  ordering requirement on `toggleFor`. (It was a push from a change handler, and
  `hoverCarry` had to be set *before* `open* or the handler latched the flag true
  with `hoverCarry` still false and never fired again.)

  Hiding the pill was never more than a workaround for the panel landing on top of
  it, and it was worth two bugs to stop doing. `visible: false` is skipped by the
  layout that positions the pill, and quickshell reads this pill's `magnet` at
  the instant the popup is shown, so the anchor was being read off geometry that
  was mid-flight and the panel landed up to half a pill off, in whichever
  direction that layout pass happened to fall. Opacity 0 fixed that one and left
  a second: the widget disappeared whenever its panel was open, which is a poor
  thing for a widget to do when the panel is meant to look like it belongs to it.

  An outside click is dismissed by the compositor (the popup is
  an xdg_popup); Escape closes, through a `Shortcut` rather than a `Keys` handler,
  because a `Keys` attached property only ever sees a key that some item in the
  window holds focus for and with the timer form empty nothing in this popup does
  — that handler was dead code until it was measured (see "Behaviour notes" below).
- **Right/middle-click does nothing.** A dead gesture that still highlights the
  pill just reads as a bug.

### The morph

Modelled on Caelestia's `BlobRect` (`modules/nexus/common/BlobPopup.qml`): the
button and the popout are *the same rectangle*, and opening is that rectangle
growing. Material 3 "expressive spatial" is a spring; QML has no spring easing, so
it is two segments — `0 → 1.04` over 210 ms `OutQuart`, then `1.04 → 1` over 90 ms
`InOutSine` (≈300 ms, fast out, small overshoot, settle). Closing is 200 ms
`InQuart` with no `from`, so it can interrupt a half-finished open without a jump.

- **One shape, one `t`.** A single `Rectangle` interpolates width, height and
  radius off the same `t` the content's opacity rides — one clock, so nothing can
  drift out of step. The panel is that rectangle's own `clip`, so the content is
  revealed edge-first, by the shape opening up, rather than fading in over it.
  The corner runs `Tokyo.pillRadius` → `Tokyo.panelRadius` off `t`, and both
  tokens are **10** — Hyprland's own `decoration.rounding` in
  `~/.config/hypr/hyprland.lua` — so today the corner does not animate at all.
  It is still interpolated rather than written as a constant: the two tokens are
  separate so the run comes back the moment one of them is dialled, and the
  argument for keeping it is that a corner that never changes reads as a
  rectangle that was resized rather than a widget that opened. The two top
  corners are the widget's own, so its outline rounds out as it opens instead of
  popping. Every *surface* in the shell wears the same 10 — bar, pills, panels,
  flyouts, tooltip, tray menu, clock panes — so a quickshell surface reads as a
  Hyprland window. Only surfaces: a button or a slider track inside a panel is a
  different scale of thing and keeps its own radius. What a control does not get
  either is a radius past half its own height — a 2 px underline with r=2 is a
  lozenge, not an underline — so the three elements that needed clamping all
  clamp: `Workspaces`' 2 px active underline and `TimerPanel`'s 3 px
  progress bar to `height / 2`, and `TrayMenu`'s separator rows to
  `Math.min(6, height / 2)`, which leaves its 30 px rows at 6. (`decoration.rounding_power`
  is 2, so a *large* Hyprland window's effective corner is rounder than 10; 10 is
  what a 26 px pill and this panel are being asked to match.)
- **The fill is the pill's fill for the whole morph**, and not a fade from it to a
  panel colour: the panel *is* the pill, grown. Fading to an opaque near-black made
  this the one surface in the shell that did not match the bar it grows out of.
  The token is `Tokyo.panelFill` rather than `pillBg`, because the panel is opaque
  and `pillBg` is `rgba(47,51,77,.9)` — over the bar it resolves to about
  `#2d3049`, a unit off `#2f334d`, so either value would sit right on its own
  widget at rest. What is not negotiable is the *lit* widget, which is opaque
  `#2f334d`: the widget does not go away when its panel opens, it sits directly
  on the panel's top edge for the whole morph, and the joint puts the two fills
  side by side. At `#2c3149` that was a 3-unit step between two touching surfaces,
  which is the one place a step that small is actually visible. So the panel takes
  the pill's raw RGB and the step is gone — the widget, the notch patch and the
  fillet are all literally the same material.
- **No border on the shape**, and that is load-bearing twice over. A `Rectangle`'s
  border is drawn *inside* its rect, so a 1 px stroke would shrink the fill: at
  `t=0` the shape would be a pixel narrower and shorter than the pill it stands in
  for — the click makes the widget visibly flinch — and the stroke would sit one
  pixel above the clock's cap height, a hairline ruled across the top of the
  digits. Without one the rect *is* the painted area: `t=0` is the pill's rect
  exactly, and the content is laid out against the same edges with nothing
  clipped. The panel's edge is defined by the fill itself, as it is for every
  other widget in the bar.
- **The panel has no header band, and the panes sit one `pad` below its top edge.**
  `panelH = pad * 2 + cellH` and the grid is at `y: root.pad`. The
  `pillH + headerGap` the band used to hold above the grid went out with it: a
  centred `time and date` label at 11 px with letterSpacing 1, and a 1 px rule
  under it. The `pad` is not a new margin invented for this — it is the one the
  panel already had on its other three sides, so the panel is now padded on four.

  The label was a name for the panes, not a reading: the CLOCK pane has the time
  and the date at a size worth reading, and the widget above had both again. A
  header that read `21:58:03` over `Sun 27 Sep` would have been the same two
  numbers the widget above it is already showing, 60 px down the same screen,
  while the widget goes quiet for exactly as long as the panel is up — so the
  panel would be the only place the clock is readable, which is the arrangement
  the whole bar was collapsed to get away from. Dropping the band is the same
  argument taken further: with the readings gone there was nothing left for it to
  do but describe what sat under it.

  **Flush, with the panes on the panel's own top edge, was tried and rejected.**
  It broke two things at once, and only one of the two was ever seen.
  `pillMouse` is a later sibling of `panel` and so topmost in the input stack,
  and a `pillH` strip off the shape covers cell y 0..26 — both title rows and 20
  of the 22 rows of each glyph button — so a press on either would close the
  flyout instead of pausing or stopping. That one is an argument, not a
  measurement: sibling declaration order plus arithmetic. It could not have been
  observed here either, because every synthetic press dismisses the xdg_popup
  whatever the coordinate space, and `TimerState` has no IPC path, so no timer
  can be created and no press routed to a button. The other *was* a capture —
  `paneEdge` at device y 69 — and it is the one that wanted a live process: a
  pane flush with the panel's own edge does not read as a bordered card. It *is*
  drawn there, but with no air outside it, it reads as the panel's own outline
  rather than the pane's. The `pad` fixes both with one number, and the strip it
  leaves is bare panel fill — which is what a click-to-close target should be
  anyway. The cost is 12 rows of top margin against the `pillH + headerGap` the
  band held above the cells, so the panel is `pillH + headerGap - pad` shorter at
  the top — less the 4 the buttons put back into `cellH`'s chrome, which comes
  to 22 rows on the whole panel: a height of 438 with the band
  (`pillH + headerGap + cellH + pad`, at the 51 chrome) against 416 with
  `pad * 2 + cellH` now.
- **The content does not move or reflow during the morph.** The grid is sized
  from `root.panelW` and placed in a nested `panelSpace` item that
  *is* the final panel rect — `panelW` wide, `pad * 2 + cellH` tall — in window
  coordinates: `x: (shape.width -
  root.panelW) / 2` puts the final panel's left edge into the shape's own still-
  moving coordinates, so the content stays nailed to the same global pixels while
  the clip grows around it. Two ways to get this wrong, both paid for: anchored to
  the parent, the grid's width went 69 → 174 → 438 across the open; positioned
  in *window* coordinates while being a child of the already-offset `panel`, every
  child landed `room` (18 px) right of where it belonged — the panes shoved
  off-centre and the right-hand one clipped by the shape.
- **Anchoring the morph's origin.** The window's top edge has to land on the
  pill's top edge, and `Edges.Top` is the intent. The anchor is the pill's **1×1
  `magnet`** (`Clock.qml`), a dot on the pill's top edge, centred across — a
  dot-sized rect makes "its centre" and "the pixel I meant" the same pixel, so
  there is no half-pill of rect for a centring rule to be ambiguous about. It is a
  child of the pill, so it cannot drift from it, and it is positioned from the
  pill's `implicitWidth` rather than its laid-out `width` for the reason in the
  opacity note above.

  **There are no `anchor.margins` in the final code, and there is a good reason
  they are gone.** For a day and a half `toggleFor` carried `left: -pillW` to undo
  a half-pill sideways error that was measured as real — the open panel's fill
  landing 46.5 px right of the closed pill's — and a matching `top: -pillH/2`.
  Both were compensating for this config's own bug. `Bar.qml` hid the pill with
  `visible: false`, a hidden item is skipped by the layout pass that positions it,
  and quickshell reads the anchor rect *at the exact instant the popup is shown*,
  which is that same instant the pill is hidden. So the anchor was being computed
  off a pill whose geometry was mid-flight, and the panel landed up to half a pill
  off in whichever direction that pass happened to fall — which is also why three
  separate measurements of the same code disagreed with each other (682, 775.75,
  729.5 for the panel's left edge) and why the "error" was not reproducible across
  a restart. Opacity fixed the layout; not hiding the pill at all fixed the rest.
  `Edges.Top` with no Left/Right edge puts the window's middle on the anchor's
  middle — the pill's centre line, as a morph wants — with no correction in it at
  all.

  Measured after, on a live process driven by real clicks: the open panel's fill
  spans **728.5..1190.0, 462 wide, centre 959.25**, and the closed pill's fill
  spans **941.0..977.5, centre 959.25** — the same centre to the pixel, and the
  same in every frame of the burst. The width is still `panelW` and is unaffected
  by anything since. The vertical figures that were taken with it are **not
  restated**: they were measured on a layout that no longer exists, and every one
  of them moved when the band came out. The panel's top is still the pill's
  bottom — that is what `drop` is — and its height is `pad * 2 + cellH`, which
  is the number to read off the code. Nothing is left
  over and there is no nudge constant to tune either: 2.5 px of extra margin
  moved the placed surface 0.57 px, so a sub-pixel correction is not expressible
  through the anchor in the first place.
- **Both edges travel, and the panel ends flush under the widget.** `shape.y` is
  `drop * min(1, t)`, with `drop = pillH` (26) — exactly the pill's height, because
  the window's top edge is the pill's top edge and nothing above that moves. The
  bottom edge runs down `panelH − pillH` while the top walks down 26, so at `t=1`
  the panel's top row lands on the pill's bottom row: one column of shapes,
  attached. Measured: the widget's fill at y 6.0..32.0, the panel's at 32.0 down
  `pad * 2 + cellH` — no gap, no overlap, the joint on the pixel it was designed
  to be on. (The y that closes that range was measured with the header band in
  place and is not restated.)

  The `min(1, t)` is load-bearing and the `1.04` overshoot is why. An overshooting
  top edge would push the panel's top row back up into the bar's padding, which is
  a joint re-opening. Capping it means the settle is expressed in the bottom edge
  alone, where it cannot move a joint. Traced through the whole burst:
  `shapeY` 0.0 → 6.5 → 11.8 → 16.0 → 19.2 → 21.7 → 23.5 → 24.9 → 25.8 → 26.0,
  holding 26.0 through the overshoot while the width went 37 → 458 → 479 → 462.

  The top 26 px of the window is therefore empty at `t=1` — it is the widget's own
  row, which the panel has moved out from under. That is why the panel's top lands
  on the bar's lower 4 px of padding; the pills either side are at the two ends of
  a 462 px gap, so there is nothing for the overlap to land on.

  **This is the third attempt at the connection, and the first two are both
  instructive.** The first had the top edge slide down out of the bar
  (`drop: 12`, `shape.y = (pillH + drop) * t`) with a narrow tab — the "neck" —
  bridging the gap to a panel that hung clear of it, so the flyout read as a
  widget that had been replaced by a panel on a stick. Three things were wrong at
  once: the tab's top corners were square, because the rounded bottom of the pill
  they used to be was no longer drawn; the tab was connected to nothing, since the
  widget's own readings had gone with it; and the replacement label ended up
  *inside* the panel, where it labelled the panel. So it was pinned — a top edge
  that never moves, the panel growing out of the widget's underside, and the
  header doubling as the widget's own row.

  That worked, and it is what the bar ran for a while. What it could not do was
  move the panel *down*, because the panel's header *was* the widget's row: a
  header below the widget had to replace something, and the only things there were
  the time and the date. The fix was not in the geometry at all — it was taking the
  readings out of the *header*, which left it free to be a header. The widget kept
  its clock the whole time; it just goes quiet for as long as the panel is up. The
  geometry is one rectangle with both edges moving and the widget it comes off
  still drawn the whole way, which is not the tab-on-a-stick shape.
- **The joint is a cusp, and the corner is added back in the popup.** The widget's
  bottom edge and the panel's top edge are the same line and *both* round it away:
  the widget in the bar's window, the panel in this one. The two roundings meet at
  a cusp — the widget's corner arc arrives at the joint travelling rightwards and
  the panel's top edge leaves it travelling leftwards, so the outline doubles back
  on itself and the widget's corner tapers to a point resting on a flat line.
  Neither half can be given up (the widget's corner belongs to the widget, the
  panel's to the panel, and they are painted by two components in two windows), so
  the corner is added back over the bar, in the flyout window, *below* `shape` so
  the shape's own top edge reveals it edge-first. Two pieces, both cuts from the
  outline rather than shapes of their own:

  - a **fillet** — a quarter disc of `ShapePath`s in `shape.color`, mirrored, from
    the widget's side out to the panel's top edge, so the top edge runs up and over
    into the widget's side instead of stepping out to it;
  - a **notch patch** — two plain `Rectangle`s of `pillRadius`² at the widget's
    bottom corners, in the widget's own colour, squaring off the corner the shape
    has not covered yet.

  What is left is *one arc*: the widget's side, the fillet, the panel's top edge,
  with the same vertical tangent at one end and the same horizontal tangent at the
  other, and no corner anywhere along it. `fillet` is
  `min(drop - pillRadius, shape.y)` — the first term is the largest arc that fits
  the widget's own straight side (a `pillRadius` round rect of height `drop` is
  straight only from `pillRadius` to `drop - pillRadius`, and the arc's tangent
  point has to land in that run or it starts on a row that is already curving and
  kinks; at that maximum the fillet meets the widget's own corner exactly where
  that corner becomes vertical, so the two arcs join without a break), the second
  caps it at the *live* top edge. Neither piece is faded in, and that is the part
  that took the thinking: the joint's resting place is a constant and the morph
  moves the top edge for 300 ms, so anything drawn at the resting place and faded
  in at the end spends that time hovering above an edge that is still short of
  where it will end up — the shoulder comes in as a wedge hanging in the bar,
  which is the silhouette this whole arrangement exists to lose, only fainter.
  Tied to the edge instead, both pieces are simply *at* the joint in every frame;
  the fillet degenerates to a point at `t=0` and so needs no opacity of its own.
  `patchMix` is tied to the edge for the same reason and for one more: until the
  edge is level with the widget's bottom the shape is painting over that corner
  in its own fill, so a patch at full strength from the first frame is a lit
  square sitting on the panel's own rows for two thirds of the morph. The patch
  reads `pill.color` rather than a Tokyo token so it follows the widget through
  its own hover state, and since the panel's fill *is* the lit pill's RGB it is
  also the same colour as the fillet beside it.

  Verified by screenshot on a live process: every row from the widget's mid-height
  to the panel's top edge is a single contiguous run of material — 0 holes, cusps
  or notches — the fillet's traced boundary is a 16 px quarter circle, and there
  is no white pixel anywhere in the joint. Closed, the joint leaves nothing behind:
  the only material outside the pill is the pill's own antialiasing.
- **The face is on the widget, and it was never in the panel at all.**
  `panelSpace` is the final panel rect — `panelW` wide, `pad * 2 + cellH` tall —
  in window coordinates, so anything in it is on the panel's own rows from the
  first frame and clipped by the shape. The panel's first band used to be a
  `headerLabel` filling it and is now `pad` of margin above the panes. The face
  is not in that space: the flyout keeps
  a second `ClockFace` outside the clip, nailed to the widget's own pixels
  (`y: 0`, the window's own top 26 rows, which *is* the widget's rect at every
  value of `t`). It cross-fades the readings into the glyph over the first ~50 ms
  of the morph and stays — no fade-out at the end, no scale at any point. Both
  copies read the same `glyphMix` and the same `now`, so they are the same face at
  the same pixels in the same colour, and which one is drawing is not a thing you
  can see; the only job the second copy has is to be there until the shape's top
  edge has walked down past the widget.

  That copy is **not** there because the bar's stands down — it never does. It is
  there because the shape *covers* the bar's copy until its top edge has walked
  down past it, and a widget that loses its clock on the very click that opens it
  is the one pop this morph cannot afford. An earlier arrangement had the copy
  fade out over the last fifth of the morph *and* shrink as it went, which was
  safe only because it was then the only widget face on screen; against a
  stationary copy underneath, a copy that changes size is the stationary thing
  changing size twice.
- **The window is sized to the finished shape**, plus an 18 px transparent
  `room` on the three sides it can grow towards (downwards from a fixed top edge,
  and sideways from a fixed centre), plus `drop` for the top edge's journey down to
  under the widget: the surface is created once at show time, so resizing it per
  frame would be a compositor round-trip per frame. The margin is what gives the
  1.04 overshoot somewhere to go, and the `MouseArea` over it turns it into
  click-to-dismiss. Across it is `panelW + room * 2` and down it is
  **`pad * 2 + cellH + room + drop`** — both formulas, deliberately, because every
  absolute written here went stale the first time a constant moved and one of them
  was already 3 px wrong before that. The shape's height is capped at
  `implicitHeight` so the overshoot cannot push its bottom edge off the surface. At
  `t=0` every row of the window below the widget's own `pillH` is empty bar.

  The click-to-close is a second `MouseArea` bound to the **shape**, not to the
  face: at `t=0` the shape is the pill's rect and this is the widget, at `t=1` the
  shape is the panel and this is the `pad`-tall margin above the panes, and in
  between it slides down with the joint — one area covering both ends instead of
  two. Its width is `shape.width`, so the strip is as wide as whatever it is
  covering. The widget's own row closes the panel too, by falling outside the
  shape and hitting the click-to-dismiss above.

  **Its height is `pillH` closed and `pad` open, interpolated on `t / contentIn`**
  — and it has to be, in both directions. Left at `pillH` it would still be 26
  rows, which past the 12 rows of top margin is 14 rows into the cells: 4 of them
  in `headerRow`, from QuadCell's `pad` 10 to `pad` + `headerH` 24, and 8 of them
  in the 22 the glyph buttons are (it is a later sibling of `panel`, so it is
  topmost); shrunk to `pad` it would stop closing the panel from the widget's own
  row. Ramping on `t` rather than on the content's own fade-in would leave the
  strip over those rows until `t` is 0.57, by which point the panes are 44%
  opaque, so the ramp is `contentIn` and the strip is down to `pad` on the frame
  the content starts to appear. That is the real reason the panes are inset by
  `pad` rather than flush: the margin is not decoration, it is the
  click-to-close target.

  It reads `shape.x` / `shape.y`, **not** `shape.left` / `shape.top`. Those look
  like plain coordinates and are documented as "the same as x", but in Qt 6 on
  any anchored item they are the *anchor lines* (`QQuickAnchorLine`), and
  assigning one to a `qreal` is 0 with no warning at all. This `MouseArea` once
  read `face.x` / `face.y` off a face that *was* anchored, and sat at the window's
  left edge, 202 px from the thing it was meant to cover: clicks on the header
  closed the panel only because the old `drop` geometry put them outside the
  shape, and `containsMouse` was always false, so the hover highlight never
  followed the pill into the morph either. `shape` is positioned by hand rather
  than by anchors, so its `x` and `y` are the plain coordinates they look like.
- **The two panes**, 214 wide each with a 10 px gap inside a 12 px-padded panel:

  | | |
  |---|---|
  | **TIMERS** (magenta) — the full timer panel: up to five rows at the top, the creator form at the **bottom** | **CLOCK** (blue) — three stacked blocks, each under its old cell title in the old cell colour |

  The clock pane's blocks, top to bottom:

  | block | |
  |---|---|
  | **TIME** (blue) | local `HH:mm:ss` at 28 px, a rule, then New York / Los Angeles / Tokyo with day delta, zone abbreviation and clock |
  | **DATE** (yellow) | weekday at 24 px, `27 September 2026`, and the machine-readable `2026-09-27 · week 39 · day Sat` |
  | **UPTIME** (teal) | `3d 04h 12m` at 28 px, boot timestamp, and how many full days |

  It started as a 2×2 grid of four cells. Four cells meant four titles, four
  rules and four sets of insets to keep in step, and the timer form — the one
  pane with something to type into — was squeezed into a square. Collapsing the
  three time-ish cells into one stacked pane gives the timers a full-height
  half of the panel without widening it, and leaves the panel
  `pad * 2 + cellH` tall where it had been 556 (2 × 258 of cell + 2 × 10 gap +
  2 × `pad`).
- **The panes are glass on glass, not holes in the panel.** `QuadCell`'s fill used
  to be `Tokyo.bg` (`#1e2030`) and its border and every rule in the flyout used
  `Tokyo.bgHighlight` (`#2f334d`) — and both of those were the wrong colour for
  the surface they sat on. `bg` is *darker* than the panel they cover (the panel
  is `panelFill`, `#2f334d`), so each pane read as a black window punched through
  the widget; and `bgHighlight` is literally the panel fill's own RGB, so the pane
  borders and the header rule were dividers drawn in the exact colour of what
  they divide — 2–3 units of difference per channel, i.e. nothing. Now:

  | token | value | sits on | step against it |
  |---|---|---|---|
  | `Tokyo.pane` | `#394161` | `panelFill` `#2f334d` | +10, +14, +20 |
  | `Tokyo.paneEdge` | `#454c65` | pane, the panel's pad, the entry field | +22, +25, +24 |
  | `Tokyo.hairline` | `#485172` | pane | +15, +16, +17 |
  | `Tokyo.dim` | `#7983a4` | pane | +64, +66, +67 |

  **Fixed values, not washes.** These were originally `rgba()` films over the
  panel, which meant the panel took its colour from whatever happened to be
  behind it — the same pane measured `#394161` over a terminal and `#394162` over
  a photo viewer, and the rules drifted with it. Every value in that table is
  what those films actually composited to, read off the screen rather than
  computed, so the panel is the same panel over any wallpaper. The one thing
  translucency did buy was the pane reading as glass over a bright window, and
  that is worth less than the panel being itself.

  One rule colour, and that is a consequence rather than a choice: the panel's
  header and its 1 px `headerRule` are gone, so every rule in the flyout is
  `hairline` and every one of them is inside a pane. With the band there were two
  — `headerRule` sat on the panel's own fill, so it was a darker fixed value
  where `hairline` was a lighter one over `pane`, and the pair read as two
  weights where one surface had one. Nothing outside a pane is ruled any more, so
  there is nothing for a second value to distinguish itself from.

  `paneEdge` is a step stronger than `hairline` on purpose — a card reads as a
  card because of its outline, and an outline at rule strength is lost in the
  fill on the far side of it.

  The last row is a gotcha rather than a choice: the zone rows' abbreviation and
  their "same" delta were **dimmed by borrowing the surface colour**
  (`bgHighlight` as a text colour, which is also what the rule above them was
  using). On the old near-black pane that was merely faint; on a lifted pane
  `#2f334d` lettering is not de-emphasised, it is unreadable, so both ride up
  with the surfaces. Anything that used a surface colour *as text* has to be
  re-checked whenever the surface moves.

  Deliberately **not** lifted, because they are inputs and gauges rather than
  surfaces: the slider track and the progress track (`bgHighlight`). A darker
  inset on a lighter card still reads as a recess, which is what they are — and
  unlike the card they are allowed to be dark, because a recess is supposed to be
  darker than the thing it is cut into. The creator's text field keeps the recess
  but could not keep the token: a `bg` field on the lifted pane is the black
  window the paragraph above is about, so its fill is `panelFill`, which is still
  darker than the `pane` it sits in and so still reads as a hole cut in the card.
  Its border and placeholder had to move off `bgHighlight` for exactly the reason
  `bgHighlight` gave for the pane borders: it is the panel fill's own RGB, and
  the field's new fill is the panel fill, so a `bgHighlight` border on it is a
  border drawn in its own fill colour and a `bgHighlight` placeholder on it is
  the fill's own RGB again — invisible on it. Hence `paneEdge` — the same
  +22/+25/+24 step, against the fill this time — and `trayGlyph` for the
  placeholder.
- **`cellH` is measured, not chosen.** It is `55 + clockTail` — 55 is
  `QuadCell`'s own chrome, and that cell's constants are the definition (`pad` +
  `headerH` + (`gap` + 4) + 1 rule + `gap` + `pad`; the same arithmetic spelled
  out beside `cellH` in `ClockFlyout.qml`) — and `clockTail` is the bottom of
  the last clock block. The block heights are font metrics and the zone count is
  data, so a hand-written constant would be wrong the moment a zone is added —
  and a wrong constant is not cosmetic, it cuts the bottom of UPTIME off.
  Measure from the last anchored child (a block's `bottom` collapses onto its
  `top` if its `height` is unset, and the blocks are plain `Item`s) rather than
  reading a positioner's implicit height, which is only correct once every child
  has polished.
- **The timers pane splits top and bottom.** It is as tall as the clock pane's
  three blocks while its own content is a couple of hundred pixels shorter. The
  list stays at the top and the creator form is pinned to the **bottom** of the
  pane, so "what is running" and "set one up" are the two ends of one pane and
  the slack between them reads as the gap it is — rather than the form floating
  in the middle of nowhere, or (the first attempt) the whole thing centred with
  the void dumped underneath. `TimerPanel` grows a `pinFormToBottom` property for
  this; the standalone window used to leave it off, being exactly as tall as its
  content, but it is gone now and the flyout is the only host. The form does not
  move as timers come and go — it is pinned to the pane's bottom edge and the
  list is what grows. (A measured y range used to be given here; it went with the
  header band and has not been re-measured, so it is not restated rather than
  restated wrong.)
- **The row cap is derived from the space, not written down.** `listCap` is the
  gap between the top of the panel and the rule above the form, so the list runs
  down to the slider instead of stopping short. It was a hard-coded two rows,
  which was right for the old 258 px square cell and left a 160 px hole in a pane
  twice that size. Five 36 px rows is what fits, and re-deriving the cap from the
  code confirms the count while correcting the arithmetic behind it. With this
  machine's `JetBrains Mono Nerd Font` metrics (a 10-px text is 13 px tall) and
  the three zones `clock-panel.sh` lists: `cellH` is 392 — `QuadCell`'s 55 px of
  chrome plus a 337 px clock pane — the form is 90 (a 26 px readout, 8, a 22 px
  slider, 8, a 26 px entry row), so `listCap = 337 − 90 − 20` = **227**, and
  `floor((227 + 8) / 44)` = **five rows**, 15 px to spare. The old text gave 224
  available and 248 for a sixth; it is 227 and 256. The count was right; the
  numbers around it were not.
  Moving the title rule down 4 px for the title row's buttons moved the chrome
  from 51 to 55 and **none** of this. That looks like it cannot be true, since
  the rule sits between the title and the body, so the obvious reading is 4 px
  off the list: `listCap` at 223, 11 px spare, and the same five rows. That is
  what it *would* be if `cellH` had stayed put. It did not — `cellH` is chrome +
  clock pane, so raising the chrome raises `cellH` by the same 4 and the body
  the panes actually get is `cellH − chrome` = the tail = 337, unchanged. And
  `cellH` cannot be left alone: the moment it is wrong by 4 the bottom of the
  UPTIME block is cut off. So the 4 px was always going to come out of the
  list's spare 15, and the `cellH` change is what stops it — 227, five rows and
  15 px of slack are exactly what they were before the rule moved.
  Deleting `TimerCreator`'s hint line moved none of this, which is worth writing
  down because it looks like it must have: `implicitHeight` read
  `hint.visible ? … : …`, and the only host passed `roomy: false`, so the false
  branch was always the one taken and the hint was never in the form's height to
  begin with. It was invisible *and* free — the case that reads like a layout
  change and is not one.
  Both sides of the subtraction are unstable — the pane's height is itself
  measured off the clock pane's font metrics, and the zone count is data — so a
  literal would be wrong the moment either changed, and wrong here means either a
  hole or rows running under the form.
  Rows stay at 36 px rather than the retired window's 46: the space is filled
  either way, and five rows show more timers than four. `TimerPanel.rowH` used
  to *declare* 46 while its one and only host passed 36 over the top, so the 46
  never took effect and the comment beside it described a value that was not
  live — the default is 36 now and the host says nothing, so the number is
  written down once. 36 is a ceiling rather than a preference: `capacity` is
  `floor((227 + 8) / (36 + 8))` = 5, and 15 px of spare is all there is, so a
  row could grow to 39 and no further before the count dropped to four.

  **What that ceiling buys, and what it does not.** A 36 px row carries the big
  countdown, the "of mm:ss" line and the 3 px bar. Measured inside one row: the
  big time's ink is 12.0 px and the small line's is 6.5 px — each one a count of
  inked *device* rows, both ends included, halved, which is why they do not
  subtract cleanly out of a y-range — the bar is 3 px, and there is
  **1 logical px** between the small line's ink and the top of the bar.
  That is tight, and it is not a cut — nothing on the row has `clip: true` and
  nothing has `elide`, so nothing has ever truncated vertically. It is not
  fixable by growing the row either, because 2 px of air costs nothing but 4 px
  costs a whole row. So it stays, and is written down here as what it is:
  tight, and by design.

  **The overrun was horizontal, and it was one string.** The small line's column
  is 86.8 px wide in a 193.5 px row — the three buttons start 114 px in. Measured
  in that budget at this font's 5.41 px advance: `of 5:00` is 37.8 px,
  `of 30:00` is 43.3, `paused · of 5:00` is 86.5 (a knife edge), and
  `paused · of 30:00` is **91.9 — 5.1 px over**. So only a paused 30-minute
  timer broke out of its box, and it broke out into the 8 px gap before the
  buttons, which is 2.9 px clear of the pause `PillButton`. Nothing was ever
  cut: no item on the row has `clip: true` and neither `Text` has `elide`, so
  every glyph painted, and the string simply ran past the width of the column
  that owns it. The `paused · ` prefix is gone: the row already says paused
  four other ways (yellow time, yellow glyph, yellow button, yellow bar) and
  it was the only one of the five that did not fit. Every state reads
  `of <total>` now, finished rows included.
- **The cap is now silent, and that is a known gap.** The overflow line used to
  read "+N more — full list in the timer window" and point at `TimerWindow.qml`.
  With the window removed the line was *deleted* rather than reworded, so past
  five running timers the sixth is not drawn and nothing says so — a pane showing
  five of six reads as if the sixth had finished. `TimerPanel.hidden` still
  computes the number for anything that wants it. The two fixes that were not
  taken, both being design changes rather than deletions: put the count in the
  host's title row (which `QuadCell` already has, and which already carries the
  pause/stop pair), or drop the cap and let the list grow — the latter means the
  two panes stop being the same height, since `cellH` is measured off the clock
  pane.
- `pinFormToBottom` fills the pane with `height: parent.height`, which is why
  the panel is anchored `top`/`left`/`right` and **never** `top`+`bottom`:
  anchoring both makes the anchors own the height, and assigning `height` on top
  of that is a binding loop. The rule above the form and the form itself are
  placed with `y` bindings rather than `top` anchors, because they need two
  branches each and **an anchor bound to a conditional keeps the value it was
  first given**.
- **Where the data comes from, and why it is uneven.** Local time/date and the
  boot timestamp are plain JS `Date` arithmetic on one in-process tick per
  second — no subprocess. The other timezones and the uptime seconds come from
  `scripts/clock-panel.sh`, because quickshell's JS engine has **no `Intl` and no
  `TimeZone` QML type** (verified on 0.3.1 / Qt 6.11) and
  `toLocaleTimeString` silently *ignores* a `timeZone` option instead of failing
  — every city would show local time under its own name. The script prints
  `<uptime-secs>|<City>\tHH:MM:SS\t<delta>\t<abbrev>|…` on one line, one `date`
  fork per zone, with the day delta from `year*366 + dayOfYear`. The poll is
  bound to `visible`, so a closed flyout forks nothing.
- **No hover tooltip.** The old timezone tooltip is redundant now that the
  flyout shows the same zones, and an earlier 250 ms hover flyout was already
  cut.
- Quickshell 0.3.1 gotcha: a `PopupWindow` set `visible: true` **declaratively,
  in the object body, never maps** — the surface does not appear and no warning
  is logged. It has to be assigned after construction (`root.visible = true`),
  which is what `toggleFor()` does. Worth knowing before trying to force a popup
  open for a screenshot: it silently does nothing.
- **`Keys.onEscapePressed` only fires if some item in the window holds the
  focus**, and nothing warns you when none does. The retired `TimerWindow.qml`
  got away with it because its box set `focus: root.visible`; the clock flyout's
  identical handler was dead code, and Escape did *nothing* with the panel open —
  measured, not assumed, by hanging a temporary `IpcHandler` off the bar that
  printed `open`/`visible`/`t` back over `quickshell ipc call`, which is a
  generally useful way to read this shell's state when a screenshot cannot tell
  you a boolean from a `null` (and the only thing that import was ever for, so
  `Bar.qml` no longer carries `Quickshell.Io`). The fix is a `Shortcut`
  (`context: Qt.WindowShortcut`), which is matched against the window rather than
  a focus item and also outranks the timer form's text field. Two other things
  that measurement settled: an xdg_popup is **not** dismissed by Escape (so there
  was no second route), and a popup that the compositor *does* dismiss never
  reaches `hide()` — the `onVisibleChanged` block is what puts the state back.
- **`Item.left` / `top` / `right` / `bottom` are anchor lines, not coordinates.**
  They read as plain numbers and the docs say `left` is "the same as `x`", so
  `x: face.left` looks like the obvious way to place something over another
  item — and assigns **0**, with no warning of any kind. The flyout's
  click-to-close `MouseArea` had been sitting at the window's left edge, 202 px
  from the header it was meant to cover. It was invisible for two reasons: the
  old geometry put header clicks *outside* the shape, so the catch-all
  `MouseArea` under everything closed the panel anyway, and `containsMouse` was
  permanently false, so the hover highlight never followed the pill into the
  morph. Found by logging the rect from a click that a sibling `MouseArea`
  received inside the claimed bounds. Use `shape.x` / `shape.y` — and know that
  they are safe *only* because `shape` is positioned by hand rather than by
  anchors. The same trap on a *bound* property is worse than silent: it is a
  binding loop rather than a zero.
- **A `MouseArea`'s hover state cannot report a pointer it never heard about.**
  `containsMouse` only changes on a *motion* event, and the ordinary case for a
  popup is mapping under a pointer that has not moved since it arrived on the
  widget — so the fresh answer is "not hovered" and the widget visibly cools off
  under the cursor on the very click that opened it. `hoverCarry` latches the
  bar's own `hovered` flag in `toggleFor`, while the bar's `MouseArea` is still
  the one under the pointer, and the shape and the face both read that.

  The same silence runs the other way and is worse: while the popup is up the bar
  gets *no* events at all, so a widget that lit itself by hover goes dark for as
  long as its panel is open. Latching is not enough — the flag has to reach the
  pill, which is why `Module` has `hoveredExtra` and a readonly `lit` that the
  paint reads. One trap, paid for, and then removed: a binding *from* the pill
  *into* the flyout cannot cross (it is a sibling, and QML bindings only run
  child-ward), so this was first done as a push from a change handler, and a
  push needs `toggleFor` to set `hoverCarry` *before* `open` or the flag latches
  true with `hoverCarry` still false and the handler never fires again, leaving a
  lit pill in the resting colour for the whole time the panel is up. A binding
  the *other* way — pill *to* flyout — has neither problem, so that is what it is
  now, and `toggleFor` sets the two flags in whatever order it likes.
- **An opaque fill cannot spend an alpha-only hover.** `pillBg` and
  `bgHighlight` are the same RGB (`47,51,77`) differing *only* in alpha (0.9 vs
  1.0), so the morph's hover tint was `mix()`-ing two identical greys and
  getting an alpha change out of it — the highlight was never a colour, it was
  0.1 of opacity over whatever was behind. Pin the fill opaque and both ends
  become two opaque copies of the same value, and `mix()` between them returns
  that value for every `f`: the hover silently stops existing, with nothing in
  the log. The tint therefore needed a real step in RGB, which is what
  `Tokyo.panelHover` is, faded out across the morph by `hoverTint = 1 - t`. Two
  consequences worth knowing: it stays *below* `pane` on purpose, because a hover
  target above the pane would turn the two panes into holes in a lit panel for
  the frames they are fading in over; and the shape is lighter than the bar pill
  for its first frames, which was read as the widget lighting up as it opens back
  when the bar's pill vanished under the shape and there was nothing to compare it
  with. That reading no longer applies — the pill stays on screen directly above
  the panel, so the step is between two surfaces that are touching, which is the
  worst place for a big one. `panelHover` is therefore `#353a55`, 6 units over
  `panelFill` (`#2f334d`), not the 30-unit `#454c65` it started at: the tint is
  a lift, not a different surface. The fill is a straight `mix()` of the two, so
  it walks `#353a55` → `#2f334d` as `t` goes 0 → 1 and settles on `#2f334d`, which
  is the lit pill's own fill and the panel's own.
- **A `ShapePath` left at its defaults strokes itself in opaque white.** Both of
  the joint's fillets carry an explicit `strokeWidth: 0`, and that is load-bearing
  rather than tidiness: on this Qt build the default stroke is a ~2 px band of
  opaque white, which no amount of `layer.enabled` or antialiasing reasoning
  accounts for. It reads as a rendering artefact, so the first instinct is to
  blame AA. Bisected instead by treating the two mirrored paths differently — one
  with the explicit zero, one without: **0** white pixels along 44 rows of the
  first, **155** along the second. Same shape, same colour, same frame.

## Switchover status (done)

The old waybar launch (`~/.config/waybar/waybar-tdelay.sh`) is replaced by
`quickshell -c tokyonight` in `hyprland.lua:66` — verified to auto-start at
login after a reboot. Waybar itself (the package) is uninstalled:

```
sudo pacman -Rns waybar
```

(The `-n` also removes its now-orphaned GTK/network deps. Use `-R` instead if
you want to keep them.) `~/.config/waybar/` stays on disk — it holds the
config/style.css design source and the GitHub backup; the bar reads nothing
from it at runtime.

## Files

```
shell.qml            entry point (ShellRoot)
Bar.qml              per-screen PanelWindow + module layout
Module.qml           reusable "pill" (radius 10, margins, hover/tooltip/click)
Tooltip.qml          hover popup styled like waybar tooltips
Poll.qml             interval script runner (waybar exec+interval equivalent)
Tokyo.qml            palette + geometry singleton
NetworkMonitor.qml  shared per-adapter rate/latency data source
Brightness.qml      shared DDC/CI brightness service (display map, debounced writes)
Workspaces/Cava/OpenApps/Wifi/Ethernet/Audio/Gpu/Cpu/Mem/Updates.qml
AudioFlyout.qml       popup with per-app volume + input/output device switching
TrayMenu.qml          SNI right-click menu rendered as a flyout (same look as AudioFlyout)
BrightnessFlyout.qml  per-monitor DDC/CI luminance slider (right-click a workspace pill)
Clock.qml             the one centre pill: HH:mm:ss over the date, a clock glyph
                      while its flyout is open (left-click → morph)
ClockFace.qml         frameless clock face — the readings, the glyph, the fonts,
                      the metrics, the width — shared by both ends of the morph
ClockFlyout.qml       the 1x2 flyout: timers | clock (time+zones, date, uptime) —
                      the pill's own rectangle, grown rather than replaced
QuadCell.qml          one titled cell of that pair (title, rule, padding, body slot)
TimerState.qml        countdown state singleton (timers, tick, fire + alert)
TimerPanel.qml        frameless timer list + creator, the only host of which
                      is now ClockFlyout's TIMERS pane;
                      pinFormToBottom + a space-derived listCap for the pane
TimerCreator.qml      the "new timer" block (slider + manual entry + START)
PillButton.qml        small flat accent button used by the timer surfaces
scripts/             all scripts + cava.config (waybar scripts, moved here)
assets/timer-done.wav generated chime (see scripts/make-timer-sound.py)
tests/               deterministic network-monitor regression tests
```

## Timer

Added after the waybar switchover, so it has no waybar counterpart.

- **Left-click the clock pill** opens `ClockFlyout.qml`, whose TIMERS pane
  carries the full panel: a 1–30 min slider (1-minute steps) plus a manual box
  that takes `25`, `25:30` or `1:00:00` and clamps to 1:00–30:00. Typing syncs
  the slider, rounding to whole minutes; the started timer keeps the exact typed
  value. Enter starts. Every running timer gets a row of its own — progress bar,
  pause/resume, +1 min, remove — and the pane's title row carries the same thing
  for all of them at once: a pause/resume toggle and a stop, both glyph-only. The
  toggle's glyph reads as the global state, exactly as a row's does — play while
  anything is still running, pause once nothing is — while the press itself is
  the opposite precedence: while a single timer counts, a press pauses the lot,
  because a global control must never *start* a timer the user can see not
  running. It greys out once the list is nothing but finished ones.
- **A row's progress bar is a playhead, and it can be dragged.** The grab area
  is a 12 px transparent strip on the row's bottom edge — big enough to hit,
  while the bar itself stays 3 px — and it is declared *before* the row's
  `RowLayout`, because a later sibling takes the clicks first and the three
  buttons reach down into the bottom 3 px of that strip. Two handlers drive it
  and they do the same arithmetic: **`onPressed` is the click** — it scrubs to
  wherever the press landed, so a click is a drag of zero length — and
  **`onPositionChanged` is the drag**, and it runs the same
  `TimerState.scrub(id, ms)`. Qt documents `positionChanged` as firing only
  while a button is down, so the `if (pressed)` test in front of it changes
  nothing on a Qt that behaves as documented; it is there so that a plain hover
  cannot rewrite a deadline if that ever stops holding. The bar's 250 ms
  `Behavior on width` is switched off for the duration of the press, because
  easing a playhead the pointer is driving leaves it trailing and settling
  somewhere the pointer is not.

  The rules are all "playhead", not "length": the value is clamped into
  `[0, totalMs]`, so **a drag can never change how long a timer is** — the
  `+1` button is the only way to do that, and `nudge()` is its only caller
  (it accepts a negative delta; nothing sends one). Two consequences are worth
  knowing, because both are reachable without any drag at all:

  - **A plain click near the *right* end of a running row's strip sets
    remaining to 0 and fires it** on the next tick. That is a click, not a drag
    — the press alone does it.
  - **A paused row dragged to 0 sits at `0:00` with a full bar and does *not*
    fire**, because `advance()` skips paused timers. It stays like that until
    resumed, and then it fires on the next tick. `scrub()` does not resume
    anything.

  A **paused** row is scrubbable and stays paused; a **finished** row is locked
  (scrub returns without touching anything), gets no grab area at all, and has
  its bar greyed to `trayGlyph` so the lock is visible. Its green time and green
  tick glyph stay green — those are the "done" signal, and the row stays on
  screen precisely because `+1` is the only way back from finished.

  **Hovering the strip for 500 ms opens a precise-entry box** above the bar,
  inside the row, so it cannot reach the row above. It is prefilled with the
  time **remaining** — the number the pointer is about to move, not the total —
  and **Enter commits it through `scrub`**. It accepts the same strings the
  creator's box does (`25`, `25:30`, `1:00:00`, one to three digits per part,
  digits only) because both validate the raw string against the same regex
  first; `Number("")` is 0, so a split-then-parse would have let `::` through
  as 0 ms and fired a running timer off a mistyped entry. Anything else throws
  the typed value away: the field losing the focus (which is also how Escape
  ends it, see below), or the pointer leaving the strip. The box does not
  appear for a finished row, and it cannot open mid-drag because the press stops
  its timer.
- **The box is closed by hand when the pane closes**, not left to the focus
  loss that normally dismisses it. `TimerPanel.reset()` walks the rows and
  closes each box, and the rows are reused rather than rebuilt, so a box left
  `visible: true` would still be up next time. The two things that would have
  dismissed it implicitly — Qt dropping item focus when a popup window is
  hidden, and a leave event reaching the grab strip on an unmapping surface —
  are not things this code can check, so the close does not depend on either.
- **Not exercised here: dragging past the end of a strip.** The grab area
  configures no drag target, so this rests on `QQuickMouseArea` stopping to
  deliver moves once the pointer leaves the item. If it does not, a drag that
  runs off the right-hand end of a strip would keep rewriting the deadline
  instead of freezing the playhead at the strip's edge. Untested.
- **There is deliberately no dismiss-on-Escape handler for that box.** It cannot
  work: `ClockFlyout` registers a window-level `Shortcut` on Escape and Qt
  resolves shortcuts before ordinary key propagation, so a handler on the field
  would never fire and would only be a lie in the source. Escape closes the
  whole flyout, and `reset()` closes the box on the way out either way.
- **The standalone timer window is gone**, along with its `SUPER + SHIFT + T`
  bind (`hyprland.lua`) and the whole `timer` IPC target that opened it, so there
  is no scripted route to a timer any more either. The flyout pane is the only
  surface. Of the two signposts it left behind, one is still a live gap — the
  list cap is silent, noted above — and the other is gone outright: the
  `roomy`-gated hint line in `TimerCreator` has been *deleted*, along with the
  `roomy` property that gated it in both there and in `TimerPanel`, so the
  field's `12 or 12:30` placeholder is now the only thing in the shell that says
  the box takes "minutes / minutes:seconds".
- **No timer badge in the bar.** The countdown pill is retired: the clock pill
  stays a clock, and what is counting is one click away. If a timer is running
  the pane's rows and the two title-row glyphs are the only sign of it.
- **The flyout resets its form on close**, so a panel dismissed by an outside
  click never reopens with half-typed minutes still in the box. It closes any
  open precise-entry box at the same time.
- **On completion**: `scripts/timer-alert.sh` plays `assets/timer-done.wav`
  (generated by `scripts/make-timer-sound.py`, stdlib only; override with
  `$TIMER_SOUND`) and a `notify-send` notification fires. Several timers landing
  on the same 200 ms tick share one chime and one notification.
- **State lives in `TimerState.qml`**, a singleton, and is **in memory only** —
  a bar reload (any file save) or a restart drops all timers. Deadlines are
  wall-clock, so a suspend that overshoots fires the alert on wake.
- **The first timer after an idle shell used to start part-elapsed.** The cause
  is worth writing down because it is invisible in the line that has the bug.
  `TimerState` keeps a single `now` that every view reads — that is what stops
  the pill, the pane and the tooltip from drifting apart — and the 200 ms tick
  that refreshes it only runs while `timers.length > 0`. So `now` is a **display
  cache, not a clock**, and it can be arbitrarily stale. `start()` was stamping
  `endsAt` off it, so the first `start()` after an empty list dated its deadline
  from a `now` frozen since the shell last had no timers: a 30-minute timer
  started after ten idle minutes came back with twenty left. It reads
  `Date.now()` now. Of the five functions that stamp `endsAt` it is the only
  one that *had* to change — `scrub()` reads the real clock too, but it only
  ever runs on a timer already in the list, and `togglePause`, `nudge` and
  `pauseAll` all need a live timer to act on, which means the tick *is* running
  and `now` is at most 200 ms old there, so they keep reading the cache.

Quickshell/Qt traps this feature ran into, all noted in the source:

- `IpcHandler` registers **single-line** function bodies only, and arguments
  need a concrete type (`minutes: string`).
- `show`/`hide` are inherited from `QQuickWindow`: a QML function of that name
  on a window is silently never called, and the `quickshell ipc call` CLI answers
  a function named `show` with the target's function list instead of dispatching
  it. Hence `open`/`close` throughout.
- A **positioner can be polished before its children exist** and never polished
  again, so a `Column`/`GridLayout` here left every child stacked at y=0 and the
  panel half a block too short. The panel body, the creator block, and the
  flyout's TIME block (zone rows are `RowLayout`s) all place their children with
  anchors or by hand instead of nesting positioners.
- Two items anchored **to each other in a cycle** make Qt drop an edge and leave
  the columns to jitter — it logs "Possible anchor loop detected on horizontal
  anchor" and carries on. The zone rows are a one-way chain inward from the
  right edge.
- An **anchor bound to a conditional, or to a derived property of the parent,
  keeps the value it was first given**: the rule above the creator stayed on its
  idle value forever, so the panel never grew for its rows. The rows and the
  placeholder line now share one box and the rule anchors to that box's `bottom`
  — a plain geometry property. The boot-time line in the flyout is the same
  lesson: it is re-worded, never hidden, so the line below it does not freeze
  and the pane — whose height is measured off that block — does not jump 18 px
  when the script's first result lands.
- `anchors.top` takes an item or an anchor line, **not a number**. A measured
  `tail` has to become the block's `height` and be anchored through
  `previousBlock.bottom`; `top: someBlock.tail` logs "Unable to assign double to
  QQuickAnchorLine" and silently places nothing.
- A **`Column` left-aligns a child narrower than itself** (x=0, not centred) —
  it only distributes along its own axis. Two stacked lines that are meant to
  read as one label need an explicit shared width plus `AlignHCenter`, or the
  shorter one drifts left.
