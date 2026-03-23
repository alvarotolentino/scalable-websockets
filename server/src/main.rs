use clap::{Parser, ValueEnum};
use std::sync::Arc;

mod common;
mod tungstenite;
mod tokio_ws;
mod wtx_impl;

#[derive(Debug, Clone, Copy, ValueEnum)]
enum CrateImpl {
    Tungstenite,
    TokioWs,
    Wtx,
}

#[derive(Parser, Debug)]
#[command(name = "ws-echo-server", version, about = "WebSocket echo server benchmark")]
struct Args {
    /// WebSocket crate implementation to use
    #[arg(long = "crate", value_enum)]
    crate_impl: CrateImpl,

    /// Bind address
    #[arg(long, default_value = "0.0.0.0")]
    bind_addr: String,

    /// Bind port
    #[arg(long, default_value_t = 9001)]
    bind_port: u16,

    /// Number of Tokio worker threads (defaults to available CPUs)
    #[arg(long, default_value_t = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4))]
    worker_threads: usize,
}

fn main() {
    let args = Args::parse();

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(args.worker_threads)
        .enable_all()
        .build()
        .expect("failed to build tokio runtime");

    let stats = Arc::new(common::ServerStats::new());

    eprintln!(
        "ws-echo-server | crate={:?} bind={}:{} workers={}",
        args.crate_impl, args.bind_addr, args.bind_port, args.worker_threads
    );

    runtime.block_on(async {
        let result = match args.crate_impl {
            CrateImpl::Tungstenite => {
                tungstenite::run(args.bind_addr, args.bind_port, stats).await
            }
            CrateImpl::TokioWs => {
                tokio_ws::run(args.bind_addr, args.bind_port, stats).await
            }
            CrateImpl::Wtx => {
                wtx_impl::run(args.bind_addr, args.bind_port, stats).await
            }
        };
        if let Err(e) = result {
            eprintln!("server error: {e}");
            std::process::exit(1);
        }
    });
}
