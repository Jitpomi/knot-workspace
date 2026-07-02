use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use std::path::PathBuf;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};
use iroh::{Endpoint, endpoint::Connection, EndpointAddr};
use tokio_util::codec::{FramedWrite, LengthDelimitedCodec};
use futures_util::SinkExt;

use knot_protocol::{ControlMessage, KnotHub, KnotClient};
use crate::{AmosDirectorListener, AmosEventListener, AmosError, StreamConfig};

#[derive(Debug)]
pub enum StreamCmd {
    SendFrame { frame_type: u8, timestamp_ms: u64, payload: Vec<u8> },
    Close,
}

#[derive(Debug, Clone)]
pub struct ConnectedClient {
    pub client_id: String,
    pub participant_id: String,
    pub display_name: String,
    pub device_type: String,
    pub control_sender: UnboundedSender<ControlMessage>,
}

#[derive(Debug)]
pub struct CoreState {
    pub endpoint: Option<Endpoint>,
    pub router: Option<KnotHub>,
    pub connection: Option<Connection>,
    pub client_control_sender: Option<UnboundedSender<ControlMessage>>,
    pub connected_clients: HashMap<String, ConnectedClient>,
    pub active_streams: HashMap<String, UnboundedSender<StreamCmd>>,
    pub stream_counter: u64,
    pub producer_name: String,
    pub is_video_on: bool,
    pub is_screen_sharing: bool,
}
pub struct AmosEngine {
    pub data_dir: PathBuf,
    pub state: Arc<Mutex<CoreState>>,
}

impl AmosEngine {
    pub fn new(data_dir: PathBuf) -> Self {
        let state = Arc::new(Mutex::new(CoreState {
            endpoint: None,
            router: None,
            connection: None,
            client_control_sender: None,
            connected_clients: HashMap::new(),
            active_streams: HashMap::new(),
            stream_counter: 0,
            producer_name: "".to_string(),
            is_video_on: false,
            is_screen_sharing: false,
        }));
        Self { data_dir, state }
    }

