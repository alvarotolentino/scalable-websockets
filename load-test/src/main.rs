use std::time::{Duration, Instant};

use clap::Parser;

mod connection;
mod metrics;
mod report;

#[derive(Parser, Debug)]
#[command(name = "ws-load-test", version, about = "WebSocket load test client")]
struct Args {
    /// WebSocket target URL (e.g. ws://10.0.0.1:9001)
    #[arg(long)]
    target: String,

    /// Total number of WebSocket connections to open
    #[arg(long)]
    connections: u64,

    /// Seconds over which to ramp up connections
    #[arg(long, default_value_t = 60)]
    ramp_up: u64,

    /// Seconds between echo messages per connection
    #[arg(long, default_value_t = 30)]
    message_interval: u64,

    /// Bytes per echo message
    #[arg(long, default_value_t = 64)]
    message_size: usize,

    /// Total test duration in seconds (after ramp-up completes)
    #[arg(long, default_value_t = 300)]
    duration: u64,

    /// Output file path for the JSON report
    #[arg(long, default_value = "results.json")]
    output: String,
}

fn main() {
    let args = Args::parse();

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("failed to build tokio runtime");

    runtime.block_on(async_main(args));
}

async fn async_main(args: Args) {
    let total = args.connections;
    let ramp_up = Duration::from_secs(args.ramp_up);
    let duration = Duration::from_secs(args.duration);
    let message_interval = Duration::from_secs(args.message_interval);
    let message_size = args.message_size;
    let target = args.target.clone();

    // Delay between each connection spawn during ramp-up.
    let ramp_delay = if total > 1 {
        ramp_up / total as u32
    } else {
        Duration::ZERO
    };

    let ramp_start = Instant::now();
    let mut handles = Vec::with_capacity(total as usize);
    let progress_step = (total / 10).max(1);

    for id in 0..total {
        let t = target.clone();
        // Each connection runs for the full duration minus time already spent ramping.
        let elapsed = ramp_start.elapsed();
        let conn_duration = duration + ramp_up.saturating_sub(elapsed);

        let handle = tokio::spawn(async move {
            connection::run_connection(id, &t, message_interval, message_size, conn_duration).await
        });
        handles.push(handle);

        if (id + 1) % progress_step == 0 {
            eprintln!("Spawned {}/{total} connections", id + 1);
        }

        if ramp_delay > Duration::ZERO {
            tokio::time::sleep(ramp_delay).await;
        }
    }

    eprintln!("All {total} connections spawned, waiting for test to complete...");

    let mut results = Vec::with_capacity(handles.len());
    for handle in handles {
        match handle.await {
            Ok(r) => results.push(r),
            Err(e) => {
                // Task panicked — record as a failed connection.
                results.push(connection::ConnectionResult {
                    id: results.len() as u64,
                    handshake_time_us: 0,
                    round_trips: Vec::new(),
                    error: Some(format!("task panic: {e}")),
                    disconnected_early: false,
                });
            }
        }
    }

    let wall_secs = ramp_start.elapsed().as_secs_f64();
    let m = metrics::aggregate(&results, wall_secs);

    eprintln!(
        "Success: {:.1}% | Connections: {}/{} | RTT p50={}µs p99={}µs | msg/s={:.0}",
        m.success_rate, m.total_successful, m.total_attempted,
        m.rtt_p50_us, m.rtt_p99_us, m.messages_per_sec,
    );

    let report = report::create_report(
        report::ReportConfig {
            target: &args.target,
            total_connections: total,
            ramp_up_secs: args.ramp_up,
            duration_secs: args.duration,
            message_interval_secs: args.message_interval,
            message_size,
        },
        m,
        results,
    );

    if let Err(e) = report::write_report(&args.output, &report) {
        eprintln!("Failed to write report: {e}");
        std::process::exit(1);
    }
}
