#!/bin/bash
# brightness.sh — DDC/CI monitor brightness for the quickshell bar.
#
# Why DDC/CI and not brightnessctl: this machine has no internal panel
# (/sys/class/backlight is empty), so brightnessctl has nothing to write. Every
# display is external and speaks DDC/CI, so brightness is the standard luminance
# VCP code 0x10 driven through ddcutil.
#
# ddcutil 3.x only accepts an *integer* display number (-d 2) — never a
# connector name — and that number is just the position of the display in
# `ddcutil detect`, which is unrelated to the Hyprland monitor id. The two
# worlds are matched here by EDID serial number (byte-identical strings in
# `ddcutil detect` and `hyprctl monitors -j`), falling back to the DRM
# connector name and then the EDID model. Serial is the only key that stays
# unique when two GPUs each expose an identically named connector.
#
# Usage:
#   brightness.sh map          -> {"DP-1":2,"DP-2":3,"HDMI-A-1":1}   (null = unsupported)
#   brightness.sh get <ddc>    -> "<value> <max>"   e.g. "79 100"    (exit 1 on failure)
#   brightness.sh set <ddc> <value> [max]
#
# Every command writes to stdout only on success and exits non-zero otherwise,
# so callers can tell "monitor did not answer" from "brightness is 0".

set -uo pipefail

DDCUTIL=${DDCUTIL:-ddcutil}

# `ddcutil detect` -> one TAB separated record per display:
#   <ddc number>\t<drm connector>\t<edid model>\t<edid serial>
# Records are emitted in display-number order. Missing fields stay empty
# (a display with no readable EDID still yields number + connector).
detect_records() {
    "$DDCUTIL" detect 2>/dev/null | awk '
        function flush() {
            if (num != "")
                printf "%d\t%s\t%s\t%s\n", num, conn, model, serial
            num = ""; conn = ""; model = ""; serial = ""
        }
        /^Display [0-9]+$/            { num = $2; next }
        /DRM_connector:/              { conn = $2; next }
        /^[[:space:]]+Model:/         { sub(/^[[:space:]]+Model:[[:space:]]*/, ""); model = $0; next }
        /^[[:space:]]+Serial number:/ { sub(/^[[:space:]]+Serial number:[[:space:]]*/, ""); serial = $0; next }
        /^[[:space:]]*$/              { flush() }
        END { flush() }
    '
}

cmd_map() {
    local monitors records
    monitors=$(hyprctl -j monitors 2>/dev/null)
    if [ -z "$monitors" ]; then
        printf '{}\n'
        return 0
    fi

    records=$(detect_records | jq -Rn '
        [ inputs
          | select(length > 0)
          | split("\t")
          | { n: (.[0] | tonumber), conn: .[1], model: .[2], serial: .[3] } ]')

    # A null value means "this monitor has no DDC/CI luminance support"; the
    # QML side turns that into a disabled slider with an explanatory label.
    jq -cn --argjson monitors "$monitors" --argjson records "$records" '
        reduce $monitors[] as $m ({};
            . + { ($m.name):
                    (($records | map(select(.serial != "" and .serial == ($m.serial // "")))      | .[0].n)
                  // ($records | map(select(.conn  != "" and (.conn  | endswith("-" + $m.name)))) | .[0].n)
                  // ($records | map(select(.model != "" and .model == ($m.model // "")))          | .[0].n)
                  // null) })'
}

cmd_get() {
    local ddc=${1:-} out value max
    case "$ddc" in '' | *[!0-9]*) return 1 ;; esac

    # "VCP code 0x10 (Brightness ): current value =   79, max value =   100"
    out=$("$DDCUTIL" -d "$ddc" getvcp 10 2>/dev/null)
    value=$(printf '%s\n' "$out" | sed -n 's/.*current value = *\([0-9]\{1,\}\).*/\1/p')
    max=$(printf '%s\n' "$out" | sed -n 's/.*max value = *\([0-9]\{1,\}\).*/\1/p')

    [ -n "$value" ] || return 1
    printf '%s %s\n' "$value" "${max:-100}"
}

cmd_set() {
    local ddc=${1:-} value=${2:-} max=${3:-100}
    case "$ddc"   in '' | *[!0-9]*) return 1 ;; esac
    case "$value" in '' | *[!0-9]*) return 1 ;; esac
    case "$max"   in '' | *[!0-9]*) max=100 ;; esac

    # Clamp to the monitor's own maximum: ddcutil reports
    # "Verification failed for feature 10" but still exits 0, so an
    # out-of-range write looks like success while changing nothing.
    if [ "$value" -gt "$max" ]; then
        value=$max
    fi

    "$DDCUTIL" -d "$ddc" setvcp 10 "$value" >/dev/null 2>&1
}

case "${1:-}" in
    map) cmd_map ;;
    get) shift; cmd_get "$@" ;;
    set) shift; cmd_set "$@" ;;
    *)
        printf 'usage: %s map | get <ddc> | set <ddc> <value> [max]\n' "$0" >&2
        exit 2
        ;;
esac
