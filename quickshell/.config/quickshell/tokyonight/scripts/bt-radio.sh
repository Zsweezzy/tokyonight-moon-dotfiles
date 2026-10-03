#!/bin/bash
# bt-radio.sh — turn the bluetooth radio on or off. `bluetoothctl power off`
# disconnects every paired device, so this is the same switch the tray applet
# would flip; nothing to clean up afterwards.
case "$1" in
    on)  exec bluetoothctl power on ;;
    off) exec bluetoothctl power off ;;
    *)   echo "usage: bt-radio.sh on|off" >&2; exit 2 ;;
esac
