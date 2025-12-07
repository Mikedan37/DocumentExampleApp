//
//  NotebookEditorViewModel.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import SwiftUI
import Combine
import BlazeFSM

/// View model for the notebook editor.
/// Manages annotation FSM instances and tool FSM state.
@MainActor
class NotebookEditorViewModel: ObservableObject {
    @Published var annotations: [AnnotationState] = []
    
    private var annotationManager: AnnotationFSM?
    private var toolFSM: ToolFSM
    private var transitions: [AnnotationStateTransition] = []
    
    init(initialTool: EditorToolState = .idle) {
        self.toolFSM = ToolFSM(initialTool: initialTool)
    }
    
    /// Load notebook data and replay transitions.
    /// - Parameter fileData: The notebook file data to load
    func load(fileData: NotebookFileData) {
        // Initialize tool FSM from saved state
        self.toolFSM = ToolFSM(initialTool: fileData.initialTool)
        
        // Store transitions for later save
        self.transitions = fileData.transitions
        
        // Replay transitions to rebuild annotation state
        Task {
            await replayTransitions()
        }
    }
    
    /// Replay all stored transitions to rebuild annotation state.
    private func replayTransitions() async {
        // Create annotation manager if needed
        if annotationManager == nil {
            annotationManager = AnnotationFSM()
        }
        
        // Replay each transition by processing the event
        for transition in transitions {
            do {
                try await annotationManager?.processEvent(transition.event)
            } catch {
                // Log error but continue replaying
                print("Warning: Failed to replay transition: \(error)")
            }
        }
        
        // Update published annotations
        updateAnnotations()
    }
    
    /// Apply a new transition and accumulate it for saving.
    /// - Parameter transition: The transition to apply
    func applyTransition(_ transition: AnnotationStateTransition) async {
        do {
            try await annotationManager?.processEvent(transition.event)
            transitions.append(transition)
            updateAnnotations()
        } catch {
            print("Error applying transition: \(error)")
        }
    }
    
    /// Update the published annotations array from the annotation manager.
    /// NOTE: AnnotationFSM tracks a single annotation at a time.
    /// For multiple annotations, you would need multiple AnnotationFSM instances.
    private func updateAnnotations() {
        // AnnotationFSM tracks one annotation at a time
        // If you need multiple annotations, maintain a dictionary of AnnotationFSM instances
        if let manager = annotationManager, manager.currentState != .idle {
            // For now, we'll just track the current state
            // In a full implementation, you'd maintain a collection of annotation FSMs
            annotations = [manager.currentState]
        } else {
            annotations = []
        }
    }
    
    /// Get all accumulated transitions for saving.
    /// - Returns: Array of all transitions
    func getTransitions() -> [AnnotationStateTransition] {
        return transitions
    }
    
    /// Get current tool state for saving.
    /// - Returns: Current editor tool state
    func getCurrentToolState() -> EditorToolState {
        return toolFSM.currentTool
    }
    
    /// Update tool state.
    /// - Parameter state: New tool state
    func setToolState(_ state: EditorToolState) async throws {
        // ToolFSM uses processToolEvent, but we need to check the API
        // For now, this is a placeholder
        // You'll need to call toolFSM.processToolEvent(.selectTool(state))
    }
}

