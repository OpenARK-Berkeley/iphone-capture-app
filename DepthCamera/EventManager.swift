//
//  EventManager.swift
//  DepthCamera
//
//  Created by Tianjian Xu on 3/6/23.
//

import Foundation

/// An event system that manages event triggers and handlers in the capture app.
class EventManager {
    enum EventType {
        case arSessionReady
        case newCapturePass
        case dataCollectionStart
        case captureComplete
        
        case captureSingleFrame
    }
    
    static var eventsTable: [EventType: [() -> Void]] = [:]
    
    static func trigger(_ eventType: EventType,
                        onComplete callback: (() -> Void)? = nil) {
        eventsTable[eventType]?.forEach { handler in
            handler()
        }
        
        if let callback = callback {
            callback()
        }
    }
    
    static func register(_ eventType: EventType, handler: @escaping () -> Void) {
        if eventsTable[eventType] == nil {
            eventsTable[eventType] = []
        }
        eventsTable[eventType]!.append(handler)
    }
}
