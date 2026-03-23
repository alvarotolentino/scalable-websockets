#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 9: Reverting miscellaneous optimizations..."

IFACE=$(ip route | awk '/default/ {print $5; exit}')

ethtool -K "$IFACE" gro on 2>/dev/null || true
echo "  Re-enabled GRO on $IFACE."

sysctl -w net.ipv4.tcp_congestion_control=cubic
echo "  Set TCP congestion control back to cubic."

echo always > /sys/kernel/mm/transparent_hugepage/enabled
echo "  Re-enabled transparent huge pages."

echo "Tier 9: Miscellaneous optimizations reverted."
