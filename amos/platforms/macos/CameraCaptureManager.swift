import AVFoundation
import VideoToolbox
import AppKit
import ScreenCaptureKit

class CameraCaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private var compressionSession: VTCompressionSession?
    private var scStream: SCStream?
    private let captureQueue = DispatchQueue(label: "com.example.amos.macos.captureQueue")
    
    private var onEncodedFrame: ((Data, Bool) -> Void)?
    private var forceNextFrameKeyframe = false
    private var isRunning = false
    
    private var sessionWidth: Int32 = 1280
    private var sessionHeight: Int32 = 720
    
    func requestAccess(completion: @escaping @Sendable (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }
    
    private var isCapturingScreen = false
    private var currentSessionToken: Int = 0
    
    var previewSession: AVCaptureSession {
        return captureSession
    }
    
    private var capturedDisplayID: CGDirectDisplayID = CGMainDisplayID()
    private var needsDimensionSync = true
    
    func startCapture(captureScreen: Bool = false, displayID: CGDirectDisplayID = CGMainDisplayID(), onFrame: @escaping (Data, Bool) -> Void) -> Bool {
        self.onEncodedFrame = onFrame
        
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentSessionToken += 1
            let sessionToken = self.currentSessionToken
            
            if self.isRunning && self.isCapturingScreen == captureScreen && self.capturedDisplayID == displayID {
                return
            }
            
            if self.isRunning {
                self.innerStopCapture()
            }
            
            self.isCapturingScreen = captureScreen
            self.capturedDisplayID = displayID
            self.needsDimensionSync = true
            
            if captureScreen {
                self.setupScreenCaptureKit(displayID: displayID, token: sessionToken)
            } else {
                self.setupCaptureSession()
                self.setupCompressionSession()
                self.captureSession.startRunning()
            }
            
            self.isRunning = true
        }
        
        return true
    }
    
    func stopCapture() {
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentSessionToken += 1
            self.innerStopCapture()
        }
    }
    
    private func innerStopCapture() {
        guard isRunning else { return }
        
        if isCapturingScreen {
            if let stream = self.scStream {
                stream.stopCapture { _ in }
                self.scStream = nil
            }
        } else {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
        
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        self.isRunning = false
    }
    
    func forceKeyframe() {
        captureQueue.async { [weak self] in
            self?.forceNextFrameKeyframe = true
        }
    }
    
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720
        
        // Remove existing inputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        
        sessionWidth = 1280
        sessionHeight = 720
        
        guard let camera = AVCaptureDevice.default(for: .video) else {
            print("Failed to get macOS camera device")
            captureSession.commitConfiguration()
            return
        }
        
        do {
            try camera.lockForConfiguration()
            let desiredDuration = CMTime(value: 1, timescale: 30)
            
            // Only adjust frame duration if the active format supports 30fps to avoid NSInvalidArgumentException crash
            var supports30fps = false
            for range in camera.activeFormat.videoSupportedFrameRateRanges {
                if range.minFrameRate <= 30.0 && 30.0 <= range.maxFrameRate {
                    supports30fps = true
                    break
                }
            }
            
            if supports30fps {
                camera.activeVideoMinFrameDuration = desiredDuration
                camera.activeVideoMaxFrameDuration = desiredDuration
            } else {
                print("Skipping frame rate lock: 30fps is not supported by this camera format.")
            }
            camera.unlockForConfiguration()
        } catch {
            print("Failed to lock camera device for frame rate configuration: \(error)")
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("Error setting up camera input: \(error)")
            captureSession.commitConfiguration()
            return
        }
        
        // Only add videoOutput if it is not already there
        if captureSession.outputs.isEmpty {
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
            videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
        }
        
        captureSession.commitConfiguration()
    }
    
    private func setupScreenCaptureKit(displayID: CGDirectDisplayID, token: Int) {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            guard let self = self else { return }
            self.captureQueue.async {
                guard token == self.currentSessionToken else {
                    print("Aborting ScreenCaptureKit setup: token mismatch.")
                    return
                }
                
                guard let content = content, error == nil else {
                    print("Failed to get shareable content: \(String(describing: error))")
                    return
                }
                
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    print("Target display \(displayID) not found in shareable content")
                    return
                }
                
                let scaleX = 1280.0 / CGFloat(display.width)
                let scaleY = 720.0 / CGFloat(display.height)
                let scale = min(scaleX, scaleY, 1.0)
                
                let width = Int(CGFloat(display.width) * scale)
                let height = Int(CGFloat(display.height) * scale)
                self.sessionWidth = Int32(width - (width % 2))
                self.sessionHeight = Int32(height - (height % 2))
                
                let streamConfig = SCStreamConfiguration()
                streamConfig.width = Int(self.sessionWidth)
                streamConfig.height = Int(self.sessionHeight)
                // 1. Cap frame rate to 30fps to avoid network & encoder congestion.
                streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                
                // 2. Limit queue depth to 2 to minimize system compositor frame buffering latency.
                streamConfig.queueDepth = 2
                
                // 3. Request native YUV format to bypass VideoToolbox conversion latency.
                streamConfig.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                streamConfig.showsCursor = true
                
                // 4. Exclude our own app by processID (PID) to prevent recursive feedback mirror loops.
                let ownPid = ProcessInfo.processInfo.processIdentifier
                let excludedApps = content.applications.filter { app in
                    app.processID == ownPid
                }
                let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
                
                let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
                do {
                    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.captureQueue)
                    stream.startCapture { [weak self] error in
                        guard let self = self else { return }
                        self.captureQueue.async {
                            guard token == self.currentSessionToken else {
                                print("SCStream started but token mismatched. Stopping stream immediately.")
                                stream.stopCapture { _ in }
                                return
                            }
                            if let error = error {
                                print("Failed to start ScreenCaptureKit stream: \(error)")
                            } else {
                                print("ScreenCaptureKit stream started successfully at \(self.sessionWidth)x\(self.sessionHeight)")
                                self.setupCompressionSession()
                            }
                        }
                    }
                    self.scStream = stream
                } catch {
                    print("Failed to add stream output: \(error)")
                }
            }
        }
    }
    
    private func setupCompressionSession() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        // 5. Enable native IOSurface support for zero-copy GPU memory encoding.
        // Ref: https://webrtc.googlesource.com/src/+/refs/heads/main/modules/desktop_capture/mac/screen_capturer_sck.mm#150
        // Ref: https://developer.apple.com/documentation/corevideo/kcvpixelbufferiosurfacepropertieskey
        let sourceImageBufferAttributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: sessionWidth,
            height: sessionHeight,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: sourceImageBufferAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: { (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
                guard status == noErr, let sampleBuffer = sampleBuffer else {
                    print("Compression error status: \(status)")
                    return
                }
                
                let manager = Unmanaged<CameraCaptureManager>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
                manager.handleEncodedSampleBuffer(sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        if status != noErr {
            print("Failed to create compression session: \(status)")
            return
        }
        
        guard let session = compressionSession else { return }
        
        // 6. Set real-time encoding constraints to prioritize low latency.
        // Ref: https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_realtime
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        
        // 6a. Set explicit Rec.709 color metadata to ensure accurate, vibrant color rendering at the receiver display layer.
        // Ref: https://github.com/obsproject/obs-studio/blob/master/plugins/mac-videotoolbox/h264-encoder.c
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        
        // Disable B-frames to allow display-order zero-lookahead encoding.
        // Ref: https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_allowframereordering
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 2_000_000 as CFNumber)
        
        // 7. Enforce strict data rate limits (CBR emulation) to avoid QUIC congestion spikes.
        // Ref: https://github.com/obsproject/obs-studio/blob/master/plugins/mac-videotoolbox/h264-encoder.c#L340
        // Ref: https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_dataratelimits
        let bytesPerSecond = (2_000_000 / 8) as CFNumber
        let windowSeconds = 1.0 as CFNumber
        let limits = [bytesPerSecond, windowSeconds] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)
        
        // 7a. Increase periodic keyframe interval to 240 frames (8 seconds) to reduce periodic network bandwidth spikes.
        // We rely on our custom control channel PLI on-demand keyframe requests for instant joins and recovery.
        // Ref: WebRTC long keyframe interval and PLI/FIR feedback loop design.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 240 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 30 as CFNumber)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        processSampleBuffer(sampleBuffer)
    }
    
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning else { return }
        if isCapturingScreen {
            // 8. Filter out non-complete frames (like idle or suspended ones) to save network & encoder load.
            // Ref: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos#Process-a-video-sample-buffer
            // Ref: https://developer.apple.com/documentation/screencapturekit/scframestatus
            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let attachments = attachmentsArray.first {
                if let statusRawValue = attachments[.status] as? Int,
                   let status = SCFrameStatus(rawValue: statusRawValue),
                   status != .complete {
                    return
                }
            }
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let frameWidth = Int32(CVPixelBufferGetWidth(imageBuffer))
        let frameHeight = Int32(CVPixelBufferGetHeight(imageBuffer))
        
        let targetWidth = frameWidth - (frameWidth % 2)
        let targetHeight = frameHeight - (frameHeight % 2)
        
        if needsDimensionSync || targetWidth != sessionWidth || targetHeight != sessionHeight {
            sessionWidth = targetWidth
            sessionHeight = targetHeight
            setupCompressionSession()
            needsDimensionSync = false
        }
        
        guard let session = compressionSession else { return }
        
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        var frameProperties: CFDictionary? = nil
        if forceNextFrameKeyframe {
            forceNextFrameKeyframe = false
            let dict: [CFString: Any] = [
                kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue as Any
            ]
            frameProperties = dict as CFDictionary
        }
        
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
    
    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        
        var isKey = false
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) {
            if CFArrayGetCount(attachmentsArray) > 0 {
                let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachmentsArray, 0), to: CFDictionary.self)
                let isNotSync = CFDictionaryGetValue(attachment, unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self))
                isKey = (isNotSync == nil)
            }
        }
        
        var packetData = Data()
        
        if isKey {
            // Extract SPS (Sequence Parameter Set) and PPS (Picture Parameter Set)
            var spsPointer: UnsafePointer<UInt8>?
            var spsCount = 0
            var spsHeaderLength = 0
            var status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 0,
                parameterSetPointerOut: &spsPointer,
                parameterSetSizeOut: &spsHeaderLength,
                parameterSetCountOut: &spsCount,
                nalUnitHeaderLengthOut: nil
            )
            
            if status == noErr, let sps = spsPointer {
                packetData.append(Data([0, 0, 0, 1]))
                packetData.append(sps, count: spsHeaderLength)
            }
            
            var ppsPointer: UnsafePointer<UInt8>?
            var ppsCount = 0
            var ppsHeaderLength = 0
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 1,
                parameterSetPointerOut: &ppsPointer,
                parameterSetSizeOut: &ppsHeaderLength,
                parameterSetCountOut: &ppsCount,
                nalUnitHeaderLengthOut: nil
            )
            
            if status == noErr, let pps = ppsPointer {
                packetData.append(Data([0, 0, 0, 1]))
                packetData.append(pps, count: ppsHeaderLength)
            }
        }
        
        // Extract Slice NALUs from the block buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength = 0
        var lengthAtOffset = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        
        if status == noErr, let rawData = dataPointer {
            var offset = 0
            while offset < totalLength - 4 {
                var naluLength: UInt32 = 0
                memcpy(&naluLength, rawData.advanced(by: offset), 4)
                naluLength = CFSwapInt32BigToHost(naluLength)
                
                if offset + 4 + Int(naluLength) <= totalLength {
                    let naluData = Data(bytes: rawData.advanced(by: offset + 4), count: Int(naluLength))
                    packetData.append(Data([0, 0, 0, 1]))
                    packetData.append(naluData)
                }
                
                offset += 4 + Int(naluLength)
            }
        }
        
        if !packetData.isEmpty {
            onEncodedFrame?(packetData, isKey)
        }
    }
}

extension CameraCaptureManager: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        processSampleBuffer(sampleBuffer)
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("ScreenCaptureKit stream stopped with error: \(error)")
        // 9. Attempt recovery on main display if the target display becomes unavailable (monitor unplugged).
        // Ref: https://github.com/obsproject/obs-studio/blob/master/plugins/mac-capture/mac-screencapture.m#L360
        captureQueue.async { [weak self] in
            guard let self = self, self.isRunning, self.isCapturingScreen else { return }
            print("Attempting ScreenCaptureKit recovery on main display...")
            self.setupScreenCaptureKit(displayID: CGMainDisplayID(), token: self.currentSessionToken)
        }
    }
}
