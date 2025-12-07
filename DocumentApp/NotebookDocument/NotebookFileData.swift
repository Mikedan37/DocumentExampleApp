//
//  NotebookFileData.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import Foundation
import BlazeBinary
import BlazeFSM

/// Complete file contents for a notebook document.
/// Contains metadata, all annotation state transitions, and initial tool state.
/// Conforms to BlazeBinaryCodable for deterministic binary serialization.
struct NotebookFileData: BlazeBinaryCodable {
    var metadata: NotebookMetadata
    var transitions: [AnnotationStateTransition]
    var initialTool: EditorToolState
    
    init(metadata: NotebookMetadata = NotebookMetadata(),
         transitions: [AnnotationStateTransition] = [],
         initialTool: EditorToolState = .idle) {
        self.metadata = metadata
        self.transitions = transitions
        self.initialTool = initialTool
    }
    
    // MARK: - BlazeBinaryCodable
    
    /// Encode file data to binary format.
    /// Field order is preserved: metadata, transitions array, initialTool.
    /// AnnotationStateTransition and EditorToolState must conform to BlazeBinaryCodable.
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        // Encode metadata
        try encoder.encode(metadata)
        
        // Encode transitions array
        try encoder.encode(transitions)
        
        // Encode initial tool state
        try encoder.encode(initialTool)
    }
    
    /// Decode file data from binary format.
    /// Field order must match encoding: metadata, transitions array, initialTool.
    init(from decoder: BlazeBinaryDecoder) throws {
        // Decode metadata
        self.metadata = try decoder.decode(NotebookMetadata.self)
        
        // Decode transitions array
        self.transitions = try decoder.decodeArray(AnnotationStateTransition.self)
        
        // Decode initial tool state
        self.initialTool = try decoder.decode(EditorToolState.self)
    }
}

