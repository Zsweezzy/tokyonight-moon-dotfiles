#!/bin/bash
# disk.sh — free space on the root filesystem + the disk's cumulative I/O
# counters, for the pc-stats flyout (Sys.qml / SysFlyout.qml).
#
# NOTE: output must fit on ONE line — Poll.qml's SplitParser emits one event
# per stdout line, so a multiline script would overwrite the last field with
# the last line. Fields are pipe-delimited:
#   1: free GB          2: total GB         3: used %
#   4: sectors read     5: sectors written  (cumulative, straight from diskstats)
#
# The rates are differenced in QML, not here: every bar window polls its own
# copy of this script, so a /tmp snapshot of the counters would be overwritten
# twice a second and each window would measure its delta against the other
# window's sample — every speed would read double. Keeping the raw counters
# here and the subtraction per window costs nothing and cannot race.
set -euo pipefail

src=$(df --output=source / | tail -1)
dev=${src##*/}
# Counters live on the whole disk, not the partition: /sys/block/<name> only
# exists for the latter, so a bare name is a disk and needs no trimming. For a
# partition, drop the suffix (nvme0n1p7 -> nvme0n1, sda3 -> sda).
if [ ! -e "/sys/block/$dev" ]; then
    dev=$(printf '%s' "$dev" | sed -E 's/p?[0-9]+$//')
fi

read -r free_b total_b <<< "$(df -B1 --output=avail,size / | tail -1)"
free_gb=$(awk -v b="$free_b" 'BEGIN { printf "%.1f", b / 1073741824 }')
total_gb=$(awk -v b="$total_b" 'BEGIN { printf "%.1f", b / 1073741824 }')
used_pct=$(awk -v f="$free_b" -v t="$total_b" 'BEGIN { printf "%.0f", (t - f) * 100 / t }')

# /proc/diskstats: field 6 is sectors read, field 10 sectors written. Empty on
# a container or a kernel without it, so the fallback is 0 rather than an
# unbound variable under `set -u`.
stats=$(awk -v d="$dev" '$3 == d { print $6, $10 }' /proc/diskstats)
read -r sec_r sec_w <<< "${stats:-0 0}"

printf '%s|%s|%s|%s|%s' "$free_gb" "$total_gb" "$used_pct" "$sec_r" "$sec_w"