//
//  CaptureDisplayView.swift
//  DepthCamera
//
//  Created by Tianjian Xu on 3/1/23.
//

import SwiftUI
import ARKit
import MetalKit

struct CaptureDisplayView: UIViewRepresentable {
    func makeCoordinator() -> CaptureDisplayViewCoordinator {
        return CaptureDisplayViewCoordinator()
    }
    
    func makeUIView(context: Context) -> CaptureDisplayUIView {
        let view = CaptureDisplayUIView(frame: .zero, coordinator: context.coordinator)
        context.coordinator.view = view
        return view
    }
    
    func updateUIView(_ uiView: CaptureDisplayUIView, context: Context) {
        
    }
}

class CaptureDisplayUIView: MTKView {
    
    var session: ARSession!
    var coordinator: CaptureDisplayViewCoordinator!
    
    init(frame frameRect: CGRect, coordinator: CaptureDisplayViewCoordinator) {
        super.init(frame: frameRect, device: coordinator.device)
        
        self.coordinator = coordinator
        self.session = ARSession()
        
        initMTKView()
        initSession()
    }
    

    private func initMTKView() {
        self.delegate = coordinator
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.colorPixelFormat = .bgra8Unorm
    }
    
    private func initSession() {
        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            fatalError("The device does not have full support for ARKit.")
        }
        
        let config = ARWorldTrackingConfiguration()
        
        // Pass in config params.
        config.frameSemantics = [.sceneDepth]
        
        session.delegate = coordinator
        session.run(config)
        GlobalVariables.instance.captureState = .availableForCapture
        EventManager.trigger(.arSessionReady)
    }
    
    
    @available(swift, obsoleted: 1.0, message: "This init function is not implemented.")
    required init(coder: NSCoder) {
        super.init(coder: coder)
        fatalError("init(coder:) not implemented.")
    }
}
