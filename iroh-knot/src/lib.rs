use knot_protocol::{KnotConnection, KnotClient, JoinPolicy, Capability, HubEvent, handle_connection};
use iroh::{Endpoint, EndpointAddr};
use iroh::endpoint::{Connection, RecvStream, SendStream};
use iroh::protocol::{ProtocolHandler, AcceptError, Router};
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender, UnboundedReceiver};
use anyhow::{Result, Context, anyhow};
use base64::{prelude::BASE64_URL_SAFE_NO_PAD, Engine};
use std::path::PathBuf;
use std::sync::Arc;
use std::future::Future;
use std::pin::Pin;

pub const KNOT_ALPN: &[u8] = b"jitpomi/studio/1";

pub fn base64_url_decode(s: &str) -> Result<Vec<u8>, String> {
    BASE64_URL_SAFE_NO_PAD.decode(s).map_err(|e| e.to_string())
}

pub fn generate_ticket(endpoint: &Endpoint) -> String {
    let addr = endpoint.addr();
    let mut bytes = vec![1];
    bytes.extend_from_slice(addr.id.as_bytes());
    if let Ok(json_bytes) = serde_json::to_vec(&addr.addrs) {
        bytes.extend_from_slice(&json_bytes);
    }
    BASE64_URL_SAFE_NO_PAD.encode(bytes)
}

pub fn unpack_addr(bytes: &[u8]) -> Result<EndpointAddr, String> {
    if bytes.is_empty() || bytes[0] != 1 {
        return Err("invalid version".to_string());
    }
    if bytes.len() < 33 {
        return Err("data too short".to_string());
    }
    let node_id_bytes: [u8; 32] = bytes[1..33].try_into().map_err(|_| "failed to read node id".to_string())?;
    let node_id = iroh::PublicKey::from_bytes(&node_id_bytes).map_err(|e| e.to_string())?;
    
    let addrs = if bytes.len() > 33 {
        serde_json::from_slice(&bytes[33..]).map_err(|e| e.to_string())?
    } else {
        std::collections::BTreeSet::new()
    };
    
    Ok(EndpointAddr {
        id: node_id,
        addrs,
    })
}

pub async fn bind_endpoint() -> Result<Endpoint> {
    let transport_config = iroh::endpoint::QuicTransportConfig::builder()
        .keep_alive_interval(std::time::Duration::from_secs(4))
        .max_idle_timeout(Some(std::time::Duration::from_secs(12).try_into().unwrap()))
        .build();
    
    let endpoint = Endpoint::builder(iroh::endpoint::presets::N0)
        .transport_config(transport_config)
        .bind()
        .await?;
    Ok(endpoint)
}

#[derive(Clone)]
pub struct IrohConnection {
    pub conn: Connection,
    pub local_id: String,
    pub _endpoint: Option<Endpoint>,
}

#[async_trait::async_trait]
impl KnotConnection for IrohConnection {
    type SendStream = SendStream;
    type RecvStream = RecvStream;

    async fn accept_bi(&self) -> Result<(Self::SendStream, Self::RecvStream)> {
        let (send, recv) = self.conn.accept_bi().await?;
        Ok((send, recv))
    }

    async fn accept_uni(&self) -> Result<Self::RecvStream> {
        let recv = self.conn.accept_uni().await?;
        Ok(recv)
    }

    async fn open_bi(&self) -> Result<(Self::SendStream, Self::RecvStream)> {
        let (send, recv) = self.conn.open_bi().await?;
        Ok((send, recv))
    }

    async fn open_uni(&self) -> Result<Self::SendStream> {
        let send = self.conn.open_uni().await?;
        Ok(send)
    }

    fn remote_node_id(&self) -> String {
        self.conn.remote_id().to_string()
    }

    fn local_node_id(&self) -> String {
        self.local_id.clone()
    }
}

pub type IrohKnotClient = KnotClient<IrohConnection>;

#[derive(Clone)]
pub struct KnotProtocol {
    data_dir: PathBuf,
    event_tx: UnboundedSender<HubEvent>,
    metadata_fn: Arc<dyn Fn() -> String + Send + Sync + 'static>,
    join_policy: JoinPolicy,
    cap_validator: Option<Arc<dyn Fn(&[Capability]) -> bool + Send + Sync + 'static>>,
    local_id: String,
}

impl std::fmt::Debug for KnotProtocol {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("KnotProtocol")
            .field("data_dir", &self.data_dir)
            .field("join_policy", &self.join_policy)
            .finish()
    }
}

impl ProtocolHandler for KnotProtocol {
    #[allow(refining_impl_trait)]
    fn accept(
        &self,
        connection: Connection,
    ) -> Pin<Box<dyn Future<Output = Result<(), AcceptError>> + Send>> {
        let data_dir = self.data_dir.clone();
        let event_tx = self.event_tx.clone();
        let metadata_fn = self.metadata_fn.clone();
        let join_policy = self.join_policy.clone();
        let cap_validator = self.cap_validator.clone();
        let local_id = self.local_id.clone();
        
        Box::pin(async move {
            let wrapped = IrohConnection { conn: connection, local_id, _endpoint: None };
            tokio::spawn(async move {
                let res = handle_connection(wrapped, data_dir, event_tx, metadata_fn, join_policy, cap_validator).await;
                println!("DEBUG HOST: handle_connection exited with: {:?}", res);
            });
            Ok(())
        })
    }
}

