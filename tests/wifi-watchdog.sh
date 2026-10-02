#!/usr/bin/env bash
# Fixture test for modules/wifi-watchdog.sh: stubbed route, ping,
# networksetup and sleep on PATH; asserts when Wi-Fi gets power-cycled.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/networksetup" <<'EOF'
#!/bin/sh
case $1 in
  -listallhardwareports) printf 'Hardware Port: Ethernet\nDevice: en0\n\nHardware Port: Wi-Fi\nDevice: en1\n' ;;
  -setairportpower) echo "$2 $3" >>"$CALLS" ;;
  -getairportpower)
    # Off for the first $OFF_READS reads, then On.
    n=$(($(cat "$READS") + 1)); echo "$n" >"$READS"
    if [ "$n" -le "$OFF_READS" ]; then echo "Wi-Fi Power ($2): Off"; else echo "Wi-Fi Power ($2): On"; fi ;;
esac
EOF
cat >"$tmp/route" <<'EOF'
#!/bin/sh
[ -n "$IFACE" ] || { echo "route: writing to routing socket: not in table" >&2; exit 1; }
printf '   route to: default\ndestination: default\n    gateway: 192.168.1.1\n  interface: %s\n' "$IFACE"
EOF
cat >"$tmp/ping" <<'EOF'
#!/bin/sh
echo ping >>"$CALLS"
echo "--- 192.168.1.1 ping statistics ---"
echo "20 packets transmitted, $RECEIVED packets received, 0.0% packet loss"
EOF
printf '#!/bin/sh\n' >"$tmp/sleep"
chmod +x "$tmp"/*

# run <default-route iface ("" = none)> <pings received of 20> [off reads before On]
# Echoes the calls the script made, one per line.
run() {
  : >"$tmp/calls"
  echo 0 >"$tmp/reads"
  PATH="$tmp:$PATH" IFACE="$1" RECEIVED="$2" OFF_READS="${3:-0}" \
    CALLS="$tmp/calls" READS="$tmp/reads" sh modules/wifi-watchdog.sh >/dev/null
  cat "$tmp/calls"
}
cycled=$'ping\nen1 off\nen1 on'

[ "$(run en1 20)" = ping ] || fail "healthy router: touched Wi-Fi"
[ "$(run en1 15)" = ping ] || fail "15/20 is above the bar: touched Wi-Fi"
[ "$(run en1 4)" = "$cycled" ] || fail "lossy router: did not power-cycle Wi-Fi"
[ -z "$(run en0 0)" ] || fail "default route on ethernet: pinged or touched Wi-Fi"
[ "$(run "" 0)" = $'en1 off\nen1 on' ] || fail "no default route: did not power-cycle Wi-Fi"
[ "$(run en1 0 2)" = "$cycled"$'\nen1 on\nen1 on' ] || fail "power-on not retried until Wi-Fi reports On"

echo "wifi-watchdog: all checks passed"
