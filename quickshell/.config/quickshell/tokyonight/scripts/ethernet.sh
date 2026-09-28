#!/bin/bash
# ethernet.sh — shows "ethernet" (or "off") with the ethernet icon and, on
# hover, a tooltip with the interface, IP, DNS, netmask and MAC of the link.
# Emits JSON so Waybar uses the `tooltip` field; the icon and text are
# separated by a space.

. "$(dirname "$0")/net-common.sh"

iface="enp14s0"
carrier=$(cat "/sys/class/net/$iface/carrier" 2>/dev/null)

# Label: ethernet icon + space + text
if [ "$carrier" = "1" ]; then
    label=$(printf '\uef44  ethernet')
else
    label=$(printf '\uef44  off')
fi

# Network details for the tooltip
ipaddr=$(iface_ip "$iface")
netmask=$(prefix_to_mask "$(iface_cidr "$iface")")
dns=$(iface_dns "$iface")
mac=$(iface_mac "$iface")

tooltip=$(printf 'Interface: %s\nIP: %s\nNetmask: %s\nDNS: %s\nMAC: %s' \
    "$(jesc "$iface")"     "$(jesc "${ipaddr:--}")" \
    "$(jesc "${netmask:--}")" "$(jesc "${dns:--}")" \
    "$(jesc "${mac:--}")")
tooltip=${tooltip//$'\n'/\\n}   # literal \n so the JSON stays on one line

printf '{"text": "%s", "tooltip": "%s"}\n' "$(jesc "$label")" "$tooltip"