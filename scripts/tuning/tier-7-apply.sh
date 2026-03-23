#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 7: Disabling syscall auditing..."

auditctl -a never,task 2>/dev/null || true
auditctl -e 0 2>/dev/null || true

echo "Tier 7: Audit system disabled."
