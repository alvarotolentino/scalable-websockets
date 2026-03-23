#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 2: Reverting TCP/network stack tuning..."

rm -f /etc/sysctl.d/99-websocket-tcp.conf
echo "  Removed /etc/sysctl.d/99-websocket-tcp.conf"

sysctl --system
echo "Tier 2: TCP/network stack tuning reverted to defaults."
