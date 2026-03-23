use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::Message;

use crate::common::{create_reuse_port_listener, ServerStats};

pub async fn run(
    bind_addr: String,
    bind_port: u16,
    stats: Arc<ServerStats>,
) -> std::io::Result<()> {
    let std_listener = create_reuse_port_listener(&bind_addr, bind_port, 65535)?;
    std_listener.set_nonblocking(true)?;
    let listener = TcpListener::from_std(std_listener)?;

    loop {
        let (stream, _addr) = match listener.accept().await {
            Ok(conn) => conn,
            Err(_) => continue,
        };
        let stats = stats.clone();
        tokio::spawn(handle_connection(stream, stats));
    }
}

async fn handle_connection(stream: tokio::net::TcpStream, stats: Arc<ServerStats>) {
    stats.connection_opened();

    let ws_stream = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(_) => {
            stats.connection_closed();
            return;
        }
    };

    let (mut sink, mut stream) = ws_stream.split();

    while let Some(msg_result) = stream.next().await {
        let msg = match msg_result {
            Ok(msg) => msg,
            Err(_) => break,
        };
        match msg {
            Message::Text(_) | Message::Binary(_) => {
                stats.message_received();
                if sink.send(msg).await.is_err() {
                    break;
                }
            }
            Message::Ping(_) => {
                // tungstenite handles pong automatically
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    stats.connection_closed();
}
