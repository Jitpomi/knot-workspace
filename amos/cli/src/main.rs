use clap::{Parser, Subcommand};
use amos_core::Core;
use std::sync::Arc;

#[derive(Parser)]
#[command(name = "amos")]
#[command(about = "Amos — Peer-to-peer AV Studio Core CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Starts the Director / AV mixer server
    Director {
        /// Display name for the director
        #[arg(short, long, default_value = "Director")]
        name: String,
        /// Data directory to store session databases
        #[arg(short, long, default_value = ".amos")]
        data_dir: String,
    },
    /// Connects to a running Director server as a participant
    Client {
        /// Ticket string printed by the director
        ticket: String,
        /// Display name for this participant
        #[arg(short, long, default_value = "Client")]
        name: String,
        /// Unique participant ID
        #[arg(short, long, default_value = "client-cli")]
        participant_id: String,
        /// Device type identifier
        #[arg(short, long, default_value = "CLI")]
        device: String,
        /// Session ID
        #[arg(short, long, default_value = "session-cli")]
        session_id: String,
        /// Data directory for client files
        #[arg(long, default_value = ".amos")]
        data_dir: String,
        /// Publish a simulated camera stream to the stage
        #[arg(short, long)]
        camera: bool,
        /// Publish a simulated microphone stream to the stage
        #[arg(short, long)]
        microphone: bool,
    },
}

struct CliDirectorListener;
impl amos_core::AmosDirectorListener for CliDirectorListener {
    fn on_client_connected(&self, client_id: String, participant_id: String, display_name: String, device_type: String) {
        println!("🚀 Client Connected: {} ({}) [ID: {}, Participant: {}]", display_name, device_type, client_id, participant_id);
    }

    fn on_client_disconnected(&self, client_id: String) {
        println!("❌ Client Disconnected: {}", client_id);
    }

    fn on_client_stream_configured(&self, client_id: String, stream_id: String, config: amos_core::StreamConfig) {
        println!("⚙️ Stream Configured for {}: ID {} ({:?} - {})", client_id, stream_id, config.source_type, config.name);
    }

    fn on_frame_received(&self, client_id: String, stream_id: String, frame_type: u8, timestamp_ms: u64, payload: Vec<u8>) {
        println!("📹 Received Frame from {}: Stream {}, Type {}, Size {} bytes, TS {}", client_id, stream_id, frame_type, payload.len(), timestamp_ms);
    }

    fn on_client_video_state_changed(&self, client_id: String, is_video_on: bool, is_screen_sharing: bool) {
        println!("📹 Client Video State: {} (Video: {}, Screen: {})", client_id, is_video_on, is_screen_sharing);
    }

    fn on_force_keyframe(&self, stream_id: String) {
        println!("🔑 Force Keyframe requested for stream: {}", stream_id);
    }

    fn on_custom_message(&self, client_id: String, variant: String, data: String) {
        println!("✉️ Custom Message from Client {}: [{}] {}", client_id, variant, data);
    }
}

struct CliEventListener;
impl amos_core::AmosEventListener for CliEventListener {
    fn on_force_keyframe(&self, stream_id: String) {
        println!("🔑 Host requested force keyframe on stream: {}", stream_id);
    }

    fn on_recording_state_changed(&self, is_recording: bool) {
        println!("⏺️ Recording State: {}", if is_recording { "ON" } else { "OFF" });
    }

    fn on_connection_status_changed(&self, connected: bool) {
        println!("🔌 Connection Status Changed: {}", if connected { "CONNECTED" } else { "DISCONNECTED" });
    }

    fn on_frame_received(&self, client_id: String, stream_id: String, frame_type: u8, timestamp_ms: u64, _payload: Vec<u8>) {
        println!("📹 Received Frame: Source {}, Stream {}, Type {}, TS {}", client_id, stream_id, frame_type, timestamp_ms);
    }

    fn on_host_info_changed(&self, producer_name: String, is_video_on: bool, is_screen_sharing: bool) {
        println!("👤 Host Info: {} (Video: {}, Screen: {})", producer_name, is_video_on, is_screen_sharing);
    }

    fn on_host_video_state_changed(&self, is_video_on: bool, is_screen_sharing: bool) {
        println!("👤 Host Video State Changed: (Video: {}, Screen: {})", is_video_on, is_screen_sharing);
    }

    fn on_client_connected(&self, client_id: String, participant_id: String, display_name: String, device_type: String) {
        println!("👥 Peer Connected: {} ({}) [ID: {}, Participant: {}]", display_name, device_type, client_id, participant_id);
    }

    fn on_client_disconnected(&self, client_id: String) {
        println!("👥 Peer Disconnected: {}", client_id);
    }

    fn on_client_video_state_changed(&self, client_id: String, is_video_on: bool, is_screen_sharing: bool) {
        println!("📹 Peer Video State Changed: {} (Video: {}, Screen: {})", client_id, is_video_on, is_screen_sharing);
    }

    fn on_talkback_changed(&self, enabled: bool) {
        println!("🎤 Talkback changed: {}", enabled);
    }

    fn on_prompter_changed(&self, text: String) {
        println!("📝 Prompter Text Update: \"{}\"", text);
    }

    fn on_tally_changed(&self, stream_id: String, is_live: bool, is_preview: bool) {
        println!("🚨 Tally Changed for stream {}: Live={}, Preview={}", stream_id, is_live, is_preview);
    }

