//! audio-popup — Tokyo Night Moon audio panel for Hyprland.
//!
//! A GTK4 + gtk4-layer-shell window anchored directly below the top-right
//! bar cluster (it "flies out" of the audio widget). Re-invoking the binary
//! toggles it: clicking the audio module closes/opens the panel.
//! Esc, the ✕ button, a Hyprland event, or the pointer leaving the panel
//! closes it.
//!
//! Sections:
//!   • Master volume slider + mute toggle
//!   • OUTPUT (click to set the default output device)
//!   • INPUT  (click to set the default input device)
//!   • APPS   (per-application volume sliders)
//!
//! Ported from the GTK3 `audio-popup.py` that used to live in
//! `~/.config/quickshell/tokyonight/scripts/`. It cannot run on this machine:
//! there is no `libgtk-layer-shell` and no `GtkLayerShell-0.1.typelib`, so
//! `gi.require_version("GtkLayerShell", "0.1")` dies with
//! `ValueError: Namespace GtkLayerShell not available`. See README.md.
#![forbid(unsafe_code)]

use std::cell::{Cell, RefCell};
use std::error::Error;
use std::io::{self, Read};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::rc::Rc;
use std::sync::mpsc::{channel, Receiver, Sender, TryRecvError};
use std::time::Duration;

use gtk::gdk;
use gtk::prelude::*;
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use nix::sys::signal::{SigSet, Signal};
use serde_json::Value;

// ---- Tokyo Night Moon palette ----
// The `CSS` string below is what actually reaches the compositor; these are
// the same values it spells out, kept for parity with the Python.
#[allow(dead_code)]
const PANEL: &str = "#2f334d"; // bg_highlight
#[allow(dead_code)]
const BORDER: &str = "#414868";
#[allow(dead_code)]
const FG: &str = "#c8d3f5";
#[allow(dead_code)]
const DIM: &str = "#7f849c";
#[allow(dead_code)]
const BLUE: &str = "#82aaff";
#[allow(dead_code)]
const MAGENTA: &str = "#bb9af7";
#[allow(dead_code)]
const RED: &str = "#f7768e";

const BAR_HEIGHT: i32 = 34;
#[allow(dead_code)]
const RADIUS: i32 = 10; // matches hyprland decoration:rounding

/// Substrings of stream names we don't want in the "Apps" list (system
/// plumbing). Case-insensitive and unanchored, like the Python `re.I` search.
const BLOCKLIST: [&str; 7] = [
    "cava",
    "gsr-",
    "pipewire",
    "wireplumber",
    "xdg-desktop",
    "linuxsoundboard",
    "monitor",
];

/// Prefixes of bare per-channel routing links ("input_FL", "output_FR",
/// "monitor_FL", …) — stereo channel links of a stream, not apps.
const CHANLINK_PREFIXES: [&str; 3] = ["input", "output", "monitor"];

/// Hyprland events = "the user did something outside the panel" → close.
/// (activewindowv2/workspacev2 are excluded: they fire on title/rename churn.)
const CLOSE_EVENTS: [&str; 13] = [
    "workspace",
    "focusedmon",
    "activateworkspace",
    "moveworkspace",
    "openwindow",
    "closewindow",
    "movewindow",
    "activewindow",
    "fullscreen",
    "monitor",
    "urgent",
    "submap",
    "togglegroup",
];

