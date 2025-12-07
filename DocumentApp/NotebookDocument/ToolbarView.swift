//
//  ToolbarView.swift
//  DocumentApp
//
//  Created by Michael Danylchuk on 12/6/25.
//

import SwiftUI
import BlazeFSM

/// Floating toolbar component displaying all available editor tools.
/// Supports dragging and edge snapping.
struct ToolbarView: View {
    @ObservedObject var viewModel: NotebookEditorViewModel
    @State private var toolbarPosition: CGPoint = .zero
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    @State private var edge: ToolbarEdge = .right
    
    private let tools: [(EditorToolState, String, String)] = [
        (.idle, "circle", "Idle"),
        (.selection, "arrow.up.and.down.and.arrow.left.and.right", "Select"),
        (.pen, "pencil.tip", "Pen"),
        (.pencil, "pencil", "Pencil"),
        (.highlighter, "highlighter", "Highlight"),
        (.text, "text.bubble", "Text"),
        (.arrow, "arrow.up.right", "Arrow"),
        (.eraser, "eraser", "Eraser"),
        (.lasso, "lasso", "Lasso")
    ]
    
    enum ToolbarEdge {
        case top, bottom, left, right
    }
    
    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            let toolbarSize = calculateToolbarSize(geometry, safeArea: safeArea)
            let basePosition = positionForEdge(edge, in: geometry.size, safeArea: safeArea, toolbarSize: toolbarSize)
            
            Group {
                if edge == .top || edge == .bottom {
                    // Horizontal toolbar - center the tools
                    HStack {
                        Spacer()
                        toolsStack
                            .padding(4)
                        Spacer()
                    }
                    .frame(width: toolbarSize.width, height: toolbarSize.height)
                } else {
                    // Vertical toolbar - center the tools vertically
                    ZStack {
                        // Center the tools vertically
                        VStack {
                            Spacer()
                            toolsStack
                                .padding(4)
                            Spacer()
                        }
                    }
                    .frame(width: toolbarSize.width, height: toolbarSize.height)
                }
            }
            .background(toolbarBackground)
            .clipped()
            .scaleEffect(isDragging ? 0.95 : 1.0)
            .opacity(isDragging ? 0.9 : 1.0)
            .position(
                x: constrainedX(basePosition.x, toolbarSize: toolbarSize, geometry: geometry, edge: edge) + (isDragging ? dragOffset.width : 0),
                y: constrainedY(basePosition.y, toolbarSize: toolbarSize, geometry: geometry, edge: edge) + (isDragging ? dragOffset.height : 0)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .onAppear {
                initializePosition(geometry: geometry)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            // Smooth start animation
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                // Visual feedback when starting to drag
                            }
                        }
                        // Smooth drag tracking with slight easing
                        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        // Snap to nearest edge based on final position
                        let finalX = basePosition.x + value.translation.width
                        let finalY = basePosition.y + value.translation.height
                        
                        // Determine which edge is closest
                        let edgePadding: CGFloat = 16
                        let distToTop = abs(finalY - safeArea.top)
                        let distToBottom = abs(finalY - (geometry.size.height - safeArea.bottom))
                        let distToLeft = abs(finalX - (safeArea.leading + edgePadding))
                        let distToRight = abs(finalX - (geometry.size.width - safeArea.trailing - edgePadding))
                        
                        let newEdge: ToolbarEdge
                        let minDist = min(distToTop, distToBottom, distToLeft, distToRight)
                        
                        if minDist == distToTop {
                            newEdge = .top
                        } else if minDist == distToBottom {
                            newEdge = .bottom
                        } else if minDist == distToLeft {
                            newEdge = .left
                        } else {
                            newEdge = .right
                        }
                        
                        // Reset position to ensure proper centering when edge changes
                        toolbarPosition = .zero
                        
