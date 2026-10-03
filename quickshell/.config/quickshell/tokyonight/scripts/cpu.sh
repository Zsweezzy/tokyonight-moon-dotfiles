#!/bin/bash
# cpu.sh — overall CPU usage % + per-core breakdown for the quickshell bar.
# Diff of /proc/stat between consecutive polls (idle = idle + iowait).
#
# NOTE: output must fit on ONE line — Poll.qml's SplitParser emits one event
# per stdout line, so a multiline script would overwrite the pill text with
# the last line. Fields are pipe-delimited:
#   1: pill text "\uf2db N%"
#   2: tooltip headline "CPU: N%"
#   3: current clock "4.50 GHz"  (Sys.qml's tachometer reads this one)
#   4..: per-core grid rows, 3 columns each ("P01 12%   E01 03%   E02 00%")
#   last: legend explaining the P/E labels
set -euo pipefail

prev="/tmp/opencode/quickshell-cpu-prev"
snap=$(mktemp)
trap 'rm -f "$snap"' EXIT

# Per-CPU core-type labels. This machine (Ryzen 9 7950X3D) has no Intel P/E
# cores, but its two CCDs differ: 96MB 3D V-Cache CCD  -> labeled "P",
# 32MB standard L3 CCD                             -> labeled "E".
# Generic rule: L3 >= 64MB counts as the big-cache ("P") die.
declare -a ctype
for i in $(seq 0 $(( $(nproc) - 1 ))); do
    sz=$(cat "/sys/devices/system/cpu/cpu$i/cache/index3/size" 2>/dev/null || echo 0)
    case "$sz" in
        *K) mb=$(( ${sz%K} / 1024 )) ;;
        *M) mb=${sz%M} ;;
        *)  mb=0 ;;
    esac
    [ "$mb" -ge 64 ] && ctype[$i]=P || ctype[$i]=E
done

# Snapshot /proc/stat: line 1 is the aggregate (TOTAL), then one cN line per core.
awk '
  /^cpu / { print "TOTAL", $2+$3+$4+$5+$6+$7+$8+$9, $5+$6 }
  /^cpu[0-9]+ / { print "C" substr($1, 4), $2+$3+$4+$5+$6+$7+$8+$9, $5+$6 }
' /proc/stat > "$snap"

# ---------------- aggregate usage ----------------
read -r tag now_total now_idle < "$snap"
has_prev=0
if [ -f "$prev" ] && read -r ptag pt pi < "$prev" && [ "$ptag" = "TOTAL" ]; then
    has_prev=1
    dt=$((now_total - pt))
    di=$((now_idle - pi))
fi
if [ "$has_prev" = 1 ] && [ "$dt" -gt 0 ]; then
    pct=$(( (dt - di) * 100 / dt ))
    [ "$pct" -lt 0 ] && pct=0
    [ "$pct" -gt 100 ] && pct=100
else
    pct=0
fi

# ---------------- per-core usage ----------------
declare -A prev_t prev_i
if [ "$has_prev" = 1 ]; then
    while read -r cn ct ci; do
        case "$cn" in
            C*) prev_t[$cn]=$ct; prev_i[$cn]=$ci ;;
        esac
    done < <(tail -n +2 "$prev")
fi

pcts=()
while read -r cn ct ci; do
    if [ -n "${prev_t[$cn]+x}" ]; then
        cdt=$((ct - prev_t[$cn]))
        cdi=$((ci - prev_i[$cn]))
        if [ "$cdt" -gt 0 ]; then
            cp=$(( (cdt - cdi) * 100 / cdt ))
            [ "$cp" -lt 0 ] && cp=0
            [ "$cp" -gt 100 ] && cp=100
        else
            cp=0
        fi
    else
        cp=0
    fi
    pcts+=("$cp")
done < <(tail -n +2 "$snap")

# persist this snapshot for the next poll
cp "$snap" "$prev"

# ---------------- per-core type labels (parallel to pcts[]) ----------------
# P-cores (V-Cache CCD) and E-cores (std CCD) each get their own numbering,
# like Intel presents hybrid parts: cpu0-7 -> P01..P08, cpu16-23 -> P09..P16,
# cpu8-15 -> E01..E08, cpu24-31 -> E09..E16.
declare -a labels
declare -A type_idx=( [P]=0 [E]=0 )
for ((i = 0; i < ${#pcts[@]}; i++)); do
    t=${ctype[$i]}
    n=$(( ${type_idx[$t]} + 1 ))
    type_idx[$t]=$n
    printf -v lbl '%s%02d' "$t" "$n"
    labels[$i]=$lbl
done

# ---------------- current clock ----------------
# Mean of the per-core MHz lines: a boost clock is per core, so the mean is
# what the package is running at right now — which is the number the CPU dial
# puts in its hole (the ring is the utilization above).
ghz=$(awk '/^cpu MHz/ { s += $4; n++ } END { if (n > 0) printf "%.2f", s / n / 1000; else print "0.00" }' /proc/cpuinfo)

# ---------------- output (single line, pipe-delimited, no trailing newline) ----------------
# Tooltip grid: 8 rows x 3 columns, "1 P-core + 2 E-cores" per row:
#   row i: P{01+i}  E{1+2i}  E{2+2i}  for i = 0..7
# Cpu layout (7950X3D): cpu0-7 = P01-P08 (V-Cache CCD), cpu8-15 = E01-E08,
# cpu24-31 = E09-E16 (std CCD); cpu16-23 are the P cores' SMT twins (hidden).
printf '\uf2db %d%%|CPU: %d%%|%s GHz' "$pct" "$pct" "$ghz"
for ((i = 0; i < 8; i++)); do
    printf -v cell1 '%s %2d%%' "${labels[$i]}"        "${pcts[$i]}"
    printf -v cell2 '%s %2d%%' "${labels[$((i + 8))]}"  "${pcts[$((i + 8))]}"
    printf -v cell3 '%s %2d%%' "${labels[$((i + 24))]}" "${pcts[$((i + 24))]}"
    printf '|%s   %s   %s' "$cell1" "$cell2" "$cell3"
done
printf '|P = 3D V-Cache CCD (96MB L3)|E = standard CCD (32MB L3)'