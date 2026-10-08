#!/bin/bash
# speedtest.sh — the peak download and upload this line can currently reach.
#
# One JSON line, {"down":<Mbit/s>,"up":<Mbit/s>}, which is what
# Settings.qml's speedPoll parses. Cloudflare's speed endpoints need no
# account and no client package, so this stays a curl and an awk — the tree
# has no speedtest CLI and adding one for two numbers is a dependency the
# widget does not need.
#
# Both transfers are capped at 10s each so one run is always shorter than
# speedPoll's 30s interval: a test that could outlive its own timer would
# have two curls running at once and the second one would be dropped.
set -euo pipefail

# 50 MB, not 100: the endpoint answers 403 to anything larger, which came
# back as a clean 0 rather than as an error the widget could say something
# about.
DOWN_BYTES=${SPEEDTEST_DOWN_BYTES:-50000000}
UP_BYTES=${SPEEDTEST_UP_BYTES:-30000000}
MAX_TIME=${SPEEDTEST_MAX_TIME:-10}
# Cloudflare's speed endpoints refuse curl's default agent.
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36"

# A failed or timed-out transfer still prints what it managed, which is the
# number wanted here; an empty print (no route, no DNS) falls back to 0 so
# the widget can show a dash instead of a blank line.
down=$(curl -s -o /dev/null --max-time "$MAX_TIME" -A "$UA" \
    -w '%{speed_download}' \
    "https://speed.cloudflare.com/__down?bytes=$DOWN_BYTES" || true)
up=$(head -c "$UP_BYTES" /dev/zero \
    | curl -s -o /dev/null --max-time "$MAX_TIME" -A "$UA" \
        --data-binary @- -w '%{speed_upload}' \
        "https://speed.cloudflare.com/__up" || true)

awk -v d="${down:-0}" -v u="${up:-0}" 'BEGIN {
    printf "{\"down\":%.1f,\"up\":%.1f}\n", d * 8 / 1000000, u * 8 / 1000000
}'
