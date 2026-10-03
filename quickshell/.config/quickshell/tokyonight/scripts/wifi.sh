#!/bin/bash
# wifi.sh — shows "wifi" (or the SSID while the toggle state is present) and,
# on hover, a tooltip with the SSID, IP, DNS, netmask and MAC of the wifi link.
# Emits JSON so Waybar uses the `tooltip` field; the icon and text are
# separated by a space.

. "$(dirname "$0")/net-common.sh"

state="/tmp/opencode/wifi-show"

# Interface of the active wifi connection (fall back to any wl* device)
iface=$(nmcli -t -f IN-USE,DEVICE dev wifi 2>/dev/null | awk -F: '/^\*/ {print $2; exit}')
[ -z "$iface" ] && iface=$(ls /sys/class/net 2>/dev/null | grep '^wl' | head -n1)

# Label: wifi icon + space + text
ssid=$(nmcli -t -f IN-USE,SSID dev wifi 2>/dev/null | awk -F: '/^\*/ {print $2; exit}')
if [ -f "$state" ]; then
    label=$(printf '\uf1eb  %s' "${ssid:-off}")
else
    label=$(printf '\uf1eb  wifi')
fi

# Whether the SSID is revealed. Reported as its own field, because the label is
# the only other consumer of this state and an SSID that happens to read "wifi"
# is indistinguishable from the hidden label.
if [ -f "$state" ]; then show_ssid=true; else show_ssid=false; fi

if [ -z "$ssid" ]; then
    printf '{"text": "%s", "showSsid": %s, "tooltip": "Not connected"}\n' "$(jesc "$label")" "$show_ssid"
    exit 0
fi

# Network details for the tooltip
ipaddr=$(iface_ip "$iface")
netmask=$(prefix_to_mask "$(iface_cidr "$iface")")
dns=$(iface_dns "$iface")
mac=$(iface_mac "$iface")

tooltip=$(printf 'SSID: %s\nIP: %s\nNetmask: %s\nDNS: %s\nMAC: %s' \
    "$(jesc "$ssid")"      "$(jesc "${ipaddr:--}")" \
    "$(jesc "${netmask:--}")" "$(jesc "${dns:--}")" \
    "$(jesc "${mac:--}")")
tooltip=${tooltip//$'\n'/\\n}   # literal \n so the JSON stays on one line

printf '{"text": "%s", "showSsid": %s, "tooltip": "%s"}\n' "$(jesc "$label")" "$show_ssid" "$tooltip"