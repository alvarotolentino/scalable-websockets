#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# generate-report.sh — Post-benchmark report generator
#
# Reads raw results from a benchmark run and produces a Markdown comparison
# report and a machine-readable summary JSON.
# Requires: jq
###############################################################################

if [[ $# -lt 1 ]]; then
  echo "Usage: generate-report.sh <results-directory>"
  echo "  e.g. ./scripts/generate-report.sh results/20260323-120000/"
  exit 1
fi

DIR="$1"
REPORT="$DIR/report.md"
SUMMARY="$DIR/summary.json"

if [[ ! -d "$DIR" ]]; then
  echo "Error: $DIR is not a directory"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed"
  exit 1
fi

# Read metadata
META="$DIR/metadata.json"
if [[ -f "$META" ]]; then
  TIMESTAMP=$(jq -r '.timestamp // "unknown"' "$META")
  GIT_SHA=$(jq -r '.git_sha // "unknown"' "$META")
  RUST_VERSION=$(jq -r '.rust_version // "unknown"' "$META")
  KERNEL_VERSION=$(jq -r '.kernel_version // "unknown"' "$META")
else
  TIMESTAMP="unknown"
  GIT_SHA="unknown"
  RUST_VERSION="unknown"
  KERNEL_VERSION="unknown"
fi

# Start building report
cat > "$REPORT" <<EOF
# Scalable WebSockets Benchmark Report

| Property | Value |
|----------|-------|
| Date | $TIMESTAMP |
| Git SHA | \`$GIT_SHA\` |
| Rust | $RUST_VERSION |
| Kernel | $KERNEL_VERSION |

---

## Comparison Table

| Crate | Tier | Connections | Success % | RTT p50 µs | RTT p99 µs | Handshake p50 µs | msg/s |
|-------|------|-------------|-----------|------------|------------|------------------|-------|
EOF

# Also build summary JSON as an array
echo "[" > "$SUMMARY"
FIRST_ENTRY=true

# Iterate through results directory structure
for CRATE_DIR in "$DIR"/*/; do
  CRATE=$(basename "$CRATE_DIR")
  # Skip non-crate directories
  [[ "$CRATE" == "metadata.json" || "$CRATE" == "report.md" || "$CRATE" == "summary.json" ]] && continue
  [[ ! -d "$CRATE_DIR" ]] && continue

  for TIER_DIR in "$CRATE_DIR"/tier-*/; do
    [[ ! -d "$TIER_DIR" ]] && continue
    TIER=$(basename "$TIER_DIR" | sed 's/tier-//')

    for CONN_DIR in "$TIER_DIR"/*/; do
      [[ ! -d "$CONN_DIR" ]] && continue
      CONN_LEVEL=$(basename "$CONN_DIR")

      # Find the result file (either single combined or first client result)
      RESULT_FILE=""
      if [[ -f "$CONN_DIR/client-results.json" ]]; then
        RESULT_FILE="$CONN_DIR/client-results.json"
      elif [[ -f "$CONN_DIR/client-0-results.json" ]]; then
        RESULT_FILE="$CONN_DIR/client-0-results.json"
      fi

      if [[ -z "$RESULT_FILE" ]]; then
        continue
      fi

      # Extract metrics
      SUCCESS_RATE=$(jq -r '.metrics.success_rate // 0' "$RESULT_FILE")
      RTT_P50=$(jq -r '.metrics.rtt_p50_us // 0' "$RESULT_FILE")
      RTT_P99=$(jq -r '.metrics.rtt_p99_us // 0' "$RESULT_FILE")
      HS_P50=$(jq -r '.metrics.handshake_p50_us // 0' "$RESULT_FILE")
      MSGS=$(jq -r '.metrics.messages_per_sec // 0' "$RESULT_FILE")
      TOTAL_MSGS=$(jq -r '.metrics.total_messages // 0' "$RESULT_FILE")

      # Append to Markdown table
      printf "| %s | %s | %s | %.1f | %s | %s | %s | %.0f |\n" \
        "$CRATE" "$TIER" "$CONN_LEVEL" "$SUCCESS_RATE" "$RTT_P50" "$RTT_P99" "$HS_P50" "$MSGS" \
        >> "$REPORT"

      # Append to summary JSON
      if [[ "$FIRST_ENTRY" == "true" ]]; then
        FIRST_ENTRY=false
      else
        echo "," >> "$SUMMARY"
      fi
      cat >> "$SUMMARY" <<ENTRY
  {
    "crate": "$CRATE",
    "tier": $TIER,
    "connections": $CONN_LEVEL,
    "success_rate": $SUCCESS_RATE,
    "rtt_p50_us": $RTT_P50,
    "rtt_p99_us": $RTT_P99,
    "handshake_p50_us": $HS_P50,
    "total_messages": $TOTAL_MSGS,
    "messages_per_sec": $MSGS
  }
ENTRY
    done
  done
done

echo "" >> "$SUMMARY"
echo "]" >> "$SUMMARY"

# Tuning impact section
cat >> "$REPORT" <<'EOF'

---

## Tuning Impact

Percentage improvement in RTT p99 from one tier to the next for each crate.

EOF

# Compute tuning impact per crate
for CRATE_DIR in "$DIR"/*/; do
  CRATE=$(basename "$CRATE_DIR")
  [[ ! -d "$CRATE_DIR" ]] && continue
  [[ "$CRATE" == "metadata.json" || "$CRATE" == "report.md" || "$CRATE" == "summary.json" ]] && continue

  echo "### $CRATE" >> "$REPORT"
  echo "" >> "$REPORT"

  PREV_RTT=""
  PREV_TIER=""
  for TIER_DIR in "$CRATE_DIR"/tier-*/; do
    [[ ! -d "$TIER_DIR" ]] && continue
    TIER=$(basename "$TIER_DIR" | sed 's/tier-//')

    # Use the highest connection level for comparison
    HIGHEST_CONN_DIR=""
    for CONN_DIR in "$TIER_DIR"/*/; do
      [[ -d "$CONN_DIR" ]] && HIGHEST_CONN_DIR="$CONN_DIR"
    done
    [[ -z "$HIGHEST_CONN_DIR" ]] && continue

    RESULT_FILE=""
    if [[ -f "$HIGHEST_CONN_DIR/client-results.json" ]]; then
      RESULT_FILE="$HIGHEST_CONN_DIR/client-results.json"
    elif [[ -f "$HIGHEST_CONN_DIR/client-0-results.json" ]]; then
      RESULT_FILE="$HIGHEST_CONN_DIR/client-0-results.json"
    fi
    [[ -z "$RESULT_FILE" ]] && continue

    RTT_P99=$(jq -r '.metrics.rtt_p99_us // 0' "$RESULT_FILE")

    if [[ -n "$PREV_RTT" ]] && [[ "$PREV_RTT" -gt 0 ]]; then
      IMPROVEMENT=$(awk "BEGIN { printf \"%.1f\", (($PREV_RTT - $RTT_P99) / $PREV_RTT) * 100 }")
      echo "- Tier $PREV_TIER → Tier $TIER: **${IMPROVEMENT}%** improvement in RTT p99 ($PREV_RTT → $RTT_P99 µs)" >> "$REPORT"
    fi
    PREV_RTT="$RTT_P99"
    PREV_TIER="$TIER"
  done
  echo "" >> "$REPORT"
done

# Peak performance section
cat >> "$REPORT" <<'EOF'

---

## Peak Performance

EOF

# Find which crate reached 1M (or highest) first
BEST_CRATE=""
BEST_RTT=999999999
for CRATE_DIR in "$DIR"/*/; do
  CRATE=$(basename "$CRATE_DIR")
  [[ ! -d "$CRATE_DIR" ]] && continue
  [[ "$CRATE" == "metadata.json" || "$CRATE" == "report.md" || "$CRATE" == "summary.json" ]] && continue

  # Check for 1000000 connection result
  for TIER_DIR in "$CRATE_DIR"/tier-*/; do
    if [[ -d "$TIER_DIR/1000000" ]]; then
      RESULT_FILE=""
      if [[ -f "$TIER_DIR/1000000/client-results.json" ]]; then
        RESULT_FILE="$TIER_DIR/1000000/client-results.json"
      elif [[ -f "$TIER_DIR/1000000/client-0-results.json" ]]; then
        RESULT_FILE="$TIER_DIR/1000000/client-0-results.json"
      fi
      if [[ -n "$RESULT_FILE" ]]; then
        RTT=$(jq -r '.metrics.rtt_p99_us // 999999999' "$RESULT_FILE")
        if [[ "$RTT" -lt "$BEST_RTT" ]]; then
          BEST_RTT="$RTT"
          BEST_CRATE="$CRATE ($(basename "$TIER_DIR"))"
        fi
      fi
    fi
  done
done

if [[ -n "$BEST_CRATE" ]]; then
  echo "Best at 1M connections: **$BEST_CRATE** with RTT p99 = ${BEST_RTT} µs" >> "$REPORT"
else
  echo "No crate reached 1M connections in this run." >> "$REPORT"
fi

cat >> "$REPORT" <<'EOF'

---

## Summary

This report was auto-generated by `scripts/generate-report.sh`.
Refer to the raw JSON files in each subdirectory for full per-connection data.
EOF

echo ""
echo "Report generated: $REPORT"
echo "Summary JSON: $SUMMARY"
