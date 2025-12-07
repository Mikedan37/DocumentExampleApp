//
//  NotebookDocument.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import SwiftUI
import UniformTypeIdentifiers
import BlazeBinary
import BlazeFSM

/// SwiftUI FileDocument implementation for Blaze notebook files.
/// Handles loading and saving notebook documents using BlazeBinary format.
struct NotebookDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.notebookDocument] }
    static var writableContentTypes: [UTType] { [.notebookDocument] }
    
    var fileData: NotebookFileData
    
    init(fileData: NotebookFileData = NotebookFileData()) {
        self.fileData = fileData
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        do {
            self.fileData = try BlazeBinaryNotebookCoder.decode(data)
        } catch {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSUnderlyingErrorKey: error
            ])
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Update metadata timestamps
        let now = UInt64(Date().timeIntervalSince1970)
        var updatedFileData = fileData
        if updatedFileData.metadata.createdAt == 0 {
            updatedFileData.metadata.createdAt = now
        }
        updatedFileData.metadata.updatedAt = now
        
        do {
            let data = try BlazeBinaryNotebookCoder.encode(updatedFileData)
            return FileWrapper(regularFileWithContents: data)
        } catch {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSUnderlyingErrorKey: error
            ])
        }
    }
}

