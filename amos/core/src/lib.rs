#[cfg(target_os = "android")]
mod android;

use std::sync::Arc;
use std::path::PathBuf;
use tokio::runtime::{Builder, Runtime};

pub mod engine;

use crate::engine::AmosEngine;

// Define error taxonomy
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum AmosError {
    #[error("IO error: {message}")]
    Io { message: String },
    #[error("Network error: {message}")]
    Network { message: String },
    #[error("Serialization error: {message}")]
    Serialization { message: String },
    #[error("Invalid ticket: {message}")]
    InvalidTicket { message: String },
    #[error("Connection not established: {message}")]
    NotConnected { message: String },
    #[error("Stream not found: {message}")]
    StreamNotFound { message: String },
    #[error("Internal error: {message}")]
    Internal { message: String },
}

impl From<std::io::Error> for AmosError {
    fn from(e: std::io::Error) -> Self {
        Self::Io { message: e.to_string() }
    }
}

impl From<serde_json::Error> for AmosError {
    fn from(e: serde_json::Error) -> Self {
        Self::Serialization { message: e.to_string() }
    }
}

impl From<iroh::endpoint::WriteError> for AmosError {
    fn from(e: iroh::endpoint::WriteError) -> Self {
        Self::Network { message: e.to_string() }
    }
}

impl From<iroh::endpoint::ReadExactError> for AmosError {
    fn from(e: iroh::endpoint::ReadExactError) -> Self {
        Self::Network { message: e.to_string() }
    }
}

impl From<iroh::endpoint::ReadError> for AmosError {
    fn from(e: iroh::endpoint::ReadError) -> Self {
        Self::Network { message: e.to_string() }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, uniffi::Record)]