    fn on_host_stream_configured(&self, stream_id: String, config: amos_core::StreamConfig) {
        println!("⚙️ Host Stream Configured: ID {} ({})", stream_id, config.name);
    }

    fn on_client_stream_configured(&self, client_id: String, stream_id: String, config: amos_core::StreamConfig) {
        println!("⚙️ Peer Stream Configured: Client {}, Stream ID {} ({})", client_id, stream_id, config.name);
    }

    fn on_sound_triggered(&self, sound_name: String, target_output: String) {
        println!("🔊 Sound Triggered: {} to {}", sound_name, target_output);
    }

    fn on_custom_message(&self, client_id: String, variant: String, data: String) {
        println!("✉️ Custom Message from {}: [{}] {}", client_id, variant, data);
    }
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Director { name, data_dir } => {
            let core = Core::new(data_dir).expect("Failed to initialize Amos core");
            println!("Node ID: {}", core.node_id());
            
            let listener = Arc::new(CliDirectorListener);
            let ticket = core.engine.start_director(name, listener).await
                .expect("Failed to start director");
            
            println!("\n🎫 Director ticket generated:");
            println!("{}", ticket);
            println!("\n🔊 Listening for incoming connections... Press Ctrl+C to stop.");
            
            let (tx, rx) = std::sync::mpsc::channel();
            ctrlc::set_handler(move || {
                tx.send(()).ok();
            }).expect("Error setting Ctrl-C handler");
            rx.recv().ok();
            
            println!("\nShutting down director.");
            core.engine.stop_director_or_client().await.ok();
        }
        Commands::Client { ticket, name, participant_id, device, session_id, data_dir, camera, microphone } => {
            let core = Core::new(data_dir).expect("Failed to initialize Amos core");
            println!("Node ID: {}", core.node_id());
            
            let listener = Arc::new(CliEventListener);
            core.engine.connect_to_director(ticket, participant_id, name, device, session_id, listener).await
                .expect("Failed to connect to director");
            
            println!("\n🔌 Connected to director. Listening for events... Press Ctrl+C to disconnect.");
            
            if camera {
                let core_clone = core.clone();
                tokio::spawn(async move {
                    let config = amos_core::StreamConfig {
                        stream_id: None,
                        source_type: "webcam".to_string(),
                        name: "CLI Camera Feed".to_string(),
                        codec: "h264".to_string(),
                        width: Some(1280),
                        height: Some(720),
                        audio_profile: None,
                        sample_rate: None,
                        channels: None,
                        echo_cancellation: None,
                        noise_suppression: None,
                    };
                    
                    let stream_id = core_clone.engine.publish_stream(config).await
                        .expect("Failed to publish stream");
                    println!("📹 Stream published: {}. Sending simulated frames at 30 FPS...", stream_id);
                    
                    let mut interval = tokio::time::interval(std::time::Duration::from_millis(33));
                    let start_time = std::time::Instant::now();
                    let mut frame_count: u64 = 0;
                    loop {
                        interval.tick().await;
                        let elapsed = start_time.elapsed().as_millis() as u64;
                        frame_count += 1;
                        let payload = format!("cli_camera_frame_{}_elapsed_{}", frame_count, elapsed).into_bytes();
                        let frame_type = if frame_count % 30 == 0 { 1 } else { 2 };
                        if core_clone.engine.write_frame(stream_id.clone(), frame_type, elapsed, payload).is_err() {
                            break;
                        }
                    }
                    println!("📹 Simulated camera stream stopped.");
                });
            }

            if microphone {
                let core_clone = core.clone();
                tokio::spawn(async move {
                    let config = amos_core::StreamConfig {
                        stream_id: None,
                        source_type: "microphone".to_string(),
                        name: "CLI Microphone Feed".to_string(),
                        codec: "opus".to_string(),
                        width: None,
                        height: None,
                        audio_profile: Some("voice".to_string()),
                        sample_rate: Some(48000),
                        channels: Some(1),
                        echo_cancellation: Some(true),
                        noise_suppression: Some(true),
                    };
                    
                    let stream_id = core_clone.engine.publish_stream(config).await
                        .expect("Failed to publish mic stream");
                    println!("🎤 Stream published: {}. Sending simulated audio packets at 50 packets/s...", stream_id);
                    
                    let mut interval = tokio::time::interval(std::time::Duration::from_millis(20));
                    let start_time = std::time::Instant::now();
                    let mut frame_count: u64 = 0;
                    loop {
                        interval.tick().await;
                        let elapsed = start_time.elapsed().as_millis() as u64;
                        frame_count += 1;
                        let payload = vec![0u8; 20];
                        let level = ((frame_count % 30) as u8) * 3 + 10;
                        if core_clone.engine.write_frame(stream_id.clone(), level, elapsed, payload).is_err() {
                            break;
                        }
                    }
                    println!("🎤 Simulated audio stream stopped.");
                });
            }

            let (tx, rx) = std::sync::mpsc::channel();
            ctrlc::set_handler(move || {
                tx.send(()).ok();
            }).expect("Error setting Ctrl-C handler");
            rx.recv().ok();
            
            println!("\nDisconnecting client.");
            core.engine.stop_director_or_client().await.ok();
        }
    }
}
