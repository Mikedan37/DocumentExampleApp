//
//  BlazeFSM+BlazeBinary.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//
//  PURPOSE:
//  This file extends imported BlazeFSM types to conform to BlazeBinaryCodable.
//  These extensions are intentional and necessary for notebook document serialization
//  using BlazeBinary format (not Codable/JSON).
//
//  EXPECTED WARNINGS:
//  Swift will emit warnings about extending imported types with protocol conformances.
//  These warnings are EXPECTED and ACCEPTABLE because:
//  1. BlazeFSM types currently use Codable, not BlazeBinaryCodable
//  2. We need BlazeBinaryCodable for deterministic binary serialization
//  3. The extensions are in our module, so we control the implementation
//
//  FUTURE MIGRATION:
//  If BlazeFSM adds native BlazeBinaryCodable conformance in the future:
//  1. Remove the corresponding extension from this file
//  2. Update imports if needed
//  3. Verify encoding/decoding behavior matches
//
//  WARNING SUPPRESSION:
//  These warnings are EXPECTED and documented as intentional behavior.
//  They inform us that if BlazeFSM adds native BlazeBinaryCodable support,
//  we should remove these extensions to avoid conflicts.
//
//  To suppress these warnings in Xcode:
//  1. Select BlazeFSM+BlazeBinary.swift in the Project Navigator
//  2. Open File Inspector (right panel)
//  3. Under "Compiler Flags", add: -Xfrontend -warn-long-function-bodies=0
//
//  OR add to Build Settings > Other Swift Flags for the target:
//  -Xfrontend -warn-long-function-bodies=0
//
//  NOTE: These are informational warnings and do not affect functionality.
//  The extensions are safe and intentional as documented above.
//

import Foundation
import CoreGraphics
import BlazeBinary
import BlazeFSM

// MARK: - Protocol Conformance Extensions (Expected Warnings - Can Be Ignored)
//
// The following extensions add BlazeBinaryCodable conformance to imported BlazeFSM types.
// Swift will emit warnings about extending imported types - these are EXPECTED and documented.
//
// WARNING SUPPRESSION NOTE:
// These specific warnings cannot be suppressed via compiler flags in Swift.
// They are informational warnings about potential future conflicts if BlazeFSM adds
// native BlazeBinaryCodable support. The warnings are SAFE TO IGNORE because:
//
// 1. We control the implementation in our module
// 2. BlazeFSM doesn't currently provide BlazeBinaryCodable conformance
// 3. If BlazeFSM adds native support, we'll remove these extensions (as documented)
// 4. The warnings do NOT affect functionality or compilation
//
// These warnings serve as a reminder to check for native BlazeFSM support when updating dependencies.
// They can be filtered from build output or ignored during development.
//

// MARK: - EditorToolState BlazeBinaryCodable

extension EditorToolState: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode as String (rawValue)
        encoder.encode(self.rawValue)
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let rawValue = try decoder.decodeString()
        guard let state = EditorToolState(rawValue: rawValue) else {
            throw BlazeBinaryError.decodeFailed("Invalid EditorToolState rawValue: \(rawValue)")
        }
        self = state
    }
}

// MARK: - AnnotationState BlazeBinaryCodable

extension AnnotationState: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode as String (rawValue)
        encoder.encode(self.rawValue)
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let rawValue = try decoder.decodeString()
        guard let state = AnnotationState(rawValue: rawValue) else {
            throw BlazeBinaryError.decodeFailed("Invalid AnnotationState rawValue: \(rawValue)")
        }
        self = state
    }
}

// MARK: - ResizeAnchor BlazeBinaryCodable

extension ResizeAnchor: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(self.rawValue)
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let rawValue = try decoder.decodeString()
        guard let anchor = ResizeAnchor(rawValue: rawValue) else {
            throw BlazeBinaryError.decodeFailed("Invalid ResizeAnchor rawValue: \(rawValue)")
        }
        self = anchor
    }
}

// MARK: - ResizeDelta BlazeBinaryCodable

extension ResizeDelta: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode CGFloat as Double bit pattern for deterministic encoding
        encoder.encode(Double(width).bitPattern)
        encoder.encode(Double(height).bitPattern)
        try encoder.encode(anchor)
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let widthBits = try decoder.decodeUInt64()
        let heightBits = try decoder.decodeUInt64()
        let width = CGFloat(Double(bitPattern: widthBits))
        let height = CGFloat(Double(bitPattern: heightBits))
        let anchor = try decoder.decode(ResizeAnchor.self)
        self = ResizeDelta(width: width, height: height, anchor: anchor)
    }
}

// MARK: - AnnotationEditPayload BlazeBinaryCodable

