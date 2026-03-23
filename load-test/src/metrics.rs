use std::collections::HashMap;

use hdrhistogram::Histogram;
use serde::Serialize;

use crate::connection::ConnectionResult;

/// Aggregated benchmark metrics computed from all connection results.
#[derive(Debug, Clone, Serialize)]
pub struct AggregatedMetrics {
    pub total_attempted: u64,
    pub total_successful: u64,
    pub total_failed: u64,
    pub total_disconnected_early: u64,
    pub success_rate: f64,
    pub handshake_p50_us: u64,
    pub handshake_p90_us: u64,
    pub handshake_p99_us: u64,
    pub handshake_p999_us: u64,
    pub handshake_max_us: u64,
    pub rtt_p50_us: u64,
    pub rtt_p90_us: u64,
    pub rtt_p99_us: u64,
    pub rtt_p999_us: u64,
    pub rtt_max_us: u64,
    pub total_messages: u64,
    pub messages_per_sec: f64,
    pub errors: HashMap<String, u64>,
}

/// Aggregate raw connection results into summary statistics using HDR histograms.
pub fn aggregate(results: &[ConnectionResult], duration_secs: f64) -> AggregatedMetrics {
    // Max trackable: 60 seconds in microseconds, 3 significant digits.
    let mut hs_hist = Histogram::<u64>::new_with_max(60_000_000, 3)
        .expect("valid histogram params");
    let mut rtt_hist = Histogram::<u64>::new_with_max(60_000_000, 3)
        .expect("valid histogram params");

    let mut total_successful: u64 = 0;
    let mut total_failed: u64 = 0;
    let mut total_disconnected_early: u64 = 0;
    let mut total_messages: u64 = 0;
    let mut errors: HashMap<String, u64> = HashMap::new();

    for r in results {
        if let Some(ref err) = r.error {
            total_failed += 1;
            *errors.entry(err.clone()).or_insert(0) += 1;
        } else {
            total_successful += 1;
            // Clamp to max trackable value to avoid record errors.
            let hs_val = r.handshake_time_us.min(60_000_000);
            let _ = hs_hist.record(hs_val);
        }

        if r.disconnected_early {
            total_disconnected_early += 1;
        }

        for &rtt in &r.round_trips {
            let rtt_val = rtt.min(60_000_000);
            let _ = rtt_hist.record(rtt_val);
            total_messages += 1;
        }
    }

    let total_attempted = results.len() as u64;
    let success_rate = if total_attempted > 0 {
        (total_successful as f64 / total_attempted as f64) * 100.0
    } else {
        0.0
    };

    let messages_per_sec = if duration_secs > 0.0 {
        total_messages as f64 / duration_secs
    } else {
        0.0
    };

    AggregatedMetrics {
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
    }
}
