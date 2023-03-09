//
//  CaptureDisplayViewCoordinator.swift
//  DepthCamera
//
//  Created by Tianjian Xu on 3/1/23.
//

import ARKit
import MetalKit


class CaptureDisplayViewCoordinator: NSObject {
    var view: CaptureDisplayUIView!
    var globals = GlobalVariables.instance
    lazy var device: MTLDevice! = globals.device
    
    var writer: CaptureDataWriter = CaptureDataWriter()
    
    var textureCache: CVMetalTextureCache!
    var videoPixelBuffer: CVPixelBuffer?
    var depthPixelBuffer: CVPixelBuffer?
    var depthConfidencePixelBuffer: CVPixelBuffer?
    
    var latestFrameID = 0
    var firstDataCaptureFrameID = 0
    
    init(view: CaptureDisplayUIView? = nil) {
        super.init()
        self.view = view
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        registerEventHandlers()
    }
    
    private func registerEventHandlers() {
        EventManager.register(.captureSingleFrame) { [weak self] in
            self?.captureSingleFrame()
        }
        
        EventManager.register(.newCapturePass) { [weak self] in
            self?.prepareForNewCaptureCycle()
        }
        
        EventManager.register(.dataCollectionStart) { [weak self ] in
            self?.onDataCollectionStart()
        }
        
        EventManager.register(.captureComplete) { [weak self] in
            self?.onCaptureComplete()
        }
    }
}

// MARK: MetalKit View Rendering
extension CaptureDisplayViewCoordinator: MTKViewDelegate {
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
    
    func draw(in view: MTKView) {
        globals.renderer.draw(in: view)
    }
}

// MARK: ARSession Controlling
extension CaptureDisplayViewCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        videoPixelBuffer = frame.capturedImage
        depthPixelBuffer = frame.sceneDepth?.depthMap
        depthConfidencePixelBuffer = frame.sceneDepth?.confidenceMap
        let cameraIntrinsics = frame.camera.intrinsics
        
        guard let videoPixelBuffer = videoPixelBuffer,
              let depthPixelBuffer = depthPixelBuffer,
              let depthConfidencePixelBuffer = depthConfidencePixelBuffer else {
            return
        }
        
        // Write the capture if calibrating or collecting data.
        if globals.captureState == .calibrating || globals.captureState == .collectingData {
            latestFrameID += 1
            writer.saveTimestamp(frame.timestamp)
            writer.write(frameID: latestFrameID, rgbPixelBuffer: videoPixelBuffer, depthPixelBuffer: depthPixelBuffer, cameraIntrinsic: cameraIntrinsics)
        }
        
        // Display the capture.
        switch globals.displayMode {
        case .displayRGB:
            globals.renderer.textures[.videoY] = nil
            globals.renderer.textures[.videoCrBr] = nil
            globals.renderer.textures[.videoY] = createMTLTexture(from: videoPixelBuffer, textureCache: textureCache, pixelFormat: .r8Unorm, planeIndex: 0)
            globals.renderer.textures[.videoCrBr] = createMTLTexture(from: videoPixelBuffer, textureCache: textureCache, pixelFormat: .rg8Unorm, planeIndex: 1)
            
        case .displayDepth:
            globals.renderer.textures[.depth] = nil
            globals.renderer.textures[.depthConfidence] = nil
            globals.renderer.textures[.depth] = createMTLTexture(from: depthPixelBuffer, textureCache: textureCache, pixelFormat: .r32Float)
            globals.renderer.textures[.depthConfidence] = createMTLTexture(from: depthConfidencePixelBuffer, textureCache: textureCache, pixelFormat: .r8Uint)
        }
    }
    
    private func createMTLTexture(from pixelBuffer: CVPixelBuffer,
                                  textureCache: CVMetalTextureCache,
                                  pixelFormat: MTLPixelFormat,
                                  planeIndex: Int = 0) -> MTLTexture? {
        var mtlTexture: MTLTexture? = nil
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var cvTexture: CVMetalTexture? = nil
        guard kCVReturnSuccess == CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &cvTexture) else {
            print("Unable to create texture.")
            return nil
        }
        
        mtlTexture = CVMetalTextureGetTexture(cvTexture!)
        return mtlTexture
    }
}

// MARK: Event handlers.
extension CaptureDisplayViewCoordinator {
    
    /// Prepare for a new around of capture cycle.
    func prepareForNewCaptureCycle() {
        writer.prepareForNewCaptureCycle()
        latestFrameID = 0
        firstDataCaptureFrameID = 0
    }
    
    // Handle the moment when the app begins data collection.
    func onDataCollectionStart() {
        firstDataCaptureFrameID = latestFrameID
    }
    
    /// Wrap up works when one capture pass completes.
    func onCaptureComplete() {
        writer.exportTimestamps(firstDataCaptureFrameID: firstDataCaptureFrameID)
        writer.sync()  // Flush all writing tasks in the writer.
    }
    
    /// Capture single frame (testing use)
    func captureSingleFrame() {
        let session = view.session
        session?.captureHighResolutionFrame { ( frame, error ) in
            if let error = error {
                print(error)
            }
            
            guard let rgb_pixelBuffer = frame?.capturedImage else { return }
            let rgb_ciImage = CIImage(cvPixelBuffer: rgb_pixelBuffer)
            let rgb_cgImage = CIContext().createCGImage(rgb_ciImage, from: rgb_ciImage.extent)!
            let rgb_uiImage = UIImage(cgImage: rgb_cgImage)
            UIImageWriteToSavedPhotosAlbum(rgb_uiImage, nil, nil, nil)
        }
    }
}
