import SwiftUI
import AVFoundation
import VideoToolbox
import CoreMedia

@MainActor
class AppState: NSObject, ObservableObject, NSSoundDelegate {
    @Published var isDirector: Bool = false
    @Published var isRunning: Bool = false
    @Published var isConnected: Bool = false
    @Published var ticketText: String = ""
    @Published var participantId: String = UUID().uuidString
    @Published var displayName: String = Host.current().localizedName ?? "Mac Participant"
    @Published var deviceType: String = "Mac Desktop"
    @Published var sessionId: String = "session_default"
    @Published var connectedClients: [String] = []
    @Published var isRecording: Bool = false
    @Published var statusMessage: String = "Ready"
    @Published var localStreamId: String? = nil
    
    @Published var isCameraAuthorized: Bool = false
    @Published var isCameraOff: Bool = true {
        didSet {
            updateCameraCapture()
            updateVideoState()
        }
    }
    @Published var isMuted: Bool = true {
        didSet {
            updateAudioCapture()
            updateVideoState()
        }
    }
    @Published var forceDismissPermissionWarning = false
    @Published var isScreenSharing: Bool = false {
        didSet {
            if isScreenSharing {
                forceDismissPermissionWarning = false
                if #available(macOS 11.0, *) {
                    if !CGPreflightScreenCaptureAccess() {
                        CGRequestScreenCaptureAccess()
                    }
                }
            }
            updateCameraCapture()
            updateVideoState()
        }
    }
    
    struct DisplayInfo: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
    }
    
    @Published var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID() {
        didSet {
            if isScreenSharing {
                updateCameraCapture()
            }
        }
    }
    @Published var availableDisplays: [DisplayInfo] = []
    @Published var isHostVideoOn: Bool = false
    @Published var isHostScreenSharing: Bool = false
    @Published var hostProducerName: String = "Host"
    @Published var clientVideoStates: [String: Bool] = [:]
    @Published var clientScreenSharingStates: [String: Bool] = [:]
    
    // For director: Client ID -> Client Details
    @Published var clientsMap: [String: (name: String, device: String)] = [:]
    
    // Dictionary to hold active display layers for remote clients
    var displayLayers: [String: AVSampleBufferDisplayLayer] = [:]
    
    // Store SPS and PPS and frame indices for each client
    var clientSps: [String: Data] = [:]
    var clientPps: [String: Data] = [:]
    private var clientFrameIndices: [String: Int64] = [:]
    
    let core: Core
    let cameraCaptureManager = CameraCaptureManager()
    let audioCaptureManager = AudioCaptureManager()
    @Published var audioStreamId: String? = nil
    @Published var localAudioLevel: Float = 0.0
    @Published var enableProximityMerge: Bool = false
    @Published var outputVolume: Float = 1.0 {
        didSet {
            updateMixVolumes()
        }
    }
    @Published var clientMixVolumes: [String: Float] = [:] {
        didSet {
            updateMixVolumes()
        }
    }
    
    func updateMixVolumes() {
        for (clientId, player) in clientAudioPlayers {
            let mixVol = clientMixVolumes[clientId] ?? 1.0
            player.setVolume(outputVolume * mixVol)
        }
    }
    
    // Live Event Production Settings
    @Published var productionProfile: String = "Proscenium"
    @Published var isStreamingLive: Bool = false
    @Published var streamKey: String = "••••••••••••"
    @Published var streamUrl: String = "rtmp://live.youtube.com/live2"
    @Published var streamQuality: String = "1080p60"
    
    // The Auditorium & FOH Controls
    @Published var auditoriumViewers: Int = 12450
    @Published var auditoriumCapacity: Int = 15000
    @Published var isAuditoriumDoorsOpen: Bool = false
    @Published var talkbackEnabled: Bool = false
    @Published var breakingFourthWall: Bool = false
    @Published var compsAllocated: Int = 125
    @Published var inputVolume: Float = 1.0 {
        didSet {
            audioCaptureManager.inputVolume = inputVolume
        }
    }
    
    @Published var availableMics: [String] = ["macOS Default"]
    @Published var selectedMic: String = "macOS Default" {
        didSet {
            applyAudioSettings()
        }
    }
    @Published var selectedAudioProfile: String = "Custom" {
        didSet {
            applyAudioSettings()
        }
    }
    
    func refreshAudioDevices() {
        let devices = AVCaptureDevice.devices(for: .audio)
        var list = ["macOS Default"]
        for d in devices {
            list.append(d.localizedName)
        }
        self.availableMics = list
        if !list.contains(selectedMic) {
            selectedMic = "macOS Default"
        }
    }
    
    func applyAudioSettings() {
        let isVoiceProcessing = (selectedAudioProfile == "Voice Isolation")
        audioCaptureManager.setVoiceProcessing(isVoiceProcessing)
        
        let devices = AVCaptureDevice.devices(for: .audio)
        if let matched = devices.first(where: { $0.localizedName == selectedMic }) {
            audioCaptureManager.inputDeviceUID = matched.uniqueID
        } else {
            audioCaptureManager.inputDeviceUID = nil
        }
        
        // Fully tear down any running audio capture instance to allow reinitialization
        audioCaptureManager.stopCapture()
        
        if isTestingMic {
            stopMicTest()
            startMicTest()
        } else if audioStreamId != nil {
            if let oldStreamId = audioStreamId {
                try? core.closeStream(streamId: oldStreamId)
                audioStreamId = nil
            }
            updateAudioCapture()
        }
    }
    @Published var studioSampleRate: Double = 44100.0
    @Published var audioBufferSize: Int = 256
    @Published var enableVoiceProcessing: Bool = true {
        didSet {
            audioCaptureManager.setVoiceProcessing(enableVoiceProcessing)
        }
    }
    @Published var clientAudioLevels: [String: Float] = [:]
    private var lastAudioTime: [String: Date] = [:]
    private var audioDecayTimer: Timer?
    var clientAudioPlayers: [String: AudioPlaybackManager] = [:]

    @Published var isTestingMic: Bool = false {
        didSet {
            if isTestingMic {
                startMicTest()
            } else {
                stopMicTest()
            }
        }
    }
    @Published var micTestLevel: Float = 0.0
    @Published var isPlayingTestSound: Bool = false
    private var wasCapturingBeforeTest = false

    override init() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0].appendingPathComponent("AmosRecordings").path
        
        do {
            try FileManager.default.createDirectory(atPath: documentsDirectory, withIntermediateDirectories: true)
        } catch {}
        
        self.core = try! Core(dataDir: documentsDirectory)
        
        super.init()
        
        refreshAvailableDisplays()
        
        requestPermissions()
        refreshAudioDevices()
        
        self.audioDecayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            Task { @MainActor in
                for (clientId, lastTime) in self.lastAudioTime {
                    if now.timeIntervalSince(lastTime) > 0.3 {
                        self.clientAudioLevels[clientId] = 0.0
                    }
                }
            }
        }
    }
    
    nonisolated func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor [weak self] in
                self?.isCameraAuthorized = granted
            }
        }
        
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("Microphone access: \(granted)")
        }
    }
    
    func registerDisplayLayer(_ layer: AVSampleBufferDisplayLayer, for clientId: String) {
        self.displayLayers[clientId] = layer
        self.clientSps[clientId] = nil
        self.clientPps[clientId] = nil
    }
    
    func handleRemoteFrame(clientId: String, timestampMs: UInt64, payload: Data) {
        let nalus = parseAnnexB(data: payload)
        var sliceNalus: [Data] = []
        for nalu in nalus {
            guard !nalu.isEmpty else { continue }
            let naluType = nalu[0] & 0x1F
            
            if naluType == 7 {
                print("DEBUG: Received SPS for \(clientId), length: \(nalu.count)")
                clientSps[clientId] = nalu
            } else if naluType == 8 {
                print("DEBUG: Received PPS for \(clientId), length: \(nalu.count)")
                clientPps[clientId] = nalu
            } else if naluType == 5 || naluType == 1 {
                sliceNalus.append(nalu)
            } else {
                print("DEBUG: Received other NALU type \(naluType) for \(clientId)")
            }
        }
        
        if !sliceNalus.isEmpty {
            if clientSps[clientId] == nil || clientPps[clientId] == nil {
                print("DEBUG: Lacking SPS/PPS for \(clientId), requesting keyframe...")
                if isDirector {
                    try? core.requestKeyframe(clientId: clientId, streamId: clientId)
                } else {
                    try? core.requestKeyframeFromHost(streamId: clientId)
                }
                return
            }
            renderFrame(clientId: clientId, timestampMs: timestampMs, slices: sliceNalus)
        } else {
            print("DEBUG: No slice NALUs found in frame payload for \(clientId)")
        }
    }
    
    func isVideoFrame(payload: Data) -> Bool {
        guard payload.count >= 3 else { return false }
        if payload[0] == 0 && payload[1] == 0 {
            if payload[2] == 1 { return true }
            if payload.count >= 4 && payload[2] == 0 && payload[3] == 1 { return true }
        }
        return false
    }

    func handleFrame(clientId: String, frameType: UInt8, timestampMs: UInt64, payload: Data) {
        if isVideoFrame(payload: payload) {
            handleRemoteFrame(clientId: clientId, timestampMs: timestampMs, payload: payload)
        } else {
            let level = Float(frameType) / 255.0
            clientAudioLevels[clientId] = level
            lastAudioTime[clientId] = Date()
            
            if clientAudioPlayers[clientId] == nil {
                let player = AudioPlaybackManager()
                player.setVolume(outputVolume * (clientMixVolumes[clientId] ?? 1.0))
                clientAudioPlayers[clientId] = player
            }
            clientAudioPlayers[clientId]?.playAudioFrame(payload: payload)
        }
    }
    
    private func parseAnnexB(data: Data) -> [Data] {
        var nalus: [Data] = []
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return [] }
        
        var startIndices: [Int] = []
        var i = 0
        let limit = bytes.count - 4
        while i <= limit {
            if bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 0 && bytes[i+3] == 1 {
                startIndices.append(i)
                i += 4
            } else {
                i += 1
            }
        }
        
        for idx in 0..<startIndices.count {
            let startOffset = startIndices[idx] + 4
            let endOffset = (idx + 1 < startIndices.count) ? startIndices[idx + 1] : bytes.count
            if endOffset > startOffset {
                let start = data.startIndex + startOffset
                let end = data.startIndex + endOffset
                nalus.append(data.subdata(in: start..<end))
            }
        }
        
        return nalus
    }
    
    private func renderFrame(clientId: String, timestampMs: UInt64, slices: [Data]) {
        guard let layer = displayLayers[clientId] else {
            print("DEBUG: Cannot render frame for \(clientId) - displayLayer is nil!")
            return
        }
        
        if layer.status == .failed {
            print("WARNING: displayLayer for \(clientId) is in failed state (\(String(describing: layer.error))). Flushing and requesting keyframe...")
            layer.flushAndRemoveImage()
            clientSps[clientId] = nil
            clientPps[clientId] = nil
            if isDirector {
                try? core.requestKeyframe(clientId: clientId, streamId: clientId)
            } else {
                try? core.requestKeyframeFromHost(streamId: clientId)
            }
            return
        }
        guard let sps = clientSps[clientId] else {
            print("DEBUG: Cannot render frame for \(clientId) - SPS is missing!")
            return
        }
        guard let pps = clientPps[clientId] else {
            print("DEBUG: Cannot render frame for \(clientId) - PPS is missing!")
            return
        }
              
        var formatDescription: CMVideoFormatDescription?
        sps.withUnsafeBytes { (spsBytes: UnsafeRawBufferPointer) in
            pps.withUnsafeBytes { (ppsBytes: UnsafeRawBufferPointer) in
                guard let spsBase = spsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ppsBase = ppsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                
                let parameterSetPointers = [spsBase, ppsBase]
                let parameterSetSizes = [sps.count, pps.count]
                
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil,
                    parameterSetCount: 2,
                    parameterSetPointers: parameterSetPointers,
                    parameterSetSizes: parameterSetSizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &formatDescription
                )
                if status != noErr {
                    print("DEBUG: CMVideoFormatDescriptionCreateFromH264ParameterSets failed: \(status)")
                }
            }
        }
        
        guard let formatDesc = formatDescription else {
            print("DEBUG: Cannot render frame for \(clientId) - formatDescription is nil!")
            return
        }
        
        // Convert all slices to AVCC format (4-byte length prefix) and concatenate
        var avccData = Data()
        for slice in slices {
            var len = UInt32(slice.count).bigEndian
            withUnsafeBytes(of: &len) { avccData.append(contentsOf: $0) }
            avccData.append(slice)
        }
        
        // Create block buffer
        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: nil,
            blockLength: avccData.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard blockStatus == noErr, let buffer = blockBuffer else {
            print("DEBUG: CMBlockBufferCreateWithMemoryBlock failed: \(blockStatus)")
            return
        }
        
        // Copy the data into the block buffer
        let copyStatus = avccData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else {
                return OSStatus(-1)
            }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: avccData.count
            )
        }
        guard copyStatus == noErr else {
            print("DEBUG: CMBlockBufferReplaceDataBytes failed: \(copyStatus)")
            return
        }
        
        // Timing: Passing CMTime.invalid as presentationTimeStamp disables
        // AVSampleBufferDisplayLayer's internal clock synchronization, forcing
        // the hardware display layer to decode and render the frame immediately upon receipt.
        var timing = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTime.invalid,
            decodeTimeStamp: CMTime.invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: nil,
            dataBuffer: buffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        if sampleStatus != noErr {
            print("DEBUG: CMSampleBufferCreateReady failed: \(sampleStatus)")
            return
        }
        
        if let sample = sampleBuffer {
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
                if CFArrayGetCount(attachmentsArray) > 0 {
                    let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, 0), to: CFMutableDictionary.self)
                    CFDictionarySetValue(attachment,
                                         unsafeBitCast(kCMSampleAttachmentKey_DisplayImmediately, to: UnsafeRawPointer.self),
                                         unsafeBitCast(kCFBooleanTrue, to: UnsafeRawPointer.self))
                }
            }
            
            if timestampMs % 30 == 0 {
                print("DEBUG: Successfully enqueued frame at \(timestampMs) for \(clientId). Layer status: \(layer.status.rawValue), error: \(String(describing: layer.error))")
            }
            layer.enqueue(sample)
        }
    }
    
    func startDirector() {
        self.statusMessage = "Starting Studio Host..."
        let directorBridge = AmosDirectorListenerBridge(appState: self)
        let name = self.displayName
        let isCamOff = self.isCameraOff
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let ticket = try self.core.startDirector(displayName: name, listener: directorBridge)
                Task { @MainActor in
                    self.ticketText = ticket
                    self.isRunning = true
                    self.statusMessage = "Director running. Share ticket to connect!"
                    if let streamId = self.localStreamId {
                        try? self.core.closeStream(streamId: streamId)
                        self.localStreamId = nil
                        self.currentPublishType = nil
                    }
                    self.updateCameraCapture()
                    try? self.core.setProducerVideoState(isVideoOn: !isCamOff, isScreenSharing: self.isScreenSharing)
                }
            } catch {
                Task { @MainActor in
                    self.statusMessage = "Failed to start director: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func stopDirector() {
        do {
            try core.stopDirector()
            self.isRunning = false
            self.ticketText = ""
            self.connectedClients.removeAll()
            self.clientsMap.removeAll()
            self.displayLayers.removeAll()
            self.clientSps.removeAll()
            self.clientPps.removeAll()
            self.clientFrameIndices.removeAll()
            self.statusMessage = "Director stopped."
        } catch {
            self.statusMessage = "Failed to stop director: \(error.localizedDescription)"
        }
    }
    
    func toggleRecording() {
        let newState = !isRecording
        do {
            try core.setRecordingState(isRecording: newState)
            self.isRecording = newState
            self.statusMessage = newState ? "Recording active across all devices!" : "Recording stopped."
        } catch {
            self.statusMessage = "Recording toggle failed: \(error.localizedDescription)"
        }
    }
    
    func requestKeyframe(clientId: String, streamId: String) {
        do {
            try core.requestKeyframe(clientId: clientId, streamId: streamId)
            self.statusMessage = "Requested keyframe from participant: \(clientId)"
        } catch {
            self.statusMessage = "Keyframe request failed: \(error.localizedDescription)"
        }
    }
    
    // Participant Actions
    func connect(ticket: String) {
        self.statusMessage = "Connecting..."
        let listenerBridge = AmosEventListenerBridge(appState: self)
        let pId = self.participantId
        let name = self.displayName
        let devType = self.deviceType
        let sessId = self.sessionId
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.core.connectToDirector(
                    ticket: ticket,
                    participantId: pId,
                    displayName: name,
                    deviceType: devType,
                    sessionId: sessId,
                    listener: listenerBridge
                )
                Task { @MainActor in
                    self.statusMessage = "Connected to Director session."
                }
            } catch {
                Task { @MainActor in
                    self.statusMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    var hasScreenCapturePermission: Bool {
        if #available(macOS 11.0, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }
    
    func disconnect() {
        do {
            try core.disconnectFromDirector()
            self.isConnected = false
            self.localStreamId = nil
            self.audioStreamId = nil
            self.isCameraOff = true
            self.isScreenSharing = false
            self.isMuted = true
            self.statusMessage = "Left session."
        } catch {
            self.statusMessage = "Failed to disconnect: \(error.localizedDescription)"
        }
    }
    
    func updateAudioCapture() {
        if isMuted {
            if let streamId = audioStreamId {
                try? core.closeStream(streamId: streamId)
                audioStreamId = nil
            }
            if !isTestingMic {
                audioCaptureManager.stopCapture()
            }
            localAudioLevel = 0.0
        } else {
            if audioStreamId == nil {
                let isVoiceProcessing = (selectedAudioProfile == "Voice Isolation")
                let config = StreamConfig(
                    streamId: nil,
                    sourceType: "audio",
                    name: selectedMic,
                    codec: "aac",
                    width: nil,
                    height: nil,
                    audioProfile: selectedAudioProfile,
                    sampleRate: 44100,
                    channels: 1,
                    echoCancellation: isVoiceProcessing,
                    noiseSuppression: isVoiceProcessing
                )
                if let streamId = try? core.publishStream(config: config) {
                    self.audioStreamId = streamId
                    self.statusMessage = "Audio streaming active. Stream ID: \(streamId)"
                }
            }
            
            audioCaptureManager.onAudioLevel = { [weak self] level in
                Task { @MainActor in
                    self?.localAudioLevel = level
                }
            }
            
            audioCaptureManager.onEncodedAudio = { [weak self] data in
                guard let self = self else { return }
                if let streamId = self.audioStreamId {
                    let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
                    do {
                        let levelByte = UInt8(min(max(self.localAudioLevel * 255.0, 0.0), 255.0))
                        try self.core.writeFrame(streamId: streamId, frameType: levelByte, timestampMs: timestampMs, payload: data)
                    } catch {
                        print("Audio frame write failed: \(error)")
                    }
                }
            }
            _ = audioCaptureManager.startCapture()
        }
    }
    
    @Published var currentPublishType: String? = nil
    
    func updateCameraCapture() {
        let desiredSourceType = isScreenSharing ? "screen" : "camera"
        
        // Under Option A (In-place track swapping), we ONLY close the active transport stream
        // if BOTH camera and screensharing are stopped/disabled.
        if isCameraOff && !isScreenSharing {
            if let streamId = localStreamId {
                try? core.closeStream(streamId: streamId)
                localStreamId = nil
                currentPublishType = nil
            }
        }
        
        if isCameraOff && !isScreenSharing {
            cameraCaptureManager.stopCapture()
        } else {
            // Auto-publish stream if not already active
            if localStreamId == nil {
                let config = StreamConfig(
                    streamId: nil,
                    sourceType: desiredSourceType,
                    name: isScreenSharing ? "Mac Display" : "Mac Camera",
                    codec: "h264",
                    width: 1280,
                    height: 720,
                    audioProfile: nil,
                    sampleRate: nil,
                    channels: nil,
                    echoCancellation: nil,
                    noiseSuppression: nil
                )
                if let streamId = try? core.publishStream(config: config) {
                    self.localStreamId = streamId
                    self.currentPublishType = desiredSourceType
                    self.statusMessage = "Streaming active. Stream ID: \(streamId)"
                }
            } else if currentPublishType != desiredSourceType {
                // Keep the stream open but update publish type
                self.currentPublishType = desiredSourceType
            }
            
            _ = cameraCaptureManager.startCapture(captureScreen: isScreenSharing, displayID: selectedDisplayID) { [weak self] data, isKey in
                guard let self = self else { return }
                if let streamId = self.localStreamId {
                    let frameType: UInt8 = isKey ? 1 : 0
                    let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)
                    do {
                        try self.core.writeFrame(streamId: streamId, frameType: frameType, timestampMs: timestampMs, payload: data)
                    } catch {
                        print("Frame write failed: \(error)")
                    }
                }
            }
        }
    }
    
    func refreshAvailableDisplays() {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        if CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success {
            self.availableDisplays = displays.enumerated().map { index, id in
                let bounds = CGDisplayBounds(id)
                let isMain = id == CGMainDisplayID()
                let suffix = isMain ? " (Main)" : ""
                let name = "Screen \(index + 1)\(suffix) - \(Int(bounds.width))x\(Int(bounds.height))"
                return DisplayInfo(id: id, name: name)
            }
            if !displays.contains(selectedDisplayID) {
                selectedDisplayID = CGMainDisplayID()
            }
        }
    }
    
    func updateVideoState() {
        let isVideoActive = !isCameraOff || isScreenSharing
        if isDirector {
            try? core.setProducerVideoState(isVideoOn: isVideoActive, isScreenSharing: isScreenSharing)
        } else {
            try? core.setParticipantVideoState(isVideoOn: isVideoActive, isScreenSharing: isScreenSharing)
        }
    }
    
    func startStreaming() {
        if isCameraOff {
            self.isCameraOff = false
        } else {
            updateCameraCapture()
        }
    }
    
    func stopStreaming() {
        self.isCameraOff = true
    }

    func startMicTest() {
        wasCapturingBeforeTest = !isMuted
        audioCaptureManager.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.micTestLevel = level
                if self?.wasCapturingBeforeTest == true {
                    self?.localAudioLevel = level
                }
            }
        }
        _ = audioCaptureManager.startCapture()
    }
    
    func stopMicTest() {
        micTestLevel = 0.0
        if !wasCapturingBeforeTest {
            audioCaptureManager.stopCapture()
        } else {
            // Restore production level callback
            audioCaptureManager.onAudioLevel = { [weak self] level in
                Task { @MainActor in
                    self?.localAudioLevel = level
                }
            }
        }
    }
    
    func playSpeakerTestSound() {
        let sound = NSSound(named: "Glass")
        self.isPlayingTestSound = true
        sound?.delegate = self
        sound?.play()
    }
    
    nonisolated func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        Task { @MainActor in
            self.isPlayingTestSound = false
        }
    }
    
    func playStingerSound(named name: String) {
        let soundName: String
        switch name {
        case "applause": soundName = "Purr"
        case "alert": soundName = "Basso"
        case "transition": soundName = "Blow"
        default: soundName = "Glass"
        }
        if let sound = NSSound(named: soundName) {
            sound.play()
        }
    }
}

