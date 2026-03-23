#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# run-benchmark.sh — Main benchmark orchestration script
#
# Runs the scalable-websockets benchmark across crates, tuning tiers, and
# connection levels. Requires Terraform outputs and SSH access to servers.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
CRATES="all"
TIERS="all"
CONNECTIONS="progression"
DURATION=300
OUTPUT_DIR=""
SSH_KEY="$HOME/.ssh/id_ed25519"

usage() {
  cat <<'USAGE'
Usage: run-benchmark.sh [OPTIONS]

Options:
  --crate <tungstenite|tokio-ws|wtx|all>   Crate to benchmark (default: all)
  --tier <0-9|all>                          Tuning tier (default: all)
  --connections <N|progression>             Connection count or progression (default: progression)
  --duration <seconds>                      Test duration per run (default: 300)
  --output-dir <path>                       Results directory (default: ./results/YYYYMMDD-HHMMSS)
  --ssh-key <path>                          SSH private key (default: ~/.ssh/id_ed25519)
  -h, --help                                Show this help
USAGE
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --crate)       CRATES="$2"; shift 2 ;;
    --tier)        TIERS="$2"; shift 2 ;;
    --connections) CONNECTIONS="$2"; shift 2 ;;
    --duration)    DURATION="$2"; shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --ssh-key)     SSH_KEY="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Expand "all" values
if [[ "$CRATES" == "all" ]]; then
  CRATES="tungstenite tokio-ws wtx"
fi

if [[ "$TIERS" == "all" ]]; then
  TIERS="0 1 2 3 4 5 6 7 8 9"
fi

if [[ "$CONNECTIONS" == "progression" ]]; then
  CONN_LEVELS="10000 50000 100000 250000 500000 750000 1000000"
else
  CONN_LEVELS="$CONNECTIONS"
fi

# Output directory
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$PROJECT_DIR/results/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$OUTPUT_DIR"

# Read Terraform outputs
echo "=== Reading Terraform outputs ==="
SERVER_IP=$(cd "$PROJECT_DIR/terraform" && terraform output -raw server_public_ip)
CLIENT_IPS=$(cd "$PROJECT_DIR/terraform" && terraform output -json client_public_ips | jq -r '.[]')
echo "  Server: $SERVER_IP"
echo "  Clients: $(echo "$CLIENT_IPS" | tr '\n' ' ')"

# SSH helper
remote() {
  local host="$1"; shift
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
      -i "$SSH_KEY" "root@${host}" "$@"
}

# SCP helper
fetch() {
  local host="$1" remote_path="$2" local_path="$3"
  scp -o StrictHostKeyChecking=no -i "$SSH_KEY" \
      "root@${host}:${remote_path}" "$local_path"
}

# Write metadata
echo "=== Writing metadata ==="
GIT_SHA=$(cd "$PROJECT_DIR" && git rev-parse HEAD)
RUST_VERSION=$(remote "$SERVER_IP" "rustc --version" 2>/dev/null || echo "unknown")
KERNEL_VERSION=$(remote "$SERVER_IP" "uname -r" 2>/dev/null || echo "unknown")

cat > "$OUTPUT_DIR/metadata.json" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_sha": "$GIT_SHA",
  "rust_version": "$RUST_VERSION",
  "kernel_version": "$KERNEL_VERSION",
  "duration_seconds": $DURATION,
  "crates": "$(echo $CRATES)",
  "tiers": "$(echo $TIERS)",
  "connection_levels": "$(echo $CONN_LEVELS)"
}
EOF
echo "  Metadata written to $OUTPUT_DIR/metadata.json"

# Compile load-test and orchestrator on all clients
echo "=== Building binaries on client machines ==="
for CLIENT_IP in $CLIENT_IPS; do
  echo "  Building on $CLIENT_IP..."
  remote "$CLIENT_IP" "cd /root/scalable-websockets && \
    RUSTFLAGS='-C target-cpu=native' cargo build --release 2>&1" || true
done