extension AnnotationEditPayload: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode optional content - use explicit Bool encoding
        encoder.encode(content != nil)
        if let content = content {
            encoder.encode(content)
        }
        
        // Encode optional properties dictionary - use explicit Bool encoding
        encoder.encode(properties != nil)
        if let properties = properties {
            encoder.encode(UInt64(properties.count))
            for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
                encoder.encode(key)
                encoder.encode(value)
            }
        }
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let hasContent = try decoder.decodeBool()
        let content = hasContent ? try decoder.decodeString() : nil
        
        let hasProperties = try decoder.decodeBool()
        var properties: [String: String]? = nil
        if hasProperties {
            let countInt = try decoder.decodeInt()
            let count = countInt >= 0 ? countInt : 0
            var dict: [String: String] = [:]
            for _ in 0..<count {
                let key = try decoder.decodeString()
                let value = try decoder.decodeString()
                dict[key] = value
            }
            properties = dict.isEmpty ? nil : dict
        }
        
        self = AnnotationEditPayload(content: content, properties: properties)
    }
}

// MARK: - AnnotationCreatePayload BlazeBinaryCodable

extension AnnotationCreatePayload: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(type)
        encoder.encode(Double(bounds.origin.x).bitPattern)
        encoder.encode(Double(bounds.origin.y).bitPattern)
        encoder.encode(Double(bounds.size.width).bitPattern)
        encoder.encode(Double(bounds.size.height).bitPattern)
        
        // Encode optional initialContent - use explicit Bool encoding
        encoder.encode(initialContent != nil)
        if let initialContent = initialContent {
            encoder.encode(initialContent)
        }
        
        // Encode optional properties - use explicit Bool encoding
        encoder.encode(properties != nil)
        if let properties = properties {
            encoder.encode(UInt64(properties.count))
            for (key, value) in properties.sorted(by: { $0.key < $1.key }) {
                encoder.encode(key)
                encoder.encode(value)
            }
        }
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let type = try decoder.decodeString()
        let xBits = try decoder.decodeUInt64()
        let yBits = try decoder.decodeUInt64()
        let widthBits = try decoder.decodeUInt64()
        let heightBits = try decoder.decodeUInt64()
        let x = CGFloat(Double(bitPattern: xBits))
        let y = CGFloat(Double(bitPattern: yBits))
        let width = CGFloat(Double(bitPattern: widthBits))
        let height = CGFloat(Double(bitPattern: heightBits))
        let bounds = CGRect(x: x, y: y, width: width, height: height)
        
        let hasInitialContent = try decoder.decodeBool()
        let initialContent = hasInitialContent ? try decoder.decodeString() : nil
        
        let hasProperties = try decoder.decodeBool()
        var properties: [String: String]? = nil
        if hasProperties {
            let countInt = try decoder.decodeInt()
            let count = countInt >= 0 ? countInt : 0
            var dict: [String: String] = [:]
            for _ in 0..<count {
                let key = try decoder.decodeString()
                let value = try decoder.decodeString()
                dict[key] = value
            }
            properties = dict.isEmpty ? nil : dict
        }
        
        self = AnnotationCreatePayload(type: type, bounds: bounds, initialContent: initialContent, properties: properties)
    }
}

// MARK: - AnnotationEvent BlazeBinaryCodable

extension AnnotationEvent: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        switch self {
        case .select(let annotationID):
            encoder.encode("select")
            encoder.encode(annotationID.uuidString)
            
        case .deselect(let annotationID):
            encoder.encode("deselect")
            encoder.encode(annotationID.uuidString)
            
        case .beginEditing(let annotationID):
            encoder.encode("beginEditing")
            encoder.encode(annotationID.uuidString)
            
        case .commitEdit(let annotationID, let payload):
            encoder.encode("commitEdit")
            encoder.encode(annotationID.uuidString)
            try encoder.encode(payload)
            
        case .beginMove(let annotationID):
            encoder.encode("beginMove")
            encoder.encode(annotationID.uuidString)
            
        case .moveDelta(let annotationID, let dx, let dy):
            encoder.encode("moveDelta")
            encoder.encode(annotationID.uuidString)
            encoder.encode(Double(dx).bitPattern)
            encoder.encode(Double(dy).bitPattern)
            
        case .endMove(let annotationID):
            encoder.encode("endMove")
            encoder.encode(annotationID.uuidString)
            
        case .beginResize(let annotationID):
            encoder.encode("beginResize")
            encoder.encode(annotationID.uuidString)
            
        case .resizeDelta(let annotationID, let delta):
            encoder.encode("resizeDelta")
            encoder.encode(annotationID.uuidString)
            try encoder.encode(delta)
            
