#!/bin/bash
# bt-scan.sh — discover nearby bluetooth devices, as one JSON line.
#
# Pairing is a separate step (bt-dev.sh), because a pair needs a confirmation
# on the other device's screen and so can take longer than one poll cycle.
. "$(dirname "$0")/net-common.sh"

secs=${1:-8}
bluetoothctl power on >/dev/null 2>&1
bluetoothctl --timeout "$secs" scan on >/dev/null 2>&1

# Every device bluez has ever seen, not just this scan: `devices` is bluez's
# cache, and a device that answered earlier but not now is still worth pairing.
devs=""
while read -r word mac _; do
    [ "$word" = "Device" ] || continue
    [ -z "$mac" ] && continue
    info=$(bluetoothctl info "$mac" 2>/dev/null)
    paired=false
    [ "$(printf '%s' "$info" | awk -F': ' '/Paired:/{print $2}')" = "yes" ] && paired=true
    name=$(printf '%s' "$info" | awk -F': ' '/Alias:|Name:/{print $2; exit}')
    [ -z "$name" ] && name=$(bluetoothctl list 2>/dev/null | awk -v m="$mac:" '$2==m{print $3}')
    icon=$(printf '%s' "$info" | awk -F': ' '/Icon:/{print $2}')
    [ -n "$devs" ] && devs="$devs,"
    devs="$devs{\"mac\":\"$(jesc "$mac")\",\"name\":\"$(jesc "$name")\",\"paired\":$paired,\"icon\":\"$(jesc "$icon")\"}"
done <<< "$(bluetoothctl devices 2>/dev/null)"

printf '{"devices":[%s]}\n' "$devs"
