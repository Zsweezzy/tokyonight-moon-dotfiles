#!/bin/bash
# localsend.sh — is LocalSend up, and the two actions the Airdrop tile has.
#
#   (no args)  {"running":true|false}
#   start      launch it — LocalSend is single-instance, so this also raises the
#              window when it is already running, which is why start and the
#              tile's body are the same call
#   stop       quit it
APP=org.localsend.localsend_app

running() { pgrep -x localsend >/dev/null 2>&1; }

case "${1:-state}" in
    start)
        # setsid so the script returns at once: the tile fires this detached,
        # but flatpak run would otherwise keep the script alive for as long as
        # the window is open.
        setsid flatpak run "$APP" >/dev/null 2>&1 </dev/null &
        ;;
    stop) pkill -x localsend ;;
    state|"")
        if running; then
            echo '{"running":true}'
        else
            echo '{"running":false}'
        fi ;;
    *) echo "usage: localsend.sh [start|stop]" >&2; exit 2 ;;
esac