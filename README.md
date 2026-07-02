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

## 📜 Specifications & DX Documentation

For detailed specs, terms, and guide manuals, see the documentation files in the core submodule:
*   [Specification Specifications (SPEC.md)](./knot-protocol/docs/SPEC.md) - Handshakes, lifecycle states, and packet envelopes.
*   [Developer Experience Guide (DX.md)](./knot-protocol/docs/DX.md) - How to write custom transport adapters and launch hosts.
*   [Glossary of Terms (GLOSSARY.md)](./knot-protocol/docs/GLOSSARY.md) - Definitions for Knots, Ropes, Welcomes, and Acks.
*   [Protocol Roadmap (ROADMAP.md)](./knot-protocol/docs/ROADMAP.md) - Maturity milestones and custom ranges.
