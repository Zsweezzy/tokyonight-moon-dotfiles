#!/bin/bash
# network-monitor.sh — one-line JSON snapshot for the Quickshell network pills.
#
# It samples per-interface RX/TX counters and probes an external IPv4 target.
# State is kept in a per-user directory so successive polls can calculate rates
# without making either visible widget own the data.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=net-common.sh
. "$SCRIPT_DIR/net-common.sh"

SYSFS_NET=${NETWORK_SYSFS:-/sys/class/net}
if [[ -n ${NETWORK_STATE_DIR:-} ]]; then
    STATE_DIR=$NETWORK_STATE_DIR
elif [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
    STATE_DIR=${XDG_RUNTIME_DIR}/quickshell-network-${UID}
else
    printf 'network-monitor.sh: XDG_RUNTIME_DIR or NETWORK_STATE_DIR is required\n' >&2
    exit 1
fi
STATE_FILE="$STATE_DIR/adapters.state"
LOCK_FILE="$STATE_DIR/adapters.lock"
EXTERNAL_TARGET=${NETWORK_EXTERNAL_TARGET:-1.1.1.1}
PING_TIMEOUT=${NETWORK_PING_TIMEOUT:-0.8}

state_tmp=
probe_dir=
cleanup() {
    [[ -n "$state_tmp" ]] && rm -f -- "$state_tmp"
    [[ -n "$probe_dir" ]] && rm -rf -- "$probe_dir"
}
trap cleanup EXIT

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR" 2>/dev/null || true

# Protect the read/compare/write portion when more than one Quickshell instance
# starts the monitor at nearly the same time.
exec 9>"$LOCK_FILE"
flock -x 9

declare -A previous_rx=()
declare -A previous_tx=()
declare -A previous_time=()
if [[ -r "$STATE_FILE" ]]; then
    while read -r iface rx tx timestamp; do
        [[ -n "${iface:-}" ]] || continue
        [[ "$rx" =~ ^[0-9]+$ && "$tx" =~ ^[0-9]+$ && "$timestamp" =~ ^[0-9]+$ ]] || continue
        previous_rx["$iface"]=$rx
        previous_tx["$iface"]=$tx
        previous_time["$iface"]=$timestamp
    done < "$STATE_FILE"
fi

if [[ -n ${NETWORK_NOW_NS:-} && "$NETWORK_NOW_NS" =~ ^[0-9]+$ ]]; then
    # A deterministic clock is useful for black-box tests and harmless in
    # production when the override is unset.
    now_ns=$NETWORK_NOW_NS
elif ! now_ns=$(date +%s%N 2>/dev/null) || [[ ! "$now_ns" =~ ^[0-9]+$ ]]; then
    now_ns="$(date +%s)000000000"
fi

# Keep the output stable across invocations.  lo is intentionally omitted.
interfaces=()
while IFS= read -r iface; do
    interfaces+=("$iface")
done < <(
    for path in "$SYSFS_NET"/*; do
        [[ -d "$path" ]] || continue
        name=${path##*/}
        [[ "$name" == "lo" ]] && continue
        printf '%s\n' "$name"
    done | LC_ALL=C sort
)

# Find the active Wi-Fi device once.  The visible Wifi module still owns its
# SSID/label; this only lets the tooltip associate the right sample record.
active_wifi=$(nmcli -t -f IN-USE,DEVICE dev wifi 2>/dev/null | awk -F: '$1 == "*" { print $2; exit }' || true)
[[ -n "$active_wifi" ]] || active_wifi="-"

format_rate() {
    local bytes=$1 elapsed_ms=$2
    awk -v bytes="$bytes" -v elapsed_ms="$elapsed_ms" 'BEGIN {
        rate = bytes * 1000 / elapsed_ms
        if (rate < 1024) {
            printf "%.0f B/s", rate
        } else if (rate < 1048576) {
            printf "%.1f KiB/s", rate / 1024
        } else if (rate < 1073741824) {
            printf "%.1f MiB/s", rate / 1048576
        } else {
            printf "%.1f GiB/s", rate / 1073741824
        }
    }'
}

declare -A adapter_state=()
declare -A adapter_ip=()
declare -A adapter_netmask=()
declare -A adapter_dns=()
declare -A adapter_mac=()
declare -A adapter_rx_rate=()
declare -A adapter_tx_rate=()
declare -A adapter_sample_rx=()
declare -A adapter_sample_tx=()
declare -A adapter_wireless=()
declare -A adapter_active_wifi=()

