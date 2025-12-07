//
//  NotebookEditorView.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import SwiftUI
import BlazeFSM
import PDFKit
import AppKit
import UniformTypeIdentifiers

/// Main editor view for notebook documents.
struct NotebookEditorView: View {
    @Binding var document: NotebookDocument
    @StateObject private var viewModel = NotebookEditorViewModel()
    @State private var editingTextAnnotation: UUID?
    @State private var editingText: String = ""
    
    var body: some View {
        ZStack {
            // Main content area
            VStack(spacing: 0) {
                // Title bar
                HStack(spacing: 16) {
                    TextField("Untitled Notebook", text: Binding(
                        get: { document.fileData.metadata.title.isEmpty ? "Untitled Notebook" : document.fileData.metadata.title },
                        set: { document.fileData.metadata.title = $0 }
                    ))
                    .font(.system(size: 18, weight: .semibold))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    
                    Spacer()
                    
                    // Action buttons - larger, elegant with hover effects
                    HStack(spacing: 16) {
                        // Save button
                        SaveExportButton(
                            icon: "square.and.arrow.down",
                            helpText: "Save document (⌘S)",
                            action: {
                                saveDocument()
                            }
                        )
                        
                        // Export PDF button
                        SaveExportButton(
                            icon: "doc.fill",
                            helpText: "Export annotations as PDF",
                            action: {
                                exportToPDF()
                            }
                        )
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 20)
                }
                .background(Color(NSColor.controlBackgroundColor))
                
                // Canvas area
                ZStack {
                    // Background
                    Color(NSColor.textBackgroundColor)
                        .ignoresSafeArea()
                    
                    // Annotations display - updates live as strokes are drawn
                    let allAnnotations = viewModel.getAllAnnotationData()
                    if allAnnotations.isEmpty && viewModel.activeAnnotationID == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "note.text")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No annotations yet")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("Select a tool from the toolbar and draw or click to create")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    } else {
                        // Display annotations
                        ForEach(allAnnotations, id: \.id) { annotationData in
                            ZStack {
                                if annotationData.type == .text {
                                    let isCurrentlyEditing = editingTextAnnotation == annotationData.id
                                    TextAnnotationView(
                                        id: annotationData.id,
                                        bounds: annotationData.bounds,
                                        content: annotationData.content ?? "",
                                        isEditing: isCurrentlyEditing,
                                        onTextChange: { newText in
                                            Task {
                                                await viewModel.updateTextAnnotation(id: annotationData.id, text: newText)
                                            }
                                        },
                                        onEditingEnd: {
                                            editingTextAnnotation = nil
                                        }
                                    )
                                } else {
                                    // Draw stroke annotations
                                    StrokeAnnotationView(annotationData: annotationData)
                                }
                                
                                // Selection highlight
                                if selectedAnnotationID == annotationData.id {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.accentColor, lineWidth: 2)
                                        .frame(width: annotationData.bounds.width + 4, height: annotationData.bounds.height + 4)
                                        .position(x: annotationData.bounds.midX, y: annotationData.bounds.midY)
                                }
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let tool = viewModel.getCurrentToolState()
                            // Don't handle drag for text tool - it uses tap only
                            if tool == .text {
                                return
                            }
                            // Track initial location for eraser tap detection
                            if tool == .eraser && lastDragLocation == nil {
                                lastDragLocation = value.location
                            }
                            handleCanvasDrag(at: value.location, isEnd: false)
                        }
                        .onEnded { value in
                            let tool = viewModel.getCurrentToolState()
                            // For text tool, treat a very short drag as a tap
                            if tool == .text {
                                let dragDistance = sqrt(
                                    pow(value.translation.width, 2) + pow(value.translation.height, 2)
                                )
                                if dragDistance < 5 {
                                    // It's essentially a tap
                                    handleCanvasTap(at: value.location)
                                }
                                return
                            }
                            handleCanvasDrag(at: value.location, isEnd: true)
                        }
                )
                .onTapGesture { location in
                    print("Canvas tap detected at \(location)")
                    let tool = viewModel.getCurrentToolState()
                    // Only handle tap for text tool if drag gesture didn't handle it
                    if tool == .text {
                        handleCanvasTap(at: location)
                    }
                }
                .onChange(of: viewModel.activeAnnotationID) { _, _ in
                    // Trigger re-render when active annotation changes
                }
            }
            
            // Floating toolbar
            ToolbarView(viewModel: viewModel)
        }
        .onAppear {
            // Load document data into view model
            viewModel.load(fileData: document.fileData)
        }
        .onChange(of: viewModel.getTransitions().count) { _, _ in
            // Update document when transitions change
            document.fileData.transitions = viewModel.getTransitions()
            document.fileData.initialTool = viewModel.getCurrentToolState()
        }
        .onChange(of: viewModel.currentTool) { _, newTool in
            // Clear selection when switching away from selection tool
            if newTool != .selection {
                if let selectedID = selectedAnnotationID {
                    Task {
                        await viewModel.deselectAnnotation(id: selectedID)
                    }
                }
                selectedAnnotationID = nil
                isMoving = false
                lastDragLocation = nil
            }
        }
        .onChange(of: document.fileData.metadata.title) { _, _ in
            // Mark document as needing save when title changes
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NSMenuDidSendActionNotification"))) { _ in
            // Handle keyboard shortcuts
        }
    }
    
    
    /// Save the document
    private func saveDocument() {
        // Update document with current state
        document.fileData.transitions = viewModel.getTransitions()
        document.fileData.initialTool = viewModel.getCurrentToolState()
        
        // Trigger save via document system
        #if os(macOS)
        NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
        #endif
    }
    
    /// Export annotations to PDF
    private func exportToPDF() {
        let allAnnotations = viewModel.getAllAnnotationData()
        guard !allAnnotations.isEmpty else {
            // Show alert if no annotations
            let alert = NSAlert()
            alert.messageText = "No Annotations"
            alert.informativeText = "There are no annotations to export."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // Create save panel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = document.fileData.metadata.title.isEmpty ? "Untitled Notebook" : document.fileData.metadata.title
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                Task {
                    await exportAnnotationsToPDF(annotations: allAnnotations, outputURL: url)
                }
            }
        }
    }
    
    /// Export annotations to PDF file
    @MainActor
    private func exportAnnotationsToPDF(annotations: [AnnotationData], outputURL: URL) async {
        // Calculate bounds of all annotations
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude
        
        for annotation in annotations {
            if annotation.type == .text {
                minX = min(minX, annotation.bounds.minX)
                minY = min(minY, annotation.bounds.minY)
                maxX = max(maxX, annotation.bounds.maxX)
                maxY = max(maxY, annotation.bounds.maxY)
            } else {
                for point in annotation.strokePoints {
                    minX = min(minX, point.x)
                    minY = min(minY, point.y)
                    maxX = max(maxX, point.x)
                    maxY = max(maxY, point.y)
                }
            }
        }
        
        // Add padding
        let padding: CGFloat = 40
        let width = max(800, maxX - minX + padding * 2)
        let height = max(600, maxY - minY + padding * 2)
        let offsetX = minX - padding
        let offsetY = minY - padding
        
        // Create PDF context
        let pdfData = NSMutableData()
        let pdfConsumer = CGDataConsumer(data: pdfData)!
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: &mediaBox, nil)!
        
        pdfContext.beginPDFPage(nil)
        pdfContext.translateBy(x: -offsetX, y: -offsetY)
        
        // Draw annotations
        for annotation in annotations {
            if annotation.type == .text {
                // Draw text annotation
                if let content = annotation.content, !content.isEmpty {
                    let textRect = annotation.bounds
                    let nsString = NSString(string: content)
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 14),
                        .foregroundColor: NSColor.black
                    ]
                    nsString.draw(in: textRect, withAttributes: attributes)
                }
            } else {
                // Draw stroke annotation
                if !annotation.strokePoints.isEmpty {
                    let path = CGMutablePath()
                    path.move(to: annotation.strokePoints[0])
                    for point in annotation.strokePoints.dropFirst() {
                        path.addLine(to: point)
                    }
                    
                    pdfContext.addPath(path)
                    pdfContext.setStrokeColor(strokeColorForPDF(for: annotation.type))
                    pdfContext.setLineWidth(strokeWidthForPDF(for: annotation.type))
                    pdfContext.setLineCap(.round)
                    pdfContext.setLineJoin(.round)
                    pdfContext.strokePath()
                }
            }
        }
        
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        // Write to file
        do {
            try pdfData.write(to: outputURL, options: .atomic)
            
            // Show success alert
            let alert = NSAlert()
            alert.messageText = "Export Successful"
            alert.informativeText = "Annotations exported to PDF successfully."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = "Failed to export PDF: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func strokeColorForPDF(for type: AnnotationType) -> CGColor {
        switch type {
        case .pen: return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        case .pencil: return CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        case .highlighter: return CGColor(red: 1, green: 1, blue: 0, alpha: 0.4)
        case .arrow: return CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        case .lasso: return CGColor(red: 0.5, green: 0, blue: 0.5, alpha: 0.5)
        default: return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        }
    }
    
    private func strokeWidthForPDF(for type: AnnotationType) -> CGFloat {
        switch type {
        case .pen: return 2
        case .pencil: return 1
        case .highlighter: return 10
        case .arrow: return 2
        case .lasso: return 1
        default: return 1
        }
    }
    
    @State private var currentStrokeID: UUID?
    @State private var currentStrokePoints: [CGPoint] = []
    @State private var selectedAnnotationID: UUID?
    @State private var isMoving: Bool = false
    @State private var lastDragLocation: CGPoint?
    
    /// Handle tap on canvas to create annotations based on current tool.
    private func handleCanvasTap(at location: CGPoint) {
        let tool = viewModel.getCurrentToolState()
        print("handleCanvasTap: tool=\(tool), location=\(location)")
        
        switch tool {
        case .text:
            // Create text annotation and immediately start editing
            Task {
                let annotationID = await viewModel.createTextAnnotation(at: location, initialText: "")
                if let id = annotationID {
                    editingTextAnnotation = id
                }
            }
        case .eraser:
            // Find annotation at location and delete it
            print("Eraser tool active, searching for annotation at \(location)")
            Task {
                let allAnnotations = viewModel.getAllAnnotationData()
                print("Eraser: Searching among \(allAnnotations.count) annotations")
                
                if let annotationID = viewModel.findAnnotation(at: location) {
                    print("Eraser: Found annotation \(annotationID) at \(location)")
                    await viewModel.deleteAnnotation(id: annotationID)
                    if selectedAnnotationID == annotationID {
                        selectedAnnotationID = nil
                    }
                } else {
                    print("Eraser: No annotation found at \(location)")
                    // Debug: print all annotations with their locations
                    for annotation in allAnnotations {
                        let pointsInfo = annotation.strokePoints.isEmpty ? "no points" : "\(annotation.strokePoints.count) points"
                        print("  - \(annotation.id): type=\(annotation.type), bounds=\(annotation.bounds), \(pointsInfo)")
                        if !annotation.strokePoints.isEmpty {
                            let firstPoint = annotation.strokePoints[0]
                            let lastPoint = annotation.strokePoints.last!
                            print("    First point: \(firstPoint), Last point: \(lastPoint)")
                        }
                    }
                }
            }
        case .selection:
            // Select annotation at location
            Task {
                if let annotationID = await viewModel.selectAnnotation(at: location) {
                    // Deselect previous selection if different
                    if selectedAnnotationID != annotationID {
                        if let oldID = selectedAnnotationID {
                            await viewModel.deselectAnnotation(id: oldID)
                        }
                    }
                    selectedAnnotationID = annotationID
                } else {
                    // Tap on empty space - deselect all
                    if let oldID = selectedAnnotationID {
                        await viewModel.deselectAnnotation(id: oldID)
                    }
                    selectedAnnotationID = nil
                }
            }
        default:
            // Other tools handle gestures via drag
            break
        }
    }
    
    /// Handle drag gesture for drawing strokes (pen, pencil, arrow, etc.)
    /// Flow: touchBegan → createAnnotation, touchMoved → updateStroke, touchEnded → finishCreate
    private func handleCanvasDrag(at location: CGPoint, isEnd: Bool) {
        let tool = viewModel.getCurrentToolState()
        
        // Handle eraser tool - partial erase as you drag
        if tool == .eraser {
            // Erase points within eraser radius at current location
            // Pass previous location for continuous erasing along the path
            viewModel.eraseAt(location: location, radius: viewModel.eraserSize, previousLocation: lastDragLocation)
            
            if isEnd {
                lastDragLocation = nil
            } else {
                // Track location for continuous erasing
                lastDragLocation = location
            }
            return
        }
        
        // Handle selection tool - move selected annotation
        if tool == .selection {
            if !isEnd {
                if let selectedID = selectedAnnotationID {
                    if !isMoving {
                        // Begin move - ensure annotation is selected first
                        if viewModel.getAnnotationState(id: selectedID) != .selected {
                            Task {
                                await viewModel.selectAnnotation(id: selectedID)
                            }
                        }
                        isMoving = true
                        lastDragLocation = location
                        Task {
                            await viewModel.beginMoveAnnotation(id: selectedID)
                        }
                    } else if let lastLocation = lastDragLocation {
                        // Continue move - calculate delta and move
                        let dx = location.x - lastLocation.x
                        let dy = location.y - lastLocation.y
                        if abs(dx) > 0.1 || abs(dy) > 0.1 { // Only move if there's significant movement
                            Task {
                                await viewModel.moveAnnotation(id: selectedID, delta: (dx: dx, dy: dy))
                            }
                        }
                        lastDragLocation = location
                    }
                } else {
                    // No selection - try to select on drag start
                    if lastDragLocation == nil {
                        Task {
                            if let annotationID = viewModel.findAnnotation(at: location) {
                                // Deselect previous selection if different
                                if selectedAnnotationID != annotationID, let oldID = selectedAnnotationID {
                                    await viewModel.deselectAnnotation(id: oldID)
                                }
                                await viewModel.selectAnnotation(id: annotationID)
                                selectedAnnotationID = annotationID
                                isMoving = true
                                lastDragLocation = location
                                await viewModel.beginMoveAnnotation(id: annotationID)
                            }
                        }
                    }
                }
            } else {
                // End move - transition back to selected state
                if let selectedID = selectedAnnotationID, isMoving {
                    Task {
                        await viewModel.endMoveAnnotation(id: selectedID)
                        // Ensure annotation is still selected after move ends
                        await viewModel.selectAnnotation(id: selectedID)
                    }
                }
                isMoving = false
                lastDragLocation = nil
            }
        }
        // Handle drawing tools
        else if tool == .pen || tool == .pencil || tool == .highlighter || tool == .arrow || tool == .lasso {
            if currentStrokeID == nil && !isEnd {
                // touchBegan → createAnnotation
                Task {
                    if let strokeID = await viewModel.beginStroke(tool: tool, at: location) {
                        currentStrokeID = strokeID
                        currentStrokePoints = [location]
                    }
                }
            } else if let strokeID = currentStrokeID {
                if isEnd {
                    // touchEnded → finishCreate
                    Task {
                        await viewModel.finishStroke(strokeID: strokeID, at: location)
                    }
                    currentStrokeID = nil
                    currentStrokePoints = []
                } else {
                    // touchMoved → updateStroke
                    currentStrokePoints.append(location)
                    Task {
                        await viewModel.updateStroke(strokeID: strokeID, point: location)
                    }
                }
            }
        }
    }
}

