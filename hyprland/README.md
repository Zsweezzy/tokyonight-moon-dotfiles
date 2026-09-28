# hyprland

The Hyprland compositor config for this machine, written for Hyprland 0.56.2 in
the hyprlang Lua syntax (`hl.monitor({...})`, `hl.bind(...)`) rather than the old
`key = value` line format, and coloured for Tokyo Night Moon. It covers three
monitors, a set of `SUPER`-prefixed bindings, gaps and rounded borders, a
scratchpad notepad, and animation and misc settings. The wallpaper config for
`hyprpaper` is included alongside it.

## Files and where they go

| Repo path | Install to |
| --- | --- |
| `hyprland/.config/hypr/hyprland.lua` | `~/.config/hypr/hyprland.lua` |
| `hyprland/.config/hypr/hyprpaper.conf` | `~/.config/hypr/hyprpaper.conf` |
| `hyprland/.config/hypr/scripts/duplicate-window.sh` | `~/.config/hypr/scripts/duplicate-window.sh` |
| `hyprland/.config/hypr/scripts/move-fullscreen.sh` | `~/.config/hypr/scripts/move-fullscreen.sh` |
| `hyprland/.config/hypr/scripts/rofi-outside-click.sh` | `~/.config/hypr/scripts/rofi-outside-click.sh` |
| `hyprland/.config/hypr/scripts/rofi-toggle.sh` | `~/.config/hypr/scripts/rofi-toggle.sh` |

`hyprland.lua` refers to the scripts by absolute path, so keep the folder at
`~/.config/hypr/scripts/` or edit the paths at the top of the config. The
scripts are copied with the executable bit intact; if you move them by hand,
`chmod +x` them.

**A note on `*.bak`:** the live config is `hyprland.lua` and nothing else. Any
`hyprland.lua.bak*` in your own `~/.config/hypr/` is stale history and is
deliberately not tracked here.

## Install

Run from the root of this repository:

```sh
mkdir -p ~/.config/hypr/scripts
cp hyprland/.config/hypr/hyprland.lua      ~/.config/hypr/hyprland.lua
cp hyprland/.config/hypr/hyprpaper.conf    ~/.config/hypr/hyprpaper.conf
cp hyprland/.config/hypr/scripts/duplicate-window.sh     ~/.config/hypr/scripts/duplicate-window.sh
cp hyprland/.config/hypr/scripts/move-fullscreen.sh      ~/.config/hypr/scripts/move-fullscreen.sh
cp hyprland/.config/hypr/scripts/rofi-outside-click.sh   ~/.config/hypr/scripts/rofi-outside-click.sh
cp hyprland/.config/hypr/scripts/rofi-toggle.sh          ~/.config/hypr/scripts/rofi-toggle.sh
chmod +x ~/.config/hypr/scripts/*.sh
```

Then reload:

```sh
hyprctl reload
```

or log out and back in, since the config is Lua and a full restart is the more
honest test.

## The rofi launcher lives partly here

The rofi app launcher is split across both folders in this repo. Its theme and
config are in [`rofi/`](../rofi/README.md); the two things that make it reachable
are here, in the hyprland folder.

`scripts/rofi-toggle.sh` is the wrapper that opens the launcher and closes it
again if it is already open. The bare `SUPER` bind in `hyprland.lua` runs it, so
tapping the Windows key opens rofi and tapping it again closes it. The rofi
command line lives inside the script rather than in the bind, because Hyprland's
exec dispatcher does not reliably keep a multi-word argument intact on its way
to the script — with the flags appended unquoted, the script was reached with
only `rofi` and rofi reported "rofi is unsure what to show".

`scripts/rofi-outside-click.sh`, plus its two binds on bare LMB and RMB
(`mouse:272` and `mouse:273`, both `non_consuming`), implement
click-outside-to-dismiss. This exists because rofi's own `click-to-exit` does
not work under the Wayland backend: rofi only creates its own small layer
surface, so clicks outside it never reach it and can never be seen by rofi. The
script asks the compositor where the click landed and kills rofi only if it was
outside the rofi window rect; clicks inside pass through untouched.

Installing only this folder gives you a launcher you cannot open, and installing
only the rofi folder gives you a launcher with no way to dismiss it by clicking
away. Install both.

## Dependencies

- `hyprland` 0.56.2 or newer. The config uses the hyprlang Lua API — `hl.monitor`,
  `hl.bind`, `hl.dsp` — and will not load on a version that predates it, or on a
  build that expects the old `key = value` syntax.
- `hyprpaper`, since `hyprpaper.conf` is included. The config also autostarts it;
  if you do not use hyprpaper, drop that line and this file.
- The programs the binds and autostart lines launch: `rofi`, plus whatever
  terminal and file manager `hyprland.lua` names. Those are a local preference
  rather than a dependency, and the paths are at the top of the file.
