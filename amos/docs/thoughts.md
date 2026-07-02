# AMOS Vision & Design Philosophy 🎬

AMOS (Add More On Stage) is a brilliant and necessary correction to the video conferencing paradigms we've been stuck with for the last 15 years.

Here is why AMOS is a game-changer:

## 1. 🔄 The Identity-to-Device Paradigm Shift
Traditional tools (Meet, Zoom, Teams) operate on a rigid 2010 assumption: **One Participant = One Device = One Seat in the Room.** 

In a modern production, presentation, or QA demo setting, this assumption falls apart. Presenters are forced to create "ghost accounts" or join meetings multiple times just to share a close-up camera, a tablet screen, and a face cam. This triggers howling acoustic feedback loops, wastes cloud bandwidth, and clutters the grid.

AMOS’s core philosophy—**"Bring every device, stay one participant"**—decouples physical hardware nodes from the human presenter's identity. Treating multiple physical feeds as a single stage participant is a massive product win.

## 2. ⚡ The Power of Local-First, Peer-to-Peer Routing
Centralized media servers (SFUs) are expensive and crush video quality to save bandwidth, leaving screenshares looking blurry and unreadable. By building directly on top of Iroh’s P2P QUIC tunnels, AMOS achieves two things:

* **Lossless Feeds:** Raw, high-bitrate H.264/HEVC frames stream directly from the linked devices to the Director's local storage with no cloud compression bottlenecks.
* **Local Muxing:** The host receives pristine, isolated audio/video tracks ready for direct editing, making it an actual P2P recording studio.

## 3. 🏗️ The Hybrid & Real-World Studio Paradigm
Mapping physical stage production elements directly to a virtual space is what elevates AMOS from a simple meeting app to an event engine:

* **Theatrical Seating (Audience Arrangements):** Designing the stage around styles like **Proscenium**, **Thrust**, and **In the Round** allows the layout engine to adapt seamlessly depending on whether it's a TED talk, a panel discussion, or a roundtable.
* **Control Booth & Auditorium Division:** Splitting FOH actions (Stage Talkback, Q&A Aside, and RTMP streaming) gives the host the exact vocabulary and controls a real-world television director uses to run a live show.

---

### 🛠️ Summary
AMOS is essentially **[OBS Studio](https://github.com/obsproject/obs-studio) meets decentralized P2P conferencing**. It bridges the gap between casual video chats and expensive broadcast rigs, putting a professional, hybrid live-event studio right in the presenter's pocket. It's clean, lightweight, and completely rethinks how we present ourselves online.