/// View for displaying an annotation.
/// Note: AnnotationState is a simple enum, so we'll need to track annotation data separately.
struct AnnotationView: View {
    let annotation: AnnotationState
    
    var body: some View {
        // For now, display a simple representation
        // In a full implementation, you'd maintain a dictionary mapping annotation IDs to their data
        Group {
            if annotation != .idle && annotation != .deleted {
                Text("Annotation: \(annotation.rawValue)")
                    .padding(8)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(6)
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
        }
    }
}

/// View for displaying text annotations.
struct TextAnnotationView: View {
    let id: UUID
    let bounds: CGRect
    let content: String
    let isEditing: Bool
    let onTextChange: (String) -> Void
    let onEditingEnd: () -> Void
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                TextField("Type your note...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(8)
                    .frame(width: max(200, bounds.width), height: max(30, bounds.height))
                    .background(Color.clear)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .focused($isFocused)
                    .onAppear {
                        text = content
                        isFocused = true
                    }
                    .onChange(of: text) { _, newValue in
                        onTextChange(newValue)
                    }
                    .onSubmit {
                        onEditingEnd()
                    }
            } else {
                Text(content.isEmpty ? "Text annotation" : content)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(8)
                    .frame(width: max(200, bounds.width), height: max(30, bounds.height), alignment: .topLeading)
                    .background(Color.clear)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
        }
        .position(x: bounds.midX, y: bounds.midY)
        .onChange(of: isEditing) { _, newValue in
            if !newValue {
                isFocused = false
            }
        }
    }
}

