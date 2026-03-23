#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 0: Baseline — no tuning applied."
echo "Stock Ubuntu 24.04 LTS kernel defaults."
echo "This is the control configuration for comparison."
