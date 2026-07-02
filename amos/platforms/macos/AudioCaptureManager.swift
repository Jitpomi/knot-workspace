import AVFoundation
import CoreAudio

class AudioAccumulator {
    private var buffer: [Float] = []
    private let lock = NSLock()
    
    func append(_ newSamples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: newSamples)
    }
    
    func append(_ pcmBuffer: AVAudioPCMBuffer) {
        guard let floatData = pcmBuffer.floatChannelData else { return }
        let channelData = floatData[0]
        let frameCount = Int(pcmBuffer.frameLength)
        
        lock.lock()
        defer { lock.unlock() }
        for i in 0..<frameCount {
            buffer.append(channelData[i])
        }
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }
    
    func nextChunk(size: Int) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }
        guard buffer.count >= size else { return nil }
        let chunk = Array(buffer.prefix(size))
        buffer.removeFirst(size)
        return chunk
    }
}

class AudioCaptureManager: NSObject, @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private var pcmConverter: AVAudioConverter?
    private var aacConverter: AVAudioConverter?
    private let captureQueue = DispatchQueue(label: "com.example.amos.audioCaptureQueue")
    private let accumulator = AudioAccumulator()
    
    var onEncodedAudio: ((Data) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    
    var isRunning = false
    var inputVolume: Float = 1.0
    var enableVoiceProcessing: Bool = true
    
    var inputDeviceUID: String? {
        didSet {
            applySelectedDevice()
        }
    }
    
    private var pcmFormat: AVAudioFormat?
    private var destFormat: AVAudioFormat?
    
    private func applySelectedDevice() {
        guard let uid = inputDeviceUID else { return }
        
        var deviceID: AudioDeviceID = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        if status == noErr {
            let count = Int(size) / MemoryLayout<AudioDeviceID>.size
            var devices = [AudioDeviceID](repeating: 0, count: count)
            let status2 = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
            if status2 == noErr {
                for dev in devices {
                    var uidAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyDeviceUID,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    var uidSize = UInt32(MemoryLayout<CFString?>.size)
                    var uidString: CFString? = nil
                    let status3 = AudioObjectGetPropertyData(dev, &uidAddress, 0, nil, &uidSize, &uidString)
                    if status3 == noErr, let name = uidString as String?, name == uid {
                        deviceID = dev
                        break
                    }
                }
            }
        }
        
        if deviceID != 0 {
            let inputNode = audioEngine.inputNode
            if let audioUnit = inputNode.audioUnit {
                var id = deviceID
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &id,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
            }
        }
    }
    
    func startCapture() -> Bool {
        var success = false
        captureQueue.sync {
            guard !isRunning else { 
                success = true
                return 
            }
            
            applySelectedDevice()
            
            let inputNode = audioEngine.inputNode
            try? inputNode.setVoiceProcessingEnabled(enableVoiceProcessing)
            
            let inputFormat = inputNode.inputFormat(forBus: 0)
            
            guard let pcmFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100.0, channels: 1, interleaved: false) else {
                NSLog("DEBUG: Failed to create resampled PCM format")
                return
            }
            self.pcmFormat = pcmFormat
            
            // Destination format: MPEG4AAC (AAC), 44.1 kHz, 1 channel
            var destDesc = AudioStreamBasicDescription(
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
            guard let destFormat = AVAudioFormat(streamDescription: &destDesc) else {
                NSLog("DEBUG: Failed to create destination AAC format")
                return
            }
            self.destFormat = destFormat
            
            NSLog("DEBUG: Input format: %@", inputFormat.description)
            NSLog("DEBUG: Resampled format: %@", pcmFormat.description)
            NSLog("DEBUG: Dest format: %@", destFormat.description)
            
            guard let pcmConv = AVAudioConverter(from: inputFormat, to: pcmFormat) else {
                NSLog("DEBUG: Failed to create pcmConverter")
                return
            }
            self.pcmConverter = pcmConv
            
            guard let aacConv = AVAudioConverter(from: pcmFormat, to: destFormat) else {
                NSLog("DEBUG: Failed to create aacConverter")
                return
            }
            self.aacConverter = aacConv
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                self.captureQueue.async {
                    self.processInputBuffer(buffer)
                }
            }
            
            do {
                try audioEngine.start()
                isRunning = true
                success = true
            } catch {
                NSLog("DEBUG: Failed to start AVAudioEngine: %@", error.localizedDescription)
                inputNode.removeTap(onBus: 0)
            }
        }
        return success
    }
    
    func stopCapture() {
        captureQueue.sync {
            guard isRunning else { return }
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            pcmConverter = nil
            aacConverter = nil
            isRunning = false
        }
    }
    
    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let pcmConverter = pcmConverter, let pcmFormat = pcmFormat else { return }
        
        // Apply input gain if needed
        let gain = inputVolume
        if gain != 1.0 {
            if let floatChannelData = buffer.floatChannelData {
                let channelData = floatChannelData[0]
                for i in 0..<Int(buffer.frameLength) {
                    channelData[i] *= gain
                }
            }
        }
        
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * 44100.0 / buffer.format.sampleRate) + 64
        guard let intermediateBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: outputFrameCapacity) else {
            NSLog("DEBUG: Failed to allocate intermediate buffer")
            return
        }
        
        var error: NSError?
        var inputConsumed = false
        let status = pcmConverter.convert(to: intermediateBuffer, error: &error) { numberOfPackets, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .error {
            NSLog("DEBUG: PCM resampler error: %@", error?.localizedDescription ?? "unknown")
            return
        }
        
        if intermediateBuffer.frameLength > 0 {
            accumulator.append(intermediateBuffer)
        }
        
        guard let aacConverter = aacConverter else { return }
        
        while accumulator.count >= 1024 {
            guard let chunkSamples = accumulator.nextChunk(size: 1024) else { break }
            
            guard let pcmChunk = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 1024) else { continue }
            pcmChunk.frameLength = 1024
            
            if let floatData = pcmChunk.floatChannelData {
                let channelData = floatData[0]
                for i in 0..<1024 {
                    channelData[i] = chunkSamples[i]
                }
            }
            
            var maxInputVal: Float = 0.0
            var sum: Float = 0
            for i in 0..<1024 {
                let val = abs(chunkSamples[i])
                if val > maxInputVal {
                    maxInputVal = val
                }
                sum += chunkSamples[i] * chunkSamples[i]
            }
            let rms = sqrt(sum / 1024.0)
            let normalized = min(max(rms * 4.0, 0.0), 1.0)
            onAudioLevel?(normalized)
            
            let outputBuffer = AVAudioCompressedBuffer(format: aacConverter.outputFormat, packetCapacity: 1, maximumPacketSize: 1024)
            var encodeError: NSError?
            var encodeInputConsumed = false
            
            let encodeStatus = aacConverter.convert(to: outputBuffer, error: &encodeError) { numberOfPackets, outStatus in
                if encodeInputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                encodeInputConsumed = true
                outStatus.pointee = .haveData
                return pcmChunk
            }
            
            if encodeStatus == .haveData && outputBuffer.byteLength > 0 {
                let data = Data(bytes: outputBuffer.data, count: Int(outputBuffer.byteLength))
                NSLog("DEBUG: Encoder output success. ByteLength: %d, Max Input: %f", outputBuffer.byteLength, maxInputVal)
                onEncodedAudio?(data)
            } else if encodeStatus == .error {
                NSLog("DEBUG: AAC encoding error: %@", encodeError?.localizedDescription ?? "unknown")
            }
        }
    }
    
    func setVoiceProcessing(_ enabled: Bool) {
        enableVoiceProcessing = enabled
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            if self.isRunning {
                try? self.audioEngine.inputNode.setVoiceProcessingEnabled(enabled)
            }
        }
    }
}
