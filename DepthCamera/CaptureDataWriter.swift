//
//  CaptureDataWriter.swift
//  DepthCamera
//
//  Created by Tianjian Xu on 3/7/23.
//

import simd
import CoreImage
import CoreMedia
import UIKit

/// The object manages to save capture data to local files.
class CaptureDataWriter {
    
    var globals = GlobalVariables.instance
    var saveDirectory: URL!
    
    var firstTimestamp: Double = -1
    var serializedTimestamps : String = ""
    
    let ioQueue = DispatchQueue(label: "I/O Queue", qos: .background)
    
    /// Prepare for a new around of capture cycle.
    func prepareForNewCaptureCycle() {
        saveDirectory = createSaveFolder()
        firstTimestamp = -1  // Assign a negative value indicating no timestamps received yet.
        serializedTimestamps = ""
    }
    
    /// Write data to local files. This function is very slow and should be executed in a background thread.
    func write(frameID: Int, rgbPixelBuffer: CVPixelBuffer, depthPixelBuffer : CVPixelBuffer, cameraIntrinsic: simd_float3x3) {
        let rgbURL = saveDirectory.appendingPathComponent(String(frameID) + ".jpeg")
        let depthURL = saveDirectory.appendingPathComponent(String(frameID) + ".bin")
        let calibURL = saveDirectory.appendingPathComponent(String(frameID) + "_calibration.txt")
        
        ioQueue.async { [weak self] in
            self?.writeRGBData(rgbPixelBuffer, to: rgbURL)
            self?.writeDepthData(depthPixelBuffer, to: depthURL)
            self?.writeCameraCalibData(cameraIntrinsic: cameraIntrinsic, to: calibURL)
        }
    }
    
    /// Save timestamp for each individual frame captured. All the timestamps are collected and it should be written into one single file by calling exportTimestamps when the capture completes.
    func saveTimestamp(_ timestamp: Double) {
        if firstTimestamp < 0 {
            firstTimestamp = timestamp
        }
        
        self.serializedTimestamps += String(timestamp - firstTimestamp) + ","
    }
    
    /// Write timestamps into one timestamps.cvs file.
    func exportTimestamps(firstDataCaptureFrameID: Int) {
        let csvURL = saveDirectory.appendingPathComponent("timestamps.csv")
        // Add first data capture frame id to the end of the serialized
        serializedTimestamps += String(firstDataCaptureFrameID)
        
        ioQueue.async { [weak self] in
            do {
                try self?.serializedTimestamps.write(toFile: csvURL.path, atomically: false, encoding: String.Encoding.utf8)
            } catch {
                print("Unable to export timestamps: \(error)")
            }
        }
    }
    
    /// This function will block the calling thread until all the tasks in the I/O queue complete.
    func sync() {
        ioQueue.sync {
            print("All tasks completed.")
        }
    }
}

// MARK: Private helper functions implementation
extension CaptureDataWriter {
    /// Create a new folder under the document/DTTD directory to save capture data and returns the folder URL.
    /// URL are in the format YYYY-MM-DD-HH-MM-SS, e.g. 2022-08-05-14-49-00
    private func createSaveFolder() -> URL {
        let manager = FileManager.default
        let rootURL = manager.urls(for: .documentDirectory, in: .userDomainMask).first
        let date = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let hour = calendar.component(.hour, from: date)
        let minutes = calendar.component(.minute, from: date)
        let seconds = calendar.component(.second, from: date)
        // Example: 2022-08-05-14-49-00
        let outputFolderName = [
            String(format: "%04d", year),
            String(format: "%02d", month),
            String(format: "%02d", day),
            String(format: "%02d", hour),
            String(format: "%02d", minutes),
            String(format: "%02d",seconds)
        ].joined(separator: "-")
        
        let folderURL = rootURL!.appending(component: "DTTD").appendingPathComponent(outputFolderName)
        
        do {
            try manager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            print("Write to path: " + folderURL.absoluteString)
        } catch {
            print("Unable to create the output folder: \(error)")
        }
        
        return folderURL
    }
    
    private func writeRGBData(_ rgbPixelBuffer: CVPixelBuffer, to url: URL) {
        let rgbCIImage = CIImage(cvPixelBuffer: rgbPixelBuffer)
        let rgbCGImage = CIContext().createCGImage(rgbCIImage, from: rgbCIImage.extent)!
        let rgbImage = UIImage(cgImage: rgbCGImage)
        
        let rgbJpeg = rgbImage.jpegData(compressionQuality: 0.3)!
        do {
            try rgbJpeg.write(to: url)
        } catch {
            print("Unable to write RGB data: \(error)")
        }
    }
    
    private func writeDepthData(_ depthPixelBuffer: CVPixelBuffer, to url: URL) {
        let uint16_DepthPixelBuffer: CVPixelBuffer = depthCVPixelToData(from: depthPixelBuffer)
        CVPixelBufferLockBaseAddress(uint16_DepthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let height = CVPixelBufferGetHeight(uint16_DepthPixelBuffer)
        let baseAddress = CVPixelBufferGetBaseAddress(uint16_DepthPixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(uint16_DepthPixelBuffer)
        CVPixelBufferUnlockBaseAddress(uint16_DepthPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let yLength = bytesPerRow *  height
        
        let depthData = Data(bytes: baseAddress!, count: yLength)
        do {
            try depthData.write(to: url)
        } catch {
            print("Unable to write depth data: \(error)")
        }
    }
    
    private func writeCameraCalibData(cameraIntrinsic: simd_float3x3, to url: URL) {
        let cameraIntrinsic: String = matrix_to_string(from: cameraIntrinsic, name: "Camera Intrinsic: \n")
        
        // MARK: Only intrinsic is needed. Extrinsic and distortion are fake data to satisify the preprocessing script.
        let cameraExtrinsic: String = matrix_to_string(from: simd_float4x3(), name: "Camera Extrinsic: \n")
        let lensDistortionCenter: String = "Distortion Center: \n" +  String(Float(0)) + "," + String(Float(0))
        
        let calibrationData: String = cameraIntrinsic + "\n" + cameraExtrinsic + "\n" + lensDistortionCenter
        do {
            try calibrationData.write(toFile: url.path, atomically: false, encoding: String.Encoding.utf8)
        } catch {
            print("Unable to write calibration data: \(error)")
        }
    }
    
    /// Converts the pixel format of the depth CVPixelBuffer from Float32 to UInt16.
    private func depthCVPixelToData(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        
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
        
        for y in 0...(rows-1) {
            for x in 0...(cols-1) {
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
    
    private func matrix_to_string(from matrix: matrix_float3x3, name: String) -> String {
        var output = name
        output += "["
        for i in 0...2 {
            output += "["
            for j in 0...2 {
                output += String(matrix[i][j]) + ","
            }
            output = String(output.dropLast())
            output += "],\n"
        }
        output = String(output.dropLast(2))
        output += "]"
        return output
    }
    
    private func matrix_to_string(from matrix: matrix_float4x3, name: String) -> String {
        var output = name
        output += "["
        for i in 0...3 {
            output += "["
            for j in 0...2 {
                output += String(matrix[i][j]) + ","
            }
            output = String(output.dropLast())
            output += "],\n"
        }
        output = String(output.dropLast(2))
        output += "]"
        return output
    }
}
