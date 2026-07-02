use iroh_knot::{IrohKnotHub, IrohKnotClientJoinBuilder, bind_endpoint, generate_ticket, unpack_addr, base64_url_decode};
use knot_protocol::HubEvent;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

fn unique_temp_dir() -> std::path::PathBuf {
    let name = format!("iroh_knot_test_db_{}", std::time::Instant::now().elapsed().as_nanos());
    std::env::temp_dir().join(name)
}

#[tokio::test]
async fn test_ticket_serialization_flow() -> anyhow::Result<()> {
    let endpoint = bind_endpoint().await?;
    let ticket = generate_ticket(&endpoint);
    
    let decoded = base64_url_decode(&ticket).map_err(|e| anyhow::anyhow!(e))?;
    let unpacked = unpack_addr(&decoded).map_err(|e| anyhow::anyhow!(e))?;
    
    assert_eq!(unpacked.id, endpoint.id());
    Ok(())
}

#[tokio::test]
async fn test_end_to_end_handshake_and_streaming() -> anyhow::Result<()> {
    let host_ep = bind_endpoint().await?;
    let ticket = generate_ticket(&host_ep);

    let frame_received = Arc::new(Mutex::new(None::<(String, Vec<u8>)>));
    let frame_received_clone = frame_received.clone();

    // Spawn Hub router
    let (_hub, mut events) = IrohKnotHub::spawn(
        host_ep,
        unique_temp_dir(),
        || "{\"node\": \"host\"}".to_string(),
    ).await?;

    // Spawn event listener task
    tokio::spawn(async move {
        while let Some(ev) = events.recv().await {
            if let HubEvent::FrameReceived { stream_id, payload, .. } = ev {
                let mut lock = frame_received_clone.lock().unwrap();
                *lock = Some((stream_id, payload));
            }
        }
    });

    // Connect Client
    let client = IrohKnotClientJoinBuilder::join(&ticket)
        .knot("living-room")
        .rope_id("temperature-sensor")
        .connect()
        .await?;

    assert_eq!(client.rope_id(), "living-room_temperature-sensor");

    // Create telemetry stream
    let mut stream = client.create_stream(
        "temp_channel".to_string(),
        "temp_cap".to_string(),
        "telemetry".to_string(),
        "json".to_string(),
        HashMap::new(),
    ).await?;

    // Write binary frame payload
    let payload = b"{\"value\": 21.8}";
    stream.write_frame(1, 100, payload).await?;

    // Await delivery with a polling loop
    let mut received = None;
    for _ in 0..30 {
        tokio::time::sleep(Duration::from_millis(100)).await;
        let lock = frame_received.lock().unwrap();
        if lock.is_some() {
            received = lock.clone();
            break;
        }
    }

    let (received_stream_id, received_payload) = received.expect("Expected to receive frame on hub within 3 seconds");
    assert_eq!(received_stream_id, "temp_channel");
    assert_eq!(received_payload, payload);

    Ok(())
}
