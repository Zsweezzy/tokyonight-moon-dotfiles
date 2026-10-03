#!/bin/bash
# wifi-list.sh — every visible wifi network, as one JSON line.
#
# nmcli lists one row per BSS (per access point), so the same SSID appears up
# to a dozen times on a dense network. Kept to one entry per SSID, holding the
# strongest signal seen for it — which is the one you would actually join.
. "$(dirname "$0")/net-common.sh"

# iface: the first wireless device NetworkManager knows about
iface=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
        | awk -F: '$2=="wifi"{print $1; exit}')
[ -z "$iface" ] && { printf '{"radio":false,"active":"","networks":[]}\n'; exit 0; }

# `nmcli radio` answers enabled/disabled, not yes/no.
radio=$(nmcli -t radio wifi 2>/dev/null)
# The active row's second column is the SSID; DEVICE would give the interface,
# which is wlan0 for every row and so says nothing about which network is up.
active=$(nmcli -t -f ACTIVE,SSID dev wifi list --rescan no 2>/dev/null \
         | awk -F: '$1=="yes"{print $2; exit}')

# best-signal row per SSID, in awk: a hash keyed on the ssid, compared on signal
nets=$(nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list ifname "$iface" --rescan yes 2>/dev/null \
    | awk -F: '
        $1 == "" { next }                       # hidden ssid: nothing to join by name
        { if (!($1 in best) || $2 + 0 > best[$1] + 0) { best[$1] = $2; sec[$1] = $3 } }
        END { for (s in best) printf "%s\t%s\t%s\n", s, best[s], sec[s] }' \
    | sort -t: -k2 -rn)

# `known` = NetworkManager has a saved profile for it, i.e. it is a network
# this machine has actually used. The flyout lists those by default and keeps
# the rest out of sight until you ask to see them, so a flat in a busy building
# does not put nine strangers in the list next to your own.
known=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null \
        | awk -F: '$2 ~ /wireless/ { print $1 }')

is_known() {
    local want=$1 line
    while IFS= read -r line; do
        [ "$line" = "$want" ] && return 0
    done <<< "$known"
    return 1
}

out=""
while IFS=$'\t' read -r ssid signal security; do
    [ -z "$ssid" ] && continue
    [ -n "$out" ] && out="$out,"
    out="$out{\"ssid\":\"$(jesc "$ssid")\",\"signal\":$signal,\"secure\":$([ -n "$security" ] && echo true || echo false),\"active\":$([ "$ssid" = "$active" ] && echo true || echo false),\"known\":$(is_known "$ssid" && echo true || echo false)}"
done <<< "$nets"

printf '{"radio":%s,"active":"%s","networks":[%s]}\n' \
    "$([ "$radio" = "enabled" ] && echo true || echo false)" \
    "$(jesc "$active")" "$out"
