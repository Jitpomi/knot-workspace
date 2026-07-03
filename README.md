# Knot Workspace 🪢

This is the official monorepo workspace for coordinating the decoupled components of the **Knot Protocol** ecosystem—a transport-agnostic peer-to-peer (P2P) session orchestration framework.

---

## 🧠 The Metaphor: Ropes, Knots, and "Tying the Knot"

To make peer-to-peer networking simple, Knot introduces a real-world physical metaphor to structure logical communication:

*   **Ropes (Physical Devices):** Imagine a physical strand. In the real world, a Rope is an actual physical device—like a security camera, a smart plug, a microphone, or a smartphone. Each physical Rope has its own hardware network address and cryptographic public keys.
*   **Knots (Logical Rooms / Roles):** A Knot is a logical grouping or containment zone where multiple physical devices are gathered. For example, a logical Knot could represent `"driveway"`, `"front-gate"`, or `"living-room"`. A Knot isn't a physical device itself—it represents a logical location or role.
*   **Tying the Knot:** When physical devices (**Ropes**) connect to the network session and register under the same logical containment ID, they are **"tying the knot"**. This cryptographic link binds those separate hardware devices together into a single coordinated participant in the session.

### 💍 The Essence: "And the two shall become one" ... into a Family

At its heart, the Knot metaphor reflects a timeless concept of partnership: *two separate entities uniting to form a single, transcending bond.*

In traditional networking, devices remain fundamentally divided by their physical socket addresses. In the Knot Protocol, when Ropes register under the same `knot_id` to "tie the knot", they achieve a state of logical unity. Their physical separation is transcended by a shared logical session, allowing them to act, coordinate, and communicate as one.

This relationship naturally expands beyond a simple pair into a **Family**. A logical Knot can tie together many different Ropes (devices)—each with its own distinct roles, character, and capabilities (e.g., sensors, microphones, cameras, actuators). Under the roof of a single logical Knot, these diverse devices function in harmony, looking out for each other and working together as a unified household.

**Why is it called "Tying the Knot"?**
*   **The Union of Separation (Handfasting Ritual):** Historically, the phrase "tying the knot" traces back to ancient Celtic and medieval *handfasting* rituals, where a couple's hands were literally bound together with cords or rope to symbolize the joining of two separate lives into one unified partnership. In networking, it represents binding independent physical hardware into a single, coordinated logical session.
*   **The Noun vs. Verb Duality (The "Tie"):** In physical engineering, a *tie* is a structural member designed to hold separate components together under load so they act as a single unit. In relationships, we speak of *social or family ties*. In the protocol, sending a `Tie` envelope acts as both the verb (to bind the connection) and the noun (the logical connection or tension bond established).
*   **Cryptographic Commitment:** Just as the ceremonial knot represents a committed partnership, "tying the knot" is the secure, authenticated handshake. By presenting valid cryptographic keys and credentials, the Rope makes a session-long commitment to the Knot.
*   **Tensile Strength under Tension:** A physical knot gets tighter and stronger under load. When network conditions get rough—when IPs roam or Wi-Fi drops (tension)—the logical bond remains intact. The devices simply reconnect to "re-tie" the session state seamlessly.

As we scale upward, these structures organize organically into larger network topologies:
*   **Family (The Micro-Unit):** A single logical Knot coordinating a household or workstation of diverse Ropes (devices).
*   **Clan (The Local Community):** A collection of Knots (families) cooperating and coordinating within a local network, workspace, or shared organization.
*   **Tribe (The Ecosystem):** A wider community of Knots and Clans cooperating under a shared application domain, namespace catalog, or workspace.
*   **Nation (The Global Mesh):** The entire global, decentralized federation of Knots, Clans, and Tribes interoperating seamlessly over the open, transport-agnostic Knot protocol.

### Why is this important for P2P Networking?

In traditional networking, connections are strictly **1-to-1 links** between physical IP addresses. If you have a security camera and a floodlight at your front door, a central cloud server must manually manage and group their separate connections.