// Wrapper bridge class for UniFFI callback interface
final class AmosEventListenerBridge: AmosEventListener {
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func onForceKeyframe(streamId: String) {
        Task { @MainActor in
            appState.cameraCaptureManager.forceKeyframe()
            appState.statusMessage = "Director requested keyframe for stream \(streamId)!"
        }
    }
    
    func onRecordingStateChanged(isRecording: Bool) {
        Task { @MainActor in
            appState.isRecording = isRecording
            appState.statusMessage = isRecording ? "Recording started by Host!" : "Recording stopped by Host."
        }
    }
    
    func onConnectionStatusChanged(connected: Bool) {
        Task { @MainActor in
            appState.isConnected = connected
            appState.statusMessage = connected ? "Connected to session." : "Disconnected from session."
            if connected {
                if let streamId = appState.localStreamId {
                    try? appState.core.closeStream(streamId: streamId)
                    appState.localStreamId = nil
                    appState.currentPublishType = nil
                }
                appState.startStreaming()
            } else {
                appState.cameraCaptureManager.stopCapture()
                appState.audioCaptureManager.stopCapture()
                appState.localStreamId = nil
                appState.audioStreamId = nil
                appState.isCameraOff = true
                appState.isScreenSharing = false
                appState.isMuted = true
                if let idx = appState.connectedClients.firstIndex(of: "host") {
                    appState.connectedClients.remove(at: idx)
                }
                appState.clientsMap.removeValue(forKey: "host")
                appState.isHostVideoOn = false
            }
        }
    }
    
