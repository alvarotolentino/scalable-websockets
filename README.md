# Scalable WebSockets

WIP - Benchmark three Rust WebSocket crates on bare-metal infrastructure, apply progressive kernel and application tuning, and reach **1 million concurrent WebSocket connections** on a single server.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Bare Metal                                   │
│                                                                 │
│  ┌──────────────────────┐       ┌──────────────────────────┐    │
│  │  SERVER (1 machine)  │       │  CLIENT(s) (N machines)  │    │
│  │                      │       │                          │    │
│  │  ┌────────────────┐  │  WS   │  ┌────────────────────┐  │    │
│  │  │ ws-echo-server │◄─┼───────┼──│  load-test-client  │  │    │
│  │  │ (one of 3      │  │       │  │  (custom Rust tool │  │    │
│  │  │  crate impls)  │  │       │  │    + orchestrator) │  │    │
│  │  └────────────────┘  │       │  │                    │  │    │
│  │                      │       │  └────────────────────┘  │    │
│  │  ┌────────────────┐  │       │  ┌────────────────────┐  │    │
│  │  │ metrics-agent  │──┼───┐   │  │ metrics-agent      │  │    │
│  │  │ (node_exporter │  │   │   │  │                    │  │    │
│  │  │  + custom)     │  │   │   │  └────────────────────┘  │    │
│  │  └────────────────┘  │   │   └──────────────────────────┘    │
│  └──────────────────────┘   │                                   │
│                             ▼                                   │
│                   ┌────────────────┐                            │
│                   │ Results Store  │                            │
│                   │ (JSON / CSV)   │                            │
│                   └────────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
   Developer Machine
   ┌──────────────┐
   │  Terraform   │  terraform apply / destroy
   │  Scripts     │  + cloud-init provisioning
   │  Report gen  │  post-run analysis & comparison
   └──────────────┘
```

## Crates Under Test

| Crate | Version | Highlights |
|-------|---------|------------|
| [tokio-tungstenite](https://github.com/snapview/tokio-tungstenite) | 0.29 | Mature, widely deployed Tokio wrapper around tungstenite-rs |
| [tokio-websockets](https://github.com/Gelbpunkt/tokio-websockets) | 0.13 | Zero-copy `Bytes` payloads, SIMD frame masking (SSE2/AVX2/NEON) |
| [wtx](https://github.com/c410-f3r/wtx) | 0.42 | All-in-one transport toolkit, RFC 7692 compression, `no_std`-capable |

## Project Structure

```
scalable-websockets/
├── server/              # ws-echo-server — WebSocket echo server binary
│   └── src/
│       ├── main.rs      # CLI entry point, runtime builder
│       ├── common.rs    # ServerStats atomics, SO_REUSEPORT listener
│       ├── tungstenite.rs
│       ├── tokio_ws.rs
│       └── wtx_impl.rs
├── load-test/           # ws-load-test — load test client binary
│   ├── src/
│   │   ├── main.rs      # CLI, ramp-up loop, result collection
│   │   ├── connection.rs # single WS connection lifecycle + RTT
│   │   ├── metrics.rs   # HDR histogram aggregation
│   │   └── report.rs    # JSON report writer
│   └── tests/
│       └── integration.rs
├── orchestrator/        # ws-load-orchestrator — distributed load testing
│   └── src/
│       └── main.rs      # SSH-based multi-client coordination + result merge
├── terraform/           # Latitude.sh bare-metal provisioning
│   ├── main.tf          # Provider config
│   ├── variables.tf     # Input variables
│   ├── project.tf       # Project & SSH key resources
│   ├── server.tf        # Server instance
│   ├── clients.tf       # Client instances (count-based)
│   ├── outputs.tf       # IP addresses, project ID
│   └── templates/       # Cloud-init YAML for server & clients
├── scripts/
│   ├── run-benchmark.sh      # Full benchmark orchestration (crate × tier × connections)
│   ├── collect-metrics.sh    # Server-side system metrics sampler (1s CSV)
│   ├── generate-report.sh    # Post-run Markdown + JSON report generator
│   └── tuning/               # Kernel tuning tiers (0–9), each with apply + revert
├── results/             # Benchmark output (gitignored except .gitkeep)
└── Cargo.toml           # Workspace manifest
```

## Prerequisites

- Rust stable toolchain (1.94+)
- Terraform >= 1.5
- A [Latitude.sh](https://latitude.sh) account with API token
- Python 3 (for report generation JSON parsing)
- SSH key pair for server access

## Quick Start

### Build

```bash
cargo build --release
```

### Run the Server

```bash
# Pick a backend: tungstenite | tokio-ws | wtx
cargo run -p ws-echo-server --release -- --crate tungstenite --bind-port 9001
```

### Run the Load Test

```bash
cargo run -p ws-load-test --release -- \
  --target ws://127.0.0.1:9001 \
  --connections 1000 \
  --ramp-up 10 \
  --duration 60 \
  --message-interval 5 \
  --message-size 64 \
  --output results.json
