#!/bin/bash
# bt-state.sh — bluetooth radio state + every paired device, as one JSON line.
#
# "devices" is the list the settings flyout shows; each entry is
# { mac, name, connected }. `name` falls back to the alias, then to the mac.
. "$(dirname "$0")/net-common.sh"

# `bluetoothctl` says yes/no; JSON needs true/false, and the QML side tests
# `=== true`, so a yes here reads as the radio being off.
if [ "$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2}')" = "yes" ]; then
    powered=true
else
    powered=false
fi

devs=""
add_dev() {
    local mac=$1 conn=$2
    [ -n "$devs" ] && devs="$devs,"
    devs="$devs{\"mac\":\"$(jesc "$mac")\",\"name\":\"$(jesc "$name")\",\"connected\":$conn}"
}

name=""
# `devices` prefixes every line with the literal word "Device".
while read -r word mac _; do
    [ "$word" = "Device" ] || continue
    [ -z "$mac" ] && continue
    info=$(bluetoothctl info "$mac" 2>/dev/null)
    name=$(printf '%s' "$info" | awk -F': ' '/Alias:|Name:/{print $2; exit}')
    [ -z "$name" ] && name=$(bluetoothctl list 2>/dev/null | awk -v m="$mac:" '$2==m{print $3}')
    conn=false
    [ "$(printf '%s' "$info" | awk -F': ' '/Connected:/{print $2}')" = "yes" ] && conn=true
    add_dev "$mac" "$conn"
done <<< "$(bluetoothctl devices Paired 2>/dev/null)"

printf '{"powered":%s,"devices":[%s]}\n' "$powered" "$devs"
