# tokyonight-moon-dotfiles

Hyprland, Quickshell and rofi configs for the Tokyo Night Moon theme, on Arch.

## Apps

| App | What it is | Guide |
| --- | --- | --- |
| Rofi | Launcher config and colour theme | [rofi/README.md](rofi/README.md) |
| Hyprland | Compositor config, wallpaper, keybind scripts | [hyprland/README.md](hyprland/README.md) |
| Quickshell | Desktop shell: bar, flyouts, tray, timer | [quickshell/README.md](quickshell/README.md) |

## Known overlap

`quickshell/` is a snapshot of `~/.config/quickshell/tokyonight`, which is also
its own git repository under active development. The two will drift; the repo
copy is a snapshot, not the source.

It was resynced on 2026-10-03 and is currently exact, bar four deliberate
omissions: the live `.git`, `.opencode/` (orchestrator notes), `.qmlls.ini`
(machine-specific, gitignored upstream) and `scripts/audio-popup` (a build
artifact — build the `audio-popup/` crate instead). The live tree is the one
quickshell loads; it is backed up on its own private remote, `Zsweezzy/tokyonight-shell`.

Note that the live tree's own `AGENTS.md` tells agents not to edit this mirror
at all. That is a deliberate workflow choice, and resyncing it is a manual
decision — this commit is one such decision, not a standing permission.

## Rust tools

- [`timer-sound/`](timer-sound/) — cargo project. See [timer-sound/README.md](timer-sound/README.md).
- [`audio-popup/`](audio-popup/) — cargo project. See [audio-popup/README.md](audio-popup/README.md).
