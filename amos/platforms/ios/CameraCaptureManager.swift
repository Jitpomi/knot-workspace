import AVFoundation
import VideoToolbox
import ReplayKit

class CameraCaptureManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private var compressionSession: VTCompressionSession?
    private let captureQueue = DispatchQueue(label: "com.example.amos.captureQueue")
    
    private var onEncodedFrame: ((Data, Bool) -> Void)?
    private var forceNextFrameKeyframe = false
    private var isRunning = false
    private var isCapturingScreen = false
    
    var width: Int32 = 1280
    var height: Int32 = 720
    
    func requestAccess(completion: @escaping (Bool) -> Void) {
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
    
    var previewSession: AVCaptureSession {
        return captureSession
    }
    
    private var needsDimensionSync = true
    private var currentSessionToken: Int = 0
    
    func startCapture(captureScreen: Bool = false, onFrame: @escaping (Data, Bool) -> Void) -> Bool {
        self.onEncodedFrame = onFrame
        
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentSessionToken += 1
            let sessionToken = self.currentSessionToken
            
            if self.isRunning && self.isCapturingScreen == captureScreen {
                return
            }
            
            if self.isRunning {
                self.innerStopCapture()
            }
            
            self.isCapturingScreen = captureScreen
            self.needsDimensionSync = true
            self.setupCompressionSession()
            
            if self.isCapturingScreen {
                RPScreenRecorder.shared().startCapture(handler: { [weak self] sampleBuffer, sampleBufferType, error in
                    guard let self = self else { return }
                    self.captureQueue.async {
                        guard sessionToken == self.currentSessionToken else { return }
                        guard error == nil else { return }
                        if sampleBufferType == .video {
                            self.encodeSampleBuffer(sampleBuffer)
                        }
                    }
                }, completionHandler: { [weak self] error in
                    guard let self = self else { return }
                    self.captureQueue.async {
                        guard sessionToken == self.currentSessionToken else { return }
                        if let error = error {
                            print("Screen capture start failed: \(error)")
                        }
                    }
                })
            } else {
                self.setupCaptureSession()
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
            RPScreenRecorder.shared().stopCapture { error in
                if let error = error {
                    print("Screen capture stop failed: \(error)")
                }
            }
        } else {
            captureSession.stopRunning()
        }
        
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        isRunning = false
    }
    
    func forceKeyframe() {
        captureQueue.async { [weak self] in
            self?.forceNextFrameKeyframe = true
        }
    }
    
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720
        
        // Remove existing inputs/outputs
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        
        guard let camera = AVCaptureDevice.default(for: .video) else {
            print("Failed to get iOS camera device")
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
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        captureSession.commitConfiguration()
    }
    
    private func setupCompressionSession() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        // Enable native IOSurface support for zero-copy GPU memory encoding.
        // Ref: https://developer.apple.com/documentation/corevideo/kcvpixelbufferiosurfacepropertieskey
        let sourceImageBufferAttributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: sourceImageBufferAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: { (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
                guard status == noErr, let sampleBuffer = sampleBuffer else { return }
                let manager = Unmanaged<CameraCaptureManager>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
                manager.handleEncodedSampleBuffer(sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        guard status == noErr, let session = compressionSession else {
            print("Failed to create Compression Session")
            return
        }
        
        // Set real-time encoding constraints to prioritize low latency.
        // Ref: https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_realtime
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        
        // Set explicit Rec.709 color metadata to ensure accurate, vibrant color rendering at the receiver display layer.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        
        // Disable B-frames to allow display-order zero-lookahead encoding.
        // Ref: https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_allowframereordering
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 2_000_000 as CFNumber)
        
        // Enforce strict data rate limits (CBR emulation) to avoid QUIC congestion spikes.
        // Ref: https://developer.apple.com/documentation/videotoolbox/kvtcompressionpropertykey_dataratelimits
        let bytesPerSecond = (2_000_000 / 8) as CFNumber
        let windowSeconds = 1.0 as CFNumber
        let limits = [bytesPerSecond, windowSeconds] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)
        
        // Increase periodic keyframe interval to 240 frames (8 seconds) to reduce periodic network bandwidth spikes.
        // We rely on our custom control channel PLI on-demand keyframe requests for instant joins and recovery.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 240 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 30 as CFNumber)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        encodeSampleBuffer(sampleBuffer)
    }
    
    func encodeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRunning else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let frameWidth = Int32(CVPixelBufferGetWidth(imageBuffer))
        let frameHeight = Int32(CVPixelBufferGetHeight(imageBuffer))
        
        let targetWidth = frameWidth - (frameWidth % 2)
        let targetHeight = frameHeight - (frameHeight % 2)
        
        if needsDimensionSync || targetWidth != width || targetHeight != height {
            width = targetWidth
            height = targetHeight
            setupCompressionSession()
            needsDimensionSync = false
        }
        
        guard let session = compressionSession else { return }
        
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        var frameProperties: CFDictionary? = nil
        if forceNextFrameKeyframe {
            forceNextFrameKeyframe = false
            let keys = [kVTEncodeFrameOptionKey_ForceKeyFrame]
            let values = [kCFBooleanTrue]
            frameProperties = NSDictionary(objects: values as [CFRawPointer?], forKeys: keys as [NSCopying]) as CFDictionary
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
                parameterSetCountOut: &spsCount,
                parameterSetSizeOut: &spsHeaderLength,
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
                parameterSetCountOut: &ppsCount,
                parameterSetSizeOut: &ppsHeaderLength,
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
