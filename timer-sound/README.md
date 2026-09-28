# timer-sound

Generates the timer-finished chime at `assets/timer-done.wav` — a 16-bit mono
44.1 kHz WAV that the shell plays through `pw-play`. It is a regenerator for the
committed asset, not a new sound: the output is sample-for-sample equivalent to
the original `make-timer-sound.py` it was ported from.

## Usage

```
timer-sound [output.wav]
```

With no argument it writes `<repo>/assets/timer-done.wav`. The default path is
resolved at compile time from `CARGO_MANIFEST_DIR`, so it works from any working
directory.

## Build

```sh
cargo build --release
```

The binary lands at `target/release/timer-sound`. No dependencies — the 44-byte
WAV header is written by hand.

```sh
cargo run --release -- /tmp/timer-done.wav   # render somewhere else
```

## Retuning the chime

Three notes are stacked end to end, each a fundamental plus a quiet octave-up at
18%, under an exponential envelope that decays at 5.0 e-folds per second, faded
in over the first 20 ms and scaled to 55% peak:

| note | frequency  | duration | peak gain |
|------|------------|----------|-----------|
| E6   | 1318.51 Hz | 0.38 s   | 1.00      |
| B6   | 1975.53 Hz | 0.30 s   | 0.80      |
| E7   | 2637.02 Hz | 0.55 s   | 0.70      |

To make it ring longer, lower `DECAY`; to make it drier, raise it. The gains are
normalised by 1.18, the sum of the fundamental and the octave-up.