/// View for displaying stroke annotations (pen, pencil, highlighter, arrow, lasso).
struct StrokeAnnotationView: View {
    let annotationData: AnnotationData
    
    var body: some View {
        if !annotationData.strokePoints.isEmpty {
            if annotationData.type == .arrow && annotationData.strokePoints.count >= 2 {
                // Draw arrow with arrowhead
                ArrowPathView(points: annotationData.strokePoints)
                    .stroke(strokeColor(for: annotationData.type), lineWidth: strokeWidth(for: annotationData.type))
            } else {
                // Draw regular stroke or lasso
                Path { path in
                    path.move(to: annotationData.strokePoints[0])
                    for point in annotationData.strokePoints.dropFirst() {
                        path.addLine(to: point)
                    }
                    if annotationData.type == .lasso && annotationData.strokePoints.count > 2 {
                        // Close lasso path
                        path.closeSubpath()
                    }
                }
                .stroke(
                    strokeColor(for: annotationData.type),
                    style: StrokeStyle(
                        lineWidth: strokeWidth(for: annotationData.type),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }
    
    private func strokeColor(for type: AnnotationType) -> Color {
        switch type {
        case .pen:
            return .black
        case .pencil:
            return .gray
        case .highlighter:
            return .yellow.opacity(0.4)
        case .arrow:
            return .blue
        case .lasso:
            return .purple.opacity(0.5)
        default:
            return .black
        }
    }
    
    private func strokeWidth(for type: AnnotationType) -> CGFloat {
        switch type {
        case .pen:
            return 2.0
        case .pencil:
            return 1.5
        case .highlighter:
            return 8.0
        case .arrow:
            return 2.0
        case .lasso:
            return 1.5
        default:
            return 2.0
        }
    }
}

/// View for drawing arrows with arrowheads.
struct ArrowPathView: Shape {
    let points: [CGPoint]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        
        let start = points[0]
        let end = points[points.count - 1]
        
        // Draw line
        path.move(to: start)
        path.addLine(to: end)
        
        // Draw arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 10
        let arrowAngle: CGFloat = .pi / 6
        
        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        
        path.move(to: end)
        path.addLine(to: arrowPoint1)
        path.move(to: end)
        path.addLine(to: arrowPoint2)
        
        return path
    }
}

/// Reusable button component for Save and Export actions with hover effects
struct SaveExportButton: View {
    let icon: String
    let helpText: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundColor(isHovered ? .white : .primary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovered ? Color.accentColor : Color.clear)
                )
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }
}


