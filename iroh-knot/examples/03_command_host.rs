use iroh_knot::{IrohKnotHub, bind_endpoint, generate_ticket};
use knot_protocol::{HubEvent, Envelope, ControlMessage};
use std::time::Duration;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let endpoint = bind_endpoint().await?;
    let ticket = generate_ticket(&endpoint);

    println!("[HOST] Spawned Hub. Connection ticket:");
    println!("{}\n", ticket);

    let data_dir = std::env::temp_dir().join("iroh_knot_command_host_example");
    let (_hub, mut events) = IrohKnotHub::spawn(
        endpoint,
        data_dir,
        || "{\"node\": \"host\"}".to_string(),
    ).await?;

    while let Some(event) = events.recv().await {
        match event {
            HubEvent::RopeConnected { rope_id, control_sender, .. } => {
                println!("[HOST] Client '{}' connected.", rope_id);
                
                // Spawn a task to send a command after 1.5 seconds
                let rope_id_clone = rope_id.clone();
                tokio::spawn(async move {
                    tokio::time::sleep(Duration::from_millis(1500)).await;
                    println!("[HOST] Sending reboot command to '{}'...", rope_id_clone);
                    
                    let cmd_env = Envelope {
                        msg_id: "req-reboot-99".to_string(),
                        timestamp: knot_protocol::now_ms(),
                        source_rope_id: "host".to_string(),
                        connection_id: "conn_0".to_string(),
                        requires_ack: true,
                        payload: ControlMessage::Command {
                            command_id: "cmd-99".to_string(),
                            target_capability_id: "system".to_string(),
                            action: "reboot".to_string(),
                            payload: "{\"delay_seconds\": 5}".to_string(),
                        },
                    };
                    
                    if let Err(e) = control_sender.send(cmd_env) {
                        eprintln!("[HOST] Failed to send command: {:?}", e);
                    }
                });
            }
            HubEvent::EventReceived { rope_id, variant, data } => {
                if variant == "ack" {
                    println!("[HOST] Acknowledgment received from '{}': {}", rope_id, data);
                } else {
                    println!("[HOST] Custom event from '{}': variant='{}', data='{}'", rope_id, variant, data);
                }
            }
            HubEvent::RopeDisconnected { rope_id } => {
                println!("[HOST] Client '{}' disconnected.", rope_id);
            }
            _ => {}
        }
    }

    Ok(())
}
