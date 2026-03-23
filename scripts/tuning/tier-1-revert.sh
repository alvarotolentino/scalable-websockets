#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 1: Reverting file descriptor and socket limits..."

rm -f /etc/security/limits.d/99-websocket.conf
echo "  Removed /etc/security/limits.d/99-websocket.conf"

sysctl -w fs.file-max=9223372036854775807
sysctl -w fs.nr_open=1048576

echo "Tier 1: File descriptor limits reverted to defaults."
