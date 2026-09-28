#!/usr/bin/env python3
"""
audio-popup.py — Tokyo Night Moon audio panel for waybar.

A GTK3 + gtk-layer-shell window anchored directly below the top-right
waybar widget cluster (it "flies out" of the audio widget). Re-invoking
this script toggles it: clicking the pulseaudio widget closes/opens it.
Esc or the ✕ button closes it.

Sections:
  • Master volume slider + mute toggle
  • Outputs  (click to set the default output device)
  • Inputs   (click to set the default input device)
  • Apps     (per-application volume sliders)
"""
import gi
import json
import os
import re
import signal
import socket
import subprocess
import sys
import threading

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell

# ---- Tokyo Night Moon palette ----
PANEL   = "#2f334d"   # bg_highlight
BORDER  = "#414868"
FG      = "#c8d3f5"
DIM     = "#7f849c"
BLUE    = "#82aaff"
MAGENTA = "#bb9af7"
RED     = "#f7768e"

BAR_HEIGHT = 34
RADIUS     = 10             # matches hyprland decoration:rounding
PIDFILE    = "/tmp/opencode/audio-popup.pid"

# Streams we don't want in the "Apps" list (system plumbing)
BLOCKLIST = re.compile(r"cava|gsr-|pipewire|wireplumber|xdg-desktop|linuxsoundboard|monitor", re.I)
# Bare per-channel routing links ("input_FL", "output_FR", "monitor_FL", ...) —
# these are stereo channel links of a stream, not apps.
CHANLINK = re.compile(r"^(input|output|monitor)_[a-z0-9]+$", re.I)

# Hyprland events = "the user did something outside the panel" → close.
# (activewindowv2/workspacev2 are excluded: they fire on title/rename churn.)
CLOSE_EVENTS = {
    "workspace", "focusedmon", "activateworkspace", "moveworkspace",
    "openwindow", "closewindow", "movewindow", "activewindow",
    "fullscreen", "monitor", "urgent", "submap", "togglegroup",
}


def hypr_socket_path():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    bases = [os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "/tmp"]
    for base in bases:
        if sig:
            p = os.path.join(base, "hypr", sig, ".socket2.sock")
            if os.path.exists(p):
                return p
    try:
        for i in json.loads(sh("hyprctl", "-j", "instances") or "[]"):
            for s in i.get("sockets", []):
                if s.endswith(".socket2.sock") and os.path.exists(s):
                    return s
    except Exception:
        pass
    return None


