use iroh_knot::IrohKnotClientJoinBuilder;
use knot_protocol::{ControlMessage, Envelope};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: cargo run -p iroh-knot --example 03_command_client <CONNECTION_TICKET>");
        std::process::exit(1);
    }
    let ticket = &args[1];

    println!("[CLIENT] Connecting to command host...");

    let client = IrohKnotClientJoinBuilder::join(ticket)
        .knot("home-session")
        .rope_id("living-room-sensor")
        .connect()
        .await?;

    println!("[CLIENT] Handshake approved. Waiting for commands over control channel...");

    let control_tx = client.control_tx();

    // Await incoming command control envelopes
    while let Some(env) = client.next_event().await {
        match env.payload {
            ControlMessage::Command { command_id, target_capability_id, action, payload } => {
                println!(
                    "[CLIENT] Received Command: id='{}', target='{}', action='{}', payload='{}'",
                    command_id, target_capability_id, action, payload
                );

                // Simulate processing command and send back Ack
                println!("[CLIENT] Processing command...");
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;

                println!("[CLIENT] Sending acknowledgment...");
                let ack_env = Envelope {
                    msg_id: format!("ack-{}", env.msg_id),
                    timestamp: knot_protocol::now_ms(),
                    source_rope_id: client.rope_id().to_string(),
                    connection_id: client.connection_id().to_string(),
                    requires_ack: false,
                    payload: ControlMessage::Event {
                        variant: "ack".to_string(),
                        data: format!("{{\"command_id\": \"{}\", \"status\": \"success\"}}", command_id),
                    },
                };
                
                if let Err(e) = control_tx.send(ack_env) {
                    eprintln!("[CLIENT] Failed to send acknowledgment: {:?}", e);
                }
            }
            _ => {
                println!("[CLIENT] Control event received: {:?}", env);
            }
        }
    }

    println!("[CLIENT] Control stream closed. Exiting.");
    Ok(())
}