# Main benchmark loop
CLIENT_ARR=($CLIENT_IPS)
NUM_CLIENTS=${#CLIENT_ARR[@]}

for CRATE in $CRATES; do
  echo ""
  echo "######################################################################"
  echo "# Crate: $CRATE"
  echo "######################################################################"

  # Compile server with this crate backend
  echo "=== Compiling server with $CRATE backend ==="
  remote "$SERVER_IP" "cd /root/scalable-websockets && \
    RUSTFLAGS='-C target-cpu=native' cargo build --release -p server"

  for TIER in $TIERS; do
    echo ""
    echo "--- Tier $TIER ---"

    # Apply tuning tier on server
    if [[ "$TIER" != "0" ]]; then
      echo "  Applying tier $TIER tuning..."
      remote "$SERVER_IP" "bash -s" < "$SCRIPT_DIR/tuning/tier-${TIER}-apply.sh"
      sleep 10
    fi

    for CONN_LEVEL in $CONN_LEVELS; do
      echo ""
      echo "  >>> $CRATE / tier-$TIER / $CONN_LEVEL connections"

      RESULT_DIR="$OUTPUT_DIR/$CRATE/tier-$TIER/$CONN_LEVEL"
      mkdir -p "$RESULT_DIR"

      # Start server
      remote "$SERVER_IP" "pkill -f ws-echo-server || true"
      sleep 2
      remote "$SERVER_IP" "nohup /root/scalable-websockets/target/release/ws-echo-server \
        --crate $CRATE --bind-port 9001 > /tmp/server.log 2>&1 &"
      sleep 5

      # Get server PID
      SERVER_PID=$(remote "$SERVER_IP" "pgrep -f ws-echo-server" || echo "")
      if [[ -z "$SERVER_PID" ]]; then
        echo "  ERROR: Server failed to start. Skipping."
        continue
      fi
      echo "  Server PID: $SERVER_PID"

      # Start metrics collection on server
      remote "$SERVER_IP" "bash -s -- --pid $SERVER_PID --output /tmp/metrics.csv --duration $DURATION" \
        < "$SCRIPT_DIR/collect-metrics.sh" &
      METRICS_SSH_PID=$!

      # Run load test — use orchestrator for high connection counts
      if [[ "$CONN_LEVEL" -gt 200000 ]]; then
        echo "  Using orchestrator for $CONN_LEVEL connections..."
        CLIENTS_CSV=$(echo "${CLIENT_IPS}" | tr '\n' ',' | sed 's/,$//')
        remote "${CLIENT_ARR[0]}" "cd /root/scalable-websockets && \
          ./target/release/ws-load-orchestrator \
            --target ws://${SERVER_IP}:9001 \
            --total-connections $CONN_LEVEL \
            --clients $CLIENTS_CSV \
            --ramp-up 120 \
            --duration $DURATION \
            --output /tmp/combined-results.json"
        fetch "${CLIENT_ARR[0]}" "/tmp/combined-results.json" \
          "$RESULT_DIR/client-results.json" 2>/dev/null || true
      else
        # Direct SSH to each client for lower connection counts
        PER_CLIENT=$((CONN_LEVEL / NUM_CLIENTS))
        CLIENT_PIDS=()
        for CLIENT_IP in "${CLIENT_ARR[@]}"; do
          remote "$CLIENT_IP" "cd /root/scalable-websockets && \
            ./target/release/ws-load-test \
              --target ws://${SERVER_IP}:9001 \
              --connections $PER_CLIENT \
              --ramp-up 60 \
              --duration $DURATION \
              --output /tmp/results.json" &
          CLIENT_PIDS+=($!)
        done

        # Wait for all clients
        for pid in "${CLIENT_PIDS[@]}"; do
          wait "$pid" || true
        done

        # Collect per-client results
        for i in "${!CLIENT_ARR[@]}"; do
          fetch "${CLIENT_ARR[$i]}" "/tmp/results.json" \
            "$RESULT_DIR/client-${i}-results.json" 2>/dev/null || true
        done
      fi

      # Stop metrics collection
      kill "$METRICS_SSH_PID" 2>/dev/null || true
      wait "$METRICS_SSH_PID" 2>/dev/null || true

      # Collect server metrics
      fetch "$SERVER_IP" "/tmp/metrics.csv" \
        "$RESULT_DIR/server-metrics.csv" 2>/dev/null || true
      fetch "$SERVER_IP" "/tmp/metrics.csv" \
        "$RESULT_DIR/server-metrics.csv" 2>/dev/null || true
      fetch "$SERVER_IP" "/tmp/server.log" \
        "$RESULT_DIR/server.log" 2>/dev/null || true

      # Stop server
      remote "$SERVER_IP" "pkill -f ws-echo-server || true"
      sleep 2

      echo "  <<< Results saved to $RESULT_DIR"
    done

    # Revert tuning tier
    if [[ "$TIER" != "0" ]] && [[ -f "$SCRIPT_DIR/tuning/tier-${TIER}-revert.sh" ]]; then
      echo "  Reverting tier $TIER tuning..."
      remote "$SERVER_IP" "bash -s" < "$SCRIPT_DIR/tuning/tier-${TIER}-revert.sh"
    fi
  done
done

echo ""
echo "======================================================================"
echo "Benchmark complete. Results in $OUTPUT_DIR"
echo "======================================================================"
