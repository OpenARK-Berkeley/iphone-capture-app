/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An object that configures and manages the capture pipeline to stream video and LiDAR depth data.
*/

import Foundation
import AVFoundation
import CoreImage
import UIKit
import SwiftUI
import ARKit


protocol CaptureDataReceiver: AnyObject {
    func onNewData(capturedData: CameraCapturedData)
    
    @available(*, deprecated, message: "This function is longer used after adopting ARKit.")
    func onNewPhotoData(capturedData: CameraCapturedData)
}

class CameraController: NSObject, ObservableObject {
    
    enum ConfigurationError: Error {
        case lidarDeviceUnavailable
        case requiredFormatUnavailable
    }
    
    private let preferredWidthResolution = 1920
    
    private var arSession: ARSession!
    private var textureCache: CVMetalTextureCache!
    
    weak var delegate: CaptureDataReceiver?
    
    @available(*, deprecated, message: "This variable is no longer used nor maintained.")
    var isFilteringEnabled = false
    
    private var folder_url : URL?
    private var latest_frame_id : Int = 0
    private var can_write_data : Bool = false
    private var timestamps : String = ""
    private var start_timestamp : Double = 0
    private var data_start_frame_id : Int = -1
    private var end_collecting_data : Bool = false
    private var timestamp_exported : Bool = false
    
    override init() {
        
        // Create a texture cache to hold sample buffer textures.
        CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                  nil,
                                  MetalEnvironment.shared.metalDevice,
                                  nil,
                                  &textureCache)
        
        super.init()
        
