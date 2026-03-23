#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 3: Reverting netfilter configuration..."

rm -f /etc/modprobe.d/disable-conntrack.conf
echo "  Removed /etc/modprobe.d/disable-conntrack.conf"

modprobe nf_conntrack 2>/dev/null || true
echo "  Reloaded nf_conntrack module."

echo "Tier 3: Netfilter reverted."
