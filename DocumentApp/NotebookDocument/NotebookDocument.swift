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
            // Empty file or autosave recovery - return default document
            self.fileData = NotebookFileData()
            return
        }
        
        // Handle empty data (corrupted autosave)
        guard !data.isEmpty else {
            print("Warning: Empty file data, creating default document")
            self.fileData = NotebookFileData()
            return
        }
        
        do {
            self.fileData = try BlazeBinaryNotebookCoder.decode(data)
        } catch {
            // Log the error for debugging
            print("Error decoding notebook file: \(error)")
            print("Data size: \(data.count) bytes")
            
            // For autosave recovery or corrupted files, return a default document
            // This prevents the app from crashing on corrupted autosave files
            // Autosave files can be corrupted during app crashes or format changes
            print("Corrupted file detected, using default document")
            self.fileData = NotebookFileData()
            
            // Note: We don't throw here to allow the app to continue
            // The user can still work with a fresh document
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

