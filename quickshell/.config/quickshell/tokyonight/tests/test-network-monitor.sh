#!/bin/bash
# Black-box tests for network-monitor.sh.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/network-monitor.sh"
TMP=$(mktemp -d /tmp/opencode-network-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/sys/lo/statistics" "$TMP/state"
mkdir -p "$TMP/sys/enp14s0/statistics"
mkdir -p "$TMP/sys/wlan0/statistics" "$TMP/sys/wlan0/wireless"
mkdir -p "$TMP/sys/tailscale0/statistics"

# A non-loopback adapter is deliberately included; loopback must not be.
for iface in enp14s0 wlan0 tailscale0; do
    printf '0\n' > "$TMP/sys/$iface/statistics/rx_bytes"
    printf '0\n' > "$TMP/sys/$iface/statistics/tx_bytes"
done
printf '0\n' > "$TMP/sys/lo/statistics/rx_bytes"
printf '0\n' > "$TMP/sys/lo/statistics/tx_bytes"
printf 'up\n' > "$TMP/sys/enp14s0/operstate"
printf 'up\n' > "$TMP/sys/wlan0/operstate"
printf 'unknown\n' > "$TMP/sys/tailscale0/operstate"
printf 'aa:bb:cc:dd:ee:01\n' > "$TMP/sys/enp14s0/address"
printf 'aa:bb:cc:dd:ee:02\n' > "$TMP/sys/wlan0/address"
printf '\n' > "$TMP/sys/tailscale0/address"

cat > "$TMP/bin/ip" <<'EOF'
#!/bin/bash
iface=
for ((i=1; i<=$#; i++)); do
    if [[ ${!i} == dev ]]; then
        ((i++))
        iface=${!i}
        break
    fi
done
if [[ "$*" == *"-4 route show default dev"* ]]; then
    case "$iface" in
        enp14s0|wlan0) printf 'default via 192.168.178.1 dev %s proto dhcp\n' "$iface" ;;
        *) exit 0 ;;
    esac
elif [[ "$*" == *"-4 -o addr show dev"* ]]; then
    case "$iface" in
        enp14s0) printf '2: %s    inet 192.168.178.63/24 brd 192.168.178.255 scope global\n' "$iface" ;;
        wlan0) printf '2: %s    inet 192.168.178.75/24 brd 192.168.178.255 scope global\n' "$iface" ;;
        tailscale0) printf '2: %s    inet 100.78.119.104/32 scope global\n' "$iface" ;;
    esac
fi
EOF
chmod +x "$TMP/bin/ip"

cat > "$TMP/bin/nmcli" <<'EOF'
#!/bin/bash
if [[ "$*" == *"IP4.DNS"* ]]; then
    case "$*" in
        *enp14s0*) printf '192.168.178.1,1.1.1.1\n' ;;
        *wlan0*) printf '192.168.178.1\n' ;;
        *) printf '\n' ;;
    esac
elif [[ "$*" == *"IN-USE,DEVICE"* ]]; then
    printf '*:wlan0\n'
fi
EOF
chmod +x "$TMP/bin/nmcli"

cat > "$TMP/bin/ping" <<'EOF'
#!/bin/bash
iface=
target=
while (($#)); do
    if [[ $1 == -I ]]; then
        iface=$2
        shift 2
    else
        target=$1
        shift
    fi
done
printf '%s %s\n' "$iface" "$target" >> "${NETWORK_PING_LOG:-/dev/null}"
case "$iface:$target" in
    enp14s0:192.168.178.1|wlan0:192.168.178.1) printf '64 bytes time=0.750 ms\n' ;;
    enp14s0:1.1.1.1|wlan0:1.1.1.1) printf '64 bytes time=18.500 ms\n' ;;
    tailscale0:1.1.1.1) printf '64 bytes time=24.000 ms\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/ping"

if env -u XDG_RUNTIME_DIR -u NETWORK_STATE_DIR "$SCRIPT" >/dev/null 2>&1; then
    printf 'monitor accepted an unsafe state-directory fallback\n' >&2
    exit 1
fi

run_monitor() {
    local now_ns=${1:-}
    local args=(
        "PATH=$TMP/bin:$PATH"
        "NETWORK_SYSFS=$TMP/sys"
        "NETWORK_STATE_DIR=$TMP/state"
        "NETWORK_PING_LOG=$TMP/ping.log"
        "NETWORK_EXTERNAL_TARGET=1.1.1.1"
    )
    if [[ -n "$now_ns" ]]; then
        args+=("NETWORK_NOW_NS=$now_ns")
    fi
    env "${args[@]}" "$SCRIPT"
}

: > "$TMP/ping.log"

# First sample establishes the baseline; the result must still be valid JSON.
first=$(run_monitor 1000000000)
jq -e '.adapters | length == 3' <<<"$first" >/dev/null
jq -e '[.adapters[].name] | sort == ["enp14s0", "tailscale0", "wlan0"]' <<<"$first" >/dev/null
jq -e '.adapters[] | select(.name == "wlan0") | .ip == "192.168.178.75" and .activeWifi == true' <<<"$first" >/dev/null
jq -e '.adapters[] | select(.name == "enp14s0") | ((has("routerPing") | not) and (has("gateway") | not) and .dns == "192.168.178.1,1.1.1.1" and .mac == "aa:bb:cc:dd:ee:01" and .externalPing == "18.500 ms")' <<<"$first" >/dev/null
jq -e '.adapters[] | select(.name == "tailscale0") | ((has("routerPing") | not) and (has("gateway") | not) and (has("dns") | not) and (has("mac") | not))' <<<"$first" >/dev/null

# Change counters and take a second sample; rates must be numeric and non-zero.
printf '1048576\n' > "$TMP/sys/wlan0/statistics/rx_bytes"
printf '524288\n' > "$TMP/sys/wlan0/statistics/tx_bytes"
second=$(run_monitor 2000000000)
jq -e '.adapters[] | select(.name == "wlan0") | .rxRate == "1.0 MiB/s" and .txRate == "512.0 KiB/s"' <<<"$second" >/dev/null
jq -e '.adapters[] | select(.name == "wlan0") | .externalPing == "18.500 ms"' <<<"$second" >/dev/null
if grep -q '192\.168\.178\.1' "$TMP/ping.log"; then
    printf 'router probes were not removed\n' >&2
    exit 1
fi

if ! grep -q 'hasValue(adapter.dns)' "$ROOT/Ethernet.qml" || ! grep -q 'hasValue(adapter.mac)' "$ROOT/Ethernet.qml"; then
    printf 'optional DNS/MAC filtering is missing from Ethernet.qml\n' >&2
    exit 1
fi

for qml in "$ROOT/Wifi.qml" "$ROOT/Ethernet.qml"; do
    if grep -q 'Router ping:' "$qml"; then
        printf 'router ping line still present in %s\n' "$qml" >&2
        exit 1
    fi
    grep -q 'Download:' "$qml"
    grep -q 'External ping (1.1.1.1):' "$qml"
done

printf 'network-monitor tests passed\n'