pub struct StreamConfig {
    pub stream_id: Option<String>,
    pub source_type: String,
    pub name: String,
    pub codec: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub audio_profile: Option<String>,
    pub sample_rate: Option<u32>,
    pub channels: Option<u8>,
    pub echo_cancellation: Option<bool>,
    pub noise_suppression: Option<bool>,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct StreamConfigMetadata {
    codec: String,
    width: Option<u32>,
    height: Option<u32>,
    audio_profile: Option<String>,
    sample_rate: Option<u32>,
    channels: Option<u8>,
    echo_cancellation: Option<bool>,
    noise_suppression: Option<bool>,
}

impl From<knot_protocol::StreamConfig> for StreamConfig {
    fn from(c: knot_protocol::StreamConfig) -> Self {
        let meta: StreamConfigMetadata = serde_json::from_str(&c.metadata)
            .unwrap_or_else(|_| StreamConfigMetadata {
                codec: "raw".to_string(),
                width: None,
                height: None,
                audio_profile: None,
                sample_rate: None,
                channels: None,
                echo_cancellation: None,
                noise_suppression: None,
            });

        Self {
            stream_id: c.stream_id,
            source_type: c.source_type,
            name: c.name,
            codec: meta.codec,
            width: meta.width,
            height: meta.height,
            audio_profile: meta.audio_profile,
            sample_rate: meta.sample_rate,
            channels: meta.channels,
            echo_cancellation: meta.echo_cancellation,
            noise_suppression: meta.noise_suppression,
        }
    }
}

impl From<StreamConfig> for knot_protocol::StreamConfig {
    fn from(c: StreamConfig) -> Self {
        let meta = StreamConfigMetadata {
            codec: c.codec,
            width: c.width,
            height: c.height,
            audio_profile: c.audio_profile,
            sample_rate: c.sample_rate,
            channels: c.channels,
            echo_cancellation: c.echo_cancellation,
            noise_suppression: c.noise_suppression,
        };
        let metadata = serde_json::to_string(&meta).unwrap_or_else(|_| "{}".to_string());

        knot_protocol::StreamConfig {
            stream_id: c.stream_id,
            source_type: c.source_type,
            name: c.name,
            metadata,
        }
    }
}

#[uniffi::export(callback_interface)]
pub trait AmosEventListener: Send + Sync {
    fn on_force_keyframe(&self, stream_id: String);
    fn on_recording_state_changed(&self, is_recording: bool);
    fn on_connection_status_changed(&self, connected: bool);
    fn on_frame_received(&self, client_id: String, stream_id: String, frame_type: u8, timestamp_ms: u64, payload: Vec<u8>);
    fn on_host_info_changed(&self, producer_name: String, is_video_on: bool, is_screen_sharing: bool);
    fn on_host_video_state_changed(&self, is_video_on: bool, is_screen_sharing: bool);
    fn on_client_connected(&self, client_id: String, participant_id: String, display_name: String, device_type: String);
    fn on_client_disconnected(&self, client_id: String);
    fn on_client_video_state_changed(&self, client_id: String, is_video_on: bool, is_screen_sharing: bool);
    fn on_talkback_changed(&self, enabled: bool);
    fn on_prompter_changed(&self, text: String);
    fn on_tally_changed(&self, stream_id: String, is_live: bool, is_preview: bool);
    fn on_host_stream_configured(&self, stream_id: String, config: StreamConfig);
    fn on_client_stream_configured(&self, client_id: String, stream_id: String, config: StreamConfig);
    fn on_sound_triggered(&self, sound_name: String, target_output: String);
    fn on_custom_message(&self, client_id: String, variant: String, data: String);
}

#[uniffi::export(callback_interface)]
pub trait AmosDirectorListener: Send + Sync {
    fn on_client_connected(&self, client_id: String, participant_id: String, display_name: String, device_type: String);
    fn on_client_disconnected(&self, client_id: String);
    fn on_client_stream_configured(&self, client_id: String, stream_id: String, config: StreamConfig);
    fn on_frame_received(&self, client_id: String, stream_id: String, frame_type: u8, timestamp_ms: u64, payload: Vec<u8>);
    fn on_client_video_state_changed(&self, client_id: String, is_video_on: bool, is_screen_sharing: bool);
    fn on_force_keyframe(&self, stream_id: String);
    fn on_custom_message(&self, client_id: String, variant: String, data: String);
}

#[derive(uniffi::Object)]
pub struct Core {
    runtime: Runtime,
    pub engine: Arc<AmosEngine>,
}

#[uniffi::export]
impl Core {
    #[uniffi::constructor]
    pub fn new(data_dir: String) -> Result<Arc<Self>, AmosError> {
        #[cfg(target_os = "android")]
        let runtime = Builder::new_multi_thread()
            .worker_threads(2)
            .enable_io()
            .enable_time()
            .build()
            .map_err(|e| AmosError::Internal {
                message: format!("failed to create Tokio runtime: {}", e),
            })?;
        
        #[cfg(not(target_os = "android"))]
        let runtime = Builder::new_multi_thread()
            .enable_all()
            .build()
            .map_err(|e| AmosError::Internal {
                message: format!("failed to create Tokio runtime: {}", e),
            })?;

        let data_path = PathBuf::from(data_dir);
        let engine = Arc::new(AmosEngine::new(data_path));

        Ok(Arc::new(Self {
            runtime,
            engine,
        }))
    }

    pub fn start_director(&self, display_name: String, listener: Box<dyn AmosDirectorListener>) -> Result<String, AmosError> {
        self.runtime.block_on(self.engine.start_director(display_name, Arc::from(listener)))
    }

    pub fn stop_director(&self) -> Result<(), AmosError> {
        self.runtime.block_on(self.engine.stop_director_or_client())
    }

    pub fn disconnect_from_director(&self) -> Result<(), AmosError> {
        self.runtime.block_on(self.engine.stop_director_or_client())
    }

    pub fn connect_to_director(
        &self,
        ticket: String,
        participant_id: String,
        display_name: String,
        device_type: String,
        session_id: String,
        listener: Box<dyn AmosEventListener>,
    ) -> Result<(), AmosError> {
        self.runtime.block_on(self.engine.connect_to_director(
            ticket,
            participant_id,
            display_name,
            device_type,
            session_id,
            Arc::from(listener),
        ))
    }