    func onFrameReceived(clientId: String, streamId: String, frameType: UInt8, timestampMs: UInt64, payload: Data) {
        Task { @MainActor in
            if clientId == "host" {
                if !appState.connectedClients.contains("host") {
                    appState.connectedClients.append("host")
                }
                appState.clientsMap["host"] = (name: "\(appState.hostProducerName) (Producer)", device: "Studio Main")
            } else {
                if !appState.connectedClients.contains(clientId) {
                    appState.connectedClients.append(clientId)
                }
                if appState.clientsMap[clientId] == nil {
                    appState.clientsMap[clientId] = (name: "Guest \(clientId.prefix(4))", device: "Remote Device")
                }
            }
            appState.handleFrame(clientId: clientId, frameType: frameType, timestampMs: timestampMs, payload: payload)
        }
    }
    
    func onHostInfoChanged(producerName: String, isVideoOn: Bool, isScreenSharing: Bool) {
        Task { @MainActor in
            appState.hostProducerName = producerName
            appState.isHostVideoOn = isVideoOn
            if appState.isHostScreenSharing != isScreenSharing {
                appState.isHostScreenSharing = isScreenSharing
                appState.clientSps["host"] = nil
                appState.clientPps["host"] = nil
                appState.displayLayers["host"]?.flush()
            }
            if !isVideoOn {
                appState.clientSps["host"] = nil
                appState.clientPps["host"] = nil
                appState.displayLayers["host"]?.flush()
            }
            if !appState.connectedClients.contains("host") {
                appState.connectedClients.append("host")
            }
            appState.clientsMap["host"] = (name: "\(producerName) (Producer)", device: "Studio Main")
        }
    }
    
