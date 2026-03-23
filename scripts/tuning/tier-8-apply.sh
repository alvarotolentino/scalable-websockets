#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 8: Setting queueing discipline to noqueue/mq..."

sysctl -w net.core.default_qdisc=noqueue

IFACE=$(ip route | awk '/default/ {print $5; exit}')
echo "  Detected primary interface: $IFACE"

tc qdisc replace dev "$IFACE" root mq 2>/dev/null || \
  tc qdisc replace dev "$IFACE" root noqueue 2>/dev/null || true
echo "  Applied mq/noqueue qdisc to $IFACE."

echo "Tier 8: Queueing discipline applied."
