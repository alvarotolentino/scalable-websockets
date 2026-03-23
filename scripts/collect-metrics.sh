#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# collect-metrics.sh — Server-side metrics collection
#
# Samples system stats every second and writes CSV output.
# Run on the benchmark server during a test run.
###############################################################################

PID=""
OUTPUT="/tmp/metrics.csv"
DURATION=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid)      PID="$2"; shift 2 ;;
    --output)   OUTPUT="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    *)          shift ;;
  esac
done

if [[ -z "$PID" ]]; then
  echo "Usage: collect-metrics.sh --pid <PID> [--output <file>] [--duration <seconds>]" >&2
  exit 1
fi

# Detect primary network interface
IFACE=$(ip route | awk '/default/ {print $5; exit}')

# CSV header
echo "timestamp,cpu_user,cpu_system,cpu_idle,cpu_softirq,mem_rss_kb,open_fds,rx_packets,tx_packets,rx_bytes,tx_bytes,context_switches_voluntary,context_switches_involuntary,tcp_established,tcp_time_wait" \
  > "$OUTPUT"

SAMPLES=0
ELAPSED=0

# Read initial CPU counters
read -r _ prev_user prev_nice prev_system prev_idle prev_iowait prev_irq prev_softirq _ < /proc/stat

# Graceful shutdown
cleanup() {
  echo "Metrics collection stopped. $SAMPLES samples written to $OUTPUT." >&2
  exit 0
}
trap cleanup SIGTERM SIGINT

while true; do
  if [[ "$DURATION" -gt 0 ]] && [[ "$ELAPSED" -ge "$DURATION" ]]; then
    break
  fi

  # Check if process is still alive
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Process $PID no longer running. Stopping." >&2
    break
  fi

  TIMESTAMP=$(date +%s)

  # CPU stats (deltas since last sample)
  read -r _ cur_user cur_nice cur_system cur_idle cur_iowait cur_irq cur_softirq _ < /proc/stat
  d_user=$((cur_user - prev_user))
  d_nice=$((cur_nice - prev_nice))
  d_system=$((cur_system - prev_system))
  d_idle=$((cur_idle - prev_idle))
  d_iowait=$((cur_iowait - prev_iowait))
  d_irq=$((cur_irq - prev_irq))
  d_softirq=$((cur_softirq - prev_softirq))
  d_total=$((d_user + d_nice + d_system + d_idle + d_iowait + d_irq + d_softirq))

  if [[ "$d_total" -gt 0 ]]; then
    cpu_user=$(( (d_user + d_nice) * 100 / d_total ))
    cpu_system=$(( d_system * 100 / d_total ))
    cpu_idle=$(( d_idle * 100 / d_total ))
    cpu_softirq=$(( d_softirq * 100 / d_total ))
  else
    cpu_user=0; cpu_system=0; cpu_idle=100; cpu_softirq=0
  fi

  prev_user=$cur_user; prev_nice=$cur_nice; prev_system=$cur_system
  prev_idle=$cur_idle; prev_iowait=$cur_iowait; prev_irq=$cur_irq
  prev_softirq=$cur_softirq

  # Memory RSS
  mem_rss_kb=$(awk '/VmRSS/ {print $2}' /proc/"$PID"/status 2>/dev/null || echo 0)

  # Open file descriptors
  open_fds=$(ls /proc/"$PID"/fd 2>/dev/null | wc -l || echo 0)

  # NIC stats from /proc/net/dev
  nic_line=$(awk -v iface="$IFACE:" '$1 == iface {print}' /proc/net/dev 2>/dev/null || echo "")
  if [[ -n "$nic_line" ]]; then
    rx_bytes=$(echo "$nic_line" | awk '{print $2}')
    rx_packets=$(echo "$nic_line" | awk '{print $3}')
    tx_bytes=$(echo "$nic_line" | awk '{print $10}')
    tx_packets=$(echo "$nic_line" | awk '{print $11}')
  else
    rx_bytes=0; rx_packets=0; tx_bytes=0; tx_packets=0
  fi

  # Context switches
  vol_cs=$(awk '/voluntary_ctxt_switches/ {print $2}' /proc/"$PID"/status 2>/dev/null || echo 0)
  nonvol_cs=$(awk '/nonvoluntary_ctxt_switches/ {print $2}' /proc/"$PID"/status 2>/dev/null || echo 0)

  # TCP connection states
  tcp_established=$(ss -t state established 2>/dev/null | tail -n +2 | wc -l || echo 0)
  tcp_time_wait=$(ss -t state time-wait 2>/dev/null | tail -n +2 | wc -l || echo 0)

  # Write CSV row
  echo "$TIMESTAMP,$cpu_user,$cpu_system,$cpu_idle,$cpu_softirq,$mem_rss_kb,$open_fds,$rx_packets,$tx_packets,$rx_bytes,$tx_bytes,$vol_cs,$nonvol_cs,$tcp_established,$tcp_time_wait" \
    >> "$OUTPUT"

  SAMPLES=$((SAMPLES + 1))
  ELAPSED=$((ELAPSED + 1))
  sleep 1
done

echo "Metrics collection stopped. $SAMPLES samples written to $OUTPUT." >&2