    func onHostVideoStateChanged(isVideoOn: Bool, isScreenSharing: Bool) {
        Task { @MainActor in
            appState.isHostVideoOn = isVideoOn
            if appState.isHostScreenSharing != isScreenSharing {
                appState.isHostScreenSharing = isScreenSharing
                appState.clientSps["host"] = nil
                appState.clientPps["host"] = nil
                appState.displayLayers["host"]?.flush()
            }
            if !isVideoOn {
                appState.clientSps["host"] = nil
                appState.clientPps["host"] = nil
                appState.displayLayers["host"]?.flush()
            }
            if !appState.connectedClients.contains("host") {
                appState.connectedClients.append("host")
            }
            appState.clientsMap["host"] = (name: "\(appState.hostProducerName) (Producer)", device: "Studio Main")
        }
    }

    func onClientConnected(clientId: String, participantId: String, displayName: String, deviceType: String) {
        Task { @MainActor in
            if !appState.connectedClients.contains(clientId) {
                appState.connectedClients.append(clientId)
            }
            appState.clientsMap[clientId] = (name: displayName, device: deviceType)
            appState.clientVideoStates[clientId] = true
        }
    }
    
    func onClientDisconnected(clientId: String) {
        Task { @MainActor in
            appState.connectedClients.removeAll { $0 == clientId }
            appState.clientsMap.removeValue(forKey: clientId)
            appState.clientVideoStates.removeValue(forKey: clientId)
            appState.clientScreenSharingStates.removeValue(forKey: clientId)
        }
    }
    
