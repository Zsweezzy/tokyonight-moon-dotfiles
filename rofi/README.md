# rofi

The rofi 2.0 launcher config and its colour theme, for Tokyo Night Moon. It sets
rofi up as a three-mode launcher (drun for apps, run for commands, window for
toggling windows) with a 620px, 10-line window, a Nerd Font at size 12, and
`breeze` icons. The palette itself lives in a separate theme file rather than in
`config.rasi`, so the colours can be reused or swapped without touching the
behaviour settings. This config also departs from stock rofi on mouse handling:
a single left click launches the entry under the cursor, and clicking outside
the window dismisses the launcher. That behaviour is explained under
[Mouse behaviour](#mouse-behaviour) because it is not the default and the way it
is wired is not obvious.

## Files and where they go

| Repo path | Install to |
| --- | --- |
| `rofi/.config/rofi/config.rasi` | `~/.config/rofi/config.rasi` |
| `rofi/.local/share/rofi/themes/tokyonight-moon.rasi` | `~/.local/share/rofi/themes/tokyonight-moon.rasi` |

Both files are required. `config.rasi` ends with `@theme "tokyonight-moon"`, and
that theme is a custom file kept in this repo, not one that ships with rofi.
Install `config.rasi` on its own and the launcher still runs but renders
unstyled.

## Requires

**This app is not self-contained.** The config files below are only half of it.
The launcher has no keyboard shortcut without two things that live in the
`hyprland/` folder of this repo:

- `~/.config/hypr/scripts/rofi-toggle.sh` — the wrapper that opens the launcher
  and closes it again if it is already open.
- A bind in `~/.config/hypr/hyprland.lua` that runs that script.

The bind is bare `SUPER`: hold nothing, tap the Windows key, launcher opens; tap
it again, launcher closes. From `hypr/.config/hypr/hyprland.lua`, where
`mainMod = "SUPER"` and `menu` points at the wrapper:

```lua
describedBind(
	mainMod .. " + SUPER_L",
	hl.dsp.exec_cmd(menu),
	"Open application launcher",
	{ release = true, allow_input_capture = true }
)
```

which is the `bindr` form of:

```
bindr = SUPER, SUPER_L, exec, /home/maxii/.config/hypr/scripts/rofi-toggle.sh
```

This is a `bindr` (bind on release) form, and `SUPER_L` is named explicitly on
purpose. A bare `bind = SUPER, exec, ...` registers — `hyprctl` will show it,
with an empty key — but it never reaches the dispatcher. Naming the key and
using the release form is what makes this a modkey-only bind instead of a chord
with a missing second key. `allow_input_capture` is what makes the closing half
work: rofi grabs the keyboard while it is open, and a bind without that flag is
not dispatched while a client holds the grab, so pressing `SUPER` again would be
swallowed by rofi instead of reaching the bind.

So: copy this folder, then follow [`hyprland/README.md`](../hyprland/README.md).
Skip that and the launcher works, but only if you already have some other way to
start it.

## Install

Run from the root of this repository:

```sh
mkdir -p ~/.config/rofi ~/.local/share/rofi/themes
cp rofi/.config/rofi/config.rasi                 ~/.config/rofi/config.rasi
cp rofi/.local/share/rofi/themes/tokyonight-moon.rasi ~/.local/share/rofi/themes/tokyonight-moon.rasi
```

If you would rather copy the tree wholesale:

```sh
cp -r rofi/.config ~/.config && cp -r rofi/.local ~/.local
```

Both copy over any existing files. `config.rasi` is worth backing up first if
you have edited it — this repo mirrors the machine it was written on, not a
template.

## Dependencies

- `rofi` 2.0 or newer. The config relies on rofi 2.0's `hover-select` and
  `me-accept-entry` keys; on rofi 1.x they do nothing and the mouse behaviour
  below silently degrades to nothing.
- `JetBrainsMono Nerd Font`, at size 12. **This is a hard requirement.** The
  `font` line names it, and rofi falls back to a default face when it is
  missing: the entry text renders, but Nerd Font glyphs in the application
  names show up as tofu boxes.
- `breeze` icon theme, for `show-icons: true` to have anything to draw.

## Mouse behaviour

Three settings in the `configuration` block control clicking, and they only make
sense together:

- `hover-select: true` — the highlight follows the cursor, so the entry under the
  pointer is always the one that will run.
- `me-select-entry: ""` — the click-to-select binding is cleared.
- `me-accept-entry: "MousePrimary"` — a single left click accepts the hovered
  entry and launches it.

Clearing `me-select-entry` is mandatory, not cosmetic. In rofi's binding table
`SELECT_HOVERED_ENTRY` precedes `ACCEPT_HOVERED_ENTRY`, so if select is still
bound to `MousePrimary` it wins the same click, the entry is selected but never
accepted, and the click appears to do nothing. Setting `me-accept-entry` alone,
while leaving select on the same button, produces a launcher that ignores the
left mouse button.
