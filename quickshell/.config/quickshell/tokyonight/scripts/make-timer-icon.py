#!/usr/bin/env python3
"""Render the timer-finished notification icon (assets/timer-done.png).

Draws the hourglass glyph (U+F252) from JetBrains Mono Nerd Font — the same
font every glyph in this shell uses — in Tokyo yellow on a transparent
background, at 256px. The notification renders icons at 100px (200 device
pixels at this display's 2x scale), so a 256px source is downscaled, never
upscaled: sharp, unlike the stretched 48px theme fallback it replaces.

Usage:  scripts/make-timer-icon.py [output.png]
"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

GLYPH = "\uf252"                        # fa-hourglass-half
FONT = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"
YELLOW = (224, 175, 104, 255)           # Tokyo.yellow #e0af68
SIZE = 256
POINTSIZE = 210


def main() -> int:
    default = (
        pathlib.Path(__file__).resolve().parent.parent / "assets" / "timer-done.png"
    )
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else default

    font = ImageFont.truetype(FONT, POINTSIZE)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    box = draw.textbbox((0, 0), GLYPH, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    # The one thing this script exists to guarantee: the glyph is actually in
    # the font. An empty box means a font swap silently produced a blank icon.
    assert w > 0 and h > 0, f"glyph {GLYPH!r} not present in {FONT}"
    draw.text(((SIZE - w) / 2 - box[0], (SIZE - h) / 2 - box[1]), GLYPH,
              font=font, fill=YELLOW)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"wrote {out} ({img.width}x{img.height})")


if __name__ == "__main__":
    raise SystemExit(main())