    func onClientVideoStateChanged(clientId: String, isVideoOn: Bool, isScreenSharing: Bool) {
        Task { @MainActor in
            appState.clientVideoStates[clientId] = isVideoOn
            if appState.clientScreenSharingStates[clientId] != isScreenSharing {
                appState.clientScreenSharingStates[clientId] = isScreenSharing
                appState.clientSps[clientId] = nil
                appState.clientPps[clientId] = nil
                appState.displayLayers[clientId]?.flush()
            }
            if !isVideoOn {
                appState.clientSps[clientId] = nil
                appState.clientPps[clientId] = nil
                appState.displayLayers[clientId]?.flush()
            }
        }
    }

    func onTalkbackChanged(enabled: Bool) {
        Task { @MainActor in
            appState.statusMessage = enabled ? "Talkback Voice active!" : "Talkback muted."
        }
    }

    func onPrompterChanged(text: String) {
        Task { @MainActor in
            appState.statusMessage = "Prompter: \(text)"
        }
    }

    func onTallyChanged(streamId: String, isLive: Bool, isPreview: Bool) {
        Task { @MainActor in
            appState.statusMessage = "Tally for \(streamId): Live=\(isLive), Preview=\(isPreview)"
        }
    }

    func onHostStreamConfigured(streamId: String, config: StreamConfig) {
        Task { @MainActor in
            appState.statusMessage = "Host stream \(streamId) configured"
        }
    }

