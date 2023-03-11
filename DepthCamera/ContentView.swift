//
//  ContentView.swift
//  DepthCamera
//
//  Created by Tianjian Xu on 3/1/23.
//

import SwiftUI
import ARKit

struct ContentView: View {
    @StateObject var globals = GlobalVariables.instance
    @State var showDeleteDataAlert = false
    
    var body: some View {
        VStack(alignment: .center) {
            Picker("Display Mode", selection: $globals.displayMode) {
                ForEach(CaptureDisplayMode.allCases) { mode in
                    Text(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            
            if globals.displayMode == .displayDepth {
                HStack {
                    Text("Depth Confidence")
                    Picker("Depth Confidence", selection: $globals.depthConfidence) {
                        Text("Keep all depth").tag(ARConfidenceLevel.low)
                        Text("Medium or above").tag(ARConfidenceLevel.medium)
                        Text("High").tag(ARConfidenceLevel.high)
                    }
                }
            }
            
            ZStack(alignment: .topTrailing) {
                CaptureDisplayView()
                    .aspectRatio(1440/1920, contentMode: .fit)
                .ignoresSafeArea()
                
                // Capture State indicator
                Button(globals.captureState.getDescription(), role: .none) { }
                    .buttonStyle(.borderedProminent).tint(globals.captureState.getGuidanceColor())
            }
            
            // Capture instruction.
            Text(globals.captureState.getInstruction())
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 1.0, opacity: 0.1)))
            
            // Capture button.
            makeCaptureButton()
        }
        .padding()
        
        Spacer()
        
            
            
        HStack {
            Spacer()
            
            Button("Delete All Data", role: .destructive) {
                showDeleteDataAlert = true
            }
            .padding()
            .alert("Delete All Data", isPresented: $showDeleteDataAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) { deleteAllCaptureData() }
            } message: {
                Text("You are going to delete all the capture data. Please make sure you have a backup for the capture data.")
            }
        }

            
    }
    
    
    func makeCaptureButton() -> some View {
        switch globals.captureState {
        case .arSessionNotReady:
            return AnyView(Button{ } label: {
                Text("Unavailable").padding()
                }
                .disabled(true)
                .buttonStyle(.borderedProminent))
        
        case .availableForCapture:
            return AnyView(Button {
                    EventManager.trigger(.newCapturePass) {
                        globals.captureState.next()
                    }
                } label: {
                    Text("Prepare for Capture").padding()
                }
                .buttonStyle(.borderedProminent).tint(.blue))
            
            
        case .needCalibration:
            return AnyView(Button {
                    globals.captureState.next()
                } label: {
                    Text("Start to Calibrate").padding()
                }
                .buttonStyle(.borderedProminent).tint(.green))
            
        case .calibrating:
            return AnyView(Button {
                    globals.captureState.next()
                } label: {
                    Text("Stop Calibrating").padding()
                }
                .buttonStyle(.borderedProminent).tint(.gray))
            
        case .readyForDataCollection:
            return AnyView(Button {
                    EventManager.trigger(.dataCollectionStart) {
                        globals.captureState.next()
                    }
                } label: {
                    Text("Start to Capture").padding()
                }
                .buttonStyle(.borderedProminent).tint(.green))
            
        case .collectingData:
            return AnyView(Button {
                    EventManager.trigger(.captureComplete) {
                        globals.captureState.next()
                    }
                } label: {
                    Text("Stop Capturing").padding()
                }
                .buttonStyle(.borderedProminent).tint(.gray))
        }
    }
    
    func deleteAllCaptureData() {
        let manager = FileManager.default
        let captureDirectory = manager.urls(for: .documentDirectory, in: .userDomainMask).first!.appending(component: "DTTD")
        
        do {
            try manager.removeItem(at: captureDirectory)
            print("Remove Path: " + captureDirectory.absoluteString)
        } catch {
            print("Unable to remove the capture folder: \(error)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
