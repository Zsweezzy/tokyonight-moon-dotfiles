#!/bin/sh
# AMD GPU usage + VRAM used (GiB) for waybar — reads amdgpu sysfs.
# Picks the card matching the first VGA controller from lspci
# (skips the Ryzen iGPU / any non-display devices).

bus=$(lspci 2>/dev/null | awk '/VGA compatible controller/{print $1; exit}')
card=""
for c in /sys/class/drm/card*; do
    case "$(readlink -f "$c/device" 2>/dev/null)" in
        *"$bus"*) card=$c ;;
    esac
    [ -n "$card" ] && break
done

if [ -z "$card" ] || [ ! -f "$card/device/gpu_busy_percent" ]; then
    echo " n/a"
    exit 0
fi

gpu=$(cat "$card/device/gpu_busy_percent" 2>/dev/null || echo 0)
used=$(cat "$card/device/mem_info_vram_used" 2>/dev/null || echo 0)
total=$(cat "$card/device/mem_info_vram_total" 2>/dev/null || echo 0)
used_gb=$(( (used + 1073741823) / 1073741824 ))
total_gb=$(( (total + 1073741823) / 1073741824 ))

printf ' %d%% %d/%dGiB' "$gpu" "$used_gb" "$total_gb"