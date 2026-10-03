#!/bin/bash
# bt-dev.sh — pair / unpair / connect / disconnect one bluetooth device.
#
#   bt-dev.sh connect <mac>     pair if needed, then connect
#   bt-dev.sh disconnect <mac>
#   bt-dev.sh forget <mac>      unpair
#
# `connect` pairs first because bluez refuses to connect an unpaired device,
# and the phone still has to confirm the pairing request — hence the timeout.
# A failure here is the user not tapping "allow" on the phone, not a script
# error, so the exit status is not worth branching on.
mac=$2
[ -z "$mac" ] && { echo "usage: bt-dev.sh <connect|disconnect|forget> <mac>" >&2; exit 2; }

case "$1" in
    connect)
        if [ "$(bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Paired:/{print $2}')" != "yes" ]; then
            bluetoothctl --timeout 25 pair "$mac" >/dev/null 2>&1
        fi
        bluetoothctl --timeout 15 connect "$mac" >/dev/null 2>&1
        ;;
    disconnect) bluetoothctl disconnect "$mac" >/dev/null 2>&1 ;;
    forget)     bluetoothctl --timeout 15 untrust "$mac" >/dev/null 2>&1
                 bluetoothctl remove "$mac" >/dev/null 2>&1 ;;
    *) echo "usage: bt-dev.sh <connect|disconnect|forget> <mac>" >&2; exit 2 ;;
esac