        // create a new folder to save data
        folder_url = createNewFolder()
        initARSession()
    }
    
    func initARSession() {
        arSession = ARSession()
        arSession.delegate = self
        
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = [.sceneDepth]
        } else {
            fatalError("This device does not support scene depth.")
        }
        arSession.run(config)
    }
    
    func changeAppStatus(can_write_data : Bool, collecting_data: Bool){
        self.can_write_data = can_write_data
        if(collecting_data){
            if(can_write_data){ // when start collecting data
                data_start_frame_id = latest_frame_id
            }
            else{ // when end collecting data
                end_collecting_data = true
            }
        }
    }
    
    private func createNewFolder() -> URL{
        let manager = FileManager.default
        let root_url = manager.urls(for: .documentDirectory, in: .userDomainMask).first
        let date = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let hour = calendar.component(.hour, from: date)
        let minutes = calendar.component(.minute, from: date)
        let seconds = calendar.component(.second, from: date)
        let cur_date = String(format: "%04d", year) + "-" + String(format: "%02d", month) + "-" + String(format: "%02d", day) + "-" + String(format: "%02d", hour) + "-" + String(format: "%02d", minutes) + "-" + String(format: "%02d",seconds)
        let folder_url = root_url!.appendingPathComponent(cur_date)
        try? manager.createDirectory(at: folder_url, withIntermediateDirectories: true)
        // 2022-08-05-14-49-00
        return folder_url
    }
    
    func hasZero(from pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let rows = CVPixelBufferGetHeight(pixelBuffer)
        let cols = CVPixelBufferGetWidth(pixelBuffer)
        
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let buffer = baseAddress?.assumingMemoryBound(to: UInt16.self)
        
        
        // Get the pixel.  You could iterate here of course to get multiple pixels!
        
        var out = false
        
        for y in 1...rows{
            for x in 1...cols{
                let baseAddressIndex = y  * cols + x
                let pixel = buffer![baseAddressIndex]
                if (pixel == 0) {
                    out = true
                    break
                }
            }
            if (out) {
                break
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return out
    }
    
    func depthCVPixelToData(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer{
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let rows = CVPixelBufferGetHeight(pixelBuffer)
        let cols = CVPixelBufferGetWidth(pixelBuffer)

        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let buffer = baseAddress?.assumingMemoryBound(to: Float32.self)
        
        var new_cvbuffer : CVPixelBuffer? = nil
        
        CVPixelBufferCreate(kCFAllocatorDefault, cols, rows, kCVPixelFormatType_16Gray, nil, &new_cvbuffer)
        
        CVPixelBufferLockBaseAddress(new_cvbuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        let outBaseAddress = CVPixelBufferGetBaseAddress(new_cvbuffer!)
        
        let uint16buffer = outBaseAddress?.assumingMemoryBound(to: UInt16.self)
        
        for y in 0...(rows-1){
            for x in 0...(cols-1){
                let baseAddressIndex = y  * cols + x
                var pixel = buffer![baseAddressIndex]
                if (pixel.isNaN || pixel.isInfinite) {
                    pixel = 0
                }
                let pixel_uint16 : UInt16 = UInt16(pixel * 1000)
                uint16buffer![baseAddressIndex] = pixel_uint16
            }
        }
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        CVPixelBufferUnlockBaseAddress(new_cvbuffer!, CVPixelBufferLockFlags(rawValue: 0))
        return new_cvbuffer!
    }
    
    func save_depth_data(from depthDataMap : CVPixelBuffer, url: URL){
        let new_cvbuffer : CVPixelBuffer = depthCVPixelToData(from: depthDataMap)
        CVPixelBufferLockBaseAddress(new_cvbuffer, CVPixelBufferLockFlags(rawValue: 0))
        let height = CVPixelBufferGetHeight(new_cvbuffer)
        let yBaseAddress = CVPixelBufferGetBaseAddress(new_cvbuffer)
        let yBytesPerRow = CVPixelBufferGetBytesPerRow(new_cvbuffer)
        CVPixelBufferUnlockBaseAddress(new_cvbuffer, CVPixelBufferLockFlags(rawValue: 0))
        let yLength = yBytesPerRow *  height
        let d_data = Data(bytes: yBaseAddress!, count: yLength)
        try? d_data.write(to: url)
    }
    
    func save_timestamp_data(from timestamp: CMTime){
        // save timestamps, write later as one single file
        if(start_timestamp == 0){
            start_timestamp = timestamp.seconds
            print("start timestamp: ", start_timestamp)
        }
        self.timestamps += String(timestamp.seconds - start_timestamp) + ","
    }
    
    func matrix_to_string(from matrix : matrix_float3x3, name : String) -> String{
        var matrix_name = name
        matrix_name += "["
        for i in 0...2{
            matrix_name += "["
            for j in 0...2{
                matrix_name += String(matrix[i][j]) + ","
            }
            matrix_name = String(matrix_name.dropLast())
            matrix_name += "],\n"
        }
        matrix_name = String(matrix_name.dropLast(2))
        matrix_name += "]"
        return matrix_name
    }
    
    func matrix_to_string(from matrix : matrix_float4x3, name : String) -> String{
        var matrix_name = name
        matrix_name += "["
        for i in 0...3{
            matrix_name += "["
            for j in 0...2{
                matrix_name += String(matrix[i][j]) + ","
            }
            matrix_name = String(matrix_name.dropLast())
            matrix_name += "],\n"
        }
        matrix_name = String(matrix_name.dropLast(2))
        matrix_name += "]"
        return matrix_name
    }
    
    func save_camera_calib_data(from intrinsicMatrix: simd_float3x3, calibration_url: URL, inverse_lookup_table_url: URL) {
        let cameraIntrinsic : String = matrix_to_string(from: intrinsicMatrix, name: "Camera Intrinsic: \n")
        
        // MARK: Only intrinsic is needed. Extrinsic and distortion are fake data to satisify the preprocessing script.
        let cameraExtrinsic : String = matrix_to_string(from: simd_float4x3(), name: "Camera Extrinsic: \n")
        let lensDistortionCenter : String = "Distortion Center: \n" +  String(Float(0)) + "," + String(Float(0))
        let calibrationData : String = cameraIntrinsic + "\n" + cameraExtrinsic + "\n" + lensDistortionCenter

        try? calibrationData.write(toFile: calibration_url.path, atomically: false, encoding: String.Encoding.utf8)
    }
    
    func save_data(sampleBuffer : CMSampleBuffer, depthDataMap : CVPixelBuffer, timestamp: CMTime, cameraIntrinsic: simd_float3x3, frame_id: Int){
        // retrieve rgb data
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let rgb_ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let rgb_cgImage = CIContext(options: nil).createCGImage(rgb_ciImage, from: rgb_ciImage.extent)!
        let rgb_img = UIImage(cgImage: rgb_cgImage)
        
        if let img = rgb_img.jpegData(compressionQuality: 0.3) {
            let rgb_url = folder_url!.appendingPathComponent(String(frame_id) + ".jpeg")
            let depth_url = folder_url!.appendingPathComponent(String(frame_id) + ".bin")
            let calibration_url = folder_url!.appendingPathComponent(String(frame_id) + "_calibration.txt")
            let inverse_lookup_table_url = folder_url!.appendingPathComponent(String(frame_id) + "_distortion_table.bin")
            
            try! img.write(to: rgb_url)
            save_depth_data(from: depthDataMap, url: depth_url)
            save_timestamp_data(from: timestamp)
            save_camera_calib_data(from: cameraIntrinsic, calibration_url: calibration_url, inverse_lookup_table_url: inverse_lookup_table_url)
        }
    }
    
    private func exportTimeStampData(){
        let csv_url = folder_url!.appendingPathComponent("timestamps.csv")
        timestamps += String(data_start_frame_id) // add id to the end of the array
        try? timestamps.write(toFile: csv_url.path, atomically: false, encoding: String.Encoding.utf8)
    }
}

// Mark: ARSession Delegate
extension CameraController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        let videoData = frame.capturedImage
        guard let depthDataMap = frame.sceneDepth?.depthMap else { return }
        
        // Package the captured data.
        let data = CameraCapturedData(
            depth: depthDataMap.texture(withFormat: .r32Float, planeIndex: 0, addToCache: textureCache),
            colorY: videoData.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache),
            colorCbCr: videoData.texture(withFormat: .rg8Unorm, planeIndex: 1, addToCache: textureCache),
            cameraIntrinsics: frame.camera.intrinsics,
            cameraReferenceDimensions: CGSize()) // FIXME: Not sure what to put here...
        
        
        // apply distortion correction to both rgb images and depth images
//        apply_distortion_correction(sampleBuffer : syncedVideoData.sampleBuffer, lookupTable: cameraCalibrationData.lensDistortionLookupTable!, opticalCenter: cameraCalibrationData.lensDistortionCenter)
        
        // save to local directory
        if(can_write_data){
            let frame_id = latest_frame_id
            latest_frame_id += 1
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var sampleBuffer: CMSampleBuffer?
                var timimgInfo  = CMSampleTimingInfo()
                var formatDescription: CMFormatDescription? = nil
                
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: videoData, formatDescriptionOut: &formatDescription)
                
                CMSampleBufferCreateReadyWithImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: videoData,
                    formatDescription: formatDescription!,
                    sampleTiming: &timimgInfo,
                    sampleBufferOut: &sampleBuffer
                )
                    
                if let sampleBuffer = sampleBuffer {
                    self?.save_data(
                        sampleBuffer: sampleBuffer,
                        depthDataMap: depthDataMap,
                        timestamp: CMTime(seconds: frame.timestamp, preferredTimescale: 1000000),
                        cameraIntrinsic: frame.camera.intrinsics,
                        frame_id: frame_id)
                }
            }
        }
        
        if(end_collecting_data && !timestamp_exported){
            exportTimeStampData()
            timestamp_exported = true
        }
        
        // delegate data
        delegate?.onNewData(capturedData: data)
        
    }
}
