import SwiftUI

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
    
    // Bottom Sheet states
    @State private var showDetailsSheet: Bool = false
    @State private var activeSheetTab: Int = 0 // 0: Info, 1: Devices, 2: Logs
    
    // Bind states directly to AppState
    private var isCameraOff: Bool { appState.isCameraOff }
    private var isMuted: Bool { appState.isMuted }
    private var isScreenSharing: Bool { appState.isScreenSharing }
    @State private var currentTime: String = ""
    @State private var showQRScanner: Bool = false
    @State private var isPulsing: Bool = false
    @State private var lastNonMuteVolume: Float = 0.5
    @State private var showVolumePopover: Bool = false
    @State private var showMicPopover: Bool = false

    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Google Meet Premium Colors
    private let meetBackground = Color(red: 23/255, green: 24/255, blue: 26/255)
    private let meetCardBackground = Color(red: 32/255, green: 33/255, blue: 36/255)
    private let meetControlBackground = Color(red: 60/255, green: 64/255, blue: 67/255)
    private let meetControlRed = Color(red: 234/255, green: 67/255, blue: 53/255)
    private let meetAccentBlue = Color(red: 138/255, green: 180/255, blue: 248/255)

    var body: some View {
        VStack(spacing: 0) {
            // Main Content Area
            ZStack {
                meetBackground
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Status Bar
                    HStack {
                        Text(appState.isDirector ? "Host Studio" : "Guest Node")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if appState.isRecording {
                            HStack(spacing: 4) {
                                Circle().fill(Color.red).frame(width: 6, height: 6)
                                Text("REC").font(.caption2).fontWeight(.bold).foregroundColor(.red)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.15))
                    
                    ZStack {
                        mainVideoStage
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        if appState.enableProximityMerge && !appState.isMuted && !appState.isDirector {
                            VStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Microphone active in proximity? Use headphones to prevent echo.")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.85))
                                .cornerRadius(6)
                                .shadow(radius: 4)
                                .padding(.top, 10)
                                
                                Spacer()
                            }
                        }
                    }
                }
            }
            
            // Full-Width Google Meet Bottom Control Bar (only in active studio session)
            if appState.isDirector ? appState.isRunning : appState.isConnected {
                fullWidthControlBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            updateTime()
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onReceive(timer) { _ in
            updateTime()
        }

        .sheet(isPresented: $showDetailsSheet) {
            meetingDetailsSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showQRScanner) {
            VStack {
                HStack {
                    Text("Scan QR Code")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button("Cancel") {
                        showQRScanner = false
                    }
                    .foregroundColor(.blue)
                }
                .padding()
                
                QRScannerView(onScan: { code in
                    Task { @MainActor in
                        self.ticketInput = code
                        showQRScanner = false
                        if !appState.displayName.isEmpty {
                            appState.connect(ticket: code)
                        }
                    }
                }, onFailure: { error in
                    Task { @MainActor in
                        print("Scanner error: \(error.localizedDescription)")
                        showQRScanner = false
                    }
                })
                .cornerRadius(12)
                .padding()
            }
            .background(Color(red: 23/255, green: 24/255, blue: 26/255))
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Main Video Stage
    private var mainVideoStage: some View {
        VStack {
            if appState.isDirector {
                if !appState.isRunning {
                    greenRoomView(title: "Host Studio", subtitle: "Configure settings in the sheet, then boot the host session.")
                } else if appState.connectedClients.isEmpty {
                    greenRoomView(title: "Waiting for Devices...", subtitle: "Tap Info on the bottom bar to copy the joining ticket for other devices.")
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
                                        .frame(width: 110, height: 75)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                                        .padding(12)
                                }
                            }
                        }
                    }
                }
            } else {
                if !appState.isConnected {
                    greenRoomView(title: "Ready to join?", subtitle: "Enter the Director's session code in the sheet to link your camera/mic.")
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
                                        .frame(width: 110, height: 75)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                                        .padding(12)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Green Room (Self-Preview)
    private func greenRoomView(title: String, subtitle: String) -> some View {
        VStack(spacing: 24) {
            // Self preview card
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(meetCardBackground)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                
                if isCameraOff && !appState.isScreenSharing {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 64, height: 64)
                                .scaleEffect(isPulsing ? 1.05 : 0.95)
                                .opacity(isPulsing ? 0.8 : 0.5)
                            
                            Image(systemName: "video.slash.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary)
                        }
                        Text("Camera is off")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if appState.isScreenSharing {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(meetAccentBlue.opacity(0.1))
                                .frame(width: 64, height: 64)
                            
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.system(size: 22))
                                .foregroundColor(meetAccentBlue)
                        }
                        Text("You are sharing your screen")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    CameraPreviewView(session: appState.cameraCaptureManager.previewSession)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                
                // Docked preview toggles (only shown if bottom control bar is hidden)
                if !(appState.isDirector ? appState.isRunning : appState.isConnected) {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Button(action: { appState.isMuted.toggle() }) {
                                ZStack {
                                    Circle()
                                        .fill(isMuted ? meetControlRed : Color.white.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                                        .font(.caption)
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
                                        .frame(width: 36, height: 36)
                                    Image(systemName: isCameraOff ? "video.slash.fill" : "video.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                if showDetailsSheet && activeSheetTab == 0 {
                                    showDetailsSheet = false
                                } else {
                                    activeSheetTab = 0
                                    showDetailsSheet = true
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(showDetailsSheet && activeSheetTab == 0 ? meetAccentBlue : Color.white.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "gearshape.fill")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .frame(maxWidth: 380)
            
            // Text Details & Quick Actions
            VStack(spacing: 12) {
                if !appState.isRunning && !appState.isConnected {
                    Picker("", selection: $appState.isDirector) {
                        Text("Join Session").tag(false)
                        Text("Host Studio").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    .padding(.bottom, 8)
                }

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                if !appState.isRunning && !appState.isConnected {
                    VStack(spacing: 8) {
                        TextField("Your name", text: $appState.displayName)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(maxWidth: 280)
                    .padding(.top, 10)
                    
                    if appState.isDirector {
                        Button(action: {
                            appState.startDirector()
                            activeSheetTab = 0
                            showDetailsSheet = true
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start Studio Host")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: 240)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(meetAccentBlue)
                        .foregroundColor(.black)
                        .padding(.top, 10)
                        .disabled(appState.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    HStack {
                                        TextField("Enter code (e.g. amos-xxx)", text: $ticketInput)
                                        
                                        if !ticketInput.isEmpty {
                                            Button(action: { ticketInput = "" }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.white.opacity(0.08))
                                    .cornerRadius(8)
                                    
                                    if ticketInput.isEmpty {
                                        Button(action: {
                                            if let clipboard = UIPasteboard.general.string {
                                                ticketInput = clipboard
                                            }
                                        }) {
                                            Image(systemName: "doc.on.clipboard")
                                                .font(.body)
                                                .foregroundColor(.white)
                                                .frame(width: 44, height: 36)
                                                .background(Color.white.opacity(0.12))
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: {
                                            showQRScanner = true
                                        }) {
                                            Image(systemName: "qrcode.viewfinder")
                                                .font(.body)
                                                .foregroundColor(.white)
                                                .frame(width: 44, height: 36)
                                                .background(Color.white.opacity(0.12))
                                                .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
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
                                .frame(maxWidth: 240)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(meetAccentBlue)
                            .foregroundColor(.black)
                            .disabled(ticketInput.isEmpty || appState.displayName.isEmpty)
                        }
                        .frame(maxWidth: 280)
                        .padding(.top, 10)
                    }
                } else if appState.isDirector && appState.isRunning {
                    // Host is running, waiting for devices
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Waiting for devices...")
                                .font(.headline)
                                .foregroundColor(meetAccentBlue)
                        }
                        
                        Text("Tap Info or Share on the bottom bar to copy the ticket or scan the QR code to link your devices.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Director Grid
    private var directorVideoGrid: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(appState.connectedClients, id: \.self) { clientId in
                    let name = appState.clientsMap[clientId]?.name ?? "Guest"
                    let device = appState.clientsMap[clientId]?.device ?? "Camera Feed"
                    
                    VStack(spacing: 0) {
                        let isVideoOn = (clientId == "host") ? appState.isHostVideoOn : (appState.clientVideoStates[clientId] ?? true)
                        
                        ZStack {
                            RemoteVideoView(clientId: clientId, appState: appState)
                                .aspectRatio(16/9, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .opacity(isVideoOn ? 1.0 : 0.0)
                            
                            if !isVideoOn {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(meetCardBackground)
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.white.opacity(0.1))
                                                    .frame(width: 50, height: 50)
                                                    .scaleEffect(isPulsing ? 1.05 : 0.95)
                                                    .opacity(isPulsing ? 0.8 : 0.5)
                                                
                                                Image(systemName: "video.slash.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(.secondary)
                                            }
                                            Text("\(name)'s camera is off")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    )
                            }
                            
                            // HUD Overlay
                            VStack(alignment: .leading) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text(name)
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                            
                                            let currentLevel = (clientId == "host" && appState.isDirector)
                                                ? appState.localAudioLevel
                                                : (appState.clientAudioLevels[clientId] ?? 0.0)
                                            
                                            if currentLevel > 0.05 {
                                                HStack(spacing: 1.5) {
                                                    RoundedRectangle(cornerRadius: 0.5)
                                                        .fill(Color.green)
                                                        .frame(width: 1.5, height: CGFloat(4 + currentLevel * 8))
                                                    RoundedRectangle(cornerRadius: 0.5)
                                                        .fill(Color.green)
                                                        .frame(width: 1.5, height: CGFloat(6 + currentLevel * 12))
                                                    RoundedRectangle(cornerRadius: 0.5)
                                                        .fill(Color.green)
                                                        .frame(width: 1.5, height: CGFloat(4 + currentLevel * 8))
                                                }
                                                .animation(.easeInOut(duration: 0.1), value: currentLevel)
                                            }
                                        }
                                        Text("\(device) • P2P H.264")
                                            .font(.system(size: 8))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                     .padding(.horizontal, 8)
                                     .padding(.vertical, 4)
                                     .background(.ultraThinMaterial)
                                     .cornerRadius(8)
                                     .overlay(
                                         RoundedRectangle(cornerRadius: 8)
                                             .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                     )
                                    
                                    Spacer()
                                    
                                    if appState.isRecording {
                                        HStack(spacing: 3) {
                                            Circle().fill(Color.red).frame(width: 5, height: 5)
                                            Text("REC").font(.system(size: 8, weight: .bold))
                                        }
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(4)
                                    }
                                }
                                .padding(8)
                                
                                Spacer()
                                
                                HStack {
                                    Text(appState.isRecording ? "Recording" : "Connected")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(appState.isRecording ? .red : .green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.black.opacity(0.6))
                                        .cornerRadius(4)
                                    
                                    Spacer()
                                    
                                    // Trigger Keyframe
                                    Button(action: { appState.requestKeyframe(clientId: clientId, streamId: "1") }) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(6)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(8)
                            }
                        }
                        .frame(height: 180)
                        .background(meetCardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Participant Video Stage
    private var participantVideoStage: some View {
        let isHostOnline = appState.connectedClients.contains("host")
        let isSpeaking = !isMuted && appState.localStreamId != nil
        let remoteClients = appState.connectedClients
        
        return ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(meetCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSpeaking ? Color.green : Color.white.opacity(0.08), lineWidth: isSpeaking ? 2.5 : 1)
                )
            
            if remoteClients.isEmpty {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 76, height: 76)
                            .scaleEffect(isPulsing ? 1.05 : 0.95)
                            .opacity(isPulsing ? 0.8 : 0.5)
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                    }
                    Text("Waiting for Host (Producer)...")
                        .font(.subheadline)
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
                                    .frame(width: 76, height: 76)
                                Image(systemName: "video.slash.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary)
                            }
                            Text("\(name)'s video is off")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(meetCardBackground)
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
                                            .fill(meetCardBackground)
                                            .aspectRatio(16/9, contentMode: .fit)
                                            .overlay(
                                                VStack(spacing: 12) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(Color.white.opacity(0.1))
                                                            .frame(width: 50, height: 50)
                                                        Image(systemName: "video.slash.fill")
                                                            .font(.system(size: 18))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Text("\(name)'s camera is off")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            )
                                    }
                                    
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Text(name)
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.black.opacity(0.6))
                                                .cornerRadius(4)
                                            Spacer()
                                        }
                                        .padding(6)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                            .frame(width: 110, height: 75)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                            .padding(12)
                    }
                }
            }
            
            // 3. Name Tag Overlay (Top-Left: Host name, Bottom-Left: User name tag)
            VStack {
                HStack {
                    Text(isHostOnline ? "\(appState.hostProducerName) (Producer)" : "Waiting for Host")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                    Spacer()
                }
                .padding(12)
                
                Spacer()
                
                HStack {
                    Text("\(appState.displayName) (You)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(4)
                        .padding(12)
                    Spacer()
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
    }

    // MARK: - Bottom Control Bar
    private var fullWidthControlBar: some View {
        VStack(spacing: 4) {
            HStack {
                // Time & Status Code
                HStack(spacing: 6) {
                    Text(currentTime)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    if (appState.isDirector && appState.isRunning) || appState.isConnected {
                        Text("•")
                            .foregroundColor(.secondary)
                        let statusText = appState.isDirector ? "Host Active" : "Guest Connected"
                        let txStatus = (!isMuted && appState.localAudioLevel > 0.05) ? " | 🎙️ Broadcasting" : ""
                        Text("\(statusText)\(txStatus)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            HStack(spacing: 12) {
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
                            Text("Input Diagnostics")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            // Micro level preview inside popover
                            HStack(spacing: 3) {
                                ForEach(0..<15, id: \.self) { index in
                                    let levelThreshold = Float(index) / 15.0
                                    let isActive = appState.localAudioLevel > levelThreshold
                                    let color: Color = index > 11 ? .red : (index > 8 ? .yellow : .green)
                                    
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(isActive ? color : Color.white.opacity(0.1))
                                        .frame(width: 6, height: 14)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            
                            Text("Input Volume")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "mic.fill")
                                    .foregroundColor(.secondary)
                                Slider(value: $appState.inputVolume, in: 0...1)
                                    .accentColor(.blue)
                                Image(systemName: "mic.and.signal.meter.fill")
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            Button(action: {
                                showMicPopover = false
                                activeSheetTab = 0
                                showDetailsSheet = true
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
                                    .accentColor(.blue)
                                Image(systemName: "speaker.wave.3.fill")
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider()
                            
                            Button(action: {
                                showVolumePopover = false
                                activeSheetTab = 0
                                showDetailsSheet = true
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
                circularControl(icon: isCameraOff ? "video.slash.fill" : "video.fill", color: isCameraOff ? meetControlRed : meetControlBackground) {
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
                
                // Share Screen Button
                circularControl(icon: isScreenSharing ? "square.and.arrow.up.fill" : "square.and.arrow.up", color: isScreenSharing ? Color.blue : meetControlBackground) {
                    appState.isScreenSharing.toggle()
                }
                
                // Recording Toggle (Director only)
                if appState.isDirector && appState.isRunning {
                    circularControl(icon: appState.isRecording ? "record.circle.fill" : "record.circle", color: appState.isRecording ? meetControlRed : meetControlBackground) {
                        appState.toggleRecording()
                    }
                }
                
                // Info Details sheet trigger
                circularControl(icon: "info.circle", color: meetControlBackground) {
                    activeSheetTab = 0
                    showDetailsSheet = true
                }
                
                // Linked Devices sheet trigger
                circularControl(icon: "tv.and.hardware.on.tablet", color: meetControlBackground) {
                    activeSheetTab = 1
                    showDetailsSheet = true
                }
                
                Spacer()
                
                Spacer().frame(width: 16)
                
                // Red End Call Pill (Meet Style)
                Button(action: {
                    if appState.isDirector {
                        appState.stopDirector()
                    } else {
                        appState.disconnect()
                    }
                }) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(meetControlRed)
                        .frame(width: 52, height: 40)
                        .overlay(
                            Image(systemName: "phone.down.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(TactileButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
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
                        .frame(width: 40, height: 40)
                }
                Circle()
                    .fill(color)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(TactileButtonStyle())
    }

    // MARK: - Slide sheets for mobile settings
    private var meetingDetailsSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Tabs Row
            HStack(spacing: 20) {
                TabButton(title: "Info", index: 0, activeIndex: $activeSheetTab)
                TabButton(title: "Devices", index: 1, activeIndex: $activeSheetTab)
                TabButton(title: "Logs", index: 2, activeIndex: $activeSheetTab)
                Spacer()
                Button("Done") {
                    showDetailsSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding(.top)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if activeSheetTab == 0 {
                        sheetInfoTab
                    } else if activeSheetTab == 1 {
                        sheetDevicesTab
                    } else {
                        sheetLogsTab
                    }
                }
            }
        }
        .padding()
    }

    private var sheetInfoTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if appState.isDirector {
                Text("Host Studio Control")
                    .font(.headline)
                
                if appState.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Joining Code").font(.caption).foregroundColor(.secondary)
                        HStack {
                            Text(appState.ticketText)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(action: {
                                UIPasteboard.general.string = appState.ticketText
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
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(6)
                    }
                } else {
                    Button(action: {
                        appState.startDirector()
                        showDetailsSheet = false
                    }) {
                        Text("Start Studio Host")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            } else {
                Text("Join Session")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Display Name").font(.caption).foregroundColor(.secondary)
                    TextField("Name", text: $appState.displayName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(appState.isConnected)
                    
                    Text("Device Type").font(.caption).foregroundColor(.secondary)
                    TextField("Device", text: $appState.deviceType)
                        .textFieldStyle(.roundedBorder)
                        .disabled(appState.isConnected)
                    
                    if !appState.isConnected {
                        Text("Session Ticket").font(.caption).foregroundColor(.secondary)
                        TextField("Paste code...", text: $ticketInput)
                            .textFieldStyle(.roundedBorder)
                        
                        Button(action: {
                            appState.connect(ticket: ticketInput)
                            showDetailsSheet = false
                        }) {
                            Text("Connect Device")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(ticketInput.isEmpty)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Linked to session successfully")
                                .fontWeight(.bold)
                        }
                        .padding(.top, 10)
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Text("Studio Console Setup")
                .font(.headline)
            
            // SECTION 1: EVENT PRODUCTION PROFILE
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group")
                        .foregroundColor(.blue)
                        .font(.subheadline)
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
                
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)

            // SECTION 2: RTMP BROADCAST STREAM
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: appState.isStreamingLive ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(appState.isStreamingLive ? .red : .secondary)
                        .font(.subheadline)
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
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stream Key")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    SecureField("Key", text: $appState.streamKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
                
                Button(action: {
                    appState.isStreamingLive.toggle()
                }) {
                    Text(appState.isStreamingLive ? "Stop Stream" : "Go Live & Broadcast")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(appState.isStreamingLive ? Color.red : Color.blue)
                        .cornerRadius(8)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)

            // SECTION 3: THE AUDITORIUM (House & FOH)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "theatermasks.fill")
                        .foregroundColor(.blue)
                        .font(.subheadline)
                    Text("The Auditorium (House & FOH)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                // Audience Seating Progress
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("House Occupancy")
                            .font(.caption2)
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
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
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
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(appState.talkbackEnabled ? Color.green : Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
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
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(appState.breakingFourthWall ? Color.orange : Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                
                // Comps Counter
                HStack {
                    Text("VIP Comps Issued")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Stepper(value: $appState.compsAllocated, in: 0...500) {
                        Text("\(appState.compsAllocated) tix")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)

            // SECTION 4: LIVE MIXER CONSOLE
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "fader.up")
                        .foregroundColor(.blue)
                        .font(.subheadline)
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
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)

            // SECTION 4: STUDIO SOUNDBOARD ( Stingers )
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.house")
                        .foregroundColor(.blue)
                        .font(.subheadline)
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
                                .font(.title3)
                            Text("Applause")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                    }
                    
                    Button(action: {
                        appState.playStingerSound(named: "alert")
                    }) {
                        VStack(spacing: 4) {
                            Text("🔔")
                                .font(.title3)
                            Text("Buzzer")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                    }
                    
                    Button(action: {
                        appState.playStingerSound(named: "transition")
                    }) {
                        VStack(spacing: 4) {
                            Text("💨")
                                .font(.title3)
                            Text("Whoosh")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)

            // SECTION 5: CONSOLE HARDWARE CONFIGURATION (Buffer, Sample Rate, AEC)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .foregroundColor(.blue)
                        .font(.subheadline)
                    Text("Studio Engine Config")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                // Sample Rate Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hardware Sample Rate")
                        .font(.caption2)
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
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Picker("Buffer Size", selection: $appState.audioBufferSize) {
                        Text("128").tag(128)
                        Text("256").tag(256)
                        Text("512").tag(512)
                        Text("1024").tag(1024)
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
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .labelsHidden()
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)

            // SECTION 6: STAGE ACOUSTIC OPTIONS (Bleed protection)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.badge.minus")
                        .foregroundColor(.blue)
                        .font(.subheadline)
                    Text("Stage Bleed Protection")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                Toggle("Enable Bleed Prevention", isOn: $appState.enableProximityMerge)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .font(.caption)
                
                Text("Mutes incoming feeds when multiple devices are in close physical proximity to prevent howling feedback loops.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)

            // SECTION 7: HARDWARE CHECK / DIAGNOSTICS
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle")
                        .foregroundColor(.blue)
                        .font(.subheadline)
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
                    }
                    
                    // Small visual meter
                    HStack(spacing: 3) {
                        ForEach(0..<15, id: \.self) { index in
                            let levelThreshold = Float(index) / 15.0
                            let isActive = appState.micTestLevel > levelThreshold
                            let color: Color = index > 11 ? .red : (index > 8 ? .yellow : .green)
                            
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isActive ? color : Color.white.opacity(0.1))
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
                    .disabled(appState.isPlayingTestSound)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .cornerRadius(12)
        }
    }

    private var sheetDevicesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Linked hardware streams (\(appState.connectedClients.count))")
                .font(.headline)
            
            if appState.connectedClients.isEmpty {
                Text("No other devices connected to this studio.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(appState.connectedClients, id: \.self) { clientId in
                    let details = appState.clientsMap[clientId]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(details?.name ?? "Guest")
                                .font(.body)
                                .fontWeight(.semibold)
                            Text(details?.device ?? "Hardware")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                }
            }
        }
    }

    private var sheetLogsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terminal Logs")
                .font(.headline)
            
            Text(appState.statusMessage)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.black)
                .cornerRadius(8)
        }
    }

    // MARK: - Helpers
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        currentTime = formatter.string(from: Date())
    }


}

struct TabButton: View {
    let title: String
    let index: Int
    @Binding var activeIndex: Int
    
    var body: some View {
        Button(action: { activeIndex = index }) {
            VStack(spacing: 4) {
                Text(title)
                    .fontWeight(activeIndex == index ? .bold : .regular)
                    .foregroundColor(activeIndex == index ? .blue : .secondary)
                
                Rectangle()
                    .fill(activeIndex == index ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

// MARK: - Native QR Scanner Component
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    var onScan: @Sendable (String) -> Void
    var onFailure: @Sendable (Error) -> Void
    
    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: @Sendable (String) -> Void
        var onFailure: @Sendable (Error) -> Void
        
        init(onScan: @escaping @Sendable (String) -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
            self.onScan = onScan
            self.onFailure = onFailure
        }
        
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
                guard let stringValue = readableObject.stringValue else { return }
                AudioServicesPlaySystemSound(SystemSoundID(1519)) // Subtle peek haptic/vibe
                let scanCallback = self.onScan
                DispatchQueue.main.async {
                    scanCallback(stringValue)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onFailure: onFailure)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            context.coordinator.onFailure(NSError(domain: "QRScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video device available"]))
            return viewController
        }
        
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            context.coordinator.onFailure(error)
            return viewController
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            context.coordinator.onFailure(NSError(domain: "QRScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to add input"]))
            return viewController
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(context.coordinator, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            context.coordinator.onFailure(NSError(domain: "QRScanner", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to add output"]))
            return viewController
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = viewController.view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        viewController.view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
        
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onScan = onScan
        context.coordinator.onFailure = onFailure
    }
}
