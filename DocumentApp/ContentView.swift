//
//  ContentView.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import SwiftUI

/// Example ContentView demonstrating DocumentGroup integration with NotebookDocument.
/// Note: DocumentGroup should be used in the App's Scene, not in a View.
/// This is a placeholder - move DocumentGroup to DocumentAppApp.swift
struct ContentView: View {
    var body: some View {
        VStack {
            Text("Notebook Document Editor")
                .font(.title)
            Text("Use DocumentGroup in your App's Scene")
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