    pub async fn start_director(&self, display_name: String, listener: Arc<dyn AmosDirectorListener>) -> Result<String, AmosError> {
        let mut state = self.state.lock().unwrap();
        state.producer_name = display_name;
        
        if state.endpoint.is_some() {
            return Err(AmosError::Internal {
                message: "Director already running".to_string(),
            });
        }

        // Create directories
        tokio::fs::create_dir_all(&self.data_dir).await?;

        // Bind endpoint
        let endpoint = knot_protocol::bind_endpoint().await
            .map_err(|e| AmosError::Network { message: e.to_string() })?;

        let state_for_meta = self.state.clone();
        let (hub, mut hub_events) = KnotHub::spawn(endpoint.clone(), self.data_dir.clone(), move || {
            let state = state_for_meta.lock().unwrap();
            serde_json::json!({
                "producer_name": state.producer_name,
                "is_video_on": state.is_video_on,
                "is_screen_sharing": state.is_screen_sharing,
            }).to_string()
        }).await.map_err(|e| AmosError::Network { message: e.to_string() })?;

        // Spawn a background event loop task to dispatch KnotHub events to listener
        let state_clone = self.state.clone();
        let listener_clone = listener.clone();
        tokio::spawn(async move {
            use knot_protocol::HubEvent;
            while let Some(event) = hub_events.recv().await {
                match event {
                    HubEvent::RopeConnected {
                        rope_id,
                        knot_id,
                        display_name,
                        rope_type,
                        metadata,
                        control_sender,
                    } => {
                        let client_id = rope_id.clone();
                        let participant_id = knot_id.clone();
                        println!("Client registered in core: {} ({}) under identity {}", display_name, rope_type, participant_id);
                        listener_clone.on_client_connected(client_id.clone(), participant_id.clone(), display_name.clone(), rope_type.clone());

                        // 1. Notify the new client about all ALREADY connected clients!
                        {
                            let state = state_clone.lock().unwrap();
                            for (existing_id, existing_client) in state.connected_clients.iter() {
                                let payload = serde_json::json!({
                                    "participant_id": existing_client.participant_id,
                                    "display_name": existing_client.display_name,
                                    "device_type": existing_client.device_type,
                                    "metadata": "{}",
                                }).to_string();

                                let msg = ControlMessage::KnotEvent {
                                    rope_id: existing_id.clone(),
                                    variant: "client_connected".to_string(),
                                    data: payload,
                                };
                                let _ = control_sender.send(msg);
                            }
                        }

                        // 2. Broadcast the new client to all OTHER connected clients!
                        {
                            let state = state_clone.lock().unwrap();
                            for existing_client in state.connected_clients.values() {
                                let payload = serde_json::json!({
                                    "participant_id": participant_id.clone(),
                                    "display_name": display_name.clone(),
                                    "device_type": rope_type.clone(),
                                    "metadata": metadata.clone(),
                                }).to_string();

                                let msg = ControlMessage::KnotEvent {
                                    rope_id: client_id.clone(),
                                    variant: "client_connected".to_string(),
                                    data: payload,
                                };
                                let _ = existing_client.control_sender.send(msg);
                            }
                        }

                        // 3. Register the client locally
                        let mut state = state_clone.lock().unwrap();
                        state.connected_clients.insert(client_id.clone(), ConnectedClient {
                            client_id: client_id.clone(),
                            participant_id,
                            display_name,
                            device_type: rope_type,
                            control_sender,
                        });
                    }
                    HubEvent::RopeDisconnected { rope_id } => {
                        let client_id = rope_id;
                        println!("Client disconnected in core: {}", client_id);
                        listener_clone.on_client_disconnected(client_id.clone());

                        // Broadcast disconnection to other clients
                        let clients = {
                            let state = state_clone.lock().unwrap();
                            state.connected_clients.values().cloned().collect::<Vec<_>>()
                        };
                        for client in clients {
                            if client.client_id != client_id {
                                let msg = ControlMessage::KnotEvent {
                                    rope_id: client_id.clone(),
                                    variant: "client_disconnected".to_string(),
                                    data: "{}".to_string(),
                                };
                                let _ = client.control_sender.send(msg);
                            }
                        }

                        let mut state = state_clone.lock().unwrap();
                        state.connected_clients.remove(&client_id);
                    }
                    HubEvent::RopeStreamConfigured { rope_id, stream_id, config } => {
                        let client_id = rope_id;
                        listener_clone.on_client_stream_configured(client_id.clone(), stream_id.clone(), config.clone().into());

                        // Broadcast the client's stream configuration to all OTHER connected clients!
                        let clients = {
                            let state = state_clone.lock().unwrap();
                            state.connected_clients.values().cloned().collect::<Vec<_>>()
                        };
                        for client in clients {
                            if client.client_id != client_id {
                                let payload = serde_json::to_string(&config).unwrap_or_default();
                                let msg = ControlMessage::KnotEvent {
                                    rope_id: client_id.clone(),
                                    variant: "client_stream_configured".to_string(),
                                    data: payload,
                                };
                                let _ = client.control_sender.send(msg);
                            }
                        }
                    }
                    HubEvent::FrameReceived { rope_id, stream_id, frame_type, timestamp_ms, payload } => {
                        let client_id = rope_id;
                        listener_clone.on_frame_received(client_id.clone(), stream_id.clone(), frame_type, timestamp_ms, payload.clone());

                        // Broadcast to other peers (KnotBinaryEvent)
                        let clients = {
                            let state = state_clone.lock().unwrap();
                            state.connected_clients.values().cloned().collect::<Vec<_>>()
                        };
                        let metadata = serde_json::json!({
                            "stream_id": stream_id,
                            "frame_type": frame_type,
                            "timestamp_ms": timestamp_ms,
                        }).to_string();

                        for client in clients {
                            if client.client_id != client_id {
                                let msg = ControlMessage::KnotBinaryEvent {
                                    rope_id: client_id.clone(),
                                    variant: "client_frame".to_string(),
                                    metadata: metadata.clone(),
                                    payload: payload.clone(),
                                };
                                let _ = client.control_sender.send(msg);
                            }
                        }
                    }
                    HubEvent::EventReceived { rope_id, variant, data } => {
                        let client_id = rope_id;
                        match variant.as_str() {
                            "video_state" => {
                                #[derive(serde::Deserialize)]
                                struct VideoStatePayload {
                                    is_video_on: bool,
                                    is_screen_sharing: bool,
                                }
                                if let Ok(payload) = serde_json::from_str::<VideoStatePayload>(&data) {
                                    listener_clone.on_client_video_state_changed(client_id.clone(), payload.is_video_on, payload.is_screen_sharing);

                                    // Broadcast to other peers
                                    let clients = {
                                        let state = state_clone.lock().unwrap();
                                        state.connected_clients.values().cloned().collect::<Vec<_>>()
                                    };
                                    for client in clients {
                                        if client.client_id != client_id {
                                            let _ = client.control_sender.send(ControlMessage::KnotEvent {
                                                rope_id: client_id.clone(),
                                                variant: variant.clone(),
                                                data: data.clone(),
                                            });
                                        }
                                    }
                                }
                            }
                            "force_keyframe" => {
                                #[derive(serde::Deserialize)]
                                struct ForceKeyframePayload {
                                    stream_id: String,
                                }
                                if let Ok(payload) = serde_json::from_str::<ForceKeyframePayload>(&data) {
                                    if payload.stream_id == "host" {
                                        listener_clone.on_force_keyframe("host".to_string());
                                    }
                                }
                            }
                            _ => {
                                listener_clone.on_custom_message(client_id.clone(), variant.clone(), data.clone());

                                // Broadcast to other peers (KnotEvent)
                                let clients = {
                                    let state = state_clone.lock().unwrap();
                                    state.connected_clients.values().cloned().collect::<Vec<_>>()
                                };
                                for client in clients {
                                    if client.client_id != client_id {
                                        let _ = client.control_sender.send(ControlMessage::KnotEvent {
                                            rope_id: client_id.clone(),
                                            variant: variant.clone(),
                                            data: data.clone(),
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        });

        // Wait for relay/address resolution (up to 3 seconds)
        let _ = tokio::time::timeout(
            std::time::Duration::from_secs(3),
            endpoint.online()
        ).await;

        let addr = endpoint.addr();
        let packed = pack_addr(&addr);
        let ticket = base64_url_encode(&packed);

        state.endpoint = Some(endpoint);
        state.router = Some(hub);

        Ok(ticket)
    }

    pub async fn stop_director_or_client(&self) -> Result<(), AmosError> {
        let mut state = self.state.lock().unwrap();
        
        if let Some(router) = state.router.take() {
            router.shutdown().await
                .map_err(|e| AmosError::Network { message: e.to_string() })?;
        }
        if let Some(endpoint) = state.endpoint.take() {
            endpoint.close().await;
        }
        state.connected_clients.clear();
        state.connection = None;
        state.client_control_sender = None;
        Ok(())
    }

    pub async fn connect_to_director(
        &self,
        ticket: String,
        participant_id: String,
        display_name: String,
        device_type: String,
        session_id: String,
        listener: Arc<dyn AmosEventListener>,
    ) -> Result<(), AmosError> {
        let endpoint = {
            let mut state = self.state.lock().unwrap();
            if state.endpoint.is_none() {
                let ep = knot_protocol::bind_endpoint().await
                    .map_err(|e| AmosError::Network { message: e.to_string() })?;
                state.endpoint = Some(ep.clone());
                ep
            } else {
                state.endpoint.clone().unwrap()
            }
        };

        println!("Connecting to director with ticket: {}", ticket);

        let (is_video_on, is_screen_sharing) = {
            let state = self.state.lock().unwrap();
            (state.is_video_on, state.is_screen_sharing)
        };

        let metadata = serde_json::json!({
            "is_video_on": is_video_on,
            "is_screen_sharing": is_screen_sharing,
        }).to_string();

        let mut client = KnotClient::builder(&endpoint)
            .hub_ticket(ticket)
            .knot_id(participant_id)
            .display_name(display_name)
            .rope_type(device_type)
            .session_id(session_id)
            .metadata(metadata)
            .connect()
            .await
            .map_err(|e| AmosError::Network { message: format!("handshake failed: {}", e) })?;

        let conn = client.connection().clone();
        let tx = client.control_tx();
        let hub_metadata = client.hub_metadata().to_string();

        #[derive(serde::Deserialize)]
        struct HandshakeMeta {
            producer_name: String,
            is_video_on: bool,
            is_screen_sharing: bool,
        }
        let meta: HandshakeMeta = serde_json::from_str(&hub_metadata).unwrap_or_else(|_| HandshakeMeta {
            producer_name: "".to_string(),
            is_video_on: false,
            is_screen_sharing: false,
        });

        println!("Handshake approved.");

        // Trigger connection success
        listener.on_connection_status_changed(true);
        listener.on_host_info_changed(meta.producer_name, meta.is_video_on, meta.is_screen_sharing);

        // Spawn a control stream reader task to handle incoming commands from Host
        let listener_arc = Arc::new(Mutex::new(Some(listener)));
        let listener_clone = listener_arc.clone();
        tokio::spawn(async move {
            while let Some(msg) = client.next_event().await {
                match msg {
                    ControlMessage::Event { variant, data } => {
                        let guard = listener_clone.lock().unwrap();
                        if let Some(ref l) = *guard {
                            match variant.as_str() {
                                "force_keyframe" => {
                                    #[derive(serde::Deserialize)]
                                    struct ForceKeyframePayload {
                                        stream_id: String,
                                    }
                                    if let Ok(payload) = serde_json::from_str::<ForceKeyframePayload>(&data) {
                                        l.on_force_keyframe(payload.stream_id);
                                    }
                                }
                                "recording_state" => {
                                    #[derive(serde::Deserialize)]
                                    struct RecordingStatePayload {
                                        is_recording: bool,
                                    }
                                    if let Ok(payload) = serde_json::from_str::<RecordingStatePayload>(&data) {
                                        l.on_recording_state_changed(payload.is_recording);
                                    }
                                }
                                "host_video_state" => {
                                    #[derive(serde::Deserialize)]
                                    struct HostVideoStatePayload {
                                        is_video_on: bool,
                                        is_screen_sharing: bool,
                                    }
                                    if let Ok(payload) = serde_json::from_str::<HostVideoStatePayload>(&data) {
                                        l.on_host_video_state_changed(payload.is_video_on, payload.is_screen_sharing);
                                    }
                                }
                                "talkback" => {
                                    #[derive(serde::Deserialize)]
                                    struct TalkbackPayload {
                                        enabled: bool,
                                    }
                                    if let Ok(payload) = serde_json::from_str::<TalkbackPayload>(&data) {
                                        l.on_talkback_changed(payload.enabled);
                                    }
                                }
                                "prompter" => {
                                    #[derive(serde::Deserialize)]
                                    struct PrompterPayload {
                                        text: String,
                                    }
                                    if let Ok(payload) = serde_json::from_str::<PrompterPayload>(&data) {
                                        l.on_prompter_changed(payload.text);
                                    }
                                }
                                "tally" => {
                                    #[derive(serde::Deserialize)]
                                    struct TallyPayload {
                                        stream_id: String,
                                        is_live: bool,
                                        is_preview: bool,
                                    }
                                    if let Ok(payload) = serde_json::from_str::<TallyPayload>(&data) {
                                        l.on_tally_changed(payload.stream_id, payload.is_live, payload.is_preview);
                                    }
                                }
                                "host_stream_configured" => {
                                    if let Ok(config) = serde_json::from_str::<knot_protocol::StreamConfig>(&data) {
                                        let stream_id = config.stream_id.clone().unwrap_or_default();
                                        l.on_host_stream_configured(stream_id, config.into());
                                    }
                                }
                                "sound_trigger" => {
                                    #[derive(serde::Deserialize)]
                                    struct SoundTriggerPayload {
                                        sound_name: String,
                                        target_output: String,
                                    }
                                    if let Ok(payload) = serde_json::from_str::<SoundTriggerPayload>(&data) {
                                        l.on_sound_triggered(payload.sound_name, payload.target_output);
                                    }
                                }
                                _ => {
                                    l.on_custom_message("host".to_string(), variant, data);
                                }
                            }
                        }
                    }
                    ControlMessage::KnotEvent { rope_id, variant, data } => {
                        let client_id = rope_id;
                        let guard = listener_clone.lock().unwrap();
                        if let Some(ref l) = *guard {
                            match variant.as_str() {
                                "client_connected" => {
                                    #[derive(serde::Deserialize)]
                                    #[allow(dead_code)]
                                    struct ConnectedPayload {
                                        participant_id: String,
                                        display_name: String,
                                        device_type: String,
                                        metadata: String,
                                    }
                                    if let Ok(payload) = serde_json::from_str::<ConnectedPayload>(&data) {
                                        l.on_client_connected(client_id, payload.participant_id, payload.display_name, payload.device_type);
                                    }
                                }
                                "client_disconnected" => {
                                    l.on_client_disconnected(client_id);
                                }
                                "video_state" => {
                                    #[derive(serde::Deserialize)]
                                    struct VideoStatePayload {
                                        is_video_on: bool,
                                        is_screen_sharing: bool,
                                    }
                                    if let Ok(payload) = serde_json::from_str::<VideoStatePayload>(&data) {
                                        l.on_client_video_state_changed(client_id, payload.is_video_on, payload.is_screen_sharing);
                                    }
                                }
                                "client_stream_configured" => {
                                    if let Ok(config) = serde_json::from_str::<knot_protocol::StreamConfig>(&data) {
                                        let stream_id = config.stream_id.clone().unwrap_or_default();
                                        l.on_client_stream_configured(client_id, stream_id, config.into());
                                    }
                                }
                                _ => {
                                    l.on_custom_message(client_id, variant, data);
                                }
                            }
                        }
                    }
                    ControlMessage::BinaryEvent { variant, metadata, payload } => {
                        let guard = listener_clone.lock().unwrap();
                        if let Some(ref l) = *guard {
                            match variant.as_str() {
                                "host_frame" => {
                                    #[derive(serde::Deserialize)]
                                    struct HostFramePayload {
                                        stream_id: String,
                                        frame_type: u8,
                                        timestamp_ms: u64,
                                    }
                                    if let Ok(meta) = serde_json::from_str::<HostFramePayload>(&metadata) {
                                        l.on_frame_received("host".to_string(), meta.stream_id, meta.frame_type, meta.timestamp_ms, payload);
                                    }
                                }
                                _ => {
                                    // Custom binary event handler if any
                                }
                            }
                        }
                    }
                    ControlMessage::KnotBinaryEvent { rope_id, variant, metadata, payload } => {
                        let client_id = rope_id;
                        let guard = listener_clone.lock().unwrap();
                        if let Some(ref l) = *guard {
                            match variant.as_str() {
                                "client_frame" => {
                                    #[derive(serde::Deserialize)]
                                    struct ClientFramePayload {
                                        stream_id: String,
                                        frame_type: u8,
                                        timestamp_ms: u64,
                                    }
                                    if let Ok(meta) = serde_json::from_str::<ClientFramePayload>(&metadata) {
                                        l.on_frame_received(client_id, meta.stream_id, meta.frame_type, meta.timestamp_ms, payload);
                                    }
                                }
                                _ => {
                                    // Custom participant binary event handler
                                }
                            }
                        }
                    }
                    ControlMessage::Pong { .. } => {
                        // Pong received
                    }
                    _ => {}
                }
            }

            // Notify native UI of disconnection
            let guard = listener_clone.lock().unwrap();
            if let Some(ref l) = *guard {
                l.on_connection_status_changed(false);
            }
        });

        // Store connection and sender channel
        let mut state = self.state.lock().unwrap();
        state.connection = Some(conn);
        state.client_control_sender = Some(tx);

        Ok(())
    }

    pub fn request_keyframe(&self, client_id: String, stream_id: String) -> Result<(), AmosError> {
        let client = {
            let state = self.state.lock().unwrap();
            state.connected_clients.get(&client_id).cloned().ok_or_else(|| AmosError::Internal {
                message: format!("client {} not connected", client_id),
            })?
        };

        let data = serde_json::json!({ "stream_id": stream_id }).to_string();
        let msg = ControlMessage::Event {
            variant: "force_keyframe".to_string(),
            data,
        };

        client.control_sender.send(msg)
            .map_err(|e| AmosError::Internal { message: e.to_string() })?;

        Ok(())
    }

    pub fn request_keyframe_from_host(&self, stream_id: String) -> Result<(), AmosError> {
        let sender = {
            let state = self.state.lock().unwrap();
            state.client_control_sender.clone()
        };
        if let Some(tx) = sender {
            let data = serde_json::json!({ "stream_id": stream_id }).to_string();
            let msg = ControlMessage::Event {
                variant: "force_keyframe".to_string(),
                data,
            };
            let _ = tx.send(msg).map_err(|e| AmosError::Internal { message: e.to_string() })?;
        }
        Ok(())
    }

    pub fn set_recording_state(&self, is_recording: bool) -> Result<(), AmosError> {
        let clients = {
            let state = self.state.lock().unwrap();
            state.connected_clients.values().cloned().collect::<Vec<_>>()
        };

        let data = serde_json::json!({ "is_recording": is_recording }).to_string();
        for client in clients {
            let msg = ControlMessage::Event {
                variant: "recording_state".to_string(),
                data: data.clone(),
            };
            let _ = client.control_sender.send(msg);
        }

        Ok(())
    }

    pub async fn publish_stream(&self, mut config: StreamConfig) -> Result<String, AmosError> {
        let conn_opt = {
            let state = self.state.lock().unwrap();
            state.connection.clone()
        };

        let (stream_id, tx, mut rx) = {
            let mut state = self.state.lock().unwrap();
            state.stream_counter += 1;
            let stream_id = state.stream_counter.to_string();
            config.stream_id = Some(stream_id.clone());
            let (tx, rx) = unbounded_channel::<StreamCmd>();
            (stream_id, tx, rx)
        };

        if let Some(conn) = conn_opt {
            // Client media stream publisher task
            // Open unidirectional media stream
            let send = conn.open_uni().await
                .map_err(|e| AmosError::Network { message: format!("failed to open unidirectional stream: {}", e) })?;

            let mut framed_write = FramedWrite::new(send, LengthDelimitedCodec::new());

            // Serialize config to JSON
            let config_bytes = serde_json::to_vec(&config)?;

            // Write length-prefixed JSON config header
            framed_write.send(bytes::Bytes::from(config_bytes)).await?;

            tokio::spawn(async move {
                while let Some(cmd) = rx.recv().await {
                    match cmd {
                        StreamCmd::SendFrame { frame_type, timestamp_ms, payload } => {
                            let mut packet = Vec::with_capacity(payload.len() + 9);
                            packet.push(frame_type);
                            packet.extend_from_slice(&timestamp_ms.to_be_bytes());
                            packet.extend_from_slice(&payload);
                            if framed_write.send(bytes::Bytes::from(packet)).await.is_err() {
                                break;
                            }
                        }
                        StreamCmd::Close => {
                            break;
                        }
                    }
                }
            });
        } else {
            // Host/Director stream publisher task (Broadcasts HostFrame messages)
            let state_clone = self.state.clone();
            let stream_id_clone = stream_id.clone();
            tokio::spawn(async move {
                while let Some(cmd) = rx.recv().await {
                    match cmd {
                        StreamCmd::SendFrame { frame_type, timestamp_ms, payload } => {
                            let clients = {
                                let state = state_clone.lock().unwrap();
                                state.connected_clients.values().cloned().collect::<Vec<_>>()
                            };
                            let metadata = serde_json::json!({
                                "stream_id": stream_id_clone.clone(),
                                "frame_type": frame_type,
                                "timestamp_ms": timestamp_ms,
                            }).to_string();

                            for client in clients {
                                let msg = ControlMessage::BinaryEvent {
                                    variant: "host_frame".to_string(),
                                    metadata: metadata.clone(),
                                    payload: payload.clone(),
                                };
                                let _ = client.control_sender.send(msg);
                            }
                        }
                        StreamCmd::Close => {
                            break;
                        }
                    }
                }
            });
        }

        {
            let mut state = self.state.lock().unwrap();
            state.active_streams.insert(stream_id.clone(), tx);
        }

        Ok(stream_id)
    }

    pub fn write_frame(&self, stream_id: String, frame_type: u8, timestamp_ms: u64, payload: Vec<u8>) -> Result<(), AmosError> {
        let sender = {
            let state = self.state.lock().unwrap();
            state.active_streams.get(&stream_id).cloned().ok_or_else(|| AmosError::StreamNotFound {
                message: format!("Stream with ID {} not found", stream_id),
            })?
        };

        sender.send(StreamCmd::SendFrame { frame_type, timestamp_ms, payload })
            .map_err(|e| AmosError::Internal {
                message: format!("failed to queue frame: {}", e),
            })?;

        Ok(())
    }

    pub fn close_stream(&self, stream_id: String) -> Result<(), AmosError> {
        let sender = {
            let mut state = self.state.lock().unwrap();
            state.active_streams.remove(&stream_id).ok_or_else(|| AmosError::StreamNotFound {
                message: format!("Stream with ID {} not found", stream_id),
            })?
        };

        let _ = sender.send(StreamCmd::Close);
        Ok(())
    }

    pub fn set_producer_video_state(&self, is_video_on: bool, is_screen_sharing: bool) -> Result<(), AmosError> {
        let mut state = self.state.lock().unwrap();
        state.is_video_on = is_video_on;
        state.is_screen_sharing = is_screen_sharing;
        
        let data = serde_json::json!({
            "is_video_on": is_video_on,
            "is_screen_sharing": is_screen_sharing,
        }).to_string();

        let clients = state.connected_clients.values().cloned().collect::<Vec<_>>();
        for client in clients {
            let msg = ControlMessage::Event {
                variant: "host_video_state".to_string(),
                data: data.clone(),
            };
            let _ = client.control_sender.send(msg);
        }
        Ok(())
    }

    pub fn set_participant_video_state(&self, is_video_on: bool, is_screen_sharing: bool) -> Result<(), AmosError> {
        let sender = {
            let state = self.state.lock().unwrap();
            state.client_control_sender.clone()
        };
        if let Some(tx) = sender {
            let data = serde_json::json!({
                "is_video_on": is_video_on,
                "is_screen_sharing": is_screen_sharing,
            }).to_string();

            let msg = ControlMessage::Event {
                variant: "video_state".to_string(),
                data,
            };
            let _ = tx.send(msg);
        }
        Ok(())
    }

    pub fn set_talkback_state(&self, client_id: String, enabled: bool) -> Result<(), AmosError> {
        let client = {
            let state = self.state.lock().unwrap();
            state.connected_clients.get(&client_id).cloned().ok_or_else(|| AmosError::Internal {
                message: format!("client {} not connected", client_id),
            })?
        };

        let data = serde_json::json!({ "enabled": enabled }).to_string();
        let msg = ControlMessage::Event {
            variant: "talkback".to_string(),
            data,
        };
        let _ = client.control_sender.send(msg).map_err(|e| AmosError::Internal { message: e.to_string() })?;
        Ok(())
    }

    pub fn set_tally_state(&self, client_id: String, stream_id: String, is_live: bool, is_preview: bool) -> Result<(), AmosError> {
        let client = {
            let state = self.state.lock().unwrap();
            state.connected_clients.get(&client_id).cloned().ok_or_else(|| AmosError::Internal {
                message: format!("client {} not connected", client_id),
            })?
        };

        let data = serde_json::json!({
            "stream_id": stream_id,
            "is_live": is_live,
            "is_preview": is_preview,
        }).to_string();

        let msg = ControlMessage::Event {
            variant: "tally".to_string(),
            data,
        };
        let _ = client.control_sender.send(msg).map_err(|e| AmosError::Internal { message: e.to_string() })?;
        Ok(())
    }

    pub fn configure_host_stream(&self, stream_id: String, mut config: StreamConfig) -> Result<(), AmosError> {
        let clients = {
            let state = self.state.lock().unwrap();
            state.connected_clients.values().cloned().collect::<Vec<_>>()
        };

        config.stream_id = Some(stream_id);
        let proto_config: knot_protocol::StreamConfig = config.into();
        let data = serde_json::to_string(&proto_config).unwrap_or_default();

        for client in clients {
            let msg = ControlMessage::Event {
                variant: "host_stream_configured".to_string(),
                data: data.clone(),
            };
            let _ = client.control_sender.send(msg);
        }
        Ok(())
    }

    pub fn trigger_sound(&self, client_id: String, sound_name: String, target_output: String) -> Result<(), AmosError> {
        let client = {
            let state = self.state.lock().unwrap();
            state.connected_clients.get(&client_id).cloned().ok_or_else(|| AmosError::Internal {
                message: format!("client {} not connected", client_id),
            })?
        };

        let data = serde_json::json!({
            "sound_name": sound_name,
            "target_output": target_output,
        }).to_string();

        let msg = ControlMessage::Event {
            variant: "sound_trigger".to_string(),
            data,
        };
        let _ = client.control_sender.send(msg).map_err(|e| AmosError::Internal { message: e.to_string() })?;
        Ok(())
    }

    pub fn broadcast_sound(&self, sound_name: String, target_output: String) -> Result<(), AmosError> {
        let clients = {
            let state = self.state.lock().unwrap();
            state.connected_clients.values().cloned().collect::<Vec<_>>()
        };

        let data = serde_json::json!({
            "sound_name": sound_name,
            "target_output": target_output,
        }).to_string();

        for client in clients {
            let msg = ControlMessage::Event {
                variant: "sound_trigger".to_string(),
                data: data.clone(),
            };
            let _ = client.control_sender.send(msg);
        }
        Ok(())
    }

    pub fn broadcast_prompter_text(&self, text: String) -> Result<(), AmosError> {
        let clients = {
            let state = self.state.lock().unwrap();
            state.connected_clients.values().cloned().collect::<Vec<_>>()
        };

        let data = serde_json::json!({ "text": text }).to_string();
        for client in clients {
            let msg = ControlMessage::Event {
                variant: "prompter".to_string(),
                data: data.clone(),
            };
            let _ = client.control_sender.send(msg);
        }
        Ok(())
    }

    pub fn send_custom_message(&self, client_id: String, variant: String, data: String) -> Result<(), AmosError> {
        let client = {
            let state = self.state.lock().unwrap();
            state.connected_clients.get(&client_id).cloned().ok_or_else(|| AmosError::Internal {
                message: format!("client {} not connected", client_id),
            })?
        };
        let msg = ControlMessage::Event { variant, data };
        let _ = client.control_sender.send(msg).map_err(|e| AmosError::Internal { message: e.to_string() })?;
        Ok(())
    }

    pub fn broadcast_custom_message(&self, variant: String, data: String) -> Result<(), AmosError> {
        let clients = {
            let state = self.state.lock().unwrap();
            state.connected_clients.values().cloned().collect::<Vec<_>>()
        };
        for client in clients {
            let msg = ControlMessage::Event { variant: variant.clone(), data: data.clone() };
            let _ = client.control_sender.send(msg);
        }
        Ok(())
    }

    pub fn send_custom_message_to_host(&self, variant: String, data: String) -> Result<(), AmosError> {
        let sender = {
            let state = self.state.lock().unwrap();
            state.client_control_sender.clone()
        };
        if let Some(tx) = sender {
            let msg = ControlMessage::Event { variant, data };
            let _ = tx.send(msg).map_err(|e| AmosError::Internal { message: e.to_string() })?;
        }
        Ok(())
    }

    pub fn export_recording(&self, db_path: String, output_h264_path: String) -> Result<(), AmosError> {
        use knot_protocol::{FRAMES, TIMELINE};
        use std::fs::File as StdFile;
        use std::io::Write;
        use redb::ReadableTable;

        let db = redb::Database::open(&db_path).map_err(|e| AmosError::Internal {
            message: format!("failed to open redb database: {}", e),
        })?;

        let read_txn = db.begin_read().map_err(|e| AmosError::Internal {
            message: format!("failed to begin read transaction: {}", e),
        })?;

        let table_timeline = read_txn.open_table(TIMELINE).map_err(|e| AmosError::Internal {
            message: format!("failed to open timeline table: {}", e),
        })?;

        let table_frames = read_txn.open_table(FRAMES).map_err(|e| AmosError::Internal {
            message: format!("failed to open frames table: {}", e),
        })?;

        let mut output_file = StdFile::create(&output_h264_path).map_err(|e| AmosError::Io {
            message: format!("failed to create output file: {}", e),
        })?;

        let iter = table_timeline.iter().map_err(|e| AmosError::Internal {
            message: format!("failed to iterate timeline table: {}", e),
        })?;

        for entry_result in iter {
            let entry = entry_result.map_err(|e| AmosError::Internal {
                message: format!("failed to read timeline entry: {}", e),
            })?;
            let hash = entry.1.value();

            let frame_payload = table_frames.get(&hash).map_err(|e| AmosError::Internal {
                message: format!("failed to read frame payload: {}", e),
            })?
            .ok_or_else(|| AmosError::Internal {
                message: format!("corrupted database: frame payload not found for hash {:?}", hash),
            })?;

            output_file.write_all(frame_payload.value()).map_err(|e| AmosError::Io {
                message: format!("failed to write frame to file: {}", e),
            })?;
        }

        output_file.flush().map_err(|e| AmosError::Io {
            message: format!("failed to flush output file: {}", e),
        })?;

        Ok(())
    }

    pub fn node_id(&self) -> String {
        let state = self.state.lock().unwrap();
        if let Some(ref ep) = state.endpoint {
            ep.id().to_string()
        } else {
            String::new()
        }
    }
}

use base64::{prelude::BASE64_URL_SAFE_NO_PAD, Engine};

pub(crate) fn base64_url_encode(data: &[u8]) -> String {
    BASE64_URL_SAFE_NO_PAD.encode(data)
}

pub(crate) fn pack_addr(addr: &EndpointAddr) -> Vec<u8> {
    let mut bytes = Vec::new();
    bytes.push(1);
    bytes.extend_from_slice(addr.id.as_bytes());
    if let Ok(json_bytes) = serde_json::to_vec(&addr.addrs) {
        bytes.extend_from_slice(&json_bytes);
    }
    bytes
}
