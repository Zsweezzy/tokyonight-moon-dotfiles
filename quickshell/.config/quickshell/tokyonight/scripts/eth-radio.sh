#!/bin/bash
# eth-radio.sh — bring the wired link up or down via NetworkManager.
#
#   on   nmcli device connect   — re-activates the saved profile
#   off  nmcli device disconnect — drops the link, carrier goes to 0
#
# `device disconnect` is the reversible half of `nmcli device set managed no`:
# it does not unmanage the interface, so the profile, the static address and
# the DNS all survive, and `connect` puts back exactly what was there.
#
# The interface is discovered rather than hardcoded — ethernet.sh still names
# enp14s0 for its tooltip, but the toggle should work on a different box, and a
# wrong hardcoded name would silently fail in a way that looks like the switch
# is broken.
case "$1" in
    on|off) ;;
    *) echo "usage: eth-radio.sh on|off" >&2; exit 2 ;;
esac

iface=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null \
        | awk -F: '$2 == "ethernet" { print $1; exit }')

if [ -z "$iface" ]; then
    echo "eth-radio.sh: no ethernet interface" >&2
    exit 1
fi

case "$1" in
    on)  exec nmcli device connect "$iface" ;;
    off) exec nmcli device disconnect "$iface" ;;
esac
