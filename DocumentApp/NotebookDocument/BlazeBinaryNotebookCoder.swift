//
//  BlazeBinaryNotebookCoder.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import Foundation
import BlazeBinary

/// Encoder/decoder for NotebookFileData using BlazeBinary format.
/// Ensures deterministic binary layout following TLV conventions.
enum BlazeBinaryNotebookCoder {
    /// Encode NotebookFileData to binary Data.
    /// - Parameter data: The notebook file data to encode
    /// - Returns: Binary data representation
    /// - Throws: BlazeBinaryEncodingError if encoding fails
    static func encode(_ data: NotebookFileData) throws -> Data {
        let encoder = BlazeBinaryEncoder()
        try data.blazeEncode(to: encoder)
        return encoder.encodedData()
    }
    
    /// Decode binary Data to NotebookFileData.
    /// - Parameter data: Binary data to decode
    /// - Returns: Decoded notebook file data
    /// - Throws: BlazeBinaryDecodingError if decoding fails
    static func decode(_ data: Data) throws -> NotebookFileData {
        let decoder = BlazeBinaryDecoder(data: data)
        return try NotebookFileData(from: decoder)
    }
}

