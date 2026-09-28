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

## Rust tools

- [`timer-sound/`](timer-sound/) — cargo project. See [timer-sound/README.md](timer-sound/README.md).
- [`audio-popup/`](audio-popup/) — cargo project. See [audio-popup/README.md](audio-popup/README.md).
