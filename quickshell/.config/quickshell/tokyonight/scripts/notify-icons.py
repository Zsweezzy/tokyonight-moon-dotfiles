#!/usr/bin/env python3
"""notify-icons.py — map every freedesktop icon name to the best local file.

    notify-icons.py <size>

Prints one JSON object, {"name": "/path/to/icon.png"}, covering every icon in
the installed themes. Run once at startup; the QML side looks names up in the
result synchronously, so no notification row ever waits on a process.

Why this exists: Qt 6 dropped Qt.labs.platform's IconImage, the QML type that
turned an icon *name* into a file. Notification.appIcon is a name, so something
has to resolve it. Doing it here is also what fixes the actual quality bug: a
32px PNG blown up into a 64px box is what makes a toast's icon look like mush,
and picking the right asset is most of the fix.

This follows the freedesktop lookup rather than guessing at it, because the
guess is wrong in a visible way: ordering themes alphabetically answers
`pavucontrol` from char-white's 16x16 instead of Adwaita's 256x256, and the
result is a blurred speck in the middle of a toast. So: the current theme comes
from gsettings, its Inherits= chain gives the theme order, and within a theme
its Directories= line gives the subdirectory order. For each name, sizes are
tried in preference order and the first hit in that theme order wins — exact
size, then scalable, then the smallest one larger, then the largest smaller.
Downscaling reads better than upscaling, which is the whole point.
"""

import json
import os
import re
import subprocess
import sys

SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 40
PIXMAPS = "/usr/share/pixmaps"
SIZE_DIR = re.compile(r"^(\d+)x(\d+)$")
EXT = (".png", ".svg", ".xpm")


def data_dirs():
    raw = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    dirs = [
        os.path.expanduser("~/.local/share"),
        os.path.expanduser("~/.icons"),
    ]
    dirs += [d for d in raw.split(":") if d]
    seen, out = set(), []
    for d in dirs:
        if d and d not in seen and os.path.isdir(d):
            seen.add(d)
            out.append(d)
    return out


def read_ini(path, key):
    """One key out of a desktop/index file. The key is passed in rather than
    derived from the filename: `index.theme` has three keys this wants and its
    own name is none of them."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith(key + "="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return ""


def current_theme():
    try:
        out = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
            capture_output=True, text=True, timeout=3,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.strip().strip("'\"")


def theme_dirs(name):
    return [os.path.join(d, "icons", name) for d in data_dirs()
            if os.path.isdir(os.path.join(d, "icons", name))]


def theme_order():
    """The current theme first, then its Inherits= chain, then hicolor.

    hicolor is appended last rather than relying on it being named in every
    Inherits= line: a theme that forgets to inherit it is broken, but hicolor
    existing is universal, and putting it last costs nothing when it is right.
    """
    order, queue = [], [current_theme()]
    while queue:
        name = queue.pop(0)
        if not name or name in order:
            continue
        dirs = theme_dirs(name)
        if not dirs:
            continue
        order.append(name)
        inherits = read_ini(os.path.join(dirs[0], "index.theme"), "Inherits")
        queue += [i for i in inherits.split(",") if i.strip()]

    every = set()
    for d in data_dirs():
        icons = os.path.join(d, "icons")
        if os.path.isdir(icons):
            every |= {e for e in os.listdir(icons)
                      if os.path.isfile(os.path.join(icons, e, "index.theme"))}
    # The unthemed leftovers, alphabetical. hicolor is already at the end of
    # `order` if any Inherits= line mentioned it; if none did, put it there.
    order += sorted(every - set(order))
    if "hicolor" in every and "hicolor" not in order:
        order.append("hicolor")
    return order


def subdir_order(theme_dir):
    """Directories= as the freedesktop spec defines it, then whatever is left."""
    listed = [d.strip() for d in
              read_ini(os.path.join(theme_dir, "index.theme"), "Directories").split(",")]
    listed = [d for d in listed if d]
    rest = []
    try:
        rest = sorted(e for e in os.listdir(theme_dir)
                      if e not in listed and os.path.isdir(os.path.join(theme_dir, e)))
    except OSError:
        pass
    return listed + rest


def walk(base, subdirs):
    """(name, size_or_None, path) for icons under base, in subdir order."""
    for sub in subdirs:
        d = os.path.join(base, sub)
        if not os.path.isdir(d):
            continue
        m = SIZE_DIR.match(sub.split("/")[0])
        size = int(m.group(1)) if m else None
        if "apps" not in sub.split("/"):
            continue  # breeze/legacy/mimetypes: thousands of files, never a notification
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for name in names:
            if not name.endswith(EXT):
                continue
            stem = name[: -len(os.path.splitext(name)[1])]
            # `foo-symbolic` is an outline variant of `foo`; answering the plain
            # name with it looks like a rendering bug.
            if stem.endswith("-symbolic"):
                continue
            yield stem, size, os.path.join(d, name)


def main():
    # tier: 0 exact, 1 scalable, 2 larger (smaller multiple = closer), 3 smaller
    def tier(size):
        if size == SIZE:
            return (0, 0)
        if size is None:
            return (1, 0)
        if size > SIZE:
            return (2, size)
        return (3, -size)

    table = {}
    for name in theme_order():
        for theme_dir in theme_dirs(name):
            for stem, size, path in walk(theme_dir, subdir_order(theme_dir)):
                if stem not in table or tier(size) < table[stem][0]:
                    table[stem] = (tier(size), path)

    # /usr/share/pixmaps last: unthemed, one directory, no size subdirs, but it
    # holds the odd app icon that predates the themes entirely.
    if os.path.isdir(PIXMAPS):
        try:
            for entry in sorted(os.listdir(PIXMAPS)):
                if not entry.endswith(EXT):
                    continue
                stem = entry[: -len(os.path.splitext(entry)[1])]
                if stem.endswith("-symbolic") or stem in table:
                    continue
                table[stem] = ((9, 0), os.path.join(PIXMAPS, entry))
        except OSError:
            pass

    json.dump({k: v[1] for k, v in table.items()}, sys.stdout, separators=(",", ":"))


if __name__ == "__main__":
    main()
