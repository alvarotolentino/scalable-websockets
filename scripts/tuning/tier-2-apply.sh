#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

echo "Tier 2: Applying TCP/network stack tuning..."

cat > /etc/sysctl.d/99-websocket-tcp.conf <<'EOF'
net.core.rmem_default=4096
net.core.wmem_default=4096
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 4096 16777216
net.ipv4.tcp_wmem=4096 4096 16777216
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.core.netdev_max_backlog=65535
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=6
net.ipv4.tcp_mem=786432 1048576 1572864
net.core.optmem_max=25165824
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_no_metrics_save=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_orphans=262144
net.ipv4.tcp_max_tw_buckets=2000000
EOF
echo "  Written /etc/sysctl.d/99-websocket-tcp.conf"

sysctl --system
echo "Tier 2: TCP/network stack tuning applied."