def watch_hypr_events(quit_fn, path, stop):
    """Thread: quit the app once a significant Hyprland event arrives
    (clicking/acting anywhere outside the popup)."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(path)
        s.settimeout(0.5)
        buf = b""
        while not stop.is_set():
            try:
                data = s.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            if not data:
                break
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                line = line.decode(errors="ignore").strip()
                if not line:
                    continue
                if line.split(">>", 1)[0] in CLOSE_EVENTS:
                    GLib.idle_add(quit_fn)
                    return
    except Exception:
        pass


def sh(*args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=5)
        return (p.stdout or "") + (p.stderr or "")
    except Exception:
        return ""


def wpctl_status():
    return sh("wpctl", "status")


def audio_section(out):
    m = re.search(r"^Audio\s*\n(.*?)(?=^Video\s*\n)", out, re.M | re.S)
    return m.group(1) if m else out


def section(audio, start, end=None):
    i = audio.find(start)
    if i < 0:
        return ""
    seg = audio[i + len(start):]
    if end is not None:
        j = seg.find(end)
        if j >= 0:
            seg = seg[:j]
    return seg


def _vol(body):
    m = re.search(r"\[vol:\s*([\d.]+)\]", body)
    return round(float(m.group(1)) * 100) if m else None


def clean_name(n):
    n = re.sub(r"\[(vol|muted)[^]]*\]", "", n)
    return re.sub(r"\s+", " ", n).strip()


def parse_nodes(seg):
    """Sinks / Sources lines like ' │  *  45. USB Audio Device [vol: 0.58]'."""
    nodes = []
    for ln in seg.splitlines():
        m = re.match(r"^\s*│?\s*\*?\s*(\d+)\.\s+(.*)$", ln)
        if not m:
            continue
        nid, body = int(m.group(1)), m.group(2)
        nodes.append(dict(
            id=nid,
            name=clean_name(body),
            default=bool(re.search(r"\*?\s*\d+\.", ln) and re.match(r"^\s*│?\s*\*", ln)),
            vol=_vol(body),
            muted="muted: yes" in body,
        ))
    return nodes


def parse_streams(seg):
    """Top-level 'Streams' entries (8 spaces indent), excluding links (deeper, contain >/<)."""
    nodes = []
    for ln in seg.splitlines():
        if "<" in ln or ">" in ln:
            continue
        m = re.match(r"^ {6,12}(\d+)\.\s+(.*?)\s*$", ln)
        if not m:
            continue
        name = m.group(2).strip()
        if BLOCKLIST.search(name) or CHANLINK.match(name):
            continue
        nodes.append(dict(id=int(m.group(1)), name=name))
    return nodes


def get_volume(node):
    out = sh("wpctl", "get-volume", node)
    m = re.search(r"Volume:\s*([\d.]+)", out)
    return (round(float(m.group(1)) * 100), "muted: yes" in out.lower()) if m else (None, False)


def gdk_monitor_for_pointer(display):
    try:
        cur = json.loads(sh("hyprctl", "-j", "cursorpos") or "{}")
        mx, my = cur.get("x", -1), cur.get("y", -1)
        for i in range(display.get_n_monitors()):
            g = display.get_monitor(i)
            gx, gy, gw, gh = g.get_geometry()
            if gx <= mx < gx + gw and gy <= my < gy + gh:
                return g
    except Exception:
        pass
    return display.get_primary_monitor() or display.get_monitor(0)


CSS = """
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
"""


class AudioPopup(Gtk.Window):
    def __init__(self):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_title("audio-popup")
        self.set_decorated(False)
        self.set_app_paintable(True)
        self.set_default_size(320, -1)
        self.set_resizable(False)
        self.drag = 0
        self.master_title = None
        self.outside = 0
        self._stop = threading.Event()

        GtkLayerShell.init_for_window(self)
        try:
            GtkLayerShell.set_namespace(self, "audio-popup")
        except Exception:
            pass
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, BAR_HEIGHT + 8)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, 8)
        GtkLayerShell.set_exclusive_zone(self, 0)
        try:
            GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        except Exception:
            pass
        try:
            mon = gdk_monitor_for_pointer(self.get_display())
            if mon is not None:
                GtkLayerShell.set_monitor(self, mon)
        except Exception:
            pass

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.connect("key-press-event", self._on_key)
        self.connect("destroy", lambda *_: self._cleanup())

        self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.panel.get_style_context().add_class("panel")
        self.add(self.panel)
        self.content = None
        self.rebuild()
        GLib.timeout_add_seconds(5, self.poll)
        self.show_all()
        # Close when the user does anything outside the popup: Hyprland
        # key/action events, or the pointer leaving the panel area.
        path = hypr_socket_path()
        if path:
            t = threading.Thread(target=watch_hypr_events,
                                 args=(self._close, path, self._stop), daemon=True)
            t.start()
        GLib.timeout_add(150, self._pointer_check)

    # ---- lifecycle ----
    def _on_key(self, _w, ev):
        if ev.keyval == Gdk.KEY_Escape:
            Gtk.main_quit()
            return True
        return False

    def _cleanup(self):
        self._stop.set()
        try:
            os.unlink(PIDFILE)
        except OSError:
            pass

    def _close(self):
        Gtk.main_quit()

    def _popup_rect(self):
        """(x, y, w, h) of this panel as reported by the compositor."""
        out = sh("hyprctl", "-j", "layers")
        if not out:
            return None
        try:
            data = json.loads(out)
        except Exception:
            return None
        for mon in data.values():
            for lvl in (mon.get("levels") or {}).values():
                for e in lvl:
                    if (e.get("namespace") or "") == "audio-popup":
                        return (e["x"], e["y"], e["w"], e["h"])
        return None

    def _pointer_check(self):
        rect = self._popup_rect()
        if rect is None:
            return True
        gx, gy, gw, gh = rect
        try:
            cur = json.loads(sh("hyprctl", "-j", "cursorpos") or "{}")
            cx, cy = cur.get("x", -1), cur.get("y", -1)
        except Exception:
            return True
        if cx < 0 or cy < 0:
            self.outside = 0
            return True
        inside = gx <= cx < gx + gw and gy <= cy < gy + gh
        in_bar = cy <= BAR_HEIGHT + 8      # hovering the waybar strip is neutral
        if inside or in_bar:
            self.outside = 0
        else:
            self.outside += 1
            if self.outside >= 2:          # ~300 ms outside → close
                Gtk.main_quit()
                return False
        return True

    def poll(self):
        if self.drag:
            return True
        try:
            self.rebuild()
        except Exception:
            pass
        return True

    # ---- helpers ----
    def _drag_inc(self, *_):
        self.drag += 1

    def _drag_dec(self, *_):
        self.drag = max(0, self.drag - 1)

    def _new_scale(self, value, on_change, wide=True, handler_ctx=None):
        s = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        s.set_size_request(200 if wide else 150, -1)
        s.set_draw_value(False)
        s.set_value(value)
        s.connect("button-press-event", self._drag_inc)
        s.connect("button-release-event", self._drag_dec)
        s.connect("value-changed", on_change, handler_ctx)
        return s

    def _section_label(self, box, text):
        lbl = Gtk.Label(label=text, xalign=0)
        lbl.get_style_context().add_class("section-label")
        box.pack_start(lbl, False, False, 0)

    # ---- builders ----
    def rebuild(self):
        if self.content is not None:
            self.panel.remove(self.content)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        self.panel.pack_start(box, True, True, 0)
        self.content = box

        master, muted = get_volume("@DEFAULT_AUDIO_SINK@")
        if master is None:
            master = 0
        self._master_section(box, master, muted)

        st = wpctl_status()
        audio = audio_section(st)
        sinks = parse_nodes(section(audio, "Sinks:", "Sources:"))
        sources = parse_nodes(section(audio, "Sources:", "Filters:"))
        streams = parse_streams(section(audio, "Streams:"))

        if sinks:
            self._section_label(box, "OUTPUT")
            for n in sinks:
                box.pack_start(self._device_row(n), False, False, 0)

        if sources:
            self._section_label(box, "INPUT")
            for n in sources:
                box.pack_start(self._device_row(n), False, False, 0)

        if streams:
            self._section_label(box, "APPS")
            for n in streams:
                box.pack_start(self._app_row(n), False, False, 0)

        self.show_all()

    def _master_section(self, box, master, muted):
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.master_title = Gtk.Label(label=f"Master  {master}%", xalign=0)
        self.master_title.get_style_context().add_class("title-label")
        mute = Gtk.Button(label="Unmute" if muted else "Mute")
        mute.get_style_context().add_class("close-btn")
        mute.connect("clicked", lambda *_: (sh("wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"),
                                            self.rebuild()))
        close = Gtk.Button(label="✕")
        close.get_style_context().add_class("close-btn")
        close.connect("clicked", lambda *_: Gtk.main_quit())
        hdr.pack_start(self.master_title, True, True, 0)
        hdr.pack_start(mute, False, False, 0)
        hdr.pack_start(close, False, False, 0)
        box.pack_start(hdr, False, False, 0)

        scale = self._new_scale(master, self._on_master)
        box.pack_start(scale, False, False, 0)

    def _on_master(self, scale, _ctx):
        v = int(round(scale.get_value()))
        sh("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{v}%")
        if self.master_title is not None:
            self.master_title.set_text(f"Master  {v}%")

    def _device_row(self, n):
        btn = Gtk.Button()
        btn.get_style_context().add_class("row")
        if n["default"]:
            btn.get_style_context().add_class("active")
        mark = "● " if n["default"] else ""
        name = GLib.markup_escape_text(n["name"])
        pct = f' <span color="{DIM}">{n["vol"]}%</span>' if n["vol"] is not None else ""
        lbl = Gtk.Label(label=f"{mark}{name}{pct}", use_markup=True, xalign=0)
        btn.add(lbl)
        btn.connect("clicked", lambda *_, nid=n["id"]: self._switch(nid))
        return btn

    def _switch(self, nid):
        sh("wpctl", "set-default", str(nid))
        self.rebuild()

    def _app_row(self, n):
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        name = Gtk.Label(label=n["name"], xalign=0, ellipsize=True)
        pct = Gtk.Label(label="", xalign=1)
        vol = get_volume(str(n["id"]))[0]
        if vol is None:
            vol = 100
        pct.set_text(f"{vol}%")
        top.pack_start(name, True, True, 0)
        top.pack_start(pct, False, False, 0)
        vbox.pack_start(top, False, False, 0)

        scale = self._new_scale(vol, self._on_app, wide=False, handler_ctx=(n["id"], pct))
        scale.get_style_context().add_class("app-scale")
        vbox.pack_start(scale, False, False, 0)

        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        frame.pack_start(vbox, False, False, 0)
        frame.set_margin_top(2)
        return frame

    def _on_app(self, scale, ctx):
        nid, pct = ctx
        v = int(round(scale.get_value()))
        sh("wpctl", "set-volume", str(nid), f"{v}%")
        pct.set_text(f"{v}%")


def main():
    signal.signal(signal.SIGTERM, lambda *_: Gtk.main_quit())
    signal.signal(signal.SIGINT, lambda *_: Gtk.main_quit())

    # Toggle: close an already-running instance, otherwise start one.
    try:
        with open(PIDFILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        os.kill(pid, signal.SIGTERM)
        return 0
    except (FileNotFoundError, ValueError, ProcessLookupError):
        pass
    try:
        os.unlink(PIDFILE)
    except OSError:
        pass

    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))

    win = AudioPopup()
    try:
        Gtk.main()
    finally:
        try:
            os.unlink(PIDFILE)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())