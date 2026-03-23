use std::net::{SocketAddr, TcpListener};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use socket2::{Domain, Protocol, Socket, Type};

#[derive(Debug)]
pub struct ServerStats {
    pub active_connections: AtomicU64,
    pub total_messages: AtomicU64,
    pub total_connections: AtomicU64,
    pub start_time: Instant,
}

impl ServerStats {
    pub fn new() -> Self {
        Self {
            active_connections: AtomicU64::new(0),
            total_messages: AtomicU64::new(0),
            total_connections: AtomicU64::new(0),
            start_time: Instant::now(),
        }
    }

    pub fn connection_opened(&self) {
        self.active_connections.fetch_add(1, Ordering::Relaxed);
        self.total_connections.fetch_add(1, Ordering::Relaxed);
    }

    pub fn connection_closed(&self) {
        self.active_connections.fetch_sub(1, Ordering::Relaxed);
    }

    pub fn message_received(&self) {
        self.total_messages.fetch_add(1, Ordering::Relaxed);
    }
}

pub fn create_reuse_port_listener(
    addr: &str,
    port: u16,
    backlog: u32,
) -> std::io::Result<TcpListener> {
    let socket = Socket::new(Domain::IPV4, Type::STREAM, Some(Protocol::TCP))?;
    socket.set_reuse_address(true)?;
    #[cfg(unix)]
    socket.set_reuse_port(true)?;
    let sock_addr: SocketAddr = format!("{addr}:{port}").parse().map_err(|e| {
        std::io::Error::new(std::io::ErrorKind::InvalidInput, e)
    })?;
    socket.bind(&sock_addr.into())?;
    socket.listen(backlog as i32)?;
    Ok(socket.into())
}