    pub fn request_keyframe(&self, client_id: String, stream_id: String) -> Result<(), AmosError> {
        self.engine.request_keyframe(client_id, stream_id)
    }

    pub fn request_keyframe_from_host(&self, stream_id: String) -> Result<(), AmosError> {
        self.engine.request_keyframe_from_host(stream_id)
    }

    pub fn set_recording_state(&self, is_recording: bool) -> Result<(), AmosError> {
        self.engine.set_recording_state(is_recording)
    }

    pub fn publish_stream(&self, config: StreamConfig) -> Result<String, AmosError> {
        self.runtime.block_on(self.engine.publish_stream(config))
    }

    pub fn write_frame(&self, stream_id: String, frame_type: u8, timestamp_ms: u64, payload: Vec<u8>) -> Result<(), AmosError> {
        self.engine.write_frame(stream_id, frame_type, timestamp_ms, payload)
    }

    pub fn close_stream(&self, stream_id: String) -> Result<(), AmosError> {
        self.engine.close_stream(stream_id)
    }

    pub fn set_producer_video_state(&self, is_video_on: bool, is_screen_sharing: bool) -> Result<(), AmosError> {
        self.engine.set_producer_video_state(is_video_on, is_screen_sharing)
    }

    pub fn set_participant_video_state(&self, is_video_on: bool, is_screen_sharing: bool) -> Result<(), AmosError> {
        self.engine.set_participant_video_state(is_video_on, is_screen_sharing)
    }

    pub fn set_talkback_state(&self, client_id: String, enabled: bool) -> Result<(), AmosError> {
        self.engine.set_talkback_state(client_id, enabled)
    }

    pub fn set_tally_state(&self, client_id: String, stream_id: String, is_live: bool, is_preview: bool) -> Result<(), AmosError> {
        self.engine.set_tally_state(client_id, stream_id, is_live, is_preview)
    }

    pub fn configure_host_stream(&self, stream_id: String, config: StreamConfig) -> Result<(), AmosError> {
        self.engine.configure_host_stream(stream_id, config)
    }

    pub fn trigger_sound(&self, client_id: String, sound_name: String, target_output: String) -> Result<(), AmosError> {
        self.engine.trigger_sound(client_id, sound_name, target_output)
    }

    pub fn broadcast_sound(&self, sound_name: String, target_output: String) -> Result<(), AmosError> {
        self.engine.broadcast_sound(sound_name, target_output)
    }

    pub fn update_prompter_text(&self, text: String) -> Result<(), AmosError> {
        self.engine.broadcast_prompter_text(text)
    }

    pub fn export_recording(&self, db_path: String, output_h264_path: String) -> Result<(), AmosError> {
        self.engine.export_recording(db_path, output_h264_path)
    }

    pub fn send_custom_message(&self, client_id: String, variant: String, data: String) -> Result<(), AmosError> {
        self.engine.send_custom_message(client_id, variant, data)
    }

    pub fn broadcast_custom_message(&self, variant: String, data: String) -> Result<(), AmosError> {
        self.engine.broadcast_custom_message(variant, data)
    }

    pub fn send_custom_message_to_host(&self, variant: String, data: String) -> Result<(), AmosError> {
        self.engine.send_custom_message_to_host(variant, data)
    }

    pub fn node_id(&self) -> String {
        self.engine.node_id()
    }
}

#[cfg(test)]
mod base64_tests {
    use crate::engine::base64_url_encode;
    use knot_protocol::base64_url_decode;

    #[test]
    fn test_base64_url_roundtrip() {
        let test_cases = vec![
            vec![],
            vec![0],
            vec![255],
            vec![1, 2, 3],
            vec![0, 0, 0],
            vec![10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
            (0..100).collect::<Vec<u8>>(),
        ];

        for case in test_cases {
            let encoded = base64_url_encode(&case);
            let decoded = base64_url_decode(&encoded).unwrap();
            assert_eq!(case, decoded);
        }
    }
}

uniffi::setup_scaffolding!();