By decoupling the physical network links from the logical groupings, Knot changes how devices coordinate:
1.  **Seamless Reconnection (Network Agility):** If your security camera (Rope 1) drops connection or roams to another Wi-Fi access point (obtaining a new physical IP), it simply reconnects and re-announces its logical Knot identity. The session remains continuous and uninterrupted.
2.  **Edge Coordination (Local Smart Automation):** Since the Host knows which physical Ropes are tied to the same Knot, it can coordinate local actions natively (e.g., *"If any motion-sensor Rope in the `driveway` Knot triggers an event, command the floodlight Rope in the same `driveway` Knot to turn on"*).
3.  **Dynamic Stream Isolation:** When a camera Rope starts streaming video, it opens an isolated data pipe (a unidirectional stream) for the video data. If the video is toggled off, only that specific data pipe is closed—the main control channel holding the "tied knot" remains active.

### Real-World Use Cases
*   **Smart Home Automation:** Grouping a P2P security camera Rope, a motion detector Rope, and a smart floodlight Rope into a single `"front-yard"` Knot.
*   **Live Broadcasting:** Grouping a camera feed Rope, an external audio microphone Rope, and an on-air tally-light Rope into a logical `"presenter-desk-1"` Knot.
*   **Industrial IoT:** Grouping temperature, pressure, and ventilation Ropes into a logical `"hvac-zone-4"` Knot for edge coordination.

---

## 📂 Workspace Topology

The workspace coordinates the following components as Git submodules:

1.  **[`knot-protocol`](./knot-protocol)**: The transport-agnostic core protocol implementation. It defines generic handshake builders, capabilities advertising, control channel event loops, and data stream parameters, generic over any transport implementing `KnotConnection`.
2.  **[`iroh-knot`](./iroh-knot)**: The default concrete transport adapter implementing the `KnotConnection` trait using **Iroh's** secure, firewall-traversing QUIC network endpoints.
3.  **[`amos`](./amos)**: A real-time media engine integration (`amos-core`) and client terminal (`amos-cli`) demonstrating the protocol integration to stream audio, video, and control events over Iroh.

---

## 🚀 Quick Start

### 1. Cloning the Workspace

To check out the workspace along with all of its submodule crates:

```bash
git clone --recursive https://github.com/Jitpomi/knot-workspace.git
cd knot-workspace
```

If you have already cloned the repository without submodules, initialize them using:

```bash
git submodule update --init --recursive
```

### 2. Building all Crates

Verify compilation of all components in the workspace:

```bash
cargo build --workspace
```

### 3. Running Conformance Tests

Run the full sequential integration conformance tests (designed to run sequentially due to loopback QUIC port bindings):

```bash
cargo test --workspace -- --test-threads=1
```

### 4. Running Simulation Examples

Execute P2P simulations using the default Iroh adapter:

```bash
# Terminal 1: Run the bidirectional command host
cargo run -p iroh-knot --example 03_command_host

# Terminal 2: Connect the client (copy the ticket printed by the host)
cargo run -p iroh-knot --example 03_command_client -- <CONNECTION_TICKET>
```

---

## 🔒 Security Architecture: Zero-Trust Admission & Platform Enclaves

Knot Workspace coordinates a zero-trust security paradigm that prevents session takeovers and privilege escalations while allowing edge devices to coordinate completely offline.

### 🎟️ The Bouncer-and-Ticket Metaphor
Imagine a venue bouncer (the Host) admitting a guest (the client device). Instead of the bouncer calling head office to check a database (online API check), the guest presents a signed ticket (the token):
1. **The Seal Check (Signature):** The bouncer looks at the signature on the ticket using a public seal (the Root Public Key). Because of asymmetric math, the bouncer knows the ticket is genuine without needing to call the office.
2. **The ID Match (Identity Binding):** The bouncer matches the guest's fingerprint (their TLS public key) against the owner identifier on the ticket. If someone else stole the ticket, they get rejected.
3. **The Bag Policy (Capability Check):** The ticket list specifies allowed gear: `["camera-1", "mic-1"]`. If the guest tries to bring in an unauthorized capability, the bouncer blocks the door.

---

### A. The Feature
A decentralized connection admission gateway that verifies asymmetric cryptographic signatures (Ed25519) at the edge, utilizing hardware-backed enclaves (Apple Keychain/Secure Enclave & Android Keystore) to validate client identity, session bounds, and capability matrices completely offline.

