import SwiftUI
import AVFoundation

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    
    class VideoPreviewView: NSView {
        private var previewLayer: AVCaptureVideoPreviewLayer?
        
        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            self.wantsLayer = true
            
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            self.layer = layer
            self.previewLayer = layer
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layout() {
            super.layout()
            previewLayer?.frame = self.bounds
        }
    }
    
    func makeNSView(context: Context) -> VideoPreviewView {
        return VideoPreviewView(session: session)
    }
    
    func updateNSView(_ nsView: VideoPreviewView, context: Context) {
        // No-op
    }
}
