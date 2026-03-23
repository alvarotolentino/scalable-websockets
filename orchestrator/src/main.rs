use std::collections::HashMap;

use clap::Parser;

/// Distributed load test orchestrator.
///
/// Coordinates multiple client machines to run ws-load-test instances
/// in parallel, then merges the results into a single combined report.
#[derive(Parser)]
#[command(name = "ws-load-orchestrator", version)]
struct Args {
    /// WebSocket target URL (e.g. ws://server:9001)
    #[arg(long)]
    target: String,

    /// Total number of connections across all clients
    #[arg(long)]
    total_connections: u64,

    /// Comma-separated client IPs
    #[arg(long)]
    clients: String,

    /// Ramp-up duration in seconds
    #[arg(long, default_value_t = 120)]
    ramp_up: u64,

    /// Test duration in seconds
    #[arg(long, default_value_t = 300)]
    duration: u64,

    /// Message send interval in seconds
    #[arg(long, default_value_t = 30)]
    message_interval: u64,

    /// Message payload size in bytes
    #[arg(long, default_value_t = 64)]
    message_size: usize,

    /// SSH private key path
    #[arg(long, default_value = "~/.ssh/id_ed25519")]
    ssh_key: String,

    /// Combined output report path
    #[arg(long, default_value = "combined-results.json")]
    output: String,
}

/// Partial representation of a single client's test report (for deserialization).
#[derive(serde::Deserialize)]
#[allow(dead_code)] // Fields deserialized from JSON; used selectively in merge_reports
struct ClientReport {
    #[serde(default)]
    timestamp: String,
    #[serde(default)]
    target: String,
    #[serde(default)]
    total_connections: u64,
    #[serde(default)]
    ramp_up_secs: u64,
    #[serde(default)]
    duration_secs: u64,
    #[serde(default)]
    message_interval_secs: u64,
    #[serde(default)]
    message_size: usize,
    #[serde(default)]
    connections: Vec<ConnectionData>,
}

/// Per-connection result from a client report.
#[derive(serde::Deserialize, serde::Serialize, Clone)]
struct ConnectionData {
    #[serde(default)]
    id: u64,
    #[serde(default)]
    handshake_time_us: u64,
    #[serde(default)]
    round_trips: Vec<u64>,
    #[serde(default)]
    error: Option<String>,
    #[serde(default)]
    disconnected_early: bool,
}

/// Combined metrics for the merged report.
#[derive(serde::Serialize)]
struct MergedMetrics {
    total_attempted: u64,
    total_successful: u64,
    total_failed: u64,
    total_disconnected_early: u64,
    success_rate: f64,
    handshake_p50_us: u64,
    handshake_p90_us: u64,
    handshake_p99_us: u64,
    handshake_p999_us: u64,
    handshake_max_us: u64,
    rtt_p50_us: u64,
    rtt_p90_us: u64,
    rtt_p99_us: u64,
    rtt_p999_us: u64,
    rtt_max_us: u64,
    total_messages: u64,
    messages_per_sec: f64,
    errors: HashMap<String, u64>,
}

/// Combined output report matching the TestReport schema from load-test.
#[derive(serde::Serialize)]
struct CombinedReport {
    timestamp: String,
    target: String,
    total_connections: u64,
    ramp_up_secs: u64,
    duration_secs: u64,
    message_interval_secs: u64,
    message_size: usize,
    metrics: MergedMetrics,
    connections: Vec<ConnectionData>,
}

fn main() {
    let args = Args::parse();

    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("failed to build tokio runtime");

    if let Err(e) = rt.block_on(run(args)) {
        eprintln!("Error: {e}");
        std::process::exit(1);
    }
}

async fn run(args: Args) -> Result<(), Box<dyn std::error::Error>> {
    let client_ips: Vec<String> = args
        .clients
        .split(',')
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
        .collect();

    if client_ips.is_empty() {
        return Err("No client IPs provided".into());
    }

    let num_clients = client_ips.len() as u64;
    let per_client = args.total_connections / num_clients;
    let remainder = args.total_connections % num_clients;

    eprintln!(
        "Distributing {} connections across {} clients ({} each + {} remainder)",
        args.total_connections,
        num_clients,
        per_client,
        remainder
    );

    // Expand ~ in SSH key path
    let ssh_key = if args.ssh_key.starts_with("~/") {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/root".to_owned());
        args.ssh_key.replacen("~", &home, 1)
    } else {
        args.ssh_key.clone()
    };

    // Spawn one task per client
    let mut handles = Vec::with_capacity(client_ips.len());
    for (i, ip) in client_ips.iter().enumerate() {
        let conns = per_client + if (i as u64) < remainder { 1 } else { 0 };
        let ip = ip.clone();
        let target = args.target.clone();
        let ssh_key = ssh_key.clone();
        let ramp_up = args.ramp_up;
        let duration = args.duration;
        let msg_interval = args.message_interval;
        let msg_size = args.message_size;

        handles.push(tokio::spawn(async move {
            let params = ClientRunParams {
                index: i,
                ip: &ip,
                target: &target,
                connections: conns,
                ramp_up,
                duration,
                msg_interval,
                msg_size,
                ssh_key: &ssh_key,
            };
            run_client(&params).await
        }));
    }

    // Collect results from all clients
    let mut all_reports: Vec<ClientReport> = Vec::new();
    for (i, handle) in handles.into_iter().enumerate() {
        match handle.await {
            Ok(Ok(report)) => {
                eprintln!("Client {} finished: {} connections", i, report.connections.len());
                all_reports.push(report);
            }
            Ok(Err(e)) => eprintln!("Client {} failed: {}", i, e),
            Err(e) => eprintln!("Client {} task panicked: {}", i, e),
        }
    }

    if all_reports.is_empty() {
        return Err("All clients failed — no results to merge".into());
    }

    // Merge results
    let combined = merge_reports(&all_reports, &args.target, &args);
    let json = serde_json::to_string_pretty(&combined)?;
    std::fs::write(&args.output, &json)?;
    eprintln!("Combined report written to {}", args.output);

    Ok(())
}

