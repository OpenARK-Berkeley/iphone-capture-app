//
//  Globals.swift
//  DepthCamera
//
//  Created by Tianjian Xu on 3/2/23.
//

import ARKit
import SwiftUI

class GlobalVariables: ObservableObject {
    static var instance = GlobalVariables()
    
    @Published var captureState: CaptureState = .arSessionNotReady
    @Published var displayMode: CaptureDisplayMode = .displayRGB
    @Published var useDepthConfidence: Bool = true
    @Published var depthConfidence: ARConfidenceLevel = .low
    
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var commandQueue: MTLCommandQueue! = device.makeCommandQueue()
    lazy var library: MTLLibrary! = device.makeDefaultLibrary()
    
    var rendererCache: [CaptureDisplayMode: CaptureRenderer] = [:]
    var renderer: CaptureRenderer {
        if let renderer = rendererCache[displayMode] {
            return renderer
        }
        
        let renderer = displayMode.makeRenderer()
        rendererCache[displayMode] = renderer
        return renderer
    }
    
    private init() { }
}

/// Possible states the capture app can go into.
/// Once the ARSession is ready, the capture states should proceed linearly from "Available for Capture", "Needs Calibration", to "Calibrating", to "Ready for Data Collection", and to "Collecting Data".
/// The capture state will go back to "Available for Capture" after "Collecting Data" completes.
enum CaptureState: CaseIterable, Identifiable {
    case arSessionNotReady
    case availableForCapture
    case needCalibration
    case calibrating
    case readyForDataCollection
    case collectingData
    
    /// Proceed to the next state.
    mutating func next() {
        // Stay not ready if ARSession is not ready yet.
        if self == .arSessionNotReady {
            return
        }
        
        // Move back to "Needs Calibration" after "Collection Completed).
        if self == .collectingData {
            self = .availableForCapture
            return
        }
        
        let allCases = Self.allCases
        let nextIdx = (allCases.firstIndex(of: self)! + 1) % allCases.count
        self = allCases[nextIdx]
    }
    
    /// String description of the state.
    func getDescription() -> String {
        switch self {
        case .arSessionNotReady:
            return "ARSession Not Ready"
        case .availableForCapture:
            return "Available for Capture"
        case .needCalibration:
            return "1. Need Calibration"
        case .calibrating:
            return "2. Calibrating"
        case .readyForDataCollection:
            return "3. Ready for Data Collection"
        case .collectingData:
            return "4. Collecting Data"
        }
    }
    
    /// Detailed instructions on what to do during each state.
    func getInstruction() -> String {
        switch self {
        case .arSessionNotReady:
            return "ARSession is not ready. Make sure the device supports ARKit and ARSession has been started."
        case .availableForCapture:
            return "The device is available for a new capture pass. Please prepare for capturing."
        case .needCalibration:
            return "The capture device needs calibration data by capturing the ARUCO marker."
        case .calibrating:
            return "Collecting calibrating data. Make sure the ARUCO marker can be seen by the camera."
        case .readyForDataCollection:
            return "Please cover the ARUCO marker. The capturing device is ready for scene data collection."
        case .collectingData:
            return "Collecting scene data. Make sure objects in the scene can be seen by the camera."
        }
    }
    
    func getGuidanceColor() -> Color {
        switch self {
        case .arSessionNotReady:
            return .red
        case .availableForCapture:
            return .green
        case .needCalibration:
            return .orange
        case .calibrating:
            return .indigo
        case .readyForDataCollection:
            return .blue
        case .collectingData:
            return .purple
        }
    }
    
    var id: Self { self }
}

/// Display mode of the capture app. Now it supports RGB display mode and depth display mode.
enum CaptureDisplayMode: String, CaseIterable, Identifiable {
    case displayRGB = "Display RGB"
    case displayDepth = "Display Depth"
    
    func makeRenderer() -> CaptureRenderer {
        switch self {
        case .displayRGB:
            return VideoCaptureRenderer()
        case .displayDepth:
            return DepthCaptureRenderer()
        }
    }
    
    var id: Self { self }
}