const CSS: &str = "
window { background: transparent; }
.panel {
    background-color: #2f334d;
    border-radius: 10px;
    border: 1px solid #414868;
    box-shadow: 0 8px 22px rgba(14, 22, 30, 0.55);
    margin: 6px;
}
.title-label { color: #c8d3f5; font-weight: 700; font-size: 13px; }
.section-label {
    color: #7f849c; font-size: 10px; letter-spacing: 1.5px;
    margin-top: 6px;
}
button.row, button.close-btn {
    background-image: none; background-color: transparent;
    border: none; box-shadow: none; border-radius: 8px;
    padding: 5px 10px; color: #c8d3f5; font-size: 12px;
}
button.row:hover { background-color: #414868; }
button.row.active { color: #82aaff; }
button.close-btn { color: #7f849c; border-radius: 6px; }
button.close-btn:hover { background-color: #414868; color: #f7768e; }
scale trough { background-color: #414868; border-radius: 5px; min-height: 6px; }
scale highlight { background-color: #82aaff; border-radius: 5px; min-height: 6px; }
scale slider {
    background-color: #c8d3f5; border-radius: 50%;
    min-width: 12px; min-height: 12px;
}
.app-scale trough { min-height: 5px; }
";

// ===========================================================================
// Process helpers
// ===========================================================================

/// Run a command, return stdout+stderr, or "" on any failure.
///
/// The Python passed `timeout=5`; keep that, because a wedged compositor must
/// not freeze the GTK main loop. The child runs on a throwaway thread and we
/// give up on the channel. Nothing here can panic.
fn sh(args: &[&str]) -> String {
    let (tx, rx) = channel::<String>();
    let argv: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    let _ = std::thread::spawn(move || {
        let out = Command::new(&argv[0]).args(&argv[1..]).output();
        let _ = tx.send(out.map_or_else(
            |_| String::new(),
            |o| {
                format!(
                    "{}{}",
                    String::from_utf8_lossy(&o.stdout),
                    String::from_utf8_lossy(&o.stderr)
                )
            },
        ));
    });
    rx.recv_timeout(Duration::from_secs(5)).unwrap_or_default()
}

fn wpctl_status() -> String {
    sh(&["wpctl", "status"])
}

/// `wpctl get-volume <node>` → (percent, muted). (None, false) if unparsable.
fn get_volume(node: &str) -> (Option<i64>, bool) {
    let out = sh(&["wpctl", "get-volume", node]);
    (
        volume_of(&out).map(|v| (v * 100.0).round() as i64),
        out.to_lowercase().contains("muted: yes"),
    )
}

/// `Volume: 0.58` → 0.58. Mirrors `re.search(r"Volume:\s*([\d.]+)", out)`.
fn volume_of(out: &str) -> Option<f64> {
    number_after(out, "Volume:")
}

/// `label` then `\s*([\d.]+)`, with nothing anchoring the tail, so whatever
/// follows the digits is ignored — that is what the Python regexes do.
/// `[\d.]+` admits a leading or trailing '.'; f64's parser takes both.
fn number_after(s: &str, label: &str) -> Option<f64> {
    let rest = s.get(s.find(label)? + label.len()..)?.trim_start();
    rest.chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect::<String>()
        .parse()
        .ok()
}

// ===========================================================================
// wpctl status parsing  (pure; unit-tested at the bottom)
// ===========================================================================

#[derive(Debug, PartialEq)]
struct Node {
    id: u32,
    name: String,
    default: bool,
    vol: Option<i64>,
    muted: bool,
}

#[derive(Debug, PartialEq)]
struct Stream {
    id: u32,
    name: String,
}

/// `[vol: 0.58]` → 58. Mirrors `re.search(r"\[vol:\s*([\d.]+)\]", body)`.
fn vol_of(body: &str) -> Option<i64> {
    number_after(body, "[vol:").map(|v| (v * 100.0).round() as i64)
}

/// Drop `[vol …]` / `[muted …]` spans (`\[(vol|muted)[^]]*\]`), collapse
/// whitespace runs to one space (`\s+` → " "), trim.
fn clean_name(n: &str) -> String {
    let mut out = String::with_capacity(n.len());
    let mut i = 0;
    while i < n.len() {
        if n[i..].starts_with('[') {
            if let Some(tag) = ["vol", "muted"].into_iter().find(|t| n[i + 1..].starts_with(t)) {
                if let Some(close) = n[i + 1 + tag.len()..].find(']') {
                    i += 1 + tag.len() + close + 1;
                    continue;
                }
            }
        }
        let c = n[i..].chars().next().unwrap_or('\u{fffd}');
        out.push(c);
        i += c.len_utf8();
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// `^Audio\s*\n(.*?)(?=^Video\s*\n)` with re.M|re.S → the Audio tree body.
fn audio_section(out: &str) -> &str {
    let mut off = 0;
    let mut body = None;
    for line in out.split('\n') {
        if body.is_none() {
            if bare_label(line, "Audio") {
                body = Some(off + line.len() + 1);
            }
        } else if bare_label(line, "Video") {
            return &out[body.unwrap().min(out.len())..off];
        }
        off += line.len() + 1;
    }
    out
}

/// `^X\s*\n`: a line that is `X` plus nothing but whitespace.
fn bare_label(line: &str, label: &str) -> bool {
    line.starts_with(label) && line[label.len()..].trim().is_empty()
}

/// `out.find(start)` … up to the next `end`; `""` if `start` is absent, as in
/// the Python (a missing section must not sweep up the rest of the dump).
fn section<'a>(audio: &'a str, start: &str, end: Option<&str>) -> &'a str {
    let Some(i) = audio.find(start) else {
        return "";
    };
    let seg = &audio[i + start.len()..];
    match end.and_then(|e| seg.find(e)) {
        Some(j) => &seg[..j],
        None => seg,
    }
}

/// Sinks / Sources lines like ` │  *   45. USB Audio Device [vol: 0.58]`.
fn parse_nodes(seg: &str) -> Vec<Node> {
    let mut nodes = Vec::new();
    for ln in seg.lines() {
        let b = ln.as_bytes();
        let mut i = 0;
        // ^\s* │? \s* \*? \s* (\d+)\. \s+ (.*)$
        while i < b.len() && b[i].is_ascii_whitespace() {
            i += 1;
        }
        if ln[i..].starts_with('│') {
            i += '│'.len_utf8();
        }
        while i < b.len() && b[i].is_ascii_whitespace() {
            i += 1;
        }
        // Python: `^\s*│?\s*\*`. The sibling half of that expression,
        // `re.search(r"\*?\s*\d+\.", ln)`, is always true once the id below
        // matched, so the `*` test is the whole of it.
        let default = b.get(i) == Some(&b'*');
        if default {
            i += 1;
        }
        while i < b.len() && b[i].is_ascii_whitespace() {
            i += 1;
        }
        let Some((id, n)) = scan_uint(&ln[i..]) else {
            continue;
        };
        i += n;
        if !ln[i..].starts_with('.') {
            continue;
        }
        i += 1;
        // \s+ — the name must be preceded by at least one space
        let ws = b[i..].iter().take_while(|c| c.is_ascii_whitespace()).count();
        if ws == 0 {
            continue;
        }
        i += ws;
        let body = &ln[i..];
        nodes.push(Node {
            id,
            name: clean_name(body),
            default,
            vol: vol_of(body),
            muted: body.contains("muted: yes"),
        });
    }
    nodes
}

/// Top-level 'Streams' entries (8 spaces indent), excluding links (deeper,
/// contain >/<).
fn parse_streams(seg: &str) -> Vec<Stream> {
    let mut nodes = Vec::new();
    for ln in seg.lines() {
        if ln.contains('<') || ln.contains('>') {
            continue;
        }
        // `^ {6,12}(\d+)\.\s+(.*?)\s*$`: 13+ leading spaces is a channel link
        // and fails to match at every backtrack position.
        let lead = ln.len() - ln.trim_start_matches(' ').len();
        if !(6..=12).contains(&lead) {
            continue;
        }
        let Some((id, n)) = scan_uint(&ln[lead..]) else {
            continue;
        };
        let Some(rest) = ln[lead + n..].strip_prefix('.') else {
            continue;
        };
        if !rest.starts_with(char::is_whitespace) {
            continue;
        }
        let name = rest.trim();
        if is_blocked(name) || is_chanlink(name) {
            continue;
        }
        nodes.push(Stream {
            id,
            name: name.to_string(),
        });
    }
    nodes
}

fn is_blocked(name: &str) -> bool {
    let n = name.to_lowercase();
    BLOCKLIST.iter().any(|b| n.contains(b))
}

/// `^(input|output|monitor)_[a-z0-9]+$`, case-insensitive.
fn is_chanlink(name: &str) -> bool {
    let n = name.to_lowercase();
    CHANLINK_PREFIXES.iter().any(|p| {
        n.strip_prefix(p)
            .and_then(|r| r.strip_prefix('_'))
            .is_some_and(|t| !t.is_empty() && t.bytes().all(|c| c.is_ascii_alphanumeric()))
    })
}

/// Parse a leading run of ASCII digits; return (value, bytes consumed).
fn scan_uint(s: &str) -> Option<(u32, usize)> {
    let n = s.bytes().take_while(u8::is_ascii_digit).count();
    if n == 0 {
        return None;
    }
    s[..n].parse().ok().map(|v| (v, n))
}

// ===========================================================================
// Hyprland
// ===========================================================================

fn hypr_socket_path() -> Option<PathBuf> {
    let sig = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").ok().filter(|s| !s.is_empty());
    let xdg = std::env::var("XDG_RUNTIME_DIR").ok().filter(|s| !s.is_empty());
    for base in [xdg.unwrap_or_else(|| "/tmp".into()), "/tmp".into()] {
        if let Some(sig) = &sig {
            let p = Path::new(&base).join("hypr").join(sig).join(".socket2.sock");
            if p.exists() {
                return Some(p);
            }
        }
    }
    let v: Value = serde_json::from_str(&sh(&["hyprctl", "-j", "instances"])).ok()?;
    v.as_array()?.iter().find_map(|i| {
        let sockets = i.get("sockets").and_then(Value::as_array)?;
        let names: Vec<&str> = sockets.iter().filter_map(Value::as_str).collect();
        names
            .into_iter()
            .find(|s| s.ends_with(".socket2.sock") && Path::new(s).exists())
            .map(PathBuf::from)
    })
}

/// Thread: notify the main loop once a significant Hyprland event arrives
/// (clicking/acting anywhere outside the popup). Touches nothing but the
/// channel — glib main-context calls from a foreign thread are unsound.
fn watch_hypr_events(path: PathBuf, tx: Sender<()>) {
    let _ = std::thread::spawn(move || {
        let Ok(mut s) = UnixStream::connect(&path) else { return };
        if s.set_read_timeout(Some(Duration::from_millis(500))).is_err() {
            return;
        }
        let (mut buf, mut chunk) = (Vec::new(), [0u8; 4096]);
        loop {
            match s.read(&mut chunk) {
                Ok(0) => break,
                Ok(n) => {
                    buf.extend_from_slice(&chunk[..n]);
                    while let Some(i) = buf.iter().position(|&b| b == b'\n') {
                        let tail = buf.split_off(i + 1);
                        let mut line = std::mem::replace(&mut buf, tail);
                        line.pop(); // the '\n'
                        let line = String::from_utf8_lossy(&line);
                        let line = line.trim();
                        if line.is_empty() {
                            continue;
                        }
                        if CLOSE_EVENTS.contains(&line.split(">>").next().unwrap_or("")) {
                            let _ = tx.send(());
                            return;
                        }
                    }
                }
                Err(e)
                    if matches!(
                        e.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                    ) => continue,
                Err(_) => break,
            }
        }
    });
}

/// (x, y, w, h) of this panel as reported by the compositor.
fn popup_rect() -> Option<(i64, i64, i64, i64)> {
    let out = sh(&["hyprctl", "-j", "layers"]);
    if out.is_empty() {
        return None;
    }
    let v: Value = serde_json::from_str(&out).ok()?;
    for mon in v.as_object()?.values() {
        let Some(levels) = mon.get("levels").and_then(Value::as_object) else {
            continue;
        };
        for lvl in levels.values() {
            for e in lvl.as_array().into_iter().flatten() {
                if e.get("namespace").and_then(Value::as_str) == Some("audio-popup") {
                    let g = |k: &str| e.get(k).and_then(Value::as_i64).unwrap_or(0);
                    return Some((g("x"), g("y"), g("w"), g("h")));
                }
            }
        }
    }
    None
}

fn cursor_pos() -> Option<(i64, i64)> {
    let v: Value = serde_json::from_str(&sh(&["hyprctl", "-j", "cursorpos"])).ok()?;
    Some((
        v.get("x").and_then(Value::as_i64)?,
        v.get("y").and_then(Value::as_i64)?,
    ))
}

/// The monitor the pointer is on, so the panel opens where the user clicked.
fn monitor_for_pointer() -> Option<gdk::Monitor> {
    let display = gdk::Display::default()?;
    // GTK 4.22 has no gdk_display_get_primary_monitor(), so monitor 0 is the
    // fallback (which is what the Python's `or get_monitor(0)` amounted to).
    let mons: Vec<gdk::Monitor> = {
        let model = display.monitors();
        (0..model.n_items())
            .filter_map(|i| model.item(i))
            .filter_map(|o| o.downcast().ok())
            .collect()
    };
    if let Some((mx, my)) = cursor_pos().map(|(x, y)| (x as i32, y as i32)) {
        for m in &mons {
            let r = m.geometry();
            if r.x() <= mx && mx < r.x() + r.width() && r.y() <= my && my < r.y() + r.height() {
                return Some(m.clone());
            }
        }
    }
    mons.first().cloned()
}

// ===========================================================================
// pidfile / toggle
// ===========================================================================

/// `$XDG_RUNTIME_DIR/audio-popup.pid`, falling back to `std::env::temp_dir()`
/// (i.e. /tmp). The Python hardcoded `/tmp/opencode/audio-popup.pid`, which is
/// really "some directory that happens to exist"; the runtime dir is the
/// XDG-sanctioned per-user, 0700, logout-cleaned place for exactly this.
fn pidfile() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map_or_else(std::env::temp_dir, PathBuf::from)
        .join("audio-popup.pid")
}

/// Liveness check. Linux-only program, so /proc answers it; this also avoids
/// `kill(pid, 0)`, which would need `unsafe`.
fn pid_alive(pid: i32) -> bool {
    pid > 0 && Path::new(&format!("/proc/{pid}")).exists()
}

/// If an instance is running, SIGTERM it and report that we should exit.
fn toggle_running() -> bool {
    let Ok(txt) = std::fs::read_to_string(pidfile()) else {
        return false;
    };
    let Ok(pid) = txt.trim().parse::<i32>() else {
        return false;
    };
    if !pid_alive(pid) {
        return false;
    }
    // kill(1) rather than libc::kill, so that `unsafe` stays forbidden.
    let _ = Command::new("kill")
        .args(["-TERM", &pid.to_string()])
        .status();
    true
}

/// Claims the pidfile: writes our pid, and removes the file however we leave,
/// including on unwind.
struct Pidfile(PathBuf);

impl Pidfile {
    fn create() -> std::io::Result<Self> {
        let p = pidfile();
        std::fs::write(&p, std::process::id().to_string())?;
        Ok(Pidfile(p))
    }
}

impl Drop for Pidfile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

// ===========================================================================
// UI
// ===========================================================================

struct App {
    panel: gtk::Box,
    content: RefCell<Option<gtk::Box>>,
    master_title: RefCell<Option<gtk::Label>>,
    /// Consecutive pointer checks that landed outside the panel.
    outside: Cell<i32>,
    /// Non-zero while a scale is being dragged; suppresses the 5 s poll so the
    /// slider is not yanked out from under the cursor.
    drag: Cell<i32>,
}

impl App {
    fn append(&self, child: &impl IsA<gtk::Widget>) {
        if let Some(c) = self.content.borrow().as_ref() {
            c.append(child);
        }
    }

    fn new_scale(
        self: &Rc<Self>,
        value: i64,
        wide: bool,
        on_change: Box<dyn Fn(&gtk::Scale)>,
    ) -> gtk::Scale {
        let s = gtk::Scale::with_range(gtk::Orientation::Horizontal, 0.0, 100.0, 1.0);
        s.set_size_request(if wide { 200 } else { 150 }, -1);
        s.set_draw_value(false);
        s.set_value(value as f64);
        // Drag tracking: the Python's button-press-event / button-release-event.
        for (kind, bump) in [
            (gdk::EventType::ButtonPress, 1i32),
            (gdk::EventType::ButtonRelease, -1i32),
        ] {
            let drag = self.drag.clone();
            let ctl = gtk::EventControllerLegacy::new();
            ctl.connect_event(move |_, ev| {
                if ev.event_type() == kind {
                    drag.set((drag.get() + bump).max(0));
                }
                // never swallow it; the scale still gets the event
                glib::Propagation::Proceed
            });
            s.add_controller(ctl);
        }
        s.connect_value_changed(move |s| on_change(s));
        s
    }

    fn section_label(text: &str) -> gtk::Label {
        let l = gtk::Label::builder().label(text).xalign(0.0).build();
        l.add_css_class("section-label");
        l
    }

    fn master_section(self: &Rc<Self>, master: Option<i64>, muted: bool) {
        let hdr = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        let title = gtk::Label::builder()
            .label(format!("Master  {}%", master.unwrap_or(0)))
            .xalign(0.0)
            .build();
        title.add_css_class("title-label");
        title.set_hexpand(true);
        *self.master_title.borrow_mut() = Some(title.clone());

        let mute = gtk::Button::with_label(if muted { "Unmute" } else { "Mute" });
        mute.add_css_class("close-btn");
        let me = self.clone();
        mute.connect_clicked(move |_| {
            sh(&["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
            me.rebuild();
        });

        let close = gtk::Button::with_label("✕");
        close.add_css_class("close-btn");
        close.connect_clicked(move |b| {
            if let Some(w) = b
                .ancestor(gtk::Window::static_type())
                .and_then(|a| a.downcast::<gtk::Window>().ok())
            {
                w.close();
            }
        });

        hdr.append(&title);
        hdr.append(&mute);
        hdr.append(&close);
        self.append(&hdr);

        let me = self.clone();
        let scale = self.new_scale(
            master.unwrap_or(0),
            true,
            Box::new(move |s| {
                let v = s.value().round() as i64;
                sh(&["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", &format!("{v}%")]);
                if let Some(l) = me.master_title.borrow().as_ref() {
                    l.set_text(&format!("Master  {v}%"));
                }
            }),
        );
        self.append(&scale);
    }

    fn device_row(self: &Rc<Self>, n: &Node) -> gtk::Button {
        let btn = gtk::Button::new();
        btn.add_css_class("row");
        if n.default {
            btn.add_css_class("active");
        }
        let mark = if n.default { "● " } else { "" };
        let name = glib::markup_escape_text(&n.name);
        let pct = match n.vol {
            Some(v) => format!(" <span color=\"{DIM}\">{v}%</span>"),
            None => String::new(),
        };
        btn.set_child(Some(
            &gtk::Label::builder()
                .label(format!("{mark}{name}{pct}"))
                .use_markup(true)
                .xalign(0.0)
                .build(),
        ));

        let me = self.clone();
        let id = n.id.to_string();
        btn.connect_clicked(move |_| {
            sh(&["wpctl", "set-default", &id]);
            me.rebuild();
        });
        btn
    }

    fn app_row(self: &Rc<Self>, s: &Stream) -> gtk::Box {
        let vbox = gtk::Box::new(gtk::Orientation::Vertical, 1);
        let top = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        let name = gtk::Label::builder()
            .label(&s.name)
            .xalign(0.0)
            .ellipsize(gtk::pango::EllipsizeMode::End)
            .build();
        name.set_hexpand(true);

        let vol = get_volume(&s.id.to_string()).0.unwrap_or(100);
        let pct = gtk::Label::builder().label(format!("{vol}%")).xalign(1.0).build();
        top.append(&name);
        top.append(&pct);
        vbox.append(&top);

        let id = s.id.to_string();
        let scale = self.new_scale(
            vol,
            false,
            Box::new(move |scale| {
                let v = scale.value().round() as i64;
                sh(&["wpctl", "set-volume", &id, &format!("{v}%")]);
                pct.set_text(&format!("{v}%"));
            }),
        );
        scale.add_css_class("app-scale");
        vbox.append(&scale);

        let frame = gtk::Box::new(gtk::Orientation::Vertical, 0);
        frame.set_margin_top(2);
        frame.append(&vbox);
        frame
    }

    fn rebuild(self: &Rc<Self>) {
        if let Some(old) = self.content.borrow_mut().take() {
            self.panel.remove(&old);
        }
        *self.master_title.borrow_mut() = None;

        let content = gtk::Box::new(gtk::Orientation::Vertical, 6);
        content.set_margin_top(12);
        content.set_margin_bottom(12);
        content.set_margin_start(12);
        content.set_margin_end(12);
        self.panel.append(&content);
        *self.content.borrow_mut() = Some(content.clone());

        let (master, muted) = get_volume("@DEFAULT_AUDIO_SINK@");
        self.master_section(master, muted);

        let status = wpctl_status();
        let audio = audio_section(&status);
        let sinks = parse_nodes(section(audio, "Sinks:", Some("Sources:")));
        let sources = parse_nodes(section(audio, "Sources:", Some("Filters:")));
        let streams = parse_streams(section(audio, "Streams:", None));

        for (label, nodes) in [("OUTPUT", &sinks), ("INPUT", &sources)] {
            if !nodes.is_empty() {
                let l = Self::section_label(label);
                content.append(&l);
                for n in nodes.iter() {
                    let row = self.device_row(n);
                    content.append(&row);
                }
            }
        }
        if !streams.is_empty() {
            let l = Self::section_label("APPS");
            content.append(&l);
            for s in &streams {
                let row = self.app_row(s);
                content.append(&row);
            }
        }
    }
}

/// Set the window up as a layer surface and return it with its `App`.
fn build_window(loop_: &glib::MainLoop) -> (gtk::Window, Rc<App>) {
    let win = gtk::Window::builder()
        .title("audio-popup")
        .decorated(false)
        .resizable(false)
        .default_width(320)
        .build();

    win.init_layer_shell();
    win.set_namespace(Some("audio-popup"));
    win.set_layer(Layer::Top);
    win.set_anchor(Edge::Top, true);
    win.set_anchor(Edge::Right, true);
    win.set_margin(Edge::Top, BAR_HEIGHT + 8);
    win.set_margin(Edge::Right, 8);
    win.set_exclusive_zone(0);
    win.set_keyboard_mode(KeyboardMode::OnDemand);
    if let Some(m) = monitor_for_pointer() {
        win.set_monitor(Some(&m));
    }

    // GTK4 has no get_rgba_visual(): `window { background: transparent; }` in
    // the CSS is what makes the panel float. GTK4 also has no
    // add_provider_for_screen, so the provider goes on the display.
    let provider = gtk::CssProvider::new();
    provider.load_from_data(CSS);
    if let Some(d) = gdk::Display::default() {
        gtk::style_context_add_provider_for_display(
            &d,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }

    let panel = gtk::Box::new(gtk::Orientation::Vertical, 0);
    panel.add_css_class("panel");
    win.set_child(Some(&panel));

    // Esc closes. ON_DEMAND keyboard mode means we only see the key once the
    // surface has focus, i.e. after the user clicked the panel.
    let esc = gtk::EventControllerKey::new();
    let l = loop_.clone();
    esc.connect_key_pressed(move |_, key, _, _| {
        if key == gdk::Key::Escape {
            l.quit();
            glib::Propagation::Stop
        } else {
            glib::Propagation::Proceed
        }
    });
    win.add_controller(esc);

    // The ✕ button calls win.close(), which only unmaps the surface — the main
    // loop is ours, not tied to window lifetime, so nothing would return and
    // the process would linger invisibly (poll still firing, pidfile still
    // there, and the next toggle would kill the ghost instead of opening the
    // panel). Route the close request to loop_.quit(), as the Python's
    // Gtk.main_quit() did.
    let l = loop_.clone();
    win.connect_close_request(move |_| {
        l.quit();
        glib::Propagation::Proceed
    });

    let app = Rc::new(App {
        panel,
        content: RefCell::new(None),
        master_title: RefCell::new(None),
        outside: Cell::new(0),
        drag: Cell::new(0),
    });
    app.rebuild();
    (win, app)
}

// ===========================================================================
// main
// ===========================================================================

/// Block SIGTERM/SIGINT process-wide and hand them to a thread that pokes the
/// channel. glib 0.22 removed `unix_signal_add_local()`, and calling into glib
/// from a signal handler is not allowed anyway; this is the boring, safe way.
///
/// Must run before any thread is spawned (the signal mask is per-thread and
/// `sh()` spawns one), so it is the first thing `main` does.
fn watch_termination_signals(tx: Sender<()>) {
    let mut set = SigSet::empty();
    set.add(Signal::SIGTERM);
    set.add(Signal::SIGINT);
    if let Err(e) = set.thread_block() {
        eprintln!("audio-popup: cannot block SIGTERM/SIGINT: {e}");
        return;
    }
    let _ = std::thread::spawn(move || {
        let _ = set.wait();
        let _ = tx.send(());
    });
}

fn main() -> Result<(), Box<dyn Error>> {
    let (tx, rx): (Sender<()>, Receiver<()>) = channel();
    watch_termination_signals(tx.clone());

    // Toggle: close an already-running instance, otherwise start one.
    if toggle_running() {
        return Ok(());
    }
    let _pid = Pidfile::create()?;

    gtk::init()?;
    let loop_ = glib::MainLoop::new(None, false);
    let (win, app) = build_window(&loop_);

    // Close when the user does anything outside the popup: a termination
    // signal, Hyprland events (read on a std thread, drained here), or the
    // pointer leaving the panel. Pidfile::drop cleans up after the loop.
    if let Some(path) = hypr_socket_path() {
        watch_hypr_events(path, tx);
    }
    let l = loop_.clone();
    glib::timeout_add_local(Duration::from_millis(100), move || match rx.try_recv() {
        Ok(()) | Err(TryRecvError::Disconnected) => {
            l.quit();
            glib::ControlFlow::Break
        }
        Err(TryRecvError::Empty) => glib::ControlFlow::Continue,
    });

    let a = app.clone();
    let l = loop_.clone();
    glib::timeout_add_local(Duration::from_millis(150), move || {
        if let (Some((gx, gy, gw, gh)), Some((cx, cy))) = (popup_rect(), cursor_pos()) {
            let inside = gx <= cx && cx < gx + gw && gy <= cy && cy < gy + gh;
            let in_bar = cy <= BAR_HEIGHT as i64 + 8; // hovering the bar is neutral
            if cx < 0 || cy < 0 || inside || in_bar {
                a.outside.set(0);
            } else {
                let n = a.outside.get() + 1;
                a.outside.set(n);
                if n >= 2 { // ~300 ms outside → close
                    l.quit();
                    return glib::ControlFlow::Break;
                }
            }
        }
        glib::ControlFlow::Continue
    });

    let a = app.clone();
    glib::timeout_add_local(Duration::from_secs(5), move || {
        if a.drag.get() == 0 {
            a.rebuild();
        }
        glib::ControlFlow::Continue
    });

    win.present();
    loop_.run();
    Ok(())
}

// ===========================================================================
// tests
// ===========================================================================

#[cfg(test)]
mod tests {
    use super::*;

    /// Real `wpctl status` output, trimmed to the parts the parser reads.
    /// Indentation is preserved exactly: top-level streams sit at 7-8 leading
    /// spaces, their channel links at 12 (with < / >) or 13 (bare `monitor_FL`).
    const WPCTL: &str = "\
PipeWire 'pipewire-0' [1.6.9, maxii@C3PO, cookie:2718393209]
 └─ Clients:
       114. Spotify                             [1.6.9, maxii@C3PO, pid:1136345]

Audio
 ├─ Devices:
 │      54. USB Audio Device                    [alsa]
 │
 ├─ Sinks:
 │  *   52. USB Audio Device Analog Stereo      [vol: 0.58]
 │      67. Navi 31 HDMI/DP Audio Digital Stereo (HDMI) [M28U] [vol: 0.56]
 │      68. HyperX QuadCast S Analog Stereo     [vol: 0.40]
 │
 ├─ Sources:
 │  *   44. Linux_Soundboard_Mic                [vol: 0.88]
 │      51. USB Audio Device Mono               [vol: 1.00]
 │      71. Webcam C930e Analog Stereo          [vol: 1.00]
 │
 ├─ Filters:
 │
 └─ Streams:
        41. linuxsoundboard.local_playback
             65. output_FL       > USB Audio Device:playback_FL\t[active]
            146. input_FL        < Linux_Soundboard_Output:output_FL\t[active]
             98. monitor_FL
       106. Spotify
            108. output_FL       > gsr-combined-NXxqa8oZ.monitor:input_FL\t[active]
       202. Firefox
            213. output_FL       > USB Audio Device:playback_FL\t[paused]

Video
 ├─ Sources:
 │  *  131. Logitech Webcam C930e (V4L2)
";

    #[test]
    fn audio_section_stops_at_video() {
        let a = audio_section(WPCTL);
        // The capture group begins after `^Audio\s*\n`, so the slice starts at
        // the first tree line, not at a newline.
        assert!(a.starts_with(" ├─ Devices:"), "got {:?}", &a[..20]);
        assert!(a.contains("HyperX QuadCast S Analog Stereo     [vol: 0.40]"));
        assert!(!a.contains("Video"), "Video leaked into the audio slice");
        assert!(!a.contains("Spotify                             [1.6.9"), "Clients leaked in");
    }

    #[test]
    fn sinks_sources_defaults_and_volumes() {
        let audio = audio_section(WPCTL);

        let sinks = parse_nodes(section(audio, "Sinks:", Some("Sources:")));
        assert_eq!(
            sinks,
            vec![
                Node { id: 52, name: "USB Audio Device Analog Stereo".into(), default: true, vol: Some(58), muted: false },
                // [M28U] is kept, [vol: …] is stripped, inner spaces collapse
                Node { id: 67, name: "Navi 31 HDMI/DP Audio Digital Stereo (HDMI) [M28U]".into(), default: false, vol: Some(56), muted: false },
                Node { id: 68, name: "HyperX QuadCast S Analog Stereo".into(), default: false, vol: Some(40), muted: false },
            ]
        );

        let sources = parse_nodes(section(audio, "Sources:", Some("Filters:")));
        assert_eq!(
            sources.iter().map(|n| (n.id, n.default, n.vol)).collect::<Vec<_>>(),
            vec![(44, true, Some(88)), (51, false, Some(100)), (71, false, Some(100))]
        );
        assert_eq!(sources[0].name, "Linux_Soundboard_Mic");
    }

    #[test]
    fn streams_drop_blocklist_and_channel_links() {
        let audio = audio_section(WPCTL);
        let streams = parse_streams(section(audio, "Streams:", None));
        assert_eq!(
            streams,
            vec![
                Stream { id: 106, name: "Spotify".into() },
                Stream { id: 202, name: "Firefox".into() },
            ],
            "only real apps survive: 41 is linuxsoundboard-blocked, 65/146/108/213 \
             contain < or >, 98 is a 13-space bare channel link"
        );
    }

    #[test]
    fn stream_filters() {
        for blocked in [
            "cava",
            "Cava Output",
            "gsr-default_output",
            "pipewire-pulse",
            "WirePlumber",
            "xdg-desktop-portal-hyprland",
            "linuxsoundboard.local_playback",
            "gsr-combined-NXxqa8oZ.monitor",
            "Monitor",
        ] {
            assert!(is_blocked(blocked), "{blocked} should be blocked");
        }
        assert!(!is_blocked("Firefox"));
        assert!(!is_blocked("Spotify"));

        for link in ["input_FL", "output_FR", "monitor_FL", "INPUT_A1", "output_1"] {
            assert!(is_chanlink(link), "{link} should be a channel link");
        }
        for app in ["Firefox", "output_FL_extra", "input_", "inputFL", "_FL", "xinput_FL"] {
            assert!(!is_chanlink(app), "{app} should not be a channel link");
        }
    }

    #[test]
    fn volume_extraction() {
        assert_eq!(vol_of("USB Audio Device Analog Stereo      [vol: 0.58]"), Some(58));
        assert_eq!(vol_of("Webcam C930e Analog Stereo          [vol: 1.00]"), Some(100));
        assert_eq!(vol_of("no volume here"), None);
        assert_eq!(volume_of("Volume: 0.58\nMuted: no\n"), Some(0.58));
        assert_eq!(volume_of("Volume: 1.00\nMuted: yes\n"), Some(1.0));
        assert_eq!(volume_of("garbage"), None);
    }

    #[test]
    fn clean_name_strips_tags() {
        assert_eq!(clean_name("Foo [vol: 0.40]"), "Foo");
        assert_eq!(clean_name("Foo [muted]"), "Foo");
        assert_eq!(clean_name("Foo [vol: 0.4] [muted: yes]"), "Foo");
        assert_eq!(clean_name("  a   b  "), "a b");
        assert_eq!(clean_name("[M28U] x"), "[M28U] x");
    }

    #[test]
    fn missing_sections_are_empty() {
        assert_eq!(parse_nodes(section("nothing here", "Sinks:", Some("Sources:"))), vec![]);
        assert_eq!(parse_streams(section("nothing here", "Streams:", None)), vec![]);
        assert_eq!(audio_section("no audio tree"), "no audio tree");
    }
}

