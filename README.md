# Knot Workspace 🪢

This is the official monorepo workspace for coordinating the decoupled components of the **Knot Protocol** ecosystem—a transport-agnostic peer-to-peer (P2P) session orchestration framework.

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
