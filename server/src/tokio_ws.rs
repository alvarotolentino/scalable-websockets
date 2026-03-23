use std::sync::Arc;

use tokio::net::TcpListener;
use futures_util::{SinkExt, StreamExt};
use tokio_websockets::ServerBuilder;
use tokio_util::sync::CancellationToken;

use crate::common::{create_reuse_port_listener, ServerStats};

pub async fn run(
    bind_addr: String,
    bind_port: u16,
    stats: Arc<ServerStats>,
    token: CancellationToken,
) -> std::io::Result<()> {
    let std_listener = create_reuse_port_listener(&bind_addr, bind_port, 65535)?;
    std_listener.set_nonblocking(true)?;
    let listener = TcpListener::from_std(std_listener)?;

    loop {
        let (stream, _addr) = tokio::select! {
            result = listener.accept() => match result {
                Ok(conn) => conn,
                Err(_) => continue,
            },
            () = token.cancelled() => break,
        };
        let stats = stats.clone();
        tokio::spawn(handle_connection(stream, stats));
    }

    Ok(())
}

async fn handle_connection(stream: tokio::net::TcpStream, stats: Arc<ServerStats>) {
    stats.connection_opened();

    let (_req, mut ws) = match ServerBuilder::new().accept(stream).await {
        Ok(pair) => pair,
        Err(_) => {
            stats.connection_closed();
            return;
        }
    };

    loop {
        let msg = match ws.next().await {
            Some(Ok(msg)) => msg,
            Some(Err(_)) => break,
            None => break,
        };

        if msg.is_text() || msg.is_binary() {
            stats.message_received();
            if ws.send(msg).await.is_err() {
                break;
            }
        } else if msg.is_close() {
            break;
        }
    }

    stats.connection_closed();
}
