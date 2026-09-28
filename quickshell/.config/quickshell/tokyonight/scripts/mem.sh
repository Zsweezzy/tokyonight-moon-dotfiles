#!/bin/bash
# mem.sh — used/total RAM in GB + top-10 processes by memory for the quickshell
# bar (waybar memory equivalent). Used = MemTotal - MemAvailable.
#
# Output must fit on ONE line — Poll.qml's SplitParser emits one event per
# stdout line, so a multiline script would overwrite the pill text with the
# last line. Fields are pipe-delimited:
#   1: pill text            "\uefc5 12.4/31.7 GB"
#   2: tooltip header       "12.4/31.7 GB (38%)"
#   3..: top-10 rows        "name SIZE P%" (RSS merged by name, desc, max 10)
set -euo pipefail

total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)

used_gb=$(awk -v t="$total" -v a="$avail" 'BEGIN { printf "%.1f", (t - a) / 1024 / 1024 }')
total_gb=$(awk -v t="$total" 'BEGIN { printf "%.1f", t / 1024 / 1024 }')
pct=$(awk -v t="$total" -v a="$avail" 'BEGIN { printf "%.0f", (t - a) * 100 / t }')

# ---------------- top processes ----------------
# Sum RSS (KiB) per process name (merges e.g. all firefox children), keep the
# 10 heaviest, then format each row as "name SIZE P%" where the size is
# human-readable and P% is the share of total physical RAM. Name column is
# padded to the longest name in the list so the size/% columns line up.
rows=$(
  ps -eo comm=,rss= |
    awk '{ mem[$1] += $2 } END { for (n in mem) if (mem[n] > 0) print mem[n], n }' |
    sort -rn |
    awk -v total="$total" '
        NR <= 10 {
            n++
            rss[n] = $1; name[n] = $2
            if (length($2) > max) max = length($2)
        }
        END {
            for (i = 1; i <= n; i++) {
                pct = rss[i] * 100 / total
                if (rss[i] >= 1048576) size = sprintf("%.1fG", rss[i] / 1048576)
                else if (rss[i] >= 1024) size = sprintf("%.0fM", rss[i] / 1024)
                else size = sprintf("%dK", rss[i])
                printf "%-*s %-4s %4.1f%%\n", max, name[i], size, pct
            }
        }
    ' |
    paste -sd'|'
)

printf '\uefc5 %s/%s GB|%s/%s GB (%s%%)|%s' "$used_gb" "$total_gb" "$used_gb" "$total_gb" "$pct" "$rows"