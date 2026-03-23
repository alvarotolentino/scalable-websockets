#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 1: Applying file descriptor and socket limits..."

cat > /etc/security/limits.d/99-websocket.conf <<'EOF'
* soft nofile 1100000
* hard nofile 1100000
EOF
echo "  Written /etc/security/limits.d/99-websocket.conf"

sysctl -w fs.file-max=2200000
sysctl -w fs.nr_open=2200000

echo "Tier 1: File descriptor limits applied."
