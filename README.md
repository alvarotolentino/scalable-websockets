# Scalable WebSockets

Benchmark three Rust WebSocket crates on bare-metal infrastructure, apply progressive kernel and application tuning, and reach **1 million concurrent WebSocket connections** on a single server.

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
└── Cargo.toml           # workspace manifest
```

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

## Design Principles

- **Zero-logging on hot path** — the server produces one startup line to stderr and nothing else during steady-state operation. All observability comes from external metrics collection via `/proc` and `ServerStats` atomics.
- **Mechanical sympathy** — manual runtime builder, `SO_REUSEPORT`, pre-sized buffers, static dispatch in hot paths.
- **Release profile tuned for throughput** — LTO fat, single codegen unit, panic=abort, stripped symbols.

## License

[MIT](LICENSE)
