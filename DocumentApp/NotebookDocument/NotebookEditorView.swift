//
//  NotebookEditorView.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import SwiftUI
import BlazeFSM

/// Main editor view for notebook documents.
struct NotebookEditorView: View {
    @Binding var document: NotebookDocument
    @StateObject private var viewModel = NotebookEditorViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            // Title display
            TextField("Notebook Title", text: Binding(
                get: { document.fileData.metadata.title },
                set: { document.fileData.metadata.title = $0 }
            ))
            .font(.title2)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            
            Divider()
            
            // Annotations list
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.annotations.indices, id: \.self) { index in
                        Text("Annotation \(index + 1)")
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    if viewModel.annotations.isEmpty {
                        Text("No annotations yet")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding()
            }
            
            // Tool state display
            HStack {
                Text("Tool State:")
                Spacer()
                Text("Active")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .onAppear {
            // Load document data into view model
            viewModel.load(fileData: document.fileData)
        }
        .onChange(of: viewModel.getTransitions()) { _ in
            // Update document when transitions change
            document.fileData.transitions = viewModel.getTransitions()
            document.fileData.initialTool = viewModel.getCurrentToolState()
        }
    }
}

