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
    @Published var currentTool: EditorToolState = .idle
    @Published var activeAnnotationID: UUID?
    @Published var eraserSize: CGFloat = 30.0 // Eraser radius in points
    
    private var toolFSM: ToolFSM
    private var transitions: [AnnotationStateTransition] = []
    
    // Track annotation data and FSMs separately - one FSM per annotation
    private var annotationData: [UUID: AnnotationData] = [:]
    private var annotationFSMs: [UUID: AnnotationFSM] = [:]
    
    init(initialTool: EditorToolState = .idle) {
        self.toolFSM = ToolFSM(initialTool: initialTool)
        self.currentTool = initialTool
        
        // Set up tool change callback
        toolFSM.onToolChange = { [weak self] newTool in
            Task { @MainActor in
                self?.currentTool = newTool
            }
        }
    }
    
    /// Load notebook data and replay transitions.
    /// - Parameter fileData: The notebook file data to load
    func load(fileData: NotebookFileData) {
        // Initialize tool FSM from saved state
        self.toolFSM = ToolFSM(initialTool: fileData.initialTool)
        self.currentTool = fileData.initialTool
        
        // Set up tool change callback
        toolFSM.onToolChange = { [weak self] newTool in
            Task { @MainActor in
                self?.currentTool = newTool
            }
        }
        
        // Store transitions for later save
        self.transitions = fileData.transitions
        
        // Replay transitions to rebuild annotation state
        Task {
            await replayTransitions()
        }
    }
    
    /// Replay all stored transitions to rebuild annotation state.
    private func replayTransitions() async {
        // Group transitions by annotation ID
        var transitionsByID: [UUID: [AnnotationStateTransition]] = [:]
        for transition in transitions {
            let id = transition.annotationID
            if transitionsByID[id] == nil {
                transitionsByID[id] = []
            }
            transitionsByID[id]?.append(transition)
        }
        
        // Replay transitions for each annotation
        for (id, annotationTransitions) in transitionsByID {
            let fsm = AnnotationFSM()
            // No need for transition callback during replay - transitions already exist
            
            for transition in annotationTransitions {
                do {
                    try await fsm.processEvent(transition.event)
                } catch {
                    print("Warning: Failed to replay transition for \(id): \(error)")
                }
            }
            
            annotationFSMs[id] = fsm
        }
        
        // Update published annotations
        updateAnnotations()
    }
    
    /// Apply a new transition and accumulate it for saving.
    /// - Parameter transition: The transition to apply
    func applyTransition(_ transition: AnnotationStateTransition) async {
        let id = transition.annotationID
        guard let fsm = annotationFSMs[id] else {
            print("Error: No FSM found for annotation \(id)")
            return
        }
        
        do {
            try await fsm.processEvent(transition.event)
            transitions.append(transition)
            updateAnnotations()
        } catch {
            print("Error applying transition: \(error)")
        }
    }
    
    /// Update the published annotations array from all annotation FSMs.
    /// This triggers SwiftUI to re-render annotations.
    private func updateAnnotations() {
        // Collect states from all annotation FSMs
        annotations = annotationFSMs.compactMap { (id, fsm) in
            fsm.currentState != .idle ? fsm.currentState : nil
        }
        // Force SwiftUI update by accessing getAllAnnotationData
        // The view observes this via ForEach
        objectWillChange.send()
    }
    
    /// Get all annotation data for display.
    func getAllAnnotationData() -> [AnnotationData] {
        return Array(annotationData.values)
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
        try await toolFSM.processToolEvent(.selectTool(state))
    }
    
    /// Create a text annotation at the specified location.
    /// - Parameters:
    ///   - location: The location where the text annotation should be created
    ///   - initialText: Optional initial text content
    /// - Returns: The annotation ID if successful, nil otherwise
    func createTextAnnotation(at location: CGPoint, initialText: String = "") async -> UUID? {
        guard toolFSM.currentTool == .text else { return nil }
        
        let annotationID = UUID()
        let payload = AnnotationCreatePayload(
            type: "text",
            bounds: CGRect(origin: location, size: CGSize(width: 200, height: 30)),
            initialContent: initialText.isEmpty ? nil : initialText,
            properties: ["tool": "text"]
        )
        
        // Store annotation data
        annotationData[annotationID] = AnnotationData(
            id: annotationID,
            type: .text,
            bounds: payload.bounds,
            content: payload.initialContent
        )
        
        // Create a new FSM for this annotation
        let fsm = AnnotationFSM()
        fsm.onTransition = { [weak self] transition in
            Task { @MainActor in
                self?.transitions.append(transition)
                self?.updateAnnotations()
            }
        }
        
        // Set the annotation ID in the FSM context before processing
        // Note: The FSM will extract the ID from the createAnnotation event
        let event = AnnotationEvent.createAnnotation(payload: payload)
        
        do {
            try await fsm.processEvent(event)
            annotationFSMs[annotationID] = fsm
            updateAnnotations()
            return annotationID
        } catch {
            print("Error creating text annotation: \(error)")
            return nil
        }
    }
    
    /// Update text annotation content
    func updateTextAnnotation(id: UUID, text: String) async {
        guard var data = annotationData[id], data.type == .text else { return }
        
        data.content = text
        annotationData[id] = data
        
        // Update bounds if text is longer
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 14)],
            context: nil
        ).size
        
        data.bounds = CGRect(
            origin: data.bounds.origin,
            size: CGSize(width: max(200, textSize.width + 16), height: max(30, textSize.height + 16))
        )
        annotationData[id] = data
        
        // Update annotations display
        updateAnnotations()
    }
    
    /// Get annotation data for a given ID.
    func getAnnotationData(for id: UUID) -> AnnotationData? {
        return annotationData[id]
    }
    
    /// Get annotation state for a given ID.
    func getAnnotationState(id: UUID) -> AnnotationState {
        return annotationFSMs[id]?.currentState ?? .idle
    }
    
    /// Select an annotation by ID (used for move tool).
    /// Deselects any previously selected annotation.
    func selectAnnotation(id: UUID) async {
        // Deselect any previously selected annotation
        for (existingID, fsm) in annotationFSMs {
            if existingID != id && fsm.currentState == .selected {
                let deselectEvent = AnnotationEvent.deselect(annotationID: existingID)
                do {
                    try await fsm.processEvent(deselectEvent)
                } catch {
                    print("Error deselecting annotation \(existingID): \(error)")
                }
            }
        }
        
        guard let fsm = annotationFSMs[id] else { return }
        
        let event = AnnotationEvent.select(annotationID: id)
        
        do {
            try await fsm.processEvent(event)
            updateAnnotations()
        } catch {
            print("Error selecting annotation: \(error)")
        }
    }
    
    /// Deselect an annotation by ID.
    func deselectAnnotation(id: UUID) async {
        guard let fsm = annotationFSMs[id] else { return }
        
        // Only deselect if currently selected
        guard fsm.currentState == .selected else { return }
        
        let event = AnnotationEvent.deselect(annotationID: id)
        
        do {
            try await fsm.processEvent(event)
            updateAnnotations()
        } catch {
            print("Error deselecting annotation: \(error)")
        }
    }
    
    /// Deselect all annotations.
    func deselectAll() async {
        for (id, fsm) in annotationFSMs {
            if fsm.currentState == .selected {
                let event = AnnotationEvent.deselect(annotationID: id)
                do {
                    try await fsm.processEvent(event)
                } catch {
                    print("Error deselecting annotation \(id): \(error)")
                }
            }
        }
        updateAnnotations()
    }
    
    /// Begin a new stroke annotation.
    /// Returns the annotation ID if successful, nil if already creating.
    func beginStroke(tool: EditorToolState, at location: CGPoint) async -> UUID? {
        // Guard against duplicate create calls
        if activeAnnotationID != nil {
            // Already creating → return nil
            return nil
        }
        
        let annotationType: AnnotationType
        switch tool {
        case .pen:
            annotationType = .pen
        case .pencil:
            annotationType = .pencil
        case .highlighter:
            annotationType = .highlighter
        case .arrow:
            annotationType = .arrow
        case .lasso:
            annotationType = .lasso
        default:
            return nil
        }
        
        let strokeID = UUID()
        let payload = AnnotationCreatePayload(
            type: annotationType.rawValue,
            bounds: CGRect(origin: location, size: .zero),
            properties: ["tool": tool.rawValue]
        )
        
        // Store annotation data
        annotationData[strokeID] = AnnotationData(
            id: strokeID,
            type: annotationType,
            bounds: CGRect(origin: location, size: .zero),
            strokePoints: [location]
        )
        
        // Create a new FSM for this stroke
        let fsm = AnnotationFSM()
        fsm.onTransition = { [weak self] transition in
            Task { @MainActor in
                self?.transitions.append(transition)
                self?.updateAnnotations()
            }
        }
        
        let event = AnnotationEvent.createAnnotation(payload: payload)
        
        do {
            try await fsm.processEvent(event)
            annotationFSMs[strokeID] = fsm
            activeAnnotationID = strokeID
            updateAnnotations()
            return strokeID
        } catch {
            print("Error creating stroke annotation: \(error)")
            return nil
        }
    }
    
    /// Update stroke with a new point (sends updateStroke event to FSM).
    func updateStroke(strokeID: UUID, point: CGPoint) async {
        guard let fsm = annotationFSMs[strokeID] else { return }
        guard fsm.currentState == .creating else { return }
        
        // Update local annotation data
        if var data = annotationData[strokeID] {
            data.strokePoints.append(point)
            data.updateBoundsFromStrokes()
            annotationData[strokeID] = data
        }
        
        // Send updateStroke event to FSM (stays in creating state)
        let event = AnnotationEvent.updateStroke(annotationID: strokeID, point: point)
        
        do {
            try await fsm.processEvent(event)
            updateAnnotations()
        } catch {
            print("Error updating stroke: \(error)")
        }
    }
    
    /// Finish creating a stroke (sends finishCreate event to FSM).
    func finishStroke(strokeID: UUID, at location: CGPoint) async {
        guard let fsm = annotationFSMs[strokeID] else { return }
        guard fsm.currentState == .creating else { return }
        
        // Update local annotation data with final point
        if var data = annotationData[strokeID] {
            if !data.strokePoints.contains(where: { $0 == location }) {
                data.strokePoints.append(location)
            }
            data.updateBoundsFromStrokes()
            annotationData[strokeID] = data
        }
        
        // Send finishCreate event to transition to committed
        let event = AnnotationEvent.finishCreate(annotationID: strokeID)
        
        do {
            try await fsm.processEvent(event)
            activeAnnotationID = nil // Clear active annotation
            updateAnnotations()
        } catch {
            print("Error finishing stroke: \(error)")
            activeAnnotationID = nil
        }
    }
    
    /// Delete an annotation.
    func deleteAnnotation(id: UUID) async {
        print("deleteAnnotation called for \(id)")
        
        // Try to send delete event to FSM first (for proper state transition)
        if let fsm = annotationFSMs[id] {
            let event = AnnotationEvent.delete(annotationID: id)
            do {
                try await fsm.processEvent(event)
            } catch {
                print("Error sending delete event to FSM: \(error) - deleting anyway")
            }
        }
        
        // Remove from data structures (regardless of FSM state)
        annotationData.removeValue(forKey: id)
        annotationFSMs.removeValue(forKey: id)
        
        // Clear active annotation if it was deleted
        if activeAnnotationID == id {
            activeAnnotationID = nil
        }
        
        updateAnnotations()
        print("deleteAnnotation completed for \(id), remaining annotations: \(annotationData.count)")
    }
    
    /// Partially erase stroke points within the eraser radius at the given location.
    /// Checks both individual points and line segments for more accurate erasing.
    func eraseAt(location: CGPoint, radius: CGFloat, previousLocation: CGPoint? = nil) {
        // Check all annotations
        for (id, data) in annotationData {
            // Only erase stroke-based annotations
            guard data.type != .text, !data.strokePoints.isEmpty else { continue }
            
            var pointsToKeep: Set<Int> = []
            var pointsErased = false
            
            // First pass: mark points to keep or remove
            for (index, point) in data.strokePoints.enumerated() {
                var shouldKeep = true
                
                // Check if point is within eraser radius
                let pointDistance = sqrt(
                    pow(location.x - point.x, 2) +
                    pow(location.y - point.y, 2)
                )
                
                if pointDistance <= radius {
                    // Point is within eraser - remove it
                    shouldKeep = false
                    pointsErased = true
                } else {
                    // Check if any segment containing this point is within eraser radius
                    // Check segment from previous point to this point
                    if index > 0 {
                        let prevPoint = data.strokePoints[index - 1]
                        let segmentDistance = distanceToLineSegment(point: location, lineStart: prevPoint, lineEnd: point)
                        if segmentDistance <= radius {
                            shouldKeep = false
                            pointsErased = true
                        }
                    }
                    
                    // Check segment from this point to next point
                    if shouldKeep && index < data.strokePoints.count - 1 {
                        let nextPoint = data.strokePoints[index + 1]
                        let segmentDistance = distanceToLineSegment(point: location, lineStart: point, lineEnd: nextPoint)
                        if segmentDistance <= radius {
                            shouldKeep = false
                            pointsErased = true
                        }
                    }
                }
                
                if shouldKeep {
                    pointsToKeep.insert(index)
                }
            }
            
            // If we erased points, update the annotation
            if pointsErased {
                // Build new points array from kept points
                let newPoints = data.strokePoints.enumerated()
                    .filter { pointsToKeep.contains($0.offset) }
                    .map { $0.element }
                
                if newPoints.isEmpty {
                    // All points erased - delete the annotation
                    Task {
                        await deleteAnnotation(id: id)
                    }
                } else if newPoints.count < data.strokePoints.count {
                    // Update annotation with remaining points
                    if var updatedData = annotationData[id] {
                        updatedData.strokePoints = newPoints
                        updatedData.updateBoundsFromStrokes()
                        annotationData[id] = updatedData
                        // Use Task to update on main thread without blocking
                        Task { @MainActor in
                            updateAnnotations()
                        }
                    }
                }
            }
        }
    }
    
    /// Find an annotation at the given location.
    /// Returns the annotation ID if found, nil otherwise.
    func findAnnotation(at location: CGPoint) -> UUID? {
        let hitTolerance: CGFloat = 50.0 // Pixels - increased for better hit detection
        
        // Check annotations in reverse order (most recent first)
        for (id, data) in annotationData.reversed() {
            // For text annotations, check bounds
            if data.type == .text {
                if data.bounds.contains(location) {
                    return id
                }
            } else {
                // For stroke annotations, check proximity to stroke points and segments
                // Don't require bounds to contain the point - strokes can extend beyond bounds
                if !data.strokePoints.isEmpty {
                    var minPointDistance: CGFloat = .greatestFiniteMagnitude
                    var minSegmentDistance: CGFloat = .greatestFiniteMagnitude
                    
                    // First, check if any stroke point is close
                    for strokePoint in data.strokePoints {
                        let distance = sqrt(
                            pow(location.x - strokePoint.x, 2) +
                            pow(location.y - strokePoint.y, 2)
                        )
                        minPointDistance = min(minPointDistance, distance)
                        if distance <= hitTolerance {
                            print("findAnnotation: Found \(id) via point (distance: \(distance))")
                            return id
                        }
                    }
                    
                    // Then check distance to stroke segments (lines between points)
                    for i in 0..<(data.strokePoints.count - 1) {
                        let p1 = data.strokePoints[i]
                        let p2 = data.strokePoints[i + 1]
                        
                        // Calculate distance from point to line segment
                        let distance = distanceToLineSegment(point: location, lineStart: p1, lineEnd: p2)
                        minSegmentDistance = min(minSegmentDistance, distance)
                        if distance <= hitTolerance {
                            print("findAnnotation: Found \(id) via segment (distance: \(distance))")
                            return id
                        }
                    }
                    
                    // Debug: log closest distances for first annotation
                    if id == annotationData.keys.first {
                        print("findAnnotation: Closest point distance: \(minPointDistance), closest segment distance: \(minSegmentDistance), tolerance: \(hitTolerance)")
                    }
                }
            }
        }
        return nil
    }
    
    /// Calculate distance from a point to a line segment.
    private func distanceToLineSegment(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let A = point.x - lineStart.x
        let B = point.y - lineStart.y
        let C = lineEnd.x - lineStart.x
        let D = lineEnd.y - lineStart.y
        
        let dot = A * C + B * D
        let lenSq = C * C + D * D
        var param: CGFloat = -1
        
        if lenSq != 0 {
            param = dot / lenSq
        }
        
        var xx: CGFloat
        var yy: CGFloat
        
        if param < 0 {
            xx = lineStart.x
            yy = lineStart.y
        } else if param > 1 {
            xx = lineEnd.x
            yy = lineEnd.y
        } else {
            xx = lineStart.x + param * C
            yy = lineStart.y + param * D
        }
        
        let dx = point.x - xx
        let dy = point.y - yy
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Select an annotation at the given location.
    func selectAnnotation(at location: CGPoint) async -> UUID? {
        guard let annotationID = findAnnotation(at: location) else { return nil }
        await selectAnnotation(id: annotationID)
        return annotationID
    }
    
    /// Move an annotation by a delta.
    /// Uses BlazeFSM to properly track state transitions.
    func moveAnnotation(id: UUID, delta: (dx: CGFloat, dy: CGFloat)) async {
        guard let fsm = annotationFSMs[id] else {
            print("Error: No FSM found for annotation \(id)")
            return
        }
        
        // Validate that annotation is in a state that allows moving
        let currentState = fsm.currentState
        guard currentState == .selected || currentState == .moving else {
            print("Warning: Cannot move annotation \(id) from state \(currentState)")
            return
        }
        
        // Update local annotation data immediately for smooth dragging
        if var data = annotationData[id] {
            data.bounds.origin.x += delta.dx
            data.bounds.origin.y += delta.dy
            // Also move stroke points
            data.strokePoints = data.strokePoints.map { point in
                CGPoint(x: point.x + delta.dx, y: point.y + delta.dy)
            }
            annotationData[id] = data
        }
        
        // Send moveDelta event to FSM (validated by FSM)
        let event = AnnotationEvent.moveDelta(annotationID: id, dx: delta.dx, dy: delta.dy)
        
        do {
            try await fsm.processEvent(event)
            updateAnnotations()
        } catch {
            print("Error moving annotation: \(error)")
            // Revert local changes if FSM rejects the move
            if var data = annotationData[id] {
                data.bounds.origin.x -= delta.dx
                data.bounds.origin.y -= delta.dy
                data.strokePoints = data.strokePoints.map { point in
                    CGPoint(x: point.x - delta.dx, y: point.y - delta.dy)
                }
                annotationData[id] = data
            }
        }
    }
    
    /// Begin moving an annotation.
    /// Uses BlazeFSM to transition from selected to moving state.
    func beginMoveAnnotation(id: UUID) async {
        guard let fsm = annotationFSMs[id] else {
            print("Error: No FSM found for annotation \(id)")
            return
        }
        
        // Ensure annotation is selected first
        if fsm.currentState != .selected {
            // Try to select it first
            let selectEvent = AnnotationEvent.select(annotationID: id)
            do {
                try await fsm.processEvent(selectEvent)
            } catch {
                print("Error selecting annotation before move: \(error)")
                return
            }
        }
        
        let event = AnnotationEvent.beginMove(annotationID: id)
        
        do {
            try await fsm.processEvent(event)
            updateAnnotations()
        } catch {
            print("Error beginning move: \(error)")
        }
    }
    
    /// End moving an annotation.
    /// Uses BlazeFSM to transition from moving back to selected state.
    func endMoveAnnotation(id: UUID) async {
        guard let fsm = annotationFSMs[id] else {
            print("Error: No FSM found for annotation \(id)")
            return
        }
        
        // Validate that annotation is in moving state
        guard fsm.currentState == .moving else {
            print("Warning: Cannot end move for annotation \(id) - not in moving state (current: \(fsm.currentState))")
            return
        }
        
        let event = AnnotationEvent.endMove(annotationID: id)
        
        do {
            try await fsm.processEvent(event)
            updateAnnotations()
        } catch {
            print("Error ending move: \(error)")
        }
    }
}

