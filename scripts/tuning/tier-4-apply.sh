#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 4: Applying interrupt & CPU affinity tuning..."

systemctl stop irqbalance 2>/dev/null || true
systemctl disable irqbalance 2>/dev/null || true
echo "  Stopped and disabled irqbalance."

IFACE=$(ip route | awk '/default/ {print $5; exit}')
echo "  Detected primary interface: $IFACE"

# Pin each NIC RX queue IRQ to a dedicated CPU core
IRQS=($(grep "$IFACE" /proc/interrupts | awk '{print $1}' | tr -d :))
for i in "${!IRQS[@]}"; do
  echo "$i" > /proc/irq/${IRQS[$i]}/smp_affinity_list 2>/dev/null || true
done
echo "  Pinned ${#IRQS[@]} IRQs to dedicated CPU cores."

# Configure XPS (Transmit Packet Steering)
TXQUEUES=($(ls -1dv /sys/class/net/$IFACE/queues/tx-* 2>/dev/null)) || true
for i in "${!TXQUEUES[@]}"; do
  printf '%x' $((1 << i)) > "${TXQUEUES[$i]}/xps_cpus" 2>/dev/null || true
done
echo "  Configured XPS for ${#TXQUEUES[@]} TX queues."

# Set interrupt coalescing
ethtool -C "$IFACE" adaptive-rx on tx-usecs 256 2>/dev/null || true
echo "  Set interrupt coalescing (adaptive-rx on, tx-usecs 256)."

echo "Tier 4: Interrupt & CPU affinity tuning applied."
