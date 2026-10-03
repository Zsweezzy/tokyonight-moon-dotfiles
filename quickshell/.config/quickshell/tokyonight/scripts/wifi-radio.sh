#!/bin/bash
# wifi-radio.sh — turn the wifi radio on or off via NetworkManager.
#
# `nmcli radio wifi off` drops the association but leaves the device present,
# which is what the existing wifi.sh / network-monitor.sh already read as
# "the interface exists but is not up" — no other change needed.
case "$1" in
    on|off) exec nmcli radio wifi "$1" ;;
    *)      echo "usage: wifi-radio.sh on|off" >&2; exit 2 ;;
esac
