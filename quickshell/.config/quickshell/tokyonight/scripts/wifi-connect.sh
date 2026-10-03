#!/bin/bash
# wifi-connect.sh — join (or leave) a network.
#
#   wifi-connect.sh join <ssid> [password]
#   wifi-connect.sh leave
#
# An open network needs no password, so the password argument is optional: it
# is passed on only when given, and NetworkManager prompts over the agent when
# the key is wrong or missing. The exit status is 0 for "connected or already
# connected" — anything else is a failure worth showing.
cmd=$1
ssid=$2
pass=$3

case "$cmd" in
    join)
        [ -z "$ssid" ] && { echo "usage: wifi-connect.sh join <ssid> [password]" >&2; exit 2; }
        if [ -n "$pass" ]; then
            nmcli device wifi connect "$ssid" password "$pass" >/dev/null 2>&1
        else
            nmcli device wifi connect "$ssid" >/dev/null 2>&1
        fi
        ;;
    leave) nmcli device disconnect wlan0 >/dev/null 2>&1
           nmcli --wait 10 connection down id "$ssid" >/dev/null 2>&1 ;;
    *)    echo "usage: wifi-connect.sh <join|leave> [ssid] [password]" >&2; exit 2 ;;
esac
