# audio-popup

Tokyo Night Moon audio panel for Hyprland.

A GTK4 + gtk4-layer-shell surface anchored under the top-right of the screen,
next to the audio module of the bar. It shows:

- master volume slider and a mute/unmute toggle, labelled `Master  NN%`
- `OUTPUT` — sinks; click one to make it the default, the current default is
  marked with a filled circle and coloured
- `INPUT` — sources, same behaviour
- `APPS` — a volume slider per application stream, with its current percentage
- a `✕` button to close

It polls `wpctl status` every 5 seconds, so changes made elsewhere (a
keybound mute, a mixer, another app) show up on their own.

## Why this exists instead of `audio-popup.py`

The original panel was a PyGObject/GTK3 script. It cannot run on this machine:
GTK3 layer-shell is not installed, so

```
$ python3 ~/.config/quickshell/tokyonight/scripts/audio-popup.py
ValueError: Namespace GtkLayerShell not available
```

comes out of `gi.require_version("GtkLayerShell", "0.1")` — there is no
`libgtk-layer-shell.so` and no `GtkLayerShell-0.1.typelib`. This is a rewrite
onto GTK4 + `gtk4-layer-shell`, not a transliteration, and it is not a
transliteration in behaviour either: the layout, the palette, the sectioning
and the parsing are the same, but the GTK3-isms had to go (see below).

Two GTK3 -> GTK4 differences worth knowing if you compare the two:

- `screen.get_rgba_visual()` has no GTK4 equivalent. The panel is transparent
  because the stylesheet says `window { background: transparent; }`, which is
  how GTK4 wants it done.
- `Gtk.StyleContext.add_provider_for_screen()` is gone; the `CssProvider` is
  attached to the display at `STYLE_PROVIDER_PRIORITY_APPLICATION`.

The stylesheet itself is carried over unchanged, so the panel looks the same.

## Build

```sh
cargo build --release
```

Binary lands at `target/release/audio-popup`.

Needs the `gtk4-layer-shell` shared library at build and run time. On Arch that
is the `gtk4-layer-shell` package (`libgtk4-layer-shell`); the header and the
`gtk4-layer-shell-0.pc` pkg-config file come with it. If the crate fails to
build with a missing-library error, that package is not installed.

## Runtime dependencies

- `libgtk4-layer-shell.so.0` and GTK 4
- `wpctl` (from WirePlumber) — device and stream state, volume and mute
- `hyprctl` and a Hyprland IPC socket — event stream and layer geometry
- a Wayland session

Nothing is read from disk except the pidfile; all state comes from PipeWire via
`wpctl`.

## How the shell invokes it

Right- and middle-clicking the audio module of the bar is the intended trigger,
and the pidfile makes that a toggle: if an instance is already running, the new
process sends it `SIGTERM` and exits immediately instead of opening a second
panel.

Not wired up yet, though. `Audio.qml` still runs the dead Python:

```qml
else Quickshell.execDetached([Tokyo.scriptDir + "/audio-popup.py"])
```

Pointing it at this binary means replacing that path with the absolute path to
`target/release/audio-popup` (or an installed copy), which is a separate change
to the shell. Until that happens nothing launches this program on its own; run
it by hand.

The pidfile is `$XDG_RUNTIME_DIR/audio-popup.pid`, falling back to
`std::env::temp_dir()` (in practice `/tmp/audio-popup.pid`) when
`XDG_RUNTIME_DIR` is unset. The Python hardcoded a literal path,
`/tmp/opencode/audio-popup.pid`, which is a directory that happens to exist on
some machines and not others; the runtime directory is the per-user, 0700,
cleaned-up-on-logout place for exactly this kind of file. The file holds the
pid and is removed on every exit path, including on unwind.

A pid in that file that is not a live process is treated as stale and replaced,
so a leftover file never blocks the panel from opening.

## Closing

Any of these closes the panel:

- `Esc`, or the `✕` button
- `SIGTERM` / `SIGINT`
- a significant Hyprland event on the IPC socket: `workspace`, `focusedmon`,
  `activateworkspace`, `moveworkspace`, `openwindow`, `closewindow`,
  `movewindow`, `activewindow`, `fullscreen`, `monitor`, `urgent`, `submap`,
  `togglegroup`. `activewindowv2` and `workspacev2` are deliberately not in the
  list, because they fire on plain window-title churn.
- the pointer staying outside the panel for about 300 ms

### How close-on-outside-click works

Two independent mechanisms, because either one alone has false positives.

**Hyprland event socket.** A thread resolves the event socket the same way the
Python did — `$HYPRLAND_INSTANCE_SIGNATURE` under `$XDG_RUNTIME_DIR/hypr/` or
`/tmp`, then `hyprctl -j instances` as a fallback — connects, and reads lines.
Anything whose part before `>>` is in the list above means the user did
something elsewhere, so the panel goes away. The thread does nothing but write
to an `mpsc` channel; a `glib::timeout_add_local` on the main loop drains that
channel and quits the loop. No glib main-context call is ever made from the
thread, which is unsound.

**Pointer position.** Every 150 ms the main loop asks `hyprctl -j layers` for
the layer surface whose namespace is `audio-popup`, and `hyprctl -j cursorpos`
for the pointer. If the pointer is outside that rectangle for two consecutive
checks (~300 ms) the panel closes. Hovering the bar strip — the top 42 px,
which is `BAR_HEIGHT + 8` — counts as inside, so moving the pointer up to the
bar to reach for something does not dismiss the panel.

If either `hyprctl` call fails or returns something unparsable the check is
skipped that tick; it never closes on bad input.

## Notes

- `main.rs` is `#![forbid(unsafe_code)]`. The one thing that would normally
  force `unsafe` is signal handling, and glib 0.22 no longer exports
  `unix_signal_add_local`, so `SIGTERM`/`SIGINT` are blocked process-wide and
  caught with a `sigwait` thread from the `nix` crate, which feeds the same
  channel as the Hyprland reader. Signalling another process uses `kill -TERM`
  rather than `libc::kill`, to keep it that way.
- The `wpctl status` parser is unit tested against a captured dump; see the
  `mod tests` at the bottom of `main.rs`. Run them with `cargo test`.
- The panel is anchored with the top margin `BAR_HEIGHT + 8` and
  `exclusive_zone(0)`, as the Python did. On this setup Hyprland additionally
  pushes top-layer surfaces clear of the bar's reserved space, so the surface
  lands ~34 px lower than the nominal margin. That is the compositor's doing,
  not this program's: setting the exclusive zone to `-1` puts it at exactly 42.
