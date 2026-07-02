import SwiftUI
import CoreImage.CIFilterBuiltins

// Helper to generate QR code image natively
func generateQRCode(from string: String) -> NSImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    
    if let outputImage = filter.outputImage {
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        
        if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
            return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
        }
    }
    return nil
}

struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var ticketInput: String = ""
    @State private var showCopiedAlert: Bool = false
    
    // Sidebar navigation (0: Info/Code, 1: Devices, 2: Logs)
    @State private var showSidebar: Bool = false
    @State private var activeSidebarTab: Int = 0
    
    // Bind states directly to AppState
    private var isCameraOff: Bool { appState.isCameraOff }
    private var isMuted: Bool { appState.isMuted }
    private var isScreenSharing: Bool { appState.isScreenSharing }
    @State private var currentTime: String = ""
    @State private var isPulsing: Bool = false
    @State private var lastNonMuteVolume: Float = 0.5
    @State private var showVolumePopover: Bool = false
    @State private var showMicPopover: Bool = false

    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Google Meet Premium Charcoal Palette
    private let meetBackground = Color(red: 23/255, green: 24/255, blue: 26/255)
    private let meetCardBackground = Color(red: 60/255, green: 64/255, blue: 67/255)
    private let meetControlBackground = Color(red: 60/255, green: 64/255, blue: 67/255)
    private let meetControlRed = Color(red: 234/255, green: 67/255, blue: 53/255)
    private let meetAccentBlue = Color(red: 138/255, green: 180/255, blue: 248/255)

    var body: some View {
        VStack(spacing: 0) {
            // Main Workspace Splitter
            HStack(spacing: 0) {
                // Main stage containing video grid or green room
                VStack(spacing: 0) {
                    ZStack {
                        mainVideoStage
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        if appState.enableProximityMerge && !isMuted && !appState.isDirector {
                            VStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Microphone active in proximity? Please use headphones to prevent echo feedback.")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.85))
                                .cornerRadius(8)
                                .shadow(radius: 4)
                                .padding(.top, 16)
                                
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Sidebar details panel (Meet style)
                if showSidebar {
                    meetingSidebarPanel
                        .frame(width: 340)
                        .background(Color(red: 32/255, green: 33/255, blue: 36/255))
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Full-Width Google Meet Bottom Control Bar (only when in active studio session)
            if appState.isDirector ? appState.isRunning : appState.isConnected {
                fullWidthControlBar
            }
        }
        .background(meetBackground)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1000, minHeight: 700)
        .onAppear {
            updateTime()
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onReceive(timer) { _ in
            updateTime()
        }

    }

    // MARK: - Main Video Stage
    private var mainVideoStage: some View {
        VStack {
            if appState.isDirector {
                if !appState.isRunning {
                    greenRoomView(title: "Host Studio", subtitle: "Configure settings on the right, then launch the studio session to Add More On Stage.")
                } else if appState.connectedClients.isEmpty {
                    greenRoomView(title: "Waiting for Linked Devices", subtitle: "Share the session code in the details panel to link microphone, camera, and guest feeds.")
                } else {
                    ZStack {
                        directorVideoGrid
                        
                        // Floating Self Preview for Director in bottom-right corner
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                if !isCameraOff {
                                    CameraPreviewView(session: appState.cameraCaptureManager.previewSession)
                                        .frame(width: 140, height: 90)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                        )
                                        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                                        .padding(16)
                                }
                            }
                        }
                    }
                }
            } else {
                if !appState.isConnected {
                    greenRoomView(title: "Ready to join?", subtitle: "Enter the Director's session code on the right to link your device.")
                } else if appState.connectedClients.isEmpty {
                    greenRoomView(title: "Waiting for host...", subtitle: "You will see the Director and other participants once they start streaming.")
                } else {
                    ZStack {
                        directorVideoGrid
                        
                        // Floating Self Preview for Participant in bottom-right corner
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                if !isCameraOff {
                                    CameraPreviewView(session: appState.cameraCaptureManager.previewSession)
                                        .frame(width: 140, height: 90)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                        )
                                        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                                        .padding(16)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
    }

    // MARK: - Google Meet Premium Green Room
    private func greenRoomView(title: String, subtitle: String) -> some View {
        HStack(spacing: 40) {
            // Left Side: Large 16:9 self-preview box
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 32/255, green: 33/255, blue: 36/255))
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: 520)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    
                    if isCameraOff && !appState.isScreenSharing {
                        // Simple video slash icon when camera is off
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "video.slash.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary)
                            }
                            Text("Camera is off")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if appState.isScreenSharing && !appState.forceDismissPermissionWarning && !appState.hasScreenCapturePermission {
                        // Helpful permission warning card when Screen Recording permission is missing
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.orange)
                            
                            Text("Screen Recording Permission Required")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Please enable Amos under Screen & System Audio Recording in System Settings, then restart the app.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            
                            HStack(spacing: 16) {
                                Button(action: {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    Text("Open Settings")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    appState.forceDismissPermissionWarning = true
                                }) {
                                    Text("Proceed Anyway")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(24)
                    } else {
                        CameraPreviewView(session: appState.cameraCaptureManager.previewSession)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // Floating quick toggles in preview (only shown if bottom control bar is hidden)
                    if !(appState.isDirector ? appState.isRunning : appState.isConnected) {
                        VStack {
                            Spacer()
                            HStack(spacing: 12) {
                                Button(action: { appState.isMuted.toggle() }) {
                                    ZStack {
                                        Circle()
                                            .fill(isMuted ? meetControlRed : Color.white.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                                            .foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    if appState.isDirector ? appState.isRunning : appState.isConnected {
                                        if appState.isCameraOff {
                                            appState.startStreaming()
                                        } else {
                                            appState.stopStreaming()
                                        }
                                    } else {
                                        appState.isCameraOff.toggle()
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(isCameraOff ? meetControlRed : Color.white.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: isCameraOff ? "video.slash.fill" : "video.fill")
                                            .foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    if showSidebar && activeSidebarTab == 3 {
                                        withAnimation { showSidebar = false }
                                    } else {
                                        activeSidebarTab = 3
                                        withAnimation { showSidebar = true }
                                    }
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(showSidebar && activeSidebarTab == 3 ? Color.blue.opacity(0.8) : Color.white.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "gearshape.fill")
                                            .foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.bottom, 16)
                        }
                    }
                }
                .frame(maxWidth: 520)
            }
            
            // Right Side: Joining details card
            VStack(alignment: .leading, spacing: 20) {
                if !appState.isRunning && !appState.isConnected {
                    Picker("", selection: $appState.isDirector) {
                        Text("Join Session").tag(false)
                        Text("Host Studio").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .padding(.bottom, 8)
                }

                Text(title)
                    .font(.system(size: 32, weight: .bold))
                
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: 360)
                
                if !appState.isRunning && !appState.isConnected {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Your name", text: $appState.displayName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)

                        if appState.isDirector {
                            Button(action: {
                                appState.startDirector()
                                withAnimation {
                                    showSidebar = true
                                    activeSidebarTab = 0 // Auto-open details to show code
                                }
                            }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Start Studio Host")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.large)
                            .disabled(appState.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            // Quick input fields before connecting
                            VStack(spacing: 12) {
                                HStack(spacing: 8) {
                                    TextField("Enter code (e.g. amos-xxx)", text: $ticketInput)
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.large)
                                    
                                    if !ticketInput.isEmpty {
                                        Button(action: { ticketInput = "" }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                                .font(.title3)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Button(action: {
                                            if let clipboard = NSPasteboard.general.string(forType: .string) {
                                                ticketInput = clipboard
                                            }
                                        }) {
                                            Image(systemName: "doc.on.clipboard")
                                                .font(.title3)
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Paste from clipboard")
                                    }
                                }
                                
                                Button(action: {
                                    appState.connect(ticket: ticketInput)
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Join Studio")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .controlSize(.large)
                                .disabled(ticketInput.isEmpty || appState.displayName.isEmpty)
                            }
                        }
                    }
                    .frame(maxWidth: 320)
                } else if appState.isDirector && appState.isRunning {
                    // Host is running, waiting for devices
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Waiting for devices...")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        
                        Text("Use the About Session panel on the right to copy the joining ticket or scan the QR code with your devices.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: 360)
                    .padding(.top, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Director Video Grid
    private var directorVideoGrid: some View {
        let count = appState.connectedClients.count
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: count > 1 ? 2 : 1)
        
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(appState.connectedClients, id: \.self) { clientId in
                    let name = appState.clientsMap[clientId]?.name ?? "Guest Feed"
                    let device = appState.clientsMap[clientId]?.device ?? "Remote Device"
                    
                    VStack(spacing: 0) {
                        let isVideoOn = (clientId == "host") ? appState.isHostVideoOn : (appState.clientVideoStates[clientId] ?? true)
                        
                        ZStack {
                            RemoteVideoView(clientId: clientId, appState: appState)
                                .aspectRatio(16/9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .opacity(isVideoOn ? 1.0 : 0.0)
                            
                            if !isVideoOn {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(red: 32/255, green: 33/255, blue: 36/255))
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .overlay(
                                        VStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.white.opacity(0.1))
                                                    .frame(width: 80, height: 80)
                                                    .scaleEffect(isPulsing ? 1.05 : 0.95)
                                                    .opacity(isPulsing ? 0.8 : 0.5)
                                                
                                                Image(systemName: "video.slash.fill")
                                                    .font(.system(size: 28))
                                                    .foregroundColor(.secondary)
                                            }
                                            Text("\(name)'s camera is off")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    )
                            }
                            
                            // Sleek Telemetry overlay
                            VStack(alignment: .leading) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Codec: H.264 (Hardware)")
                                        Text("Peer: \(clientId.prefix(8))...")
                                        Text("Status: \(appState.isRecording ? "Recording" : "Connected")")
                                            .foregroundColor(appState.isRecording ? .red : .green)
                                            .fontWeight(.semibold)
                                    }
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(6)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                    
                                    Spacer()
                                    
                                    if appState.isRecording {
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.red).frame(width: 6, height: 6)
                                            Text("REC").font(.system(size: 9, weight: .bold))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(6)
                                    }
                                }
                                .padding(12)
                                
                                Spacer()
                                
                                // Bottom Row: Name Badge and Trigger Keyframe
                                HStack {
                                    HStack(spacing: 6) {
                                        Text(name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                        
                                        let currentLevel = (clientId == "host" && appState.isDirector)
                                            ? appState.localAudioLevel
                                            : (appState.clientAudioLevels[clientId] ?? 0.0)
                                        
                                        if currentLevel > 0.05 {
                                            HStack(spacing: 2) {
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(Color.green)
                                                    .frame(width: 2, height: CGFloat(4 + currentLevel * 10))
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(Color.green)
                                                    .frame(width: 2, height: CGFloat(6 + currentLevel * 14))
                                                RoundedRectangle(cornerRadius: 1)
                                                    .fill(Color.green)
                                                    .frame(width: 2, height: CGFloat(4 + currentLevel * 10))
                                            }
                                            .animation(.easeInOut(duration: 0.1), value: currentLevel)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(8)
                                    
                                    Spacer()
                                    
                                    // Trigger Keyframe
                                    Button(action: { appState.requestKeyframe(clientId: clientId, streamId: "1") }) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(6)
                                            .background(Color.white.opacity(0.15))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                            }
                        }
                        .frame(height: 240)
                        .background(Color(red: 32/255, green: 33/255, blue: 36/255))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Participant Video Stage
    private var participantVideoStage: some View {
        let isHostOnline = appState.connectedClients.contains("host")
        let isSpeaking = !isMuted && appState.localStreamId != nil
        let remoteClients = appState.connectedClients
        
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 32/255, green: 33/255, blue: 36/255))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSpeaking ? Color.green : Color.white.opacity(0.08), lineWidth: isSpeaking ? 3 : 1)
                )
            
            if remoteClients.isEmpty {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 90, height: 90)
                            .scaleEffect(isPulsing ? 1.05 : 0.95)
                            .opacity(isPulsing ? 0.8 : 0.5)
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    }
                    Text("Waiting for Host (Producer)...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else if remoteClients.count == 1 {
                let clientId = remoteClients[0]
                let isVideoOn = clientId == "host" ? appState.isHostVideoOn : (appState.clientVideoStates[clientId] ?? true)
                let name = appState.clientsMap[clientId]?.name ?? "Participant"
                
                ZStack {
                    RemoteVideoView(clientId: clientId, appState: appState)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .opacity(isVideoOn ? 1.0 : 0.0)
                    
                    if !isVideoOn {
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 90, height: 90)
                                Image(systemName: "video.slash.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                            }
                            Text("\(name)'s video is off")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 32/255, green: 33/255, blue: 36/255))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(remoteClients, id: \.self) { clientId in
                            let name = appState.clientsMap[clientId]?.name ?? "Guest Feed"
                            let isVideoOn = clientId == "host" ? appState.isHostVideoOn : (appState.clientVideoStates[clientId] ?? true)
                            
                            VStack(spacing: 0) {
                                ZStack {
                                    RemoteVideoView(clientId: clientId, appState: appState)
                                        .aspectRatio(16/9, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .opacity(isVideoOn ? 1.0 : 0.0)
                                    
                                    if !isVideoOn {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color(red: 32/255, green: 33/255, blue: 36/255))
                                            .aspectRatio(16/9, contentMode: .fit)
                                            .overlay(
                                                VStack(spacing: 12) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(Color.white.opacity(0.1))
                                                            .frame(width: 60, height: 60)
                                                        Image(systemName: "video.slash.fill")
                                                            .font(.system(size: 20))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Text("\(name)'s camera is off")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            )
                                    }
                                    
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Text(name)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.black.opacity(0.6))
                                                .cornerRadius(6)
                                            Spacer()
                                        }
                                        .padding(8)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(16)
                }
            }
            
            // 2. Picture-in-Picture Local Camera Preview (Floating in bottom-right corner)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if appState.localStreamId != nil && !isCameraOff {
                        CameraPreviewView(session: appState.cameraCaptureManager.previewSession)
                            .frame(width: 140, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                            .padding(16)
                    }
                }
            }
            
            // 3. Name Tag Overlay (Top-Left: Host name, Bottom-Left: User name tag)
            VStack {
                HStack {
                    Text(isHostOnline ? "\(appState.hostProducerName) (Producer)" : "Waiting for Host")
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    Spacer()
                    
                    if appState.isRecording {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("STUDIO RECORDING ACTIVE").font(.caption).fontWeight(.bold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    }
                }
                .padding(16)
                
                Spacer()
                
                HStack {
                    Text("\(appState.displayName) (You)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                        .padding(16)
                    Spacer()
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
    }

    // MARK: - Full-Width Control Bar (Exactly Google Meet Style)
    private var fullWidthControlBar: some View {
        HStack {
            // Left Side: Time | Session ID details
            HStack(spacing: 12) {
                Text(currentTime)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                
                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.2))
                
                let statusText = appState.isDirector ? (appState.isRunning ? "Host Studio Active" : "Green Room") : (appState.isConnected ? "Guest Connected" : "Not Linked")
                let txStatus = (!appState.isMuted && appState.localAudioLevel > 0.05) ? " | 🎙️ Broadcasting" : ""
                Text("\(statusText)\(txStatus)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(width: 250, alignment: .leading)
            
            Spacer()
            
            // Center Controls
            HStack(spacing: 14) {
                // Mic Button Group
                HStack(spacing: 4) {
                    circularControl(
                        icon: isMuted ? "mic.slash.fill" : "mic.fill",
                        color: isMuted ? meetControlRed : meetControlBackground,
                        audioLevel: isMuted ? nil : appState.localAudioLevel
                    ) {
                        appState.isMuted.toggle()
                    }
                    
                    Button(action: {
                        showMicPopover = true
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                            .background(meetControlBackground)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showMicPopover, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Input Diagnostics
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Input Diagnostics")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                HStack(spacing: 3) {
                                    ForEach(0..<15, id: \.self) { index in
                                        let levelThreshold = Float(index) / 15.0
                                        let isActive = appState.localAudioLevel > levelThreshold
                                        let color: Color = index > 11 ? .red : (index > 8 ? .yellow : .green)
                                        
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(isActive ? color : Color.white.opacity(0.1))
                                            .frame(width: 7, height: 14)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(6)
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            // Input Device selection
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Input Device")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Picker("", selection: $appState.selectedMic) {
                                    ForEach(appState.availableMics, id: \.self) { mic in
                                        Text(mic).tag(mic)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            // Input Profile selection
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Input Profile")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Picker("", selection: $appState.selectedAudioProfile) {
                                    Text("Voice Isolation").tag("Voice Isolation")
                                    Text("Studio").tag("Studio")
                                    Text("Custom").tag("Custom")
                                }
                                .pickerStyle(.radioGroup)
                                .labelsHidden()
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            // Input Volume
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Input Volume")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                HStack(spacing: 8) {
                                    Image(systemName: "mic.fill")
                                        .foregroundColor(.secondary)
                                    Slider(value: $appState.inputVolume, in: 0...1)
                                        .accentColor(.blue)
                                    Image(systemName: "mic.and.signal.meter.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.1))
                            
                            // Bottom Action Link: Voice Settings
                            Button(action: {
                                showMicPopover = false
                                activeSidebarTab = 3
                                withAnimation { showSidebar = true }
                            }) {
                                HStack {
                                    Text("Voice Settings")
                                    Spacer()
                                    Image(systemName: "gearshape.fill")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .frame(width: 250)
                    }
                }
                
                // Speaker Button Group
                HStack(spacing: 4) {
                    circularControl(
                        icon: appState.outputVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        color: appState.outputVolume == 0 ? meetControlRed : meetControlBackground
                    ) {
                        if appState.outputVolume > 0 {
                            lastNonMuteVolume = appState.outputVolume
                            appState.outputVolume = 0
                        } else {
                            appState.outputVolume = lastNonMuteVolume
                        }
                    }
                    
                    Button(action: {
                        showVolumePopover = true
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                            .background(meetControlBackground)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showVolumePopover, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Output Volume")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "speaker.fill")
                                    .foregroundColor(.secondary)
                                Slider(value: $appState.outputVolume, in: 0...1)
                                    .frame(width: 140)
                                    .accentColor(.blue)
                                Image(systemName: "speaker.wave.3.fill")
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            Button(action: {
                                showVolumePopover = false
                                activeSidebarTab = 3
                                withAnimation { showSidebar = true }
                            }) {
                                HStack {
                                    Image(systemName: "gearshape")
                                    Text("Studio Console Setup")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .frame(width: 220)
                    }
                }
                
                // Camera Button
                circularControl(
                    icon: isCameraOff ? "video.slash.fill" : "video.fill",
                    color: isCameraOff ? meetControlRed : meetControlBackground
                ) {
                    if appState.isDirector ? appState.isRunning : appState.isConnected {
                        if isCameraOff {
                            appState.startStreaming()
                        } else {
                            appState.stopStreaming()
                        }
                    } else {
                        appState.isCameraOff.toggle()
                    }
                }
                
                // Share Screen Menu Button
                Menu {
                    Button(action: {
                        appState.refreshAvailableDisplays()
                        if appState.availableDisplays.isEmpty {
                            appState.isScreenSharing.toggle()
                        }
                    }) {
                        Text("Refresh Screen List")
                    }
                    Divider()
                    ForEach(appState.availableDisplays) { display in
                        Button(action: {
                            appState.selectedDisplayID = display.id
                            if !appState.isScreenSharing {
                                appState.isScreenSharing = true
                            }
                        }) {
                            HStack {
                                Text(display.name)
                                if appState.isScreenSharing && appState.selectedDisplayID == display.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    if appState.isScreenSharing {
                        Divider()
                        Button(action: {
                            appState.isScreenSharing = false
                        }) {
                            Text("Stop Sharing")
                                .foregroundColor(.red)
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(appState.isScreenSharing ? Color.blue : meetControlBackground)
                            .frame(width: 40, height: 40)
                        Image(systemName: appState.isScreenSharing ? "square.and.arrow.up.fill" : "square.and.arrow.up")
                            .foregroundColor(.white)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 40, height: 40)
                .onAppear {
                    appState.refreshAvailableDisplays()
                }
                
                // Recording Controller (Director Host only)
                if appState.isDirector && appState.isRunning {
                    circularControl(
                        icon: appState.isRecording ? "record.circle.fill" : "record.circle",
                        color: appState.isRecording ? meetControlRed : meetControlBackground
                    ) {
                        appState.toggleRecording()
                    }
                }
                
                Spacer().frame(width: 20)
                
                // Red End Session Pill (Meet Style)
                Button(action: {
                    if appState.isDirector {
                        appState.stopDirector()
                    } else {
                        appState.disconnect()
                    }
                }) {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(meetControlRed)
                        .frame(width: 60, height: 44)
                        .overlay(
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(TactileButtonStyle())
            }
            
            Spacer()
            
            // Right Side Utility controls
            HStack(spacing: 16) {
                // Sidebar details trigger
                utilityButton(icon: "info.circle", index: 0)
                
                // Active Devices list trigger
                utilityButton(icon: "tv.and.hardware.on.tablet", index: 1, count: appState.connectedClients.count)
                
                // Log outputs trigger
                utilityButton(icon: "terminal", index: 2)
                
                // Diagnostics settings trigger
                utilityButton(icon: "gearshape", index: 3)
            }
            .frame(width: 250, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(red: 23/255, green: 24/255, blue: 26/255))
        .border(Color.white.opacity(0.08), width: 1)
    }

    private func circularControl(icon: String, color: Color, audioLevel: Float? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if let level = audioLevel, level > 0.01 {
                    Circle()
                        .stroke(Color.green.opacity(0.8), lineWidth: CGFloat(2.0 + level * 10.0))
                        .scaleEffect(CGFloat(1.0 + level * 0.5))
                        .opacity(CGFloat(1.0 - level))
                        .frame(width: 44, height: 44)
                }
                Circle()
                    .fill(color)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(TactileButtonStyle())
    }

    private func utilityButton(icon: String, index: Int, count: Int = 0) -> some View {
        let isActive = showSidebar && activeSidebarTab == index
        
        return Button(action: {
            withAnimation {
                if showSidebar && activeSidebarTab == index {
                    showSidebar = false
                } else {
                    activeSidebarTab = index
                    showSidebar = true
                }
            }
        }) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isActive ? meetAccentBlue : .white.opacity(0.85))
                
                if count > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                                .padding(3)
                                .background(Color.blue)
                                .clipShape(Circle())
                        }
                    }
                    .frame(width: 24, height: 24)
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sidebar details Drawer Panels
    private var meetingSidebarPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text(activeSidebarTab == 0 ? "About Session" : (activeSidebarTab == 1 ? "Devices linked" : (activeSidebarTab == 2 ? "Activity Logs" : "Studio Console Setup")))
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Button(action: { withAnimation { showSidebar = false } }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 24)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if activeSidebarTab == 0 {
                        sessionDetailsTab
                    } else if activeSidebarTab == 1 {
                        devicesListTab
                    } else if activeSidebarTab == 2 {
                        logsConsoleTab
                    } else {
                        diagnosticsSettingsTab
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private var sessionDetailsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if appState.isDirector {
                Text("Hosting Studio Session")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if appState.isRunning {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Joining Code")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(appState.ticketText)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(6)
                            
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(appState.ticketText, forType: .string)
                                showCopiedAlert = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showCopiedAlert = false
                                }
                            }) {
                                Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(showCopiedAlert ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("Provide this code to remote camera/mic devices to connect them.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if let qrCode = generateQRCode(from: appState.ticketText) {
                            VStack(spacing: 8) {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                    .padding(.vertical, 8)
                                
                                Text("Scan to Link Device")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                Image(nsImage: qrCode)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 140, height: 140)
                                    .padding(8)
                                    .background(Color.white)
                                    .cornerRadius(10)
                                    .shadow(radius: 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }
            } else {
                Text("Participant Profile Settings")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Display Name").font(.caption).foregroundColor(.secondary)
                    TextField("Name", text: $appState.displayName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(appState.isConnected)
                    
                    Text("Device Class").font(.caption).foregroundColor(.secondary)
                    TextField("Device type", text: $appState.deviceType)
                        .textFieldStyle(.roundedBorder)
                        .disabled(appState.isConnected)
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
            }
        }
    }

    private var devicesListTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active linked streams (\(appState.connectedClients.count))")
                .font(.subheadline)
                .fontWeight(.medium)
            
            if appState.connectedClients.isEmpty {
                Text("No remote streams connected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(appState.connectedClients, id: \.self) { clientId in
                    let details = appState.clientsMap[clientId]
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(details?.name ?? "Guest")
                                .font(.body)
                                .fontWeight(.semibold)
                            Text(details?.device ?? "Device")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        // Status light
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }
            }
        }
    }

    private var logsConsoleTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Console status logs")
                .font(.subheadline)
                .fontWeight(.medium)
            
            ScrollViewReader { proxy in
                ScrollView {
                    Text(appState.statusMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black)
                        .cornerRadius(8)
                        .id("log_body")
                }
                .frame(maxHeight: 350)
                .onAppear {
                    proxy.scrollTo("log_body", anchor: .bottom)
                }
                .onChange(of: appState.statusMessage) { _ in
                    proxy.scrollTo("log_body", anchor: .bottom)
                }
            }
        }
    }
    private var stageConfigSection: some View {
        let desc: String = {
            switch appState.productionProfile {
            case "Proscenium":
                return "Traditional setup where the audience faces the stage. Optimizes layout for a single keynote presenter or screenshare."
            case "Thrust":
                return "Stage protrudes outward. Audience surrounds on three sides. Perfect for interactive panel discussions."
            case "In the Round":
                return "Circular performance space where the audience surrounds the stage. Ideal for roundtables and informal huddles."
            case "Traverse":
                return "Runway-style stage with audience on two opposing sides. Best for side-by-side comparisons or showcases."
            case "Black Box":
                return "Flexible room reconfigurable depending on the event. Adaptable for custom feeds and stream output."
            default:
                return "Standard stage layout."
            }
        }()
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .foregroundColor(.blue)
                    .font(.headline)
                Text("Stage Configuration")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            Picker("Stage Configuration", selection: $appState.productionProfile) {
                Text("Proscenium (TED Keynote)").tag("Proscenium")
                Text("Thrust (Panel Discussion)").tag("Thrust")
                Text("In the Round (Arena Huddle)").tag("In the Round")
                Text("Traverse (Runway Showcase)").tag("Traverse")
                Text("Black Box Studio (Custom)").tag("Black Box")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            
            Text(desc)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var rtmpBroadcastSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: appState.isStreamingLive ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundColor(appState.isStreamingLive ? .red : .secondary)
                    .font(.headline)
                Text("RTMP Live Output")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Live badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.isStreamingLive ? Color.red : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(appState.isStreamingLive ? "LIVE" : "STANDBY")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(appState.isStreamingLive ? .red : .secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06))
                .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Stream Endpoint URL")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("RTMP URL", text: $appState.streamUrl)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Stream Key")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                SecureField("Key", text: $appState.streamKey)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(4)
            }
            
            Button(action: {
                appState.isStreamingLive.toggle()
            }) {
                Text(appState.isStreamingLive ? "Stop Stream" : "Go Live & Broadcast")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(appState.isStreamingLive ? Color.red : Color.blue)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var auditoriumSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "theatermasks.fill")
                    .foregroundColor(.blue)
                    .font(.headline)
                Text("The Auditorium (House & FOH)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            // Audience Seating Progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("House Occupancy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(appState.auditoriumViewers) / \(appState.auditoriumCapacity) Seats (\(Int(Double(appState.auditoriumViewers) / Double(appState.auditoriumCapacity) * 100))%)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: Double(appState.auditoriumViewers), total: Double(appState.auditoriumCapacity))
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // House Access Control
            Toggle("Open House Doors (Start Spectator Feed)", isOn: $appState.isAuditoriumDoorsOpen)
                .toggleStyle(.switch)
                .font(.caption)
            
            // Talkback and Fourth Wall Toggles
            HStack(spacing: 12) {
                // Talkback
                Button(action: {
                    appState.talkbackEnabled.toggle()
                }) {
                    HStack {
                        Image(systemName: appState.talkbackEnabled ? "megaphone.fill" : "megaphone")
                        Text("Stage Talkback")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(appState.talkbackEnabled ? Color.green : Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // Break Fourth Wall
                Button(action: {
                    appState.breakingFourthWall.toggle()
                }) {
                    HStack {
                        Image(systemName: appState.breakingFourthWall ? "person.3.sequence.fill" : "person.3.sequence")
                        Text("Q&A Aside")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(appState.breakingFourthWall ? Color.orange : Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            // Comps Counter
            HStack {
                Text("VIP Comps Issued")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Stepper(value: $appState.compsAllocated, in: 0...500) {
                    Text("\(appState.compsAllocated) tickets")
                        .font(.system(size: 10, weight: .medium))
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var mixerConsoleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "fader.up")
                    .foregroundColor(.blue)
                    .font(.headline)
                Text("Live Mixer Console")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            // Host Channel
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Host Microphone (Preamp)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.0f%%", appState.inputVolume * 100))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Slider(value: $appState.inputVolume, in: 0...1)
                    .accentColor(.blue)
            }
            
            // Guest Channels
            if appState.connectedClients.isEmpty {
                Text("No remote guest channels connected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(appState.connectedClients, id: \.self) { clientId in
                    let name = appState.clientsMap[clientId]?.name ?? "Guest Feed"
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(name)
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            let mixVol = appState.clientMixVolumes[clientId] ?? 1.0
                            Text(String(format: "%.0f%%", mixVol * 100))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 8) {
                            // Live client level meter
                            let level = appState.clientAudioLevels[clientId] ?? 0.0
                            Capsule()
                                .fill(level > 0.05 ? Color.green : Color.white.opacity(0.1))
                                .frame(width: 8, height: 16)
                            
                            Slider(value: Binding(
                                get: { appState.clientMixVolumes[clientId] ?? 1.0 },
                                set: { appState.clientMixVolumes[clientId] = $0 }
                            ), in: 0...1)
                            .accentColor(.blue)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var soundboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "music.note.house")
                    .foregroundColor(.blue)
                    .font(.headline)
                Text("Studio Soundboard")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            HStack(spacing: 8) {
                Button(action: {
                    appState.playStingerSound(named: "applause")
                }) {
                    VStack(spacing: 4) {
                        Text("👏")
                            .font(.title2)
                        Text("Applause")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    appState.playStingerSound(named: "alert")
                }) {
                    VStack(spacing: 4) {
                        Text("🔔")
                            .font(.title2)
                        Text("Buzzer")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    appState.playStingerSound(named: "transition")
                }) {
                    VStack(spacing: 4) {
                        Text("💨")
                            .font(.title2)
                        Text("Whoosh")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var engineConfigSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .foregroundColor(.blue)
                    .font(.headline)
                Text("Studio Engine Config")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            // Sample Rate Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Hardware Sample Rate")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Sample Rate", selection: $appState.studioSampleRate) {
                    Text("44.1 kHz").tag(44100.0)
                    Text("48.0 kHz").tag(48000.0)
                }
                .pickerStyle(.segmented)
            }
            
            // Buffer Size Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("I/O Buffer Size (Latency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Buffer Size", selection: $appState.audioBufferSize) {
                    Text("128 smpl").tag(128)
                    Text("256 smpl").tag(256)
                    Text("512 smpl").tag(512)
                    Text("1024 smpl").tag(1024)
                }
                .pickerStyle(.segmented)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Echo Cancellation Toggle (AEC)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Echo Cancellation (AEC)")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Reduces microphone spill from local speakers.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $appState.enableVoiceProcessing)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Stage Bleed Protection
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.badge.minus")
                        .foregroundColor(.blue)
                        .font(.headline)
                    Text("Stage Bleed Protection")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Toggle("Enable Bleed Prevention", isOn: $appState.enableProximityMerge)
                    .toggleStyle(.switch)
                    .font(.caption)
                
                Text("Mutes incoming feeds when multiple devices are in close physical proximity to prevent howling feedback loops.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            
            // Console Diagnostics
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle")
                        .foregroundColor(.blue)
                        .font(.headline)
                    Text("Console Diagnostics")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                // Mic Check Row
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Mic Check")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Button(action: {
                            appState.isTestingMic.toggle()
                        }) {
                            Text(appState.isTestingMic ? "Stop Check" : "Start Check")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(appState.isTestingMic ? Color.red : Color.blue)
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Small visual meter
                    HStack(spacing: 3) {
                        ForEach(0..<15, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1)
                                .fill((appState.micTestLevel > Float(index) / 15.0) ? (index > 11 ? Color.red : (index > 8 ? Color.yellow : Color.green)) : Color.white.opacity(0.1))
                                .frame(height: 10)
                        }
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(4)
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                // Monitor Check Row
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monitor Check")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Trigger sound test to verify speakers.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        appState.playSpeakerTestSound()
                    }) {
                        Text(appState.isPlayingTestSound ? "Playing Chime..." : "Test Chime")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(appState.isPlayingTestSound ? Color.green : Color.blue)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isPlayingTestSound)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var diagnosticsSettingsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            stageConfigSection
            rtmpBroadcastSection
            auditoriumSection
            mixerConsoleSection
            soundboardSection
            engineConfigSection
            diagnosticsSection
        }
    }

    // MARK: - Helpers
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        currentTime = formatter.string(from: Date())
    }

}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
