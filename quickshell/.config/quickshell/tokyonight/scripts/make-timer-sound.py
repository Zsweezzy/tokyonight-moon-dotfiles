#!/usr/bin/env python3
"""Generate the timer-finished chime (assets/timer-done.wav).

Stdlib only, so it runs anywhere python3 does — no synth dependency, and the
result is a file `pw-play` can stream instantly (unlike canberra, which has no
sound theme installed on this machine and would fail silently).

Three stacked-ish partials with an exponential decay, the classic "ding-ding-
ding" of a kitchen timer: E6 - B6 - E7. Pure python, ~0.4 s of audio, so it
generates in well under a second.

Usage:  scripts/make-timer-sound.py [output.wav]
"""
import math
import os
import struct
import sys
import wave

RATE = 44100          # 44.1 kHz, what PipeWire wants
AMPLITUDE = 0.55      # headroom: this plays over whatever else is audible
DECAY = 5.0           # e-folds per second; higher = shorter, drier tail
NOTES = [
    # (frequency Hz, duration s, peak gain)
    (1318.51, 0.38, 1.00),   # E6
    (1975.53, 0.30, 0.80),   # B6
    (2637.02, 0.55, 0.70),   # E7 — rings out longest
]


def render() -> bytes:
    """Concatenate the notes as 16-bit little-endian mono samples."""
    frames = bytearray()
    for freq, duration, gain in NOTES:
        count = int(RATE * duration)
        for i in range(count):
            t = i / RATE
            # Sum a fundamental and a quiet octave-up for a bit of edge, then
            # let the exponential envelope do the percussive part.
            sample = math.sin(2 * math.pi * freq * t) + 0.18 * math.sin(4 * math.pi * freq * t)
            sample *= math.exp(-DECAY * t) * gain / 1.18
            # 20 ms fade-in kills the click a hard start would produce.
            if t < 0.02:
                sample *= t / 0.02
            frames += struct.pack("<h", int(max(-1.0, min(1.0, sample)) * AMPLITUDE * 32767))
    return bytes(frames)


def main() -> int:
    default = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "timer-done.wav"
    )
    out = sys.argv[1] if len(sys.argv) > 1 else default
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with wave.open(out, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(render())
    print(f"wrote {out} ({os.path.getsize(out)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