#[derive(Clone, Default)]
pub struct IrohKnotHubBuilder {
    data_dir: PathBuf,
    join_policy: Option<JoinPolicy>,
    metadata_fn: Option<Arc<dyn Fn() -> String + Send + Sync + 'static>>,
    event_handler: Option<Arc<dyn Fn(HubEvent) + Send + Sync + 'static>>,
    cap_validator: Option<Arc<dyn Fn(&[Capability]) -> bool + Send + Sync + 'static>>,
}

impl IrohKnotHubBuilder {
    pub fn data_dir(mut self, path: PathBuf) -> Self {
        self.data_dir = path;
        self
    }

    pub fn with_join_policy(mut self, policy: JoinPolicy) -> Self {
        self.join_policy = Some(policy);
        self
    }

    pub fn metadata_fn<F>(mut self, f: F) -> Self
    where
        F: Fn() -> String + Send + Sync + 'static,
    {
        self.metadata_fn = Some(Arc::new(f));
        self
    }

    pub fn on_event<F>(mut self, handler: F) -> Self
    where
        F: Fn(HubEvent) + Send + Sync + 'static,
    {
        self.event_handler = Some(Arc::new(handler));
        self
    }

    pub fn on_capability_validate<F>(mut self, validator: F) -> Self
    where
        F: Fn(&[Capability]) -> bool + Send + Sync + 'static,
    {
        self.cap_validator = Some(Arc::new(validator));
        self
    }

    pub async fn serve(self, endpoint: Endpoint) -> Result<IrohKnotHub> {
        let (tx, mut rx) = unbounded_channel();
        let policy = self.join_policy.unwrap_or(JoinPolicy::ApproveAll);
        let metadata_fn = self.metadata_fn.unwrap_or_else(|| Arc::new(|| "{}".to_string()));
        let local_id = endpoint.id().to_string();
        
        let protocol = KnotProtocol {
            data_dir: self.data_dir,
            event_tx: tx,
            metadata_fn,
            join_policy: policy,
            cap_validator: self.cap_validator,
            local_id,
        };
        let router = Router::builder(endpoint)
            .accept(KNOT_ALPN.to_vec(), Arc::new(protocol))
            .spawn();

        let event_handler = self.event_handler;
        tokio::spawn(async move {
            while let Some(event) = rx.recv().await {
                if let Some(ref h) = event_handler {
                    h(event);
                }
            }
        });

        Ok(IrohKnotHub { router })
    }
}

pub struct IrohKnotHub {
    router: Router,
}

impl IrohKnotHub {
    pub fn new() -> IrohKnotHubBuilder {
        IrohKnotHubBuilder::default()
    }

    pub async fn spawn<F>(endpoint: Endpoint, data_dir: PathBuf, metadata_fn: F) -> Result<(Self, UnboundedReceiver<HubEvent>)>
    where
        F: Fn() -> String + Send + Sync + 'static,
    {
        let (tx, rx) = unbounded_channel();
        let local_id = endpoint.id().to_string();
        let protocol = KnotProtocol {
            data_dir,
            event_tx: tx,
            metadata_fn: Arc::new(metadata_fn),
            join_policy: JoinPolicy::ApproveAll,
            cap_validator: None,
            local_id,
        };
        let router = Router::builder(endpoint)
            .accept(KNOT_ALPN.to_vec(), Arc::new(protocol))
            .spawn();
        Ok((Self { router }, rx))
    }

    pub async fn shutdown(self) -> Result<()> {
        self.router.shutdown().await?;
        Ok(())
    }
}

pub struct IrohKnotClientJoinBuilder {
    session_ticket: String,
    knot_id: String,
    rope_id: String,
    capabilities: Vec<Capability>,
    join_token: String,
    endpoint: Option<Endpoint>,
}

impl IrohKnotClientJoinBuilder {
    pub fn join(session_ticket: &str) -> Self {
        Self {
            session_ticket: session_ticket.to_string(),
            knot_id: "default-knot".to_string(),
            rope_id: "default-rope".to_string(),
            capabilities: Vec::new(),
            join_token: String::new(),
            endpoint: None,
        }
    }

    pub fn knot(mut self, knot_id: &str) -> Self {
        self.knot_id = knot_id.to_string();
        self
    }

    pub fn rope_id(mut self, rope_id: &str) -> Self {
        self.rope_id = rope_id.to_string();
        self
    }

    pub fn join_token(mut self, token: &str) -> Self {
        self.join_token = token.to_string();
        self
    }

    pub fn capability(mut self, cap: Capability) -> Self {
        self.capabilities.push(cap);
        self
    }

    pub fn endpoint(mut self, endpoint: Endpoint) -> Self {
        self.endpoint = Some(endpoint);
        self
    }

    pub async fn connect(self) -> Result<IrohKnotClient> {
        let endpoint = match self.endpoint {
            Some(ep) => ep,
            None => bind_endpoint().await?,
        };

        let decoded = base64_url_decode(&self.session_ticket)
            .map_err(|e| anyhow!("invalid ticket encoding: {}", e))?;
        let hub_addr = unpack_addr(&decoded)
            .map_err(|e| anyhow!("failed to unpack ticket: {}", e))?;

        let connection = endpoint.connect(hub_addr, KNOT_ALPN).await
            .context("Failed to connect to Hub")?;

        let wrapped = IrohConnection {
            conn: connection,
            local_id: endpoint.id().to_string(),
            _endpoint: Some(endpoint),
        };

        IrohKnotClient::connect_internal(
            wrapped,
            self.knot_id,
            self.rope_id,
            self.join_token,
            self.capabilities,
        ).await
    }
}