    func onClientStreamConfigured(clientId: String, streamId: String, config: StreamConfig) {
        Task { @MainActor in
            appState.statusMessage = "Client \(clientId) configured stream \(streamId)"
        }
    }

    func onSoundTriggered(soundName: String, targetOutput: String) {
        Task { @MainActor in
            appState.statusMessage = "Sound triggered: \(soundName) to \(targetOutput)"
            appState.playStingerSound(named: soundName)
        }
    }
    
    func onCustomMessage(clientId: String, variant: String, data: String) {
        Task { @MainActor in
            appState.statusMessage = "Custom Message from \(clientId) (type \(variant)): \(data)"
        }
    }
}

// Wrapper bridge class for Director connection events
final class AmosDirectorListenerBridge: AmosDirectorListener {
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func onClientConnected(clientId: String, participantId: String, displayName: String, deviceType: String) {
        Task { @MainActor in
            if !appState.connectedClients.contains(clientId) {
                appState.connectedClients.append(clientId)
            }
            appState.clientsMap[clientId] = (name: displayName, device: deviceType)
            appState.clientVideoStates[clientId] = true
            appState.statusMessage = "Participant joined: \(displayName) (\(participantId))"
        }
    }
    
    func onClientDisconnected(clientId: String) {
        Task { @MainActor in
            let displayName = appState.clientsMap[clientId]?.name ?? "Participant"
            appState.connectedClients.removeAll { $0 == clientId }
            appState.clientsMap.removeValue(forKey: clientId)
            appState.clientVideoStates.removeValue(forKey: clientId)
            appState.clientScreenSharingStates.removeValue(forKey: clientId)
            appState.clientAudioPlayers[clientId]?.stop()
            appState.clientAudioPlayers.removeValue(forKey: clientId)
            appState.statusMessage = "\(displayName) left the studio"
        }
    }

