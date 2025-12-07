//
//  UTType+NotebookDocument.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Uniform Type Identifier for Blaze notebook documents.
    /// File extension: .blaze-note
    static let notebookDocument = UTType(exportedAs: "com.danylchuk.notebook.bnbk")
}