```

### Run Tests

```bash
cargo test -p ws-load-test
```

## Server CLI

```
ws-echo-server [OPTIONS] --crate <CRATE_IMPL>

Options:
    --crate <CRATE_IMPL>              tungstenite | tokio-ws | wtx
    --bind-addr <BIND_ADDR>           [default: 0.0.0.0]
    --bind-port <BIND_PORT>           [default: 9001]
    --worker-threads <WORKER_THREADS> [default: num CPUs]
```

## Load Test CLI

```
ws-load-test [OPTIONS] --target <TARGET> --connections <CONNECTIONS>

Options:
    --target <TARGET>                     WebSocket URL
    --connections <CONNECTIONS>            Total connections to open
    --ramp-up <RAMP_UP>                   Ramp-up period in seconds [default: 60]
    --message-interval <MESSAGE_INTERVAL> Seconds between echoes [default: 30]
    --message-size <MESSAGE_SIZE>         Bytes per message [default: 64]
    --duration <DURATION>                 Test duration in seconds [default: 300]
    --output <OUTPUT>                     JSON report path [default: results.json]
```

## Orchestrator CLI

```
ws-load-orchestrator [OPTIONS] --target <TARGET> --total-connections <N> --clients <IPs>

Options:
    --target <TARGET>                     WebSocket URL
    --total-connections <N>               Connections distributed across all clients
    --clients <IPs>                       Comma-separated client IP addresses
    --ramp-up <RAMP_UP>                   Ramp-up period [default: 120]
    --duration <DURATION>                 Test duration [default: 300]
    --message-interval <MESSAGE_INTERVAL> Seconds between echoes [default: 30]
    --message-size <MESSAGE_SIZE>         Bytes per message [default: 64]
    --ssh-key <PATH>                      SSH private key [default: ~/.ssh/id_ed25519]
    --output <OUTPUT>                     Combined report path [default: combined-results.json]
```

## Full Benchmark Workflow

```bash
# 1. Provision bare-metal infrastructure
export LATITUDESH_AUTH_TOKEN="your-token"
cd terraform
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
cd ..

# 2. Run benchmarks (all crates × all tiers × connection progression)
./scripts/run-benchmark.sh --crate all --tier all --duration 300

# 3. Generate comparison report
./scripts/generate-report.sh results/<timestamp>/

# 4. Tear down infrastructure
cd terraform && terraform destroy
```

## Kernel Tuning Tiers

| Tier | Category | Description |
|------|----------|-------------|
| 0 | Baseline | Stock Ubuntu 24.04 LTS — no tuning applied |
| 1 | FD Limits | nofile 1.1M, fs.file-max 2.2M, fs.nr_open 2.2M |
| 2 | TCP Stack | 22 sysctl params: buffer sizes, backlog, port range, keepalive |
| 3 | Netfilter | Flush iptables, unload nf_conntrack, blacklist modules |
| 4 | Affinity | Stop irqbalance, pin IRQs to cores, XPS, interrupt coalescing |
| 5 | Busy Poll | net.core.busy_poll=1, net.core.busy_read=1 |
| 6 | Allocator | jemalloc (compile-time — rebuild server binary) |
| 7 | Audit | Disable syscall auditing via auditctl |
| 8 | Qdisc | Switch queueing discipline to noqueue/mq |
| 9 | Miscellaneous | GRO off, TCP Reno, transparent huge pages disabled |

## Design Principles

- **Zero-logging on hot path** — the server produces one startup line to stderr and nothing else during steady-state operation. All observability comes from external metrics collection via `/proc` and `ServerStats` atomics.
- **Mechanical sympathy** — manual runtime builder, `SO_REUSEPORT`, pre-sized buffers, static dispatch in hot paths.
- **Release profile tuned for throughput** — LTO fat, single codegen unit, panic=abort, stripped symbols.

## License

[MIT](LICENSE)
