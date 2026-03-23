#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 9: Applying miscellaneous optimizations..."

IFACE=$(ip route | awk '/default/ {print $5; exit}')
echo "  Detected primary interface: $IFACE"

ethtool -K "$IFACE" gro off 2>/dev/null || true
echo "  Disabled GRO on $IFACE."

sysctl -w net.ipv4.tcp_congestion_control=reno
echo "  Set TCP congestion control to reno."

echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo "  Disabled transparent huge pages."

echo "Tier 9: Miscellaneous optimizations applied."
