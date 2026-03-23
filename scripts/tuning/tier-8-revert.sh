#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 8: Reverting queueing discipline to fq_codel..."

sysctl -w net.core.default_qdisc=fq_codel

IFACE=$(ip route | awk '/default/ {print $5; exit}')
tc qdisc replace dev "$IFACE" root fq_codel 2>/dev/null || true
echo "  Restored fq_codel qdisc on $IFACE."

echo "Tier 8: Queueing discipline reverted."
