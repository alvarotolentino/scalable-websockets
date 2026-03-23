#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 5: Enabling busy polling..."

sysctl -w net.core.busy_poll=1
sysctl -w net.core.busy_read=1

echo "Tier 5: Busy polling enabled."
