use std::time::{Duration, Instant};

use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use tokio_tungstenite::tungstenite::Message;

/// Result of a single WebSocket connection lifecycle.
#[derive(Debug, Clone, Serialize)]
pub struct ConnectionResult {
    pub id: u64,
    pub handshake_time_us: u64,
    pub round_trips: Vec<u64>,
    pub error: Option<String>,
    pub disconnected_early: bool,
}

/// Opens a WebSocket connection to `target`, sends echo messages at
/// `message_interval` for `duration`, and returns timing results.
pub async fn run_connection(
    id: u64,
    target: &str,
    message_interval: Duration,
    message_size: usize,
    duration: Duration,
) -> ConnectionResult {
    let hs_start = Instant::now();

    let connect_timeout = Duration::from_secs(30);
    let ws = match tokio::time::timeout(connect_timeout, tokio_tungstenite::connect_async(target)).await {
        Ok(Ok((stream, _response))) => stream,
        Ok(Err(e)) => {
            return ConnectionResult {
                id,
                handshake_time_us: hs_start.elapsed().as_micros() as u64,
                round_trips: Vec::new(),
                error: Some(e.to_string()),
                disconnected_early: false,
            };
        }
        Err(_) => {
            return ConnectionResult {
                id,
                handshake_time_us: hs_start.elapsed().as_micros() as u64,
                round_trips: Vec::new(),
                error: Some("connect timeout (30s)".to_string()),
                disconnected_early: false,
            };
        }
    };

    let handshake_time_us = hs_start.elapsed().as_micros() as u64;
    let (mut sink, mut stream) = ws.split();

    let payload = vec![b'x'; message_size];
    let mut round_trips = Vec::new();
    let deadline = Instant::now() + duration;

    loop {
        if Instant::now() >= deadline {
            break;
        }

        let send_start = Instant::now();
        if let Err(e) = sink.send(Message::Binary(payload.clone().into())).await {
            return ConnectionResult {
                id,
                handshake_time_us,
                round_trips,
                error: Some(e.to_string()),
                disconnected_early: true,
            };
        }

        match stream.next().await {
            Some(Ok(_msg)) => {
                round_trips.push(send_start.elapsed().as_micros() as u64);
            }
            Some(Err(e)) => {
                return ConnectionResult {
                    id,
                    handshake_time_us,
                    round_trips,
                    error: Some(e.to_string()),
                    disconnected_early: true,
                };
            }
            None => {
                return ConnectionResult {
                    id,
                    handshake_time_us,
                    round_trips,
                    error: None,
                    disconnected_early: true,
                };
            }
        }

        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            break;
        }
        tokio::time::sleep(message_interval.min(remaining)).await;
    }

    // Graceful close — best-effort, ignore errors.
    let _ = sink.send(Message::Close(None)).await;

    ConnectionResult {
        id,
        handshake_time_us,
        round_trips,
        error: None,
        disconnected_early: false,
    }
}