                        // Smooth snap animation with spring physics
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75, blendDuration: 0.2)) {
                            edge = newEdge
                            dragOffset = .zero
                        }
                    }
            )
        }
    }
    
    private func calculateMaxToolbarHeight() -> CGFloat {
        let buttonSize: CGFloat = 48
        let spacing: CGFloat = 12
        let padding: CGFloat = 8 // Reduced padding
        let labelHeight: CGFloat = 14
        let buttonWithLabel: CGFloat = buttonSize + spacing + labelHeight
        let toggleButtonSize: CGFloat = 44
        
        // Calculate height for all tools
        return toggleButtonSize + spacing + CGFloat(tools.count) * buttonWithLabel + spacing * CGFloat(max(0, tools.count - 1)) + padding * 2
    }
    
    private func initializePosition(geometry: GeometryProxy) {
        // Position is fixed based on edge, no need to initialize
    }
    
    private func calculateToolbarSize(_ geometry: GeometryProxy, safeArea: EdgeInsets) -> CGSize {
        let buttonSize: CGFloat = 32
        let padding: CGFloat = 4
        let edgePadding: CGFloat = 16 // Padding from window edges
        let titleBarHeight: CGFloat = 56 // Height of title bar
        
        switch edge {
        case .top, .bottom:
            // Horizontal toolbar: width with padding on left/right, fixed height
            let availableWidth = geometry.size.width - safeArea.leading - safeArea.trailing - edgePadding * 2
            let height = buttonSize + padding * 2
            return CGSize(width: availableWidth, height: height)
        case .left, .right:
            // Vertical toolbar: fixed width, height with padding on top/bottom (below title bar)
            let topSpace = titleBarHeight
            let bottomSpace = safeArea.bottom
            let availableHeight = geometry.size.height - topSpace - bottomSpace - edgePadding * 2
            let width = buttonSize + padding * 2
            return CGSize(width: width, height: availableHeight)
        }
    }
    
    private func positionForEdge(_ edge: ToolbarEdge, in size: CGSize, safeArea: EdgeInsets, toolbarSize: CGSize) -> CGPoint {
        let edgePadding: CGFloat = 16 // Padding from window edges
        let titleBarHeight: CGFloat = 56 // Height of title bar
        
        switch edge {
        case .top:
            // Clip below title bar, centered horizontally with padding
            return CGPoint(
                x: size.width / 2,
                y: titleBarHeight + toolbarSize.height/2
            )
        case .bottom:
            // Clip to bottom edge, centered horizontally with padding
            return CGPoint(
                x: size.width / 2,
                y: size.height - safeArea.bottom - toolbarSize.height/2
            )
        case .left:
            // Clip to left edge, centered vertically with padding (below title bar)
            let topSpace = titleBarHeight
            let bottomSpace = safeArea.bottom
            let availableHeight = size.height - topSpace - bottomSpace
            let centerY = topSpace + availableHeight / 2
            return CGPoint(
                x: safeArea.leading + edgePadding + toolbarSize.width/2,
                y: centerY
            )
        case .right:
            // Clip to right edge, centered vertically with padding (below title bar)
            let topSpace = titleBarHeight
            let bottomSpace = safeArea.bottom
            let availableHeight = size.height - topSpace - bottomSpace
            let centerY = topSpace + availableHeight / 2
            return CGPoint(
                x: size.width - safeArea.trailing - edgePadding - toolbarSize.width/2,
                y: centerY
            )
        }
    }
    
    private func constrainedX(_ x: CGFloat, toolbarSize: CGSize, geometry: GeometryProxy, edge: ToolbarEdge) -> CGFloat {
        let safeArea = geometry.safeAreaInsets
        let edgePadding: CGFloat = 16
        
        switch edge {
        case .top, .bottom:
            // Centered horizontally for horizontal toolbars
            return geometry.size.width / 2
        case .left:
            // Fixed to left edge with padding
            return safeArea.leading + edgePadding + toolbarSize.width/2
        case .right:
            // Fixed to right edge with padding
            return geometry.size.width - safeArea.trailing - edgePadding - toolbarSize.width/2
        }
    }
    
    private func constrainedY(_ y: CGFloat, toolbarSize: CGSize, geometry: GeometryProxy, edge: ToolbarEdge) -> CGFloat {
        let safeArea = geometry.safeAreaInsets
        let titleBarHeight: CGFloat = 56 // Height of title bar
        
        switch edge {
        case .left, .right:
            // Centered vertically for vertical toolbars, but below title bar
            let topSpace = titleBarHeight
            let bottomSpace = safeArea.bottom
            let availableHeight = geometry.size.height - topSpace - bottomSpace
            let centerY = topSpace + availableHeight / 2
            return centerY
        case .top:
            // Fixed below title bar
            return titleBarHeight + toolbarSize.height/2
        case .bottom:
            // Fixed to bottom edge
            return geometry.size.height - safeArea.bottom - toolbarSize.height/2
        }
    }
    
    
    private var toolsStack: some View {
        Group {
            if edge == .top || edge == .bottom {
                // Horizontal layout for top/bottom edges - centered
                HStack(spacing: 6) {
                    ForEach(Array(tools.enumerated()), id: \.element.0) { index, toolData in
                        toolButtonView(index: index, toolData: toolData)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                // Vertical layout for left/right edges - centered
                VStack(spacing: 6) {
                    ForEach(Array(tools.enumerated()), id: \.element.0) { index, toolData in
                        toolButtonView(index: index, toolData: toolData)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func toolButtonView(index: Int, toolData: (EditorToolState, String, String)) -> some View {
        let (tool, icon, label) = toolData
        
        if tool == .eraser {
            EraserToolButton(viewModel: viewModel, icon: icon, label: label)
        } else {
            ToolButton(
                tool: tool,
                icon: icon,
                label: label,
                isSelected: viewModel.getCurrentToolState() == tool,
                action: {
                    Task {
                        try? await viewModel.setToolState(tool)
                    }
                }
            )
        }
    }
    
    
    private var toolbarBackground: some View {
        Rectangle()
            .fill(Color(NSColor.controlBackgroundColor))
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
    }
    
    
    private var edgeAnchor: UnitPoint {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }
}

/// Individual tool button in the toolbar.
struct ToolButton: View {
    let tool: EditorToolState
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            // Add haptic feedback
            #if os(macOS)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            #endif
            action()
        }) {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.1) : Color.clear))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
}

/// Eraser tool button with size selector.
struct EraserToolButton: View {
    @ObservedObject var viewModel: NotebookEditorViewModel
    let icon: String
    let label: String
    @State private var showSizeSelector = false
    @State private var isHovered = false
    
    var isSelected: Bool {
        viewModel.getCurrentToolState() == .eraser
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Button(action: {
                #if os(macOS)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                #endif
                
                if isSelected {
                    // Toggle size selector
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showSizeSelector.toggle()
                    }
                } else {
                    // Switch to eraser tool
                    Task {
                        try? await viewModel.setToolState(.eraser)
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.1) : Color.clear))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    isHovered = hovering
                }
            }
            
            if showSizeSelector {
                VStack(spacing: 8) {
                    Text("Size: \(Int(viewModel.eraserSize))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Button(action: {
                            #if os(macOS)
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            #endif
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.eraserSize = max(10, viewModel.eraserSize - 10)
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        
                        Slider(value: $viewModel.eraserSize, in: 10...100, step: 5)
                            .frame(width: 100)
                            .tint(.accentColor)
                        
                        Button(action: {
                            #if os(macOS)
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            #endif
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.eraserSize = min(100, viewModel.eraserSize + 10)
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .frame(width: 120) // Fixed width to prevent layout shifts
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.7)),
                    removal: .scale(scale: 0.8).combined(with: .opacity).animation(.spring(response: 0.25, dampingFraction: 0.8))
                ))
            }
        }
    }
}