    func onClientStreamConfigured(clientId: String, streamId: String, config: StreamConfig) {
        Task { @MainActor in
            appState.statusMessage = "Client \(clientId) configured stream \(streamId)"
        }
    }
    
    func onFrameReceived(clientId: String, streamId: String, frameType: UInt8, timestampMs: UInt64, payload: Data) {
        Task { @MainActor in
            appState.handleFrame(clientId: clientId, frameType: frameType, timestampMs: timestampMs, payload: payload)
        }
    }
    
    func onClientVideoStateChanged(clientId: String, isVideoOn: Bool, isScreenSharing: Bool) {
        Task { @MainActor in
            appState.clientVideoStates[clientId] = isVideoOn
            if appState.clientScreenSharingStates[clientId] != isScreenSharing {
                appState.clientScreenSharingStates[clientId] = isScreenSharing
                appState.clientSps[clientId] = nil
                appState.clientPps[clientId] = nil
                appState.displayLayers[clientId]?.flush()
            }
            if !isVideoOn {
                appState.displayLayers[clientId]?.flush()
            }
        }
    }
    
    func onForceKeyframe(streamId: String) {
        Task { @MainActor in
            appState.cameraCaptureManager.forceKeyframe()
            appState.statusMessage = "Client requested keyframe!"
        }
    }
    
