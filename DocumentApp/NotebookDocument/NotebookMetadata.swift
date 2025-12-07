//
//  NotebookMetadata.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import Foundation
import BlazeBinary

/// Metadata for a notebook document.
/// Conforms to BlazeBinaryCodable for deterministic binary serialization.
struct NotebookMetadata: BlazeBinaryCodable {
    var title: String
    var createdAt: UInt64  // Epoch seconds
    var updatedAt: UInt64   // Epoch seconds
    
    init(title: String = "", createdAt: UInt64 = 0, updatedAt: UInt64 = 0) {
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - BlazeBinaryCodable
    
    /// Encode metadata to binary format.
    /// Field order is preserved: title, createdAt, updatedAt.
    func blazeEncode(to encoder: BlazeBinaryEncoder) throws {
        encoder.encode(title)
        encoder.encode(createdAt)
        encoder.encode(updatedAt)
    }
    
    /// Decode metadata from binary format.
    /// Field order must match encoding: title, createdAt, updatedAt.
    init(from decoder: BlazeBinaryDecoder) throws {
        self.title = try decoder.decodeString()
        self.createdAt = try decoder.decodeUInt64()
        self.updatedAt = try decoder.decodeUInt64()
    }
}

