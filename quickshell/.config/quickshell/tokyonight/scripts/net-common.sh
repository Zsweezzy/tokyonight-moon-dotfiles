#!/bin/bash
# net-common.sh — helpers shared by the wifi/ethernet waybar modules.

# Allow the network monitor's tests (and alternate sysfs mounts) to override
# the interface tree while keeping the existing helper API unchanged.
SYSFS_NET=${NETWORK_SYSFS:-/sys/class/net}

# Escape a string so it is safe inside a JSON string literal.
jesc() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

# Convert a CIDR prefix length (e.g. 24) into a dotted-quad netmask (255.255.255.0).
prefix_to_mask() {
    local p=$1
    [ -z "$p" ] && { echo "-"; return; }
    local mask=$(( (0xFFFFFFFF << (32 - p)) & 0xFFFFFFFF ))
    printf '%d.%d.%d.%d' \
        $(( (mask >> 24) & 0xFF )) $(( (mask >> 16) & 0xFF )) \
        $(( (mask >> 8) & 0xFF ))  $((  mask       & 0xFF ))
}

# Interface details (empty values when the link is offline).
iface_ip()   { ip -4 -o addr show dev "$1" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}'; }
iface_cidr() { ip -4 -o addr show dev "$1" scope global 2>/dev/null | awk '{split($4,a,"/"); print a[2]}'; }
iface_mac()  { cat "$SYSFS_NET/$1/address" 2>/dev/null; }
iface_dns()  { nmcli -g IP4.DNS device show "$1" 2>/dev/null | awk NF | paste -sd, -; }