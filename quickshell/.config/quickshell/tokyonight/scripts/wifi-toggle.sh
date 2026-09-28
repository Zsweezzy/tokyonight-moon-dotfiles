#!/bin/bash
# wifi-toggle.sh — reveal/hide the SSID in the waybar wifi widget
state="/tmp/opencode/wifi-show"
if [ -f "$state" ]; then
    rm -f "$state"
else
    touch "$state"
fi
# Refresh the custom/wifi module (signal 8) on every waybar instance
