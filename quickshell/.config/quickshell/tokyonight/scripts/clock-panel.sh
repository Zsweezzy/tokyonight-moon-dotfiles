#!/usr/bin/env bash
# clock-panel.sh — one shot, one line: what ClockFlyout's clock quadrants need.
#
#   <uptime-secs>|<City><TAB>HH:MM:SS<TAB><delta><TAB><abbrev>|(…)
#
# `delta` is the day difference against the local zone ("0", "+1", "-1"), which
# is what makes a foreign clock readable at a glance. `abbrev` is the zone's own
# short name (EDT/PDT/JST), so a DST switch is visible instead of silently
# shifting the numbers.
#
# WHY A SCRIPT: quickshell's JS engine has neither `Intl` nor a `TimeZone` QML
# type (verified on 0.3.1 / Qt 6.11), and `Date.toLocaleTimeString` silently
# ignores a `timeZone` option — it would print local time under every city
# label. `TZ=… date` is the only correct source here, and it applies DST.
#
# Run at most once a second, and only while the flyout is open (the QML Poll is
# bound to its visibility), so a closed flyout costs nothing.
#
# No trailing newline: Poll.qml pipes this through SplitParser, which would
# otherwise emit a second empty line.
set -euo pipefail

# "IANA zone:label shown in the flyout" — edit this list to change the cities.
ZONES=(
    "America/New_York:New York"
    "America/Los_Angeles:Los Angeles"
    "Asia/Tokyo:Tokyo"
)

TAB=$'\t'

# %j (day of year) is not enough on its own: 1 Jan the next year is lower than
# 31 Dec this year. Scaling the year by 366 makes the pair monotonic (a year has
# at most 366 distinct day-of-year values, so no two dates collide) and the
# difference is then a plain day count.
read -r local_year local_doy < <(date "+%Y %j")
local_day=$(( 10#$local_year * 366 + 10#$local_doy ))

up=0
if read -r raw _ < /proc/uptime 2>/dev/null; then
    raw=${raw%.*}
    if [[ $raw =~ ^[0-9]+$ ]]; then
        up=$raw
    fi
fi

printf '%s' "$up"

for entry in "${ZONES[@]}"; do
    zone=${entry%%:*}
    label=${entry#*:}

    # One `date` per zone for all three fields, rather than three forks.
    IFS=$TAB read -r clock year doy abbrev < <(
        TZ="$zone" date "+%H:%M:%S$TAB%Y$TAB%j$TAB%Z"
    )

    delta=$(( 10#$year * 366 + 10#$doy - local_day ))
    if (( delta > 0 )); then
        delta="+$delta"
    elif (( delta < 0 )); then
        delta="$delta"
    else
        delta="0"
    fi

    printf '|%s%s%s%s%s%s%s' "$label" "$TAB" "$clock" "$TAB" "$delta" "$TAB" "$abbrev"
done
