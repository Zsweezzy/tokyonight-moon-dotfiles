# quickshell

A Quickshell/QML desktop shell for Hyprland, themed in Tokyo Night Moon. It
provides the bar and its flyouts (audio, brightness, clock), a system tray, and
a kitchen timer with a progress panel. System state — audio, brightness,
network, CPU, GPU, memory, battery and package updates — is polled by small
shell and Python helpers in `scripts/` and fed into the QML elements, rather
than reimplemented in QML.

## Files and where they go

This folder mirrors exactly one real directory. The whole of
`quickshell/.config/quickshell/tokyonight/` installs to
`~/.config/quickshell/tokyonight/`.

| Repo path | Install to |
| --- | --- |
| `quickshell/.config/quickshell/tokyonight/` | `~/.config/quickshell/tokyonight/` |

Notable contents of that one directory:

| Path (relative to `quickshell/.config/quickshell/tokyonight/`) | Contents |
| --- | --- |
| `*.qml` (29 files) | The shell itself: `shell.qml` is the entry point, `Tokyo.qml` holds shared singletons and config, the rest are bar modules and flyout panels. |
| `assets/` | `timer-done.wav`, the chime played when the timer finishes. |
| `scripts/` | Poller and action helpers (`.sh`, plus `audio-popup.py`) invoked from QML. |
| `tests/` | `test-network-monitor.sh`, a self-check for the network monitor poller. |
| `README.md` | The shell's own detailed notes, kept as-is from the live tree. |

## Install

Whole mirror:

```sh
mkdir -p ~/.config/quickshell && cp -r quickshell/.config/quickshell/tokyonight ~/.config/quickshell/
```

Run that from the repository root.

To copy only part of it — for example just the QML and the assets, leaving
`scripts/` alone — copy the pieces explicitly:

```sh
mkdir -p ~/.config/quickshell/tokyonight
cp quickshell/.config/quickshell/tokyonight/*.qml ~/.config/quickshell/tokyonight/
cp -r quickshell/.config/quickshell/tokyonight/assets ~/.config/quickshell/tokyonight/
```

`assets/timer-done.wav` is already committed here, so `pw-play` can stream it
the moment the shell starts with no generation step. Regenerating the file is
the job of the `timer-sound/` cargo project at the repository root; this
folder only carries the output.

## Running it

```sh
quickshell -c tokyonight
```

The config directory name and the `-c` argument have to match. That argument is
how Quickshell resolves which shell under `~/.config/quickshell/` to start, so
`-c tokyonight` selects this directory and nothing else.

## Dependencies

- `quickshell`
- the `qt6-wayland` / Qt 6 Wayland stack
- `hyprland` — this shell is Hyprland-specific; it talks to the compositor over
  Hyprland IPC for workspace and monitor data rather than using generic
  Wayland protocols

`scripts/` holds the shell helpers that QML calls through `Tokyo.scriptDir`
(`$HOME/.config/quickshell/tokyonight/scripts`). Several of them shell out to
`hyprctl` and `wpctl`, so those need to be on `PATH` too.

## Known overlap

This folder is a snapshot, not the live source. The same directory is also its
own git repository at `~/.config/quickshell/tokyonight` and is under active
development, so edits made there will drift from this mirror until they are
copied back over.