/// Parameters for a single client run, passed to avoid too many function arguments.
struct ClientRunParams<'a> {
    index: usize,
    ip: &'a str,
    target: &'a str,
    connections: u64,
    ramp_up: u64,
    duration: u64,
    msg_interval: u64,
    msg_size: usize,
    ssh_key: &'a str,
}

async fn run_client(
    p: &ClientRunParams<'_>,
) -> Result<ClientReport, Box<dyn std::error::Error + Send + Sync>> {
    let remote_result = "/tmp/results.json";
    let local_result = format!("/tmp/client-{}-results.json", p.index);

    // Run load test on remote client via SSH
    let run_output = tokio::process::Command::new("ssh")
        .args([
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=10",
            "-i", p.ssh_key,
            &format!("root@{}", p.ip),
            &format!(
                "cd /root/scalable-websockets && ./target/release/ws-load-test \
                 --target {} --connections {} --ramp-up {} \
                 --duration {} --message-interval {} \
                 --message-size {} --output {remote_result}",
                p.target, p.connections, p.ramp_up,
                p.duration, p.msg_interval, p.msg_size,
            ),
        ])
        .output()
        .await?;

    if !run_output.status.success() {
        let stderr = String::from_utf8_lossy(&run_output.stderr);
        return Err(format!("SSH to {} failed: {stderr}", p.ip).into());
    }

    // SCP result file back
    let scp_output = tokio::process::Command::new("scp")
        .args([
            "-o", "StrictHostKeyChecking=no",
            "-i", p.ssh_key,
            &format!("root@{}:{remote_result}", p.ip),
            &local_result,
        ])
        .output()
        .await?;

    if !scp_output.status.success() {
        let stderr = String::from_utf8_lossy(&scp_output.stderr);
        return Err(format!("SCP from {} failed: {stderr}", p.ip).into());
    }

    // Parse JSON report
    let data = tokio::fs::read_to_string(&local_result).await?;
    let report: ClientReport = serde_json::from_str(&data)?;

    // Clean up local temp file
    let _ = tokio::fs::remove_file(&local_result).await;

    Ok(report)
}

fn merge_reports(reports: &[ClientReport], target: &str, args: &Args) -> CombinedReport {
    let mut all_connections: Vec<ConnectionData> = Vec::new();
    for report in reports {
        all_connections.extend(report.connections.iter().cloned());
    }

    // Recompute accurate percentiles from raw data using HDR histograms
    let mut hs_hist =
        hdrhistogram::Histogram::<u64>::new_with_max(60_000_000, 3).expect("valid histogram");
    let mut rtt_hist =
        hdrhistogram::Histogram::<u64>::new_with_max(60_000_000, 3).expect("valid histogram");

    let mut total_successful: u64 = 0;
    let mut total_failed: u64 = 0;
    let mut total_disconnected_early: u64 = 0;
    let mut total_messages: u64 = 0;
    let mut errors: HashMap<String, u64> = HashMap::new();

    for conn in &all_connections {
        if let Some(ref err) = conn.error {
            total_failed += 1;
            *errors.entry(err.clone()).or_insert(0) += 1;
        } else {
            total_successful += 1;
            let _ = hs_hist.record(conn.handshake_time_us);
        }

        if conn.disconnected_early {
            total_disconnected_early += 1;
        }

        for &rtt in &conn.round_trips {
            let _ = rtt_hist.record(rtt);
            total_messages += 1;
        }
    }

    let total_attempted = all_connections.len() as u64;
    let success_rate = if total_attempted > 0 {
        total_successful as f64 / total_attempted as f64 * 100.0
    } else {
        0.0
    };

    let duration_secs = args.duration as f64;
    let messages_per_sec = if duration_secs > 0.0 {
        total_messages as f64 / duration_secs
    } else {
        0.0
    };

    // Use first report's metadata as baseline
    let first = &reports[0];

    CombinedReport {
        timestamp: first.timestamp.clone(),
        target: target.to_owned(),
        total_connections: args.total_connections,
        ramp_up_secs: args.ramp_up,
        duration_secs: args.duration,
        message_interval_secs: args.message_interval,
        message_size: args.message_size,
        metrics: MergedMetrics {
            total_attempted,
            total_successful,
            total_failed,
            total_disconnected_early,
            success_rate,
            handshake_p50_us: hs_hist.value_at_quantile(0.50),
            handshake_p90_us: hs_hist.value_at_quantile(0.90),
            handshake_p99_us: hs_hist.value_at_quantile(0.99),
            handshake_p999_us: hs_hist.value_at_quantile(0.999),
            handshake_max_us: hs_hist.max(),
            rtt_p50_us: rtt_hist.value_at_quantile(0.50),
            rtt_p90_us: rtt_hist.value_at_quantile(0.90),
            rtt_p99_us: rtt_hist.value_at_quantile(0.99),
            rtt_p999_us: rtt_hist.value_at_quantile(0.999),
            rtt_max_us: rtt_hist.max(),
            total_messages,
            messages_per_sec,
            errors,
        },
        connections: all_connections,
    }
}