        case .endResize(let annotationID):
            encoder.encode("endResize")
            encoder.encode(annotationID.uuidString)
            
        case .delete(let annotationID):
            encoder.encode("delete")
            encoder.encode(annotationID.uuidString)
            
        case .createAnnotation(let payload):
            encoder.encode("createAnnotation")
            try encoder.encode(payload)
            
        case .updateStroke(let annotationID, let point):
            encoder.encode("updateStroke")
            encoder.encode(annotationID.uuidString)
            encoder.encode(Double(point.x).bitPattern)
            encoder.encode(Double(point.y).bitPattern)
            
        case .finishCreate(let annotationID):
            encoder.encode("finishCreate")
            encoder.encode(annotationID.uuidString)
        }
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        let caseName = try decoder.decodeString()
        
        switch caseName {
        case "select":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            self = .select(annotationID: annotationID)
            
        case "deselect":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            self = .deselect(annotationID: annotationID)
            
        case "beginEditing":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            self = .beginEditing(annotationID: annotationID)
            
        case "commitEdit":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            let payload = try decoder.decode(AnnotationEditPayload.self)
            self = .commitEdit(annotationID: annotationID, payload: payload)
            
        case "beginMove":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            self = .beginMove(annotationID: annotationID)
            
        case "moveDelta":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            let dxBits = try decoder.decodeUInt64()
            let dyBits = try decoder.decodeUInt64()
            let dx = CGFloat(Double(bitPattern: dxBits))
            let dy = CGFloat(Double(bitPattern: dyBits))
            self = .moveDelta(annotationID: annotationID, dx: dx, dy: dy)
            
        case "endMove":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            self = .endMove(annotationID: annotationID)
            
        case "beginResize":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            self = .beginResize(annotationID: annotationID)
            
        case "resizeDelta":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            let delta = try decoder.decode(ResizeDelta.self)
            self = .resizeDelta(annotationID: annotationID, delta: delta)
            
        case "endResize":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            self = .endResize(annotationID: annotationID)
            
        case "delete":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            self = .delete(annotationID: annotationID)
            
        case "createAnnotation":
            let payload = try decoder.decode(AnnotationCreatePayload.self)
            self = .createAnnotation(payload: payload)
            
        case "updateStroke":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            let xBits = try decoder.decodeUInt64()
            let yBits = try decoder.decodeUInt64()
            let x = CGFloat(Double(bitPattern: xBits))
            let y = CGFloat(Double(bitPattern: yBits))
            self = .updateStroke(annotationID: annotationID, point: CGPoint(x: x, y: y))
            
        case "finishCreate":
            let uuidString = try decoder.decodeString()
            guard let annotationID = UUID(uuidString: uuidString) else {
                throw BlazeBinaryError.decodeFailed("Invalid UUID: \(uuidString)")
            }
            self = .finishCreate(annotationID: annotationID)
            
        default:
            throw BlazeBinaryError.decodeFailed("Unknown AnnotationEvent case: \(caseName)")
        }
    }
}

// MARK: - AnnotationStateTransition BlazeBinaryCodable

extension AnnotationStateTransition: BlazeBinaryCodable {
    public func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode fields in order: annotationID, from, to, event, timestamp, payload
        encoder.encode(annotationID.uuidString)
        try encoder.encode(from)
        try encoder.encode(to)
        try encoder.encode(event)
        
        // Timestamp as UInt64 (epoch seconds)
        let timestampSeconds = UInt64(timestamp.timeIntervalSince1970)
        encoder.encode(timestampSeconds)
        
        // Payload as optional Data
        if let payload = payload {
            encoder.encode(true)
            encoder.encode(payload)
        } else {
            encoder.encode(false)
        }
    }
    
    public init(from decoder: BlazeBinaryDecoder) throws {
        // Decode UUID
        let uuidString = try decoder.decodeString()
        guard let annotationID = UUID(uuidString: uuidString) else {
            throw BlazeBinaryError.decodeFailed("Invalid UUID string: \(uuidString)")
        }
        
        // Decode states and event
        let from = try decoder.decode(AnnotationState.self)
        let to = try decoder.decode(AnnotationState.self)
        let event = try decoder.decode(AnnotationEvent.self)
        
        // Decode timestamp
        let timestampSeconds = try decoder.decodeUInt64()
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampSeconds))
        
        // Decode optional payload
        let hasPayload = try decoder.decodeBool()
        let payload = hasPayload ? try decoder.decodeData() : nil
        
        self = AnnotationStateTransition(
            annotationID: annotationID,
            from: from,
            to: to,
            event: event,
            timestamp: timestamp,
            payload: payload
        )
    }
}

