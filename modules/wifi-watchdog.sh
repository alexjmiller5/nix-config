#!/bin/sh
# Power-cycle Wi-Fi when the router stops answering over it. A Wi-Fi link
# can stay associated while dropping most packets; a fresh association
# clears it. Does nothing while another interface (ethernet) carries the
# default route. Run periodically by modules/wifi-watchdog.nix.
set -u
iface=$(networksetup -listallhardwareports | awk '/^Hardware Port: Wi-Fi$/ { getline; print $2 }')
[ -n "$iface" ] || exit 0

route=$(route -n get default 2>/dev/null)
gw=$(printf '%s\n' "$route" | awk '/gateway:/ { print $2 }')
via=$(printf '%s\n' "$route" | awk '/interface:/ { print $2 }')
[ -z "$via" ] || [ "$via" = "$iface" ] || exit 0

if [ -n "$gw" ]; then
  got=$(ping -q -n -c 20 -i 0.5 -t 15 "$gw" 2>/dev/null | awk '/packets received/ { print $4 }')
  [ "${got:-0}" -ge 15 ] && exit 0
  why="router $gw answered ${got:-0}/20 pings"
else
  why="no default route"
fi

echo "$(date '+%F %T') $why, power-cycling $iface"
networksetup -setairportpower "$iface" off
sleep 5
networksetup -setairportpower "$iface" on
until networksetup -getairportpower "$iface" | grep -q ': On'; do
  sleep 3
  networksetup -setairportpower "$iface" on
done
