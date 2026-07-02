# `iroh-knot`

`iroh-knot` is the official Iroh-based P2P networking transport adapter for the [`knot-protocol`](../knot-protocol). It implements the transport-agnostic `KnotConnection` trait using Iroh's secure QUIC endpoints, connections, and streams.

## Features

- **P2P QUIC Transport**: Out-of-the-box support for secure, direct peer-to-peer tunnels.
- **Connection Handshake Gating**: Verifies remote identities against cryptographic public keys before session admission.
- **Pluggable Event Routing**: Dispatches transport framing events to application callbacks.
- **Zero-Configuration Endpoints**: Helper methods to bind and configure Iroh QUIC endpoints with optimized keep-alive settings.

## Usage

### 1. Spawning a Host (Hub)

To host a Knot session router on Iroh:

```rust
use iroh_knot::{IrohKnotHub, bind_endpoint, generate_ticket};
use knot_protocol::JoinPolicy;
use std::path::PathBuf;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Bind QUIC endpoint
    let endpoint = bind_endpoint().await?;
    
    // 2. Generate sharing ticket
    let ticket = generate_ticket(&endpoint);
    println!("Share this connection ticket: {}", ticket);

    // 3. Spawn Hub router
    let (hub, mut events) = IrohKnotHub::spawn(
        endpoint, 
        PathBuf::from("./knot_data"), 
        || "{\"status\": \"active\"}".to_string()
    ).await?;

    // 4. Handle connection events
    while let Some(event) = events.recv().await {
        println!("Received Event: {:?}", event);
    }

    Ok(())
}
```

### 2. Connecting a Client (Rope)

To connect to a Host router using a ticket:

```rust
use iroh_knot::{IrohKnotClientJoinBuilder, bind_endpoint};
use knot_protocol::Capability;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let ticket = "your_session_ticket_string";

    // Establish connection and run handshake
    let client = IrohKnotClientJoinBuilder::join(ticket)
        .knot("home-hub")
        .rope_id("living-room-sensor")
        .connect()
        .await?;

    println!("Joined connection: {}", client.connection_id());
    
    // Create unidirectional data stream
    let mut stream = client.create_stream(
        "temp_sensor".to_string(),
        "temperature".to_string(),
        "telemetry".to_string(),
        "json".to_string(),
        std::collections::HashMap::new()
    ).await?;

    // Write binary frame payload
    stream.write_frame(1, 1000, b"{\"temperature\": 22.5}").await?;

    Ok(())
}
```
