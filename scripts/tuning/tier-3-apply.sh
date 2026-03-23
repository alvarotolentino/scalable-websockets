#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 3: Disabling iptables / netfilter..."

iptables -F && iptables -X && iptables -t nat -F
echo "  Flushed iptables rules."

modprobe -r nf_conntrack nf_defrag_ipv4 iptable_filter 2>/dev/null || true
echo "  Attempted to unload netfilter modules."

cat > /etc/modprobe.d/disable-conntrack.conf <<'EOF'
install nf_conntrack /bin/true
EOF
echo "  Written /etc/modprobe.d/disable-conntrack.conf"

echo "Tier 3: Netfilter disabled."
