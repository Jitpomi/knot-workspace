use iroh_knot::IrohKnotClientJoinBuilder;
use std::collections::HashMap;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: cargo run -p iroh-knot --example 02_p2p_client <CONNECTION_TICKET>");
        std::process::exit(1);
    }
    let ticket = &args[1];

    println!("[CLIENT] Connecting to host using ticket...");

    // 1. Establish secure QUIC connection and authenticate
    let client = IrohKnotClientJoinBuilder::join(ticket)
        .knot("home-session")
        .rope_id("temperature-sensor")
        .connect()
        .await?;

    println!("[CLIENT] Handshake approved. Connection ID: {}", client.connection_id());

    // 2. Open unidirectional data stream channel
    println!("[CLIENT] Negotiating 'temp_sensor' stream channel...");
    let mut stream = client.create_stream(
        "temp_sensor".to_string(),
        "temperature".to_string(),
        "telemetry".to_string(),
        "json".to_string(),
        HashMap::new(),
    ).await?;

    // 3. Write 5 telemetry frames to host
    for i in 0..5 {
        let payload = format!("{{\"temperature\": {}}}", 21.0 + (i as f32) * 0.4);
        println!("[CLIENT] Writing Frame #{}: {}", i, payload);
        stream.write_frame(1, (i * 1000) as u64, payload.as_bytes()).await?;
        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }

    println!("[CLIENT] Finished streaming frames. Exiting.");
    Ok(())
}
