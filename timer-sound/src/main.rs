//! Generate the timer-finished chime (assets/timer-done.wav).
//!
//! Rust port of `.config/quickshell/tokyonight/scripts/make-timer-sound.py`,
//! constant for constant. The committed WAV is played by the shell through
//! `pw-play`, so this is a regenerator: it reproduces the Python's output
//! rather than inventing a new sound.
//!
//! Three stacked-ish partials with an exponential decay, the classic "ding-ding-
//! ding" of a kitchen timer: E6 - B6 - E7.
//!
//! Usage:  timer-sound [output.wav]

#![forbid(unsafe_code)]

use std::f64::consts::PI;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const RATE: u32 = 44100; // 44.1 kHz, what PipeWire wants
const AMPLITUDE: f64 = 0.55; // headroom: this plays over whatever else is audible
const DECAY: f64 = 5.0; // e-folds per second; higher = shorter, drier tail
                        // (frequency Hz, duration s, peak gain)
const NOTES: [(f64, f64, f64); 3] = [
    (1318.51, 0.38, 1.00), // E6
    (1975.53, 0.30, 0.80), // B6
    (2637.02, 0.55, 0.70), // E7 — rings out longest
];

/// Concatenate the notes as 16-bit little-endian mono samples.
fn render() -> Vec<i16> {
    let mut frames: Vec<i16> = Vec::new();
    for &(freq, duration, gain) in &NOTES {
        let count = (RATE as f64 * duration) as usize;
        for i in 0..count {
            let t = i as f64 / RATE as f64;
            // Sum a fundamental and a quiet octave-up for a bit of edge, then
            // let the exponential envelope do the percussive part.
            let mut sample = (2.0 * PI * freq * t).sin() + 0.18 * (4.0 * PI * freq * t).sin();
            sample *= (-DECAY * t).exp() * gain / 1.18;
            // 20 ms fade-in kills the click a hard start would produce.
            if t < 0.02 {
                sample *= t / 0.02;
            }
            // Python: int(max(-1.0, min(1.0, sample)) * AMPLITUDE * 32767).
            // The clamp is not decoration -- Rust's `as i16` *saturates* a
            // float outside the i16 range, Python's int() does not, so the
            // clamp has to happen before the cast for the two to agree. Both
            // then truncate toward zero.
            frames.push((sample.clamp(-1.0, 1.0) * AMPLITUDE * 32767.0) as i16);
        }
    }
    frames
}

/// The canonical 44-byte PCM WAV header, little-endian. Written by hand: every
/// field is a fixed-format integer, so a crate like `hound` would be a
/// dependency for 44 bytes of `to_le_bytes`.
fn wav_header(data_len: u32) -> [u8; 44] {
    let channels: u16 = 1; // mono
    let bits: u16 = 16;
    let block_align = channels * bits / 8; // bytes per frame = 2
    let byte_rate = RATE * u32::from(block_align); // bytes per second = 88200
    let mut h = [0u8; 44];
    h[0..4].copy_from_slice(b"RIFF");
    h[4..8].copy_from_slice(&(36 + data_len).to_le_bytes()); // everything after this field
    h[8..12].copy_from_slice(b"WAVE");
    h[12..16].copy_from_slice(b"fmt ");
    h[16..20].copy_from_slice(&16u32.to_le_bytes()); // PCM fmt subchunk size
    h[20..22].copy_from_slice(&1u16.to_le_bytes()); // audio format 1 = PCM
    h[22..24].copy_from_slice(&channels.to_le_bytes());
    h[24..28].copy_from_slice(&RATE.to_le_bytes());
    h[28..32].copy_from_slice(&byte_rate.to_le_bytes());
    h[32..34].copy_from_slice(&block_align.to_le_bytes());
    h[34..36].copy_from_slice(&bits.to_le_bytes());
    h[36..40].copy_from_slice(b"data");
    h[40..44].copy_from_slice(&data_len.to_le_bytes());
    h
}

fn main() -> ExitCode {
    // Default: <repo>/assets/timer-done.wav, the same file the Python wrote via
    // dirname(dirname(__file__)). CARGO_MANIFEST_DIR is <repo>/timer-sound, so
    // it resolves the repo root and works from any cwd.
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let out: PathBuf = match std::env::args_os().nth(1) {
        Some(arg) => PathBuf::from(arg),
        None => manifest
            .parent()
            .unwrap_or(manifest)
            .join("assets")
            .join("timer-done.wav"),
    };

    let samples = render();
    let data_len = (samples.len() * 2) as u32;
    let mut wav = wav_header(data_len).to_vec();
    wav.extend(samples.iter().flat_map(|s| s.to_le_bytes()));

    if let Some(dir) = out.parent() {
        if let Err(e) = fs::create_dir_all(dir) {
            eprintln!("timer-sound: cannot create {}: {e}", dir.display());
            return ExitCode::FAILURE;
        }
    }
    if let Err(e) = fs::write(&out, &wav) {
        eprintln!("timer-sound: cannot write {}: {e}", out.display());
        return ExitCode::FAILURE;
    }
    println!("wrote {} ({} bytes)", out.display(), wav.len());
    ExitCode::SUCCESS
}
