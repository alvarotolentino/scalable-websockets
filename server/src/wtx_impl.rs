use std::sync::Arc;

use tokio::net::TcpListener;
use wtx::web_socket::{Frame, OpCode, WebSocketAcceptor, WebSocketPayloadOrigin};
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

    let mut ws = match WebSocketAcceptor::default().accept(stream).await {
        Ok(ws) => ws,
        Err(_) => {
            stats.connection_closed();
            return;
        }
    };

    let mut buffer = wtx::collection::Vector::new();
    loop {
        let frame = match ws
            .read_frame(&mut buffer, WebSocketPayloadOrigin::Consistent)
            .await
        {
            Ok(f) => f,
            Err(_) => break,
        };

        let op_code = frame.op_code();
        match op_code {
            OpCode::Close => break,
            OpCode::Text | OpCode::Binary => {
                stats.message_received();
                let payload = frame.payload().to_vec();
                let mut echo = Frame::new_fin(op_code, payload);
                if ws.write_frame(&mut echo).await.is_err() {
                    break;
                }
            }
            _ => {}
        }
        buffer.clear();
    }

    stats.connection_closed();
}
