#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 5: Disabling busy polling..."

sysctl -w net.core.busy_poll=0
sysctl -w net.core.busy_read=0

echo "Tier 5: Busy polling disabled."
