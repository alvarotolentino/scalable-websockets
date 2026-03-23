#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 4: Reverting interrupt & CPU affinity tuning..."

systemctl enable irqbalance 2>/dev/null || true
systemctl start irqbalance 2>/dev/null || true
echo "  Re-enabled and started irqbalance."

IFACE=$(ip route | awk '/default/ {print $5; exit}')
ethtool -C "$IFACE" adaptive-rx off 2>/dev/null || true
echo "  Reset interrupt coalescing to defaults."

echo "Tier 4: Interrupt & CPU affinity tuning reverted."
