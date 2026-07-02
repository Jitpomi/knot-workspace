use iroh_knot::{IrohKnotHub, bind_endpoint, generate_ticket};
use knot_protocol::HubEvent;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 1. Bind local QUIC transport endpoint
    let endpoint = bind_endpoint().await?;
    println!("[HOST] Cryptographic Node ID: {}", endpoint.id());

    // 2. Generate sharing ticket
    let ticket = generate_ticket(&endpoint);
    println!("\n==========================================");
    println!("Session Connection Ticket:");
    println!("{}", ticket);
    println!("==========================================\n");

    // 3. Spawn Hub session router
    let data_dir = std::env::temp_dir().join("iroh_knot_host_example");
    let (_hub, mut events) = IrohKnotHub::spawn(
        endpoint,
        data_dir,
        || "{\"node_type\": \"reference_host\"}".to_string(),
    ).await?;

    println!("[HOST] Spawned Hub session router. Listening for incoming connections...");

    // 4. Dispatch events to console
    while let Some(event) = events.recv().await {
        match event {
            HubEvent::RopeConnected { rope_id, node_id, .. } => {
                println!("[HOST] Rope Connected: id='{}', authenticated_node='{}'", rope_id, node_id);
            }
            HubEvent::StreamOpened { rope_id, stream_id, topic, .. } => {
                println!("[HOST] Stream Opened: rope='{}', stream_id='{}', topic='{}'", rope_id, stream_id, topic);
            }
            HubEvent::FrameReceived { rope_id, stream_id, header, payload } => {
                println!(
                    "[HOST] Frame Received: rope='{}', stream='{}', seq={}, type={}, size={} bytes",
                    rope_id, stream_id, header.seq_num, header.frame_type, payload.len()
                );
                if let Ok(text) = std::str::from_utf8(&payload) {
                    println!("       Payload: {}", text);
                }
            }
            HubEvent::RopeDisconnected { rope_id } => {
                println!("[HOST] Rope Disconnected: id='{}'", rope_id);
            }
            _ => {
                println!("[HOST] Event: {:?}", event);
            }
        }
    }

    Ok(())
}