    func onCustomMessage(clientId: String, variant: String, data: String) {
        Task { @MainActor in
            appState.statusMessage = "Custom Message from \(clientId) (type \(variant)): \(data)"
        }
    }
}

struct RemoteVideoView: NSViewRepresentable {
    let clientId: String
    @ObservedObject var appState: AppState
    
    class VideoContainerView: NSView {
        override func makeBackingLayer() -> CALayer {
            return AVSampleBufferDisplayLayer()
        }
        
        init() {
            super.init(frame: .zero)
            self.wantsLayer = true
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            self.layer?.frame = NSRect(origin: .zero, size: newSize)
        }
    }
    
    func makeNSView(context: Context) -> VideoContainerView {
        let view = VideoContainerView()
        if let displayLayer = view.layer as? AVSampleBufferDisplayLayer {
            displayLayer.videoGravity = (clientId == "host") ? .resizeAspect : .resizeAspectFill
            appState.registerDisplayLayer(displayLayer, for: clientId)
        }
        return view
    }
    
    func updateNSView(_ nsView: VideoContainerView, context: Context) {
        // No-op
    }
}

class AudioPlaybackManager: NSObject, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    
    override init() {
        // Destination format: MPEG4AAC (AAC), 44.1 kHz, 1 channel
        var desc = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        guard let inFormat = AVAudioFormat(streamDescription: &desc) else {
            fatalError("Failed to create input format")
        }
        self.inputFormat = inFormat
        
        // Output format: PCM, 44.1 kHz, 1 channel
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100.0, channels: 1, interleaved: false) else {
            fatalError("Failed to create output format")
        }
        self.outputFormat = outFormat
        
        let converter = AVAudioConverter(from: inputFormat, to: outFormat)
        let cookieBytes: [UInt8] = [0x12, 0x08]
        converter?.magicCookie = Data(cookieBytes)
        self.converter = converter
        
        super.init()
        
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        
        player.volume = 1.0
        engine.mainMixerNode.outputVolume = 1.0
        
        do {
            try engine.start()
            player.play()
        } catch {
            NSLog("DEBUG: Failed to start playback engine: %@", error.localizedDescription)
        }
    }
    
    func playAudioFrame(payload: Data) {
        guard let converter = converter else {
            NSLog("DEBUG: Playback converter is nil")
            return
        }
        
        let compressedBuffer = AVAudioCompressedBuffer(format: inputFormat, packetCapacity: 1, maximumPacketSize: payload.count)
        compressedBuffer.packetCount = 1
        compressedBuffer.byteLength = UInt32(payload.count)
        
        payload.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                compressedBuffer.data.copyMemory(from: baseAddress, byteCount: payload.count)
            }
        }
        
        if let packetDescs = compressedBuffer.packetDescriptions {
            packetDescs.pointee = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 1024,
                mDataByteSize: UInt32(payload.count)
            )
        }
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1024) else {
            NSLog("DEBUG: Failed to create pcmBuffer")
            return
        }
        
        var error: NSError?
        var inputConsumed = false
        
        let status = converter.convert(to: pcmBuffer, error: &error) { numberOfPackets, outStatus -> AVAudioBuffer? in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return compressedBuffer
        }
        
        if status == .haveData || status == .inputRanDry {
            var maxVal: Float = 0.0
            if let floatChannelData = pcmBuffer.floatChannelData {
                let channelData = floatChannelData[0]
                for i in 0..<Int(pcmBuffer.frameLength) {
                    let val = abs(channelData[i])
                    if val > maxVal {
                        maxVal = val
                    }
                }
            }
            NSLog("DEBUG: Successfully decoded %d PCM frames. Max sample: %f, payload size: %d", pcmBuffer.frameLength, maxVal, payload.count)
            player.scheduleBuffer(pcmBuffer, at: nil, options: [], completionHandler: nil)
            if !player.isPlaying {
                player.play()
            }
        } else {
            NSLog("DEBUG: Failed to convert AAC to PCM: %@, status: %d", error?.localizedDescription ?? "unknown error", status.rawValue)
        }
    }
    
    func stop() {
        player.stop()
        engine.stop()
    }
    
    func setVolume(_ volume: Float) {
        player.volume = volume
    }
}
