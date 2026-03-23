use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use tokio::process::Command;
use tokio_tungstenite::tungstenite::Message;

/// Starts the echo server on a non-standard port, opens 10 WebSocket
/// connections, sends one message on each, and asserts every echo arrives.
#[tokio::test]
async fn test_echo_roundtrip() {
    // Start the server as a child process on port 19001.
    let mut server = Command::new("cargo")
        .args([
            "run",
            "-p",
            "ws-echo-server",
            "--",
            "--crate",
            "tungstenite",
            "--bind-port",
            "19001",
        ])
        .kill_on_drop(true)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .expect("failed to start server process");

    // Give the server time to bind.
    tokio::time::sleep(Duration::from_secs(3)).await;

    let url = "ws://127.0.0.1:19001";
    let mut handles = Vec::new();

    for i in 0u32..10 {
        let handle = tokio::spawn(async move {
            let (ws, _) = tokio_tungstenite::connect_async(url)
                .await
                .unwrap_or_else(|e| panic!("connection {i} failed: {e}"));

            let (mut sink, mut stream) = ws.split();

            let payload = format!("hello-{i}");
            sink.send(Message::Text(payload.clone().into()))
                .await
                .unwrap_or_else(|e| panic!("send {i} failed: {e}"));

            let echo = stream
                .next()
                .await
                .unwrap_or_else(|| panic!("connection {i}: stream ended"))
                .unwrap_or_else(|e| panic!("connection {i} recv error: {e}"));

            match echo {
                Message::Text(text) => {
                    let s: &str = &text;
                    assert_eq!(s, payload, "connection {i}: echo mismatch");
                }
                other => panic!("connection {i}: expected Text, got {other:?}"),
            }

            let _ = sink.send(Message::Close(None)).await;
        });
        handles.push(handle);
    }

    for (i, handle) in handles.into_iter().enumerate() {
        handle
            .await
            .unwrap_or_else(|e| panic!("task {i} panicked: {e}"));
    }

    // Clean up: kill the server.
    server.kill().await.ok();
}
