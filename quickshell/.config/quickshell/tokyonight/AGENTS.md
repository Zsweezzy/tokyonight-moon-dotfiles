# tokyonight quickshell config

The live config. `quickshell -c tokyonight` loads this directory.

## Edit here. Nowhere else.

There is a second copy of these files at
`~/projects/tokyonight-moon-dotfiles/quickshell/.config/quickshell/tokyonight/`.
It is a **read-only snapshot** for a public dotfiles repo, stale since 28 Sep.
Quickshell never loads it and nothing syncs it. Editing it changes nothing on
screen and the work is invisible until someone remembers to re-sync.

Do not edit the mirror. Do not "helpfully" apply the same change to both.

This directory is its own git repo — commit here. The mirror has its own,
separate history and is the user's to re-sync.

## Prove the reload

A failed reload leaves the OLD bar on screen, so the screen always looks fine.
Only the log tells you what happened.

    scripts/check-reload.sh

Run it right after saving a `.qml`. Exit 0 = loaded, exit 1 = it broke.
It prints only the last reload attempt, so it cannot be fooled by history.

Do **not** verify with `quickshell -c tokyonight log | grep "Configuration
Loaded"`. That command replays the whole journal since the instance started —
it currently contains 25 reloads going back hours. Grepping it matches a stale
line and reports success for an edit that never loaded.

`touch` does not trigger a reload; it only raises `IN_ATTRIB`. Never conclude
the file watcher is dead from a bare `touch`.

## Other trees

- `~/.config/hypr/` — a separate Hyprland config, and it has **no git**.
- `~/projects/tokyonight-moon-dotfiles/` — the mirror repo. Read-only here.

## Conventions

- **New UI? Read `DESIGN.md` first.** Tokens (which colour for which job,
  radius, border, type scale), the rules this tree actually follows, and the
  QML traps that silently render nothing. Colours, fonts and radii come from
  `Tokyo.qml` by name — never a literal.
- QML files use **4 spaces**. `grep -cP '\t'` is 0 across all of them. Check
  the file before inserting anything.
- Timer ranges: `TimerState.maxMinutes` is the slider bound;
  `maxEntryMinutes` is the typed-entry clamp. They were once one variable,
  which made typing "45" silently start a 30:00 timer.
- `Repeater { model: <reassigned array> }` rebuilds every delegate on write, so
  any write from a pointer-move handler destroys the `MouseArea` holding the
  press. Drag holds state locally and writes **once, on release**.
- `Controls.TextField` swallows the press its own `contentItem` needs when a
  `MouseArea { anchors.fill: parent }` sits inside it. The overlay is
  deliberate — it triggers the host's layer-surface keyboard grab — so focus
  the field that was clicked rather than deleting the MouseArea.
- `z` orders siblings regardless of declaration order. Read the actual `z`, not
  the comment describing it.

## Deeper notes

`.opencode/orchestrator/learnings.md` — QML/Hyprland specifics worth reading
before non-trivial work here.