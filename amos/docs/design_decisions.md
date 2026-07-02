# AMOS Architectural Design Decisions 🏗️

This document outlines key technical decisions regarding identity mapping and live stream publishing within the AMOS ecosystem.

---

## 1. Why `client_id` instead of `device_id`? 🆔

In the AMOS control and negotiation protocol, we identify participant endpoints using `client_id` rather than a hardware-locked `device_id`. This decision was made for three primary reasons:

### A. Multi-Client Execution on a Single Device
In advanced production workflows, a single physical machine (e.g., the director's workstation or a presenter's laptop) may run multiple software instances of AMOS:
* A native GUI application captures and encodes the webcam and microphone.
* Simultaneously, a command-line script (`amos-cli`) runs in a terminal to stream a window capture or log telemetry.
* If the protocol locked connections to a hardware identifier (like a MAC address or hardware UUID), these two concurrent instances would collide. Using a session-based `client_id` allows multiple client instances to coexist on the same machine.

### B. Privacy & Sandboxing Restrictions
Modern operating systems protect user privacy by restricting access to physical hardware identifiers:
* **iOS / macOS:** Access to MAC addresses and unique hardware identifiers (UDID) is deprecated or blocked entirely within the application sandbox.
* **Android:** Accessing persistent identifiers (like IMEI or hardware serial numbers) requires highly intrusive system permissions.
* Generating an ephemeral or session-based `client_id` (e.g., combining `participant_id`, `device_type`, and a random suffix) requires zero OS permissions and is fully privacy-compliant.

### C. Connection Lifecycle & Teardown Recovery
If a client experiences a transient network drop and instantly reconnects, it is safer to negotiate the new connection as a distinct software instance (`client_id`). This avoids race conditions where the backend struggles to clean up the half-open socket of the old connection, preventing state contamination.

---

## 2. Cross-Platform RTMP Architecture 📡

To implement the live broadcast RTMP output across all supported environments (**macOS, iOS, Android, Windows, and Linux**), AMOS uses a hybrid client-core architecture.

```mermaid
graph TD
    subgraph Native Platform Layer (Per OS)
        Stage["UI Stage Canvas<br>(SwiftUI/Jetpack Compose)"] -->|Native Capture| NativeEnc["Native Hardware Encoder<br>(VideoToolbox/MediaCodec)"]
    end

    subgraph Rust Core Layer (100% Cross-Platform)
        NativeEnc -->|Compressed H.264/AAC Packets| RustCore["Rust Core Engine"]
        RustCore -->|Cross-Platform RTMP Client| LiveDestination["YouTube / Twitch Live"]
    end
```

### A. Rendering & Encoding (Delegated to Native UI)
Instead of rendering or compositing video layers on the CPU or setting up complex headless OpenGL contexts in Rust (which are slow and non-portable):
* The native application captures its own rendering viewport using native OS APIs (`ScreenCaptureKit` / `ReplayKit` on Apple, `MediaProjection` on Android, `Desktop Duplication` on Windows).
* The raw buffers are compressed on GPU memory using OS-specific hardware encoders (`VideoToolbox` on Apple, `MediaCodec` on Android, `NVENC` / `AMF` on Windows/Linux).
* The hardware-compressed H.264 (video) and AAC (audio) packets are passed down to the Rust Core.

### B. Streaming & Muxing (Handled by Rust Core)
The Rust Core maintains a 100% cross-platform, shared RTMP client layer:
* It establishes the TCP socket connections, handles RTMP handshakes, and packetizes video/audio payloads into RTMP chunk streams.
* Because this protocol layer is written in Rust, the identical network code is reused across all OS targets without needing to write platform-specific network sockets.

This hybrid approach guarantees native GPU acceleration and optimal battery/CPU efficiency while ensuring the streaming engine runs anywhere.