for iface in "${interfaces[@]}"; do
    path="$SYSFS_NET/$iface"
    state=$(cat "$path/operstate" 2>/dev/null || true)
    [[ -n "$state" ]] || state=unknown
    rx=$(cat "$path/statistics/rx_bytes" 2>/dev/null || true)
    tx=$(cat "$path/statistics/tx_bytes" 2>/dev/null || true)
    [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
    [[ "$tx" =~ ^[0-9]+$ ]] || tx=0

    rx_rate=-
    tx_rate=-
    if [[ -n "${previous_time[$iface]+x}" ]]; then
        elapsed_ms=$(( (now_ns - previous_time[$iface]) / 1000000 ))
        # Do not report a stale average after Quickshell was suspended.
        if (( elapsed_ms > 0 && elapsed_ms <= 10000 )); then
            rx_delta=$(( rx - previous_rx[$iface] ))
            tx_delta=$(( tx - previous_tx[$iface] ))
            (( rx_delta < 0 )) && rx_delta=0
            (( tx_delta < 0 )) && tx_delta=0
            rx_rate=$(format_rate "$rx_delta" "$elapsed_ms")
            tx_rate=$(format_rate "$tx_delta" "$elapsed_ms")
        fi
    fi
    # Persist the exact counters used for this sample, rather than reading
    # them again after the ping probes have run.
    adapter_sample_rx["$iface"]=$rx
    adapter_sample_tx["$iface"]=$tx

    ipaddr=$(iface_ip "$iface" || true)
    cidr=$(iface_cidr "$iface" || true)
    netmask=$(prefix_to_mask "$cidr")
    dns=$(iface_dns "$iface" || true)
    mac=$(iface_mac "$iface" || true)
    [[ -n "$ipaddr" ]] || ipaddr=-
    [[ -n "$netmask" ]] || netmask=-
    [[ -n "$dns" ]] || dns=-
    [[ -n "$mac" ]] || mac=-

    adapter_state["$iface"]=$state
    adapter_ip["$iface"]=$ipaddr
    adapter_netmask["$iface"]=$netmask
    adapter_dns["$iface"]=$dns
    adapter_mac["$iface"]=$mac
    adapter_rx_rate["$iface"]=$rx_rate
    adapter_tx_rate["$iface"]=$tx_rate
    if [[ -d "$path/wireless" ]]; then
        adapter_wireless["$iface"]=true
    else
        adapter_wireless["$iface"]=false
    fi
    if [[ "$active_wifi" == "$iface" ]]; then
        adapter_active_wifi["$iface"]=true
    else
        adapter_active_wifi["$iface"]=false
    fi
done

# Persist this sample before the slower ping probes.  mv keeps readers from
# seeing a partially written state file.
state_tmp=$(mktemp "$STATE_DIR/adapters.state.XXXXXX")
: > "$state_tmp"
for iface in "${interfaces[@]}"; do
    printf '%s %s %s %s\n' \
        "$iface" \
        "${adapter_sample_rx[$iface]}" \
        "${adapter_sample_tx[$iface]}" \
        "$now_ns" >> "$state_tmp"
done
mv -f -- "$state_tmp" "$STATE_FILE"
state_tmp=
flock -u 9

# Probe each eligible adapter against the external target concurrently.  The
# sub-second timeout applies to each probe, so an unreachable target cannot hold
# up the one-second refresh or overlap the next sample.
probe_dir=$(mktemp -d "$STATE_DIR/probes.XXXXXX")
probe_ping() {
    local iface=$1 target=$2 output rtt
    output=$(ping -4 -n -c 1 -W "$PING_TIMEOUT" -I "$iface" "$target" 2>/dev/null || true)
    rtt=$(printf '%s\n' "$output" | awk '
        /time=/ {
            line = $0
            sub(/^.*time=/, "", line)
            sub(/[[:space:]].*$/, "", line)
            print line
            exit
        }
        /rtt/ {
            for (i = 1; i <= NF; i++) {
                if ($i == "=") {
                    print $(i + 1)
                    exit
                }
            }
        }
    ')
    if [[ -n "$rtt" ]]; then
        printf '%s ms\n' "$rtt"
    else
        printf '%s\n' -
    fi
}

probe_index=0
for iface in "${interfaces[@]}"; do
    prefix="$probe_dir/$probe_index"
    state=${adapter_state[$iface]}
    ipaddr=${adapter_ip[$iface]}

    if [[ "$ipaddr" != "-" && "$state" != down && "$state" != lowerlayerdown ]]; then
        probe_ping "$iface" "$EXTERNAL_TARGET" > "$prefix.external" &
    else
        printf '%s\n' - > "$prefix.external"
    fi
    probe_index=$((probe_index + 1))
done
wait || true

json_items=()
probe_index=0
for iface in "${interfaces[@]}"; do
    prefix="$probe_dir/$probe_index"
    external_ping=$(cat "$prefix.external" 2>/dev/null || true)
    [[ -n "$external_ping" ]] || external_ping=-

    # DNS and MAC are optional: virtual adapters often do not expose either
    # value, so omit those keys instead of emitting placeholder lines.
    printf -v item \
        '{"name":"%s","state":"%s","ip":"%s","netmask":"%s"' \
        "$(jesc "$iface")" \
        "$(jesc "${adapter_state[$iface]}")" \
        "$(jesc "${adapter_ip[$iface]}")" \
        "$(jesc "${adapter_netmask[$iface]}")"
    if [[ "${adapter_dns[$iface]}" != "-" ]]; then
        printf -v item '%s,"dns":"%s"' "$item" "$(jesc "${adapter_dns[$iface]}")"
    fi
    if [[ "${adapter_mac[$iface]}" != "-" ]]; then
        printf -v item '%s,"mac":"%s"' "$item" "$(jesc "${adapter_mac[$iface]}")"
    fi
    printf -v item \
        '%s,"rxRate":"%s","txRate":"%s","externalPing":"%s","wireless":%s,"activeWifi":%s}' \
        "$item" \
        "$(jesc "${adapter_rx_rate[$iface]}")" \
        "$(jesc "${adapter_tx_rate[$iface]}")" \
        "$(jesc "$external_ping")" \
        "${adapter_wireless[$iface]}" \
        "${adapter_active_wifi[$iface]}"
    json_items+=("$item")
    probe_index=$((probe_index + 1))
done

if (( ${#json_items[@]} > 0 )); then
    json_list=$(IFS=,; printf '%s' "${json_items[*]}")
else
    json_list=
fi
printf '{"adapters":[%s]}\n' "$json_list"