### B. The Problem It Solves
Traditional P2P and edge coordination frameworks suffer from three severe security and portability vulnerabilities:
1. **The Offline Dependency SPOF:** Traditional token validation usually requires a connection to a central authorization server (e.g., Auth0, database query, etc.). If the internet is down, local smart homes, broadcast stages, or offline meshes cannot coordinate.
2. **The Token Replay/Spoofing Vulnerability:** Standard access tokens (like typical bearer tokens) can be stolen and replayed by a malicious device to hijack a session. The protocol cannot prove the device holding the token is actually the device the token was issued to.
3. **The Sandboxing Portability Trap:** Edge applications must run on everything from IoT hubs to mobile apps (iOS/Android). Hardcoding paths (like `/etc/amos/config`), storing static secrets, or using raw environment variables crashes or fails on sandboxed mobile systems and exposes private keys to physical attacks.

### C. How It's Solved
We designed and implemented a **Platform-Injected, Asymmetric Gateway Pattern**:
1. **Decoupled Handshake Callback:** The core `knot-protocol` is kept protocol-pure and free of heavy crypto dependencies. It exposes a thread-safe validation callback (`JoinPolicy::Custom`) that passes the client's public key (retrieved straight from the secure TLS 1.3 socket layer), the client's `join_token`, and their declared `capabilities` to the application.
2. **Platform Dependency Injection (via UniFFI):** The Rust core (`amos-core`) exposes `start_director` to the platforms. The platform-native wrappers (Swift on iOS/macOS, Kotlin on Android) load the trusted root public key from their operating system's native secure hardware enclaves (**Apple Keychain** and **Android Keystore**) and inject the raw key bytes into the Rust engine.
3. **Detached-Signature Cryptographic Binding:** The client sends a token formatted as `Base64Url(JSON_Claims).Base64Url(Ed25519_Signature)`. The Rust engine performs the actual Ed25519 validation against the injected root public key:
   - Verifies cryptographic signature authenticity.
   - Enforces temporal expiration bounds (with a 60-second clock-skew allowance).
   - Verifies cryptographic identity binding (`claims.sub == authenticated_node_id`). If a malicious client tries to replay another device's token, the identity binding check immediately catches the mismatch and drops the connection.
   - Verifies capability matching (validates that the client's declared capabilities are a strict subset of the token-authorized list).

### D. Why It's Cool 🚀
* **Absolute Zero-Trust, 100% Offline:** A Host can boot in the middle of a forest with no internet connection and securely validate that a joining camera or microphone is authorized to connect, which session it belongs to, and exactly what streams it is allowed to publish.
* **Core Purity (Zero Dependency Bloat):** The `knot-protocol` crate remains ultra-lean (no `ring`, `ed25519-dalek`, or heavy crypto dependencies). The application layer (`amos`) imports the crypto, keeping the transport layer lightweight and transport-agnostic.
* **Hardware-Backed Cryptography:** By leveraging dependency injection via UniFFI, the system utilizes the absolute best hardware security available on the device (the **Apple Secure Enclave** and **Android StrongBox**). It is cryptographically secure without storing plain private keys on the filesystem.
* **Extensible & Future-Proof:** The validation loop supports future expansion (like UCAN/Biscuit delegation paths or prefix matching) easily, without requiring changes to the transport layer.

---

## 📜 Specifications & DX Documentation

For detailed specs, terms, and guide manuals, see the documentation files in the core submodule:
*   [Specification Specifications (SPEC.md)](./knot-protocol/docs/SPEC.md) - Handshakes, lifecycle states, and packet envelopes.
*   [Developer Experience Guide (DX.md)](./knot-protocol/docs/DX.md) - How to write custom transport adapters and launch hosts.
*   [Glossary of Terms (GLOSSARY.md)](./knot-protocol/docs/GLOSSARY.md) - Definitions for Knots, Ropes, Welcomes, and Acks.
*   [Protocol Roadmap (ROADMAP.md)](./knot-protocol/docs/ROADMAP.md) - Maturity milestones and custom ranges.
