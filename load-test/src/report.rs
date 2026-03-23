use serde::Serialize;

use crate::connection::ConnectionResult;
use crate::metrics::AggregatedMetrics;

/// Full test report written to JSON at the end of a run.
#[derive(Debug, Serialize)]
pub struct TestReport {
    pub timestamp: String,
    pub target: String,
    pub total_connections: u64,
    pub ramp_up_secs: u64,
    pub duration_secs: u64,
    pub message_interval_secs: u64,
    pub message_size: usize,
    pub metrics: AggregatedMetrics,
    pub connections: Vec<ConnectionResult>,
}

/// Build a `TestReport` from CLI configuration and collected results.
pub fn create_report(
    target: &str,
    total_connections: u64,
    ramp_up_secs: u64,
    duration_secs: u64,
    message_interval_secs: u64,
    message_size: usize,
    metrics: AggregatedMetrics,
    connections: Vec<ConnectionResult>,
) -> TestReport {
    // ISO 8601 timestamp using std only — avoids a chrono dependency.
    let now = std::time::SystemTime::now();
    let secs = now
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let timestamp = format_unix_timestamp(secs);

    TestReport {
        timestamp,
        target: target.to_owned(),
        total_connections,
        ramp_up_secs,
        duration_secs,
        message_interval_secs,
        message_size,
        metrics,
        connections,
    }
}

/// Write `report` as pretty-printed JSON to the file at `path`.
pub fn write_report(path: &str, report: &TestReport) -> std::io::Result<()> {
    let json = serde_json::to_string_pretty(report)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
    std::fs::write(path, json)?;
    eprintln!("Report written to {path}");
    Ok(())
}

/// Minimal ISO 8601 UTC formatter (avoids pulling in chrono).
fn format_unix_timestamp(epoch_secs: u64) -> String {
    // Naive conversion — good enough for report timestamps.
    const SECS_PER_MIN: u64 = 60;
    const SECS_PER_HOUR: u64 = 3600;
    const SECS_PER_DAY: u64 = 86400;

    let days = epoch_secs / SECS_PER_DAY;
    let time_of_day = epoch_secs % SECS_PER_DAY;
    let hour = time_of_day / SECS_PER_HOUR;
    let minute = (time_of_day % SECS_PER_HOUR) / SECS_PER_MIN;
    let second = time_of_day % SECS_PER_MIN;

    // Civil date from day count (algorithm from Howard Hinnant).
    let z = days as i64 + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = (z - era * 146097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };

    format!("{y:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}Z")
}
