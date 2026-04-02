import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Foundation

struct ContentView: View {
    let projectId: UUID

    private var projectStore: CanvasProjectStore { CanvasProjectStore.shared }
    private let autoSaveTimer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    @State private var projectTitle: String = ""

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    @State private var currentStroke: [CGPoint] = []
    @State private var strokes: [StrokeItem] = []
    @State private var hiddenStrokeIds: Set<UUID> = []

    @State private var importedTextLines: [ImportedTextLine] = []
    @State private var hiddenTextLineIds: Set<UUID> = []
    @State private var layerGroups: [LayerGroup] = []
    @State private var selectedLayerIdsForGrouping: Set<String> = []
    @State private var customLayerNames: [String: String] = [:]
    @State private var selectedTextLineId: UUID?
    @State private var selectedTextLineIds: Set<UUID> = []
    @State private var selectedCanvasItem: SelectedCanvasItem?
    @State private var selectedCanvasLayerIds: Set<String> = []
    @State private var draggingTextLineId: UUID?
    @State private var draggingStrokeId: UUID?
    @State private var resizingCanvasItem = false
    @State private var cursorSelectionStartPoint: CGPoint?
    @State private var cursorSelectionRect: CGRect?
    @State private var cursorPencilDragging = false
    @State private var cursorPencilResizing = false
    @State private var lastCursorPencilPointInView: CGPoint?

    @State private var editingTextLineId: UUID?
    @State private var editingTextLineText = ""
    @State private var editingTextSelectionRange = NSRange(location: 0, length: 0)

    @State private var isComposingNewText = false
    @State private var composingText = ""
    @State private var composingTextPosition: CGPoint?
    @State private var composingTextSelectionRange = NSRange(location: 0, length: 0)

    @State private var textSelectionStartPoint: CGPoint?
    @State private var textSelectionRect: CGRect?
    @State private var pencilDraggingTextSelection = false
    @State private var lastPencilPointInView: CGPoint?

    @State private var hasCapturedTextDragUndo = false
    @State private var hasCapturedEraseUndo = false
    @State private var undoStack: [CanvasSnapshot] = []
    @State private var redoStack: [CanvasSnapshot] = []

    @State private var interactionMode: InteractionMode = .draw
    @State private var drawingTool: DrawingToolKind = .pen
    @State private var drawingColor: Color = .black
    @State private var selectedPaletteColorIndex: Int? = 0
    @State private var drawingWidth: CGFloat = 5
    @State private var drawingOpacity: Double = 1
    @State private var drawingStyle: DrawingStyle = .solid

    @State private var showImportPicker = false
    @State private var searchQuery = ""
    @State private var toolDockPlacement: ToolDockPlacement = .bottom
    private let minScale: CGFloat = 0.2
    private let maxScale: CGFloat = 8
    private let virtualCanvasSize: CGFloat = 120000
    private let paletteColors: [Color] = [.black, .blue, .green, .yellow, .red]
    /// Ліва колонка: інструменти (2 ряди) + слої; ширина контенту карток.
    private let toolDockLeftSidebarWidth: CGFloat = 296
    private let toolDockLeftOuterLeading: CGFloat = 12
    private let toolDockLeftGapToCanvas: CGFloat = 10
    private var toolDockLeftColumnTotalWidth: CGFloat {
        toolDockLeftOuterLeading + toolDockLeftSidebarWidth + toolDockLeftGapToCanvas
    }
    private let toolDockBottomHeight: CGFloat = 220
    private static let docxUTType: UTType = UTType("org.openxmlformats.wordprocessingml.document")
        ?? UTType(filenameExtension: "docx")
        ?? .data

    var body: some View {
        GeometryReader { geo in
            editorRoot(geo: geo)
        }
    }

    @ViewBuilder
    private func editorRoot(geo: GeometryProxy) -> some View {
        mainEditorContent(geo: geo)
    }

    @ViewBuilder
    private func mainEditorContent(geo: GeometryProxy) -> some View {
        Group {
            if toolDockPlacement == .leading {
                HStack(alignment: .top, spacing: toolDockLeftGapToCanvas) {
                    leadingSidebarColumn(canvasHeight: geo.size.height)
                        .padding(.leading, toolDockLeftOuterLeading)
                        .padding(.top, 8)
                    canvasStack(
                        size: CGSize(width: max(1, geo.size.width - toolDockLeftColumnTotalWidth), height: geo.size.height)
                    )
                }
            } else {
                VStack(spacing: 0) {
                    canvasStack(
                        size: CGSize(width: geo.size.width, height: max(1, geo.size.height - toolDockBottomHeight))
                    )
                    fixedToolDockPanel(canvasSize: geo.size)
                }
            }
        }
            .coordinateSpace(name: EditorCanvasCoordinateSpace.name)
            .overlay(alignment: .topTrailing) { importButton.padding(.top, 12).padding(.trailing, 12) }
            .overlay(alignment: .topTrailing) { searchPanel.padding(.top, 64).padding(.trailing, 12) }
            .overlay(alignment: .topLeading) {
                if toolDockPlacement != .leading {
                    layersPanel(embedded: false).padding(12)
                }
            }
            .overlay { if editingTextLineId != nil { editTextLineOverlay(size: geo.size) } }
            .overlay { if isComposingNewText { composingTextInlineOverlay(size: geo.size) } }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [Self.docxUTType], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                importDOCX(from: url)
            }
            .onAppear {
                if let meta = projectStore.metadata(for: projectId) {
                    projectTitle = meta.title
                }
                loadCanvasStateIfNeeded()
            }
            .onChange(of: scale) { _ in saveCanvasState() }
            .onChange(of: offset) { _ in saveCanvasState() }
            .onChange(of: hiddenStrokeIds) { _ in saveCanvasState() }
            .onChange(of: hiddenTextLineIds) { _ in saveCanvasState() }
            .onChange(of: customLayerNames) { _ in saveCanvasState() }
            .onChange(of: toolDockPlacement) { _ in saveCanvasState() }
            .onReceive(autoSaveTimer) { _ in saveCanvasState() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TextField("Назва", text: $projectTitle)
                        .multilineTextAlignment(.center)
                        .submitLabel(.done)
                        .onSubmit { projectStore.renameProject(id: projectId, title: projectTitle) }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Панель інструментів", selection: $toolDockPlacement) {
                            Label("Зліва (інструменти і слої)", systemImage: "rectangle.lefthalf.filled").tag(ToolDockPlacement.leading)
                            Label("Знизу (горизонтально)", systemImage: "rectangle.bottomhalf.filled").tag(ToolDockPlacement.bottom)
                        }
                    } label: {
                        Image(systemName: toolDockPlacement == .leading ? "sidebar.left" : "rectangle.bottomhalf.filled")
                    }
                }
            }
            .onDisappear {
                projectStore.renameProject(id: projectId, title: projectTitle)
                saveCanvasState()
            }
    }

    private func canvasStack(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return ZStack {
            Color.white
            editorDrawingCanvas(center: center)
            editorTouchSurface()
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private func leadingSidebarColumn(canvasHeight: CGFloat) -> some View {
        let toolChrome = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let layersChrome = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let toolInnerW = toolDockLeftSidebarWidth - 20
        VStack(alignment: .leading, spacing: 12) {
            toolDockContent(
                dockFrameSize: CGSize(width: toolInnerW, height: 200),
                placement: .leading
            )
            .padding(10)
            .frame(width: toolDockLeftSidebarWidth - 4, alignment: .topLeading)
            .background { toolChrome.fill(Material.ultraThinMaterial) }
            .overlay { toolChrome.stroke(Color.black.opacity(0.08), lineWidth: 1) }
            .shadow(color: Color.black.opacity(0.1), radius: 12, x: 4, y: 4)

            layersPanel(embedded: true)
                .padding(10)
                .frame(width: toolDockLeftSidebarWidth - 4, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background { layersChrome.fill(Material.ultraThinMaterial) }
                .overlay { layersChrome.stroke(Color.black.opacity(0.08), lineWidth: 1) }
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 3, y: 3)
        }
        .frame(width: toolDockLeftSidebarWidth, height: canvasHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func fixedToolDockPanel(canvasSize: CGSize) -> some View {
        let bottomShape = UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 18, bottomLeading: 0, bottomTrailing: 0, topTrailing: 18),
            style: .continuous
        )
        toolDockContent(
            dockFrameSize: CGSize(width: canvasSize.width, height: toolDockBottomHeight),
            placement: .bottom
        )
        .padding(8)
        .frame(width: canvasSize.width, height: toolDockBottomHeight, alignment: .top)
        .background {
            bottomShape.fill(Material.ultraThinMaterial)
        }
        .overlay {
            bottomShape.stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private func editorDrawingCanvas(center: CGPoint) -> some View {
        ZStack {
            EditorImportedTextCanvasLayer(
                center: center,
                scale: scale,
                offset: offset,
                virtualCanvasSize: virtualCanvasSize,
                importedTextLines: importedTextLines,
                hiddenTextLineIds: hiddenTextLineIds,
                searchQuery: searchQuery,
                selectedTextLineIds: selectedTextLineIds,
                textSelectionRect: textSelectionRect
            )
            EditorStrokesCanvasLayer(
                scale: scale,
                offset: offset,
                strokes: strokes,
                hiddenStrokeIds: hiddenStrokeIds,
                currentStroke: currentStroke,
                drawingColor: drawingColor,
                drawingOpacity: drawingOpacity,
                drawingStyle: drawingStyle,
                drawingWidth: drawingWidth,
                drawingTool: drawingTool,
                interactionMode: interactionMode,
                selectedItemBounds: (drawingTool == .cursor && interactionMode == .draw) ? selectedCanvasItemBounds() : nil,
                cursorMarqueeRect: (drawingTool == .cursor && interactionMode == .draw) ? cursorSelectionRect : nil
            )
        }
    }

    private func editorTouchSurface() -> some View {
        TouchSurfaceView(
            onPencilBegan: { p in
                if interactionMode == .draw {
                    if drawingTool == .cursor {
                        let cp = viewToContent(p)
                        cursorPencilDragging = false
                        cursorPencilResizing = false
                        lastCursorPencilPointInView = nil
                        if isPointNearResizeHandle(cp) {
                            cursorPencilResizing = true
                            lastCursorPencilPointInView = p
                            hasCapturedTextDragUndo = false
                            cursorSelectionStartPoint = nil
                            cursorSelectionRect = nil
                            return
                        }
                        if isPointInsideSelectedCanvasItems(cp) {
                            cursorPencilDragging = true
                            lastCursorPencilPointInView = p
                            hasCapturedTextDragUndo = false
                            cursorSelectionStartPoint = nil
                            cursorSelectionRect = nil
                            return
                        }
                        cursorSelectionStartPoint = cp
                        cursorSelectionRect = CGRect(origin: cp, size: .zero)
                        return
                    }
                    if drawingTool == .eraser {
                        pushUndoSnapshot()
                        hasCapturedEraseUndo = true
                        _ = eraseStrokes(at: viewToContent(p))
                        currentStroke = []
                    } else {
                        currentStroke = [viewToContent(p)]
                    }
                    return
                }
                guard interactionMode == .text, editingTextLineId == nil, !isComposingNewText else { return }
                let cp = viewToContent(p)
                if let hit = textLineAt(contentPoint: cp), selectedTextLineIds.contains(hit.id), !selectedTextLineIds.isEmpty {
                    pencilDraggingTextSelection = true
                    lastPencilPointInView = p
                    hasCapturedTextDragUndo = false
                } else {
                    pencilDraggingTextSelection = false
                    textSelectionStartPoint = cp
                    textSelectionRect = CGRect(origin: cp, size: .zero)
                    selectedTextLineId = nil
                    selectedTextLineIds = []
                }
            },
            onSingleTap: { p in
                if interactionMode == .draw, drawingTool == .cursor {
                    selectCanvasItem(at: viewToContent(p))
                    return
                }
                guard interactionMode == .text, editingTextLineId == nil else { return }
                if let line = textLineAt(contentPoint: viewToContent(p)) {
                    selectedTextLineId = line.id
                    selectedTextLineIds = [line.id]
                } else {
                    selectedTextLineId = nil
                    selectedTextLineIds = []
                }
            },
            onDoubleTap: { p in
                guard interactionMode == .text else { return }
                let cp = viewToContent(p)
                if let line = textLineAt(contentPoint: cp) {
                    selectedTextLineIds = [line.id]
                    splitWordFromDoubleTap(at: cp, in: line)
                }
            },
            onPencilDoubleTap: { p in
                guard interactionMode == .text, editingTextLineId == nil else { return }
                let cp = viewToContent(p)
                if let line = textLineAt(contentPoint: cp) {
                    selectedTextLineId = line.id
                    selectedTextLineIds = [line.id]
                    startEditingSelectedTextLine()
                } else {
                    startComposingNewText(at: cp)
                }
            },
            onPencilMoved: { p in
                if interactionMode == .draw {
                    if drawingTool == .cursor {
                        if cursorPencilDragging || cursorPencilResizing {
                            guard let last = lastCursorPencilPointInView else { return }
                            if !hasCapturedTextDragUndo { pushUndoSnapshot(); hasCapturedTextDragUndo = true }
                            let delta = CGSize(width: p.x - last.x, height: p.y - last.y)
                            if cursorPencilResizing {
                                resizeSelectedCanvasItems(delta: delta)
                            } else {
                                moveSelectedCanvasItems(delta: delta)
                            }
                            lastCursorPencilPointInView = p
                            return
                        }
                        if let start = cursorSelectionStartPoint {
                            let c = viewToContent(p)
                            cursorSelectionRect = CGRect(
                                x: min(start.x, c.x),
                                y: min(start.y, c.y),
                                width: abs(c.x - start.x),
                                height: abs(c.y - start.y)
                            )
                        }
                        return
                    }
                    if drawingTool == .eraser {
                        _ = eraseStrokes(at: viewToContent(p))
                    } else {
                        currentStroke.append(viewToContent(p))
                    }
                    return
                }
                guard interactionMode == .text else { return }
                if pencilDraggingTextSelection {
                    guard let last = lastPencilPointInView else { return }
                    if !hasCapturedTextDragUndo {
                        pushUndoSnapshot()
                        detachSelectedTextLinesToNewDocumentIfNeeded()
                        hasCapturedTextDragUndo = true
                    }
                    let dx = (p.x - last.x) / scale
                    let dy = (p.y - last.y) / scale
                    for i in importedTextLines.indices where selectedTextLineIds.contains(importedTextLines[i].id) {
                        importedTextLines[i].position = CGPoint(x: importedTextLines[i].position.x + dx, y: importedTextLines[i].position.y + dy)
                    }
                    lastPencilPointInView = p
                } else if let start = textSelectionStartPoint {
                    let c = viewToContent(p)
                    textSelectionRect = CGRect(x: min(start.x, c.x), y: min(start.y, c.y), width: abs(c.x - start.x), height: abs(c.y - start.y))
                }
            },
            onPencilEnded: {
                if interactionMode == .draw {
                    if drawingTool == .cursor {
                        if cursorPencilDragging || cursorPencilResizing {
                            cursorPencilDragging = false
                            cursorPencilResizing = false
                            lastCursorPencilPointInView = nil
                            hasCapturedTextDragUndo = false
                            return
                        }
                        defer {
                            cursorSelectionStartPoint = nil
                            cursorSelectionRect = nil
                        }
                        guard let rect = cursorSelectionRect else { return }
                        if rect.width > 3, rect.height > 3 {
                            selectCanvasItems(in: rect)
                        } else if let start = cursorSelectionStartPoint {
                            selectCanvasItem(at: start)
                        }
                        return
                    }
                    if drawingTool == .eraser { hasCapturedEraseUndo = false; return }
                    if currentStroke.count > 1 {
                        pushUndoSnapshot()
                        strokes.append(StrokeItem(points: currentStroke, color: drawingColor, width: drawingWidth, style: drawingStyle, opacity: drawingOpacity))
                    }
                    currentStroke = []
                    return
                }
                guard interactionMode == .text else { return }
                if pencilDraggingTextSelection {
                    pencilDraggingTextSelection = false
                    lastPencilPointInView = nil
                    hasCapturedTextDragUndo = false
                    return
                }
                defer { textSelectionStartPoint = nil; textSelectionRect = nil }
                guard let rect = textSelectionRect, rect.width > 3, rect.height > 3 else { return }
                selectTextFragments(in: rect)
            },
            onFingerPanBegan: { p in
                if interactionMode == .draw, drawingTool == .cursor {
                    let cp = viewToContent(p)
                    if isPointNearResizeHandle(cp) {
                        resizingCanvasItem = true
                        hasCapturedTextDragUndo = false
                        return
                    }
                    if isPointInsideSelectedCanvasItems(cp) {
                        draggingStrokeId = nil
                        draggingTextLineId = nil
                        hasCapturedTextDragUndo = false
                        return
                    }
                    if case .stroke(let id)? = selectedCanvasItem, strokeContainsPoint(id: id, point: cp) {
                        draggingStrokeId = id
                        hasCapturedTextDragUndo = false
                        return
                    }
                    if case .text(let id)? = selectedCanvasItem, textContainsPoint(id: id, point: cp) {
                        draggingTextLineId = id
                        hasCapturedTextDragUndo = false
                        return
                    }
                    selectCanvasItem(at: cp)
                    return
                }
                guard interactionMode == .text, editingTextLineId == nil, !isComposingNewText else { return }
                if let hit = textLineAt(contentPoint: viewToContent(p)) {
                    if selectedTextLineIds.contains(hit.id) {
                        draggingTextLineId = hit.id
                    } else {
                        selectedTextLineId = hit.id
                        selectedTextLineIds = [hit.id]
                        draggingTextLineId = hit.id
                    }
                    hasCapturedTextDragUndo = false
                }
            },
            onFingerPanChanged: { t in
                if interactionMode == .draw, drawingTool == .cursor {
                    if !hasCapturedTextDragUndo { pushUndoSnapshot(); hasCapturedTextDragUndo = true }
                    if resizingCanvasItem {
                        resizeSelectedCanvasItems(delta: t)
                        return
                    }
                    if !selectedCanvasLayerIds.isEmpty {
                        moveSelectedCanvasItems(delta: t)
                        return
                    }
                    if let dragId = draggingStrokeId {
                        moveStroke(id: dragId, delta: t)
                        return
                    }
                    if let dragId = draggingTextLineId {
                        moveText(id: dragId, delta: t)
                        return
                    }
                    return
                }
                if interactionMode == .draw {
                    offset = CGSize(width: offset.width + t.width, height: offset.height + t.height)
                    return
                }
                guard interactionMode == .text, editingTextLineId == nil, !isComposingNewText else { return }
                if let dragId = draggingTextLineId, importedTextLines.contains(where: { $0.id == dragId }) {
                    if !hasCapturedTextDragUndo {
                        pushUndoSnapshot()
                        detachSelectedTextLinesToNewDocumentIfNeeded()
                        hasCapturedTextDragUndo = true
                    }
                    let dx = t.width / scale
                    let dy = t.height / scale
                    for i in importedTextLines.indices where selectedTextLineIds.contains(importedTextLines[i].id) {
                        importedTextLines[i].position = CGPoint(x: importedTextLines[i].position.x + dx, y: importedTextLines[i].position.y + dy)
                    }
                } else {
                    offset = CGSize(width: offset.width + t.width, height: offset.height + t.height)
                }
            },
            onFingerPanEnded: {
                draggingTextLineId = nil
                draggingStrokeId = nil
                resizingCanvasItem = false
                hasCapturedTextDragUndo = false
            },
            onTwoFingerPanChanged: { t in
                offset = CGSize(width: offset.width + t.width, height: offset.height + t.height)
            },
            onPinchChanged: { s, c in
                if !currentStroke.isEmpty { currentStroke = [] }
                let newScale = (scale * s).clamped(to: minScale...maxScale)
                offset = CGSize(
                    width: c.x * (1 - newScale / scale) + offset.width * (newScale / scale),
                    height: c.y * (1 - newScale / scale) + offset.height * (newScale / scale)
                )
                scale = newScale
            }
        )
    }

    private func toolDockContent(dockFrameSize: CGSize, placement: ToolDockPlacement) -> some View {
        ToolDockContentView(
            dockFrameSize: dockFrameSize,
            placement: placement,
            undoStackIsEmpty: undoStack.isEmpty,
            redoStackIsEmpty: redoStack.isEmpty,
            interactionMode: interactionMode,
            drawingTool: drawingTool,
            drawingWidth: drawingWidth,
            drawingOpacity: drawingOpacity,
            drawingStyle: drawingStyle,
            drawingColor: drawingColor,
            selectedPaletteColorIndex: selectedPaletteColorIndex,
            paletteColors: paletteColors,
            onUndo: { undo() },
            onRedo: { redo() },
            onTextMode: { interactionMode = .text },
            onToolSelected: { tool in
                interactionMode = .draw
                drawingTool = tool
                if tool != .eraser, tool != .cursor { drawingWidth = tool.defaultWidth }
                if tool != .cursor {
                    selectedCanvasItem = nil
                    selectedCanvasLayerIds = []
                }
            },
            onDrawingWidthChanged: {
                drawingWidth = $0
                applyWidthToSelectedLayers($0)
            },
            onDrawingOpacityChanged: {
                drawingOpacity = $0
                applyOpacityToSelectedLayers($0)
            },
            onPaletteColorSelected: { idx, color in
                drawingColor = color
                selectedPaletteColorIndex = idx
                applyColorToSelectedLayers(color)
            },
            onCustomColorSelected: { color in
                drawingColor = color
                selectedPaletteColorIndex = nil
                applyColorToSelectedLayers(color)
            },
            onDrawingStyleChanged: {
                drawingStyle = $0
                applyStyleToSelectedLayers($0)
            }
        )
    }

    private var importButton: some View {
        ImportButtonView(showImportPicker: $showImportPicker)
    }

    private var searchPanel: some View {
        SearchPanelView(searchQuery: $searchQuery)
    }



    private func layersPanel(embedded: Bool) -> some View {
        LayersPanelView(
            listMaxHeight: embedded ? nil : 280,
            useSidebarColumnWidth: embedded,
            canvasLayers: canvasLayers,
            layerGroupSections: layerGroupSections,
            selectedLayerIdsForGrouping: selectedLayerIdsForGrouping,
            createGroupFromSelection: createGroupFromSelection,
            ungroup: ungroup,
            toggleGroupExpansion: toggleGroupExpansion,
            toggleGroupVisibility: toggleGroupVisibility,
            isSectionVisible: isSectionVisible,
            toggleLayerSelectionForGrouping: toggleLayerSelectionForGrouping,
            layerNameBinding: layerNameBinding,
            groupNameBinding: groupNameBinding,
            toggleLayerVisibility: toggleLayerVisibility,
            isLayerVisible: isLayerVisible
        )
    }

    @ViewBuilder
    private func editTextLineOverlay(size: CGSize) -> some View {
        if let id = editingTextLineId, let line = importedTextLines.first(where: { $0.id == id }) {
            let vp = contentToView(line.position)
            let w = min(max(220, CGFloat(max(editingTextLineText.count, 1)) * 9), size.width - 24)
            let x = min(max(vp.x + w / 2, w / 2 + 12), size.width - w / 2 - 12)
            let y = min(max(vp.y + 24, 70), size.height - 90)

            VStack(alignment: .leading, spacing: 8) {
                SelectableTextView(text: $editingTextLineText, selectedRange: $editingTextSelectionRange)
                    .frame(width: w, height: 92)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("Винести виділене") { splitSelectedTextFromEditingLine() }
                    Button("Зберегти") { commitEditingTextLine() }
                    Button("Скасувати") { editingTextLineId = nil; editingTextLineText = "" }.foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .position(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func composingTextInlineOverlay(size: CGSize) -> some View {
        if let pos = composingTextPosition {
            let vp = contentToView(pos)
            let w = min(max(220, CGFloat(max(composingText.count, 1)) * 9), size.width - 24)
            let x = min(max(vp.x + w / 2, w / 2 + 12), size.width - w / 2 - 12)
            let y = min(max(vp.y + 12, 60), size.height - 60)

            VStack(alignment: .leading, spacing: 6) {
                SelectableTextView(text: $composingText, selectedRange: $composingTextSelectionRange)
                    .frame(width: w, height: 52)
                    .background(Color.white.opacity(0.001))
                HStack(spacing: 10) {
                    Button("Вставити") { commitComposingText() }
                    Button("Скасувати") { cancelComposingText() }.foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .position(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func importDOCX(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let paragraphs = try? DocxPlainTextParser.parseParagraphs(from: url), !paragraphs.isEmpty else { return }

        let documentId = UUID()
        let groupId = UUID()
        let topLeft = viewToContent(CGPoint(x: 24, y: 120))
        var y = topLeft.y
        var order = 0
        var lines: [ImportedTextLine] = []
        for p in paragraphs {
            for t in wrapText(p, maxChars: 64) {
                lines.append(ImportedTextLine(documentId: documentId, groupId: groupId, order: order, text: t, position: CGPoint(x: topLeft.x, y: y), fontSize: 18, color: .black))
                y += 24
                order += 1
            }
            y += 10
        }
        guard !lines.isEmpty else { return }
        pushUndoSnapshot()
        importedTextLines.append(contentsOf: lines)
    }

    private func wrapText(_ text: String, maxChars: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var lines: [String] = []
        var current = ""
        for word in words {
            if current.isEmpty { current = word; continue }
            if current.count + 1 + word.count <= maxChars {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private func textLineAt(contentPoint: CGPoint) -> ImportedTextLine? {
        importedTextLines.last { !hiddenTextLineIds.contains($0.id) && boundsForTextLine($0).contains(contentPoint) }
    }

    private func boundsForTextLine(_ line: ImportedTextLine) -> CGRect {
        let width = (line.text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: line.fontSize)]).width
        return CGRect(x: line.position.x, y: line.position.y, width: width, height: line.fontSize * 1.3)
    }

    private func startEditingSelectedTextLine() {
        guard let id = selectedTextLineId, let line = importedTextLines.first(where: { $0.id == id }) else { return }
        editingTextLineId = id
        editingTextLineText = line.text
        editingTextSelectionRange = NSRange(location: (line.text as NSString).length, length: 0)
    }

    private func commitEditingTextLine() {
        guard let id = editingTextLineId, let idx = importedTextLines.firstIndex(where: { $0.id == id }) else {
            editingTextLineId = nil
            editingTextLineText = ""
            return
        }
        if importedTextLines[idx].text != editingTextLineText {
            pushUndoSnapshot()
            importedTextLines[idx].text = editingTextLineText
        }
        editingTextLineId = nil
        editingTextLineText = ""
        editingTextSelectionRange = NSRange(location: 0, length: 0)
    }

    private func deleteSelectedTextLine() {
        guard !selectedTextLineIds.isEmpty else { return }
        pushUndoSnapshot()
        importedTextLines.removeAll { selectedTextLineIds.contains($0.id) }
        sanitizeLayerGroups()
        if case .text(let id)? = selectedCanvasItem, !importedTextLines.contains(where: { $0.id == id }) {
            selectedCanvasItem = nil
        }
        selectedTextLineId = nil
        selectedTextLineIds = []
    }

    private func startComposingNewText(at position: CGPoint) {
        composingTextPosition = position
        composingText = ""
        composingTextSelectionRange = NSRange(location: 0, length: 0)
        isComposingNewText = true
        selectedTextLineId = nil
        selectedTextLineIds = []
    }

    private func commitComposingText() {
        guard let position = composingTextPosition else { return }
        let trimmed = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            pushUndoSnapshot()
            let line = ImportedTextLine(text: composingText, position: position, fontSize: 18, color: .black)
            importedTextLines.append(line)
            selectedTextLineId = line.id
            selectedTextLineIds = [line.id]
        }
        cancelComposingText()
    }

    private func cancelComposingText() {
        isComposingNewText = false
        composingText = ""
        composingTextPosition = nil
        composingTextSelectionRange = NSRange(location: 0, length: 0)
    }

    private func splitSelectedTextFromEditingLine() {
        guard let id = editingTextLineId, let idx = importedTextLines.firstIndex(where: { $0.id == id }) else { return }
        let nsText = editingTextLineText as NSString
        let range = editingTextSelectionRange
        guard range.length > 0, range.location >= 0, range.location + range.length <= nsText.length else { return }

        pushUndoSnapshot()
        let selected = nsText.substring(with: range)
        let prefix = nsText.substring(to: range.location)
        let suffix = nsText.substring(from: range.location + range.length)
        let remaining = prefix + suffix

        let original = importedTextLines[idx]
        if remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            importedTextLines.remove(at: idx)
        } else {
            importedTextLines[idx].text = remaining
        }

        let newLine = ImportedTextLine(
            documentId: original.documentId,
            groupId: original.groupId,
            order: original.order + 1,
            text: selected,
            position: CGPoint(x: original.position.x + 14, y: original.position.y + original.fontSize * 1.5),
            fontSize: original.fontSize,
            color: original.color
        )
        importedTextLines.append(newLine)
        selectedTextLineId = newLine.id
        selectedTextLineIds = [newLine.id]
        editingTextLineId = nil
        editingTextLineText = ""
        editingTextSelectionRange = NSRange(location: 0, length: 0)
    }

    private func splitWordFromDoubleTap(at contentPoint: CGPoint, in line: ImportedTextLine) {
        guard let idx = importedTextLines.firstIndex(where: { $0.id == line.id }) else { return }
        guard let range = wordRangeAtTap(in: line, contentPoint: contentPoint), range.length > 0 else {
            selectedTextLineId = line.id
            selectedTextLineIds = [line.id]
            startEditingSelectedTextLine()
            return
        }

        pushUndoSnapshot()
        let parts = line.split(at: range)
        importedTextLines.remove(at: idx)
        var insertion: [ImportedTextLine] = []
        if let l = parts.left { insertion.append(l) }
        if let s = parts.selected { insertion.append(s) }
        if let r = parts.right { insertion.append(r) }
        importedTextLines.insert(contentsOf: insertion, at: idx)

        let picked = parts.selected?.id ?? parts.left?.id ?? parts.right?.id
        selectedTextLineId = picked
        selectedTextLineIds = picked.map { [$0] } ?? []
    }

    private func wordRangeAtTap(in line: ImportedTextLine, contentPoint: CGPoint) -> NSRange? {
        let ns = line.text as NSString
        let length = ns.length
        guard length > 0 else { return nil }
        let localX = contentPoint.x - line.position.x
        guard localX >= 0 else { return nil }
        let font = UIFont.systemFont(ofSize: line.fontSize)

        var idx = length - 1
        for i in 1...length {
            let w = (ns.substring(to: i) as NSString).size(withAttributes: [.font: font]).width
            if localX <= w { idx = i - 1; break }
        }

        let chars = CharacterSet.alphanumerics
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < length, let scalar = UnicodeScalar(ns.character(at: i)) else { return false }
            return chars.contains(scalar)
        }
        guard isWord(idx) else { return nil }
        var start = idx
        var end = idx
        while start > 0, isWord(start - 1) { start -= 1 }
        while end + 1 < length, isWord(end + 1) { end += 1 }
        return NSRange(location: start, length: end - start + 1)
    }

    private func selectTextFragments(in rect: CGRect) {
        var selectedIds: [UUID] = []
        var changed = false
        for idx in importedTextLines.indices.reversed() {
            let line = importedTextLines[idx]
            let bounds = boundsForTextLine(line)
            guard bounds.intersects(rect) else { continue }
            guard let range = characterRangeForRectOverlap(in: line, lineBounds: bounds, selectionRect: rect) else { continue }
            let len = (line.text as NSString).length
            if range.location == 0 && range.length == len {
                selectedIds.append(line.id)
                continue
            }
            changed = true
            let parts = line.split(at: range)
            importedTextLines.remove(at: idx)
            var insertion: [ImportedTextLine] = []
            if let l = parts.left { insertion.append(l) }
            if let s = parts.selected { insertion.append(s); selectedIds.append(s.id) }
            if let r = parts.right { insertion.append(r) }
            importedTextLines.insert(contentsOf: insertion, at: idx)
        }
        if changed { normalizeFragmentOrder() }
        selectedTextLineIds = Set(selectedIds)
        selectedTextLineId = selectedIds.first
    }

    private func characterRangeForRectOverlap(in line: ImportedTextLine, lineBounds: CGRect, selectionRect: CGRect) -> NSRange? {
        let ns = line.text as NSString
        let length = ns.length
        guard length > 0 else { return nil }
        let minX = max(lineBounds.minX, selectionRect.minX)
        let maxX = min(lineBounds.maxX, selectionRect.maxX)
        guard maxX > minX else { return nil }
        let start = utf16Index(forLocalX: minX - line.position.x, in: line)
        var end = utf16Index(forLocalX: maxX - line.position.x, in: line)
        if end <= start { end = min(length, start + 1) }
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func utf16Index(forLocalX x: CGFloat, in line: ImportedTextLine) -> Int {
        let ns = line.text as NSString
        let length = ns.length
        if x <= 0 { return 0 }
        let font = UIFont.systemFont(ofSize: line.fontSize)
        for i in 0...length {
            let w = (ns.substring(to: i) as NSString).size(withAttributes: [.font: font]).width
            if x <= w { return i }
        }
        return length
    }

    private func normalizeFragmentOrder() {
        var grouped: [UUID: [Int]] = [:]
        for (idx, line) in importedTextLines.enumerated() { grouped[line.groupId, default: []].append(idx) }
        for (_, indices) in grouped {
            let sorted = indices.sorted { importedTextLines[$0].position.x < importedTextLines[$1].position.x }
            for (order, idx) in sorted.enumerated() { importedTextLines[idx].order = order }
        }
    }

    private func strokeStyle(for style: DrawingStyle, width: CGFloat) -> StrokeStyle {
        switch style {
        case .solid: return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        case .dashed: return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [10, 6])
        case .dotted: return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [2, 5])
        }
    }

    private var selectedStrokeBinding: Binding<StrokeItem>? {
        guard case .stroke(let id)? = selectedCanvasItem,
              let index = strokes.firstIndex(where: { $0.id == id }) else { return nil }
        return $strokes[index]
    }

    private var selectedTextBinding: Binding<ImportedTextLine>? {
        guard case .text(let id)? = selectedCanvasItem,
              let index = importedTextLines.firstIndex(where: { $0.id == id }) else { return nil }
        return $importedTextLines[index]
    }

    private func selectCanvasItem(at contentPoint: CGPoint) {
        if let line = textLineAt(contentPoint: contentPoint) {
            selectedCanvasItem = .text(line.id)
            selectedCanvasLayerIds = [CanvasLayer.text(line).id]
            let docLineIds = importedTextLines.filter { $0.documentId == line.documentId }.map(\.id)
            selectedTextLineId = line.id
            selectedTextLineIds = Set(docLineIds)
            return
        }
        if let stroke = strokeAt(contentPoint: contentPoint) {
            selectedCanvasItem = .stroke(stroke.id)
            selectedCanvasLayerIds = [CanvasLayer.stroke(stroke).id]
            selectedTextLineId = nil
            selectedTextLineIds = []
            return
        }
        selectedCanvasItem = nil
        selectedCanvasLayerIds = []
        selectedTextLineId = nil
        selectedTextLineIds = []
    }

    private func strokeAt(contentPoint: CGPoint) -> StrokeItem? {
        let threshold = max(10, drawingWidth) / scale
        let threshold2 = threshold * threshold
        return strokes.reversed().first { stroke in
            guard !hiddenStrokeIds.contains(stroke.id) else { return false }
            return stroke.points.contains { p in
                let dx = p.x - contentPoint.x
                let dy = p.y - contentPoint.y
                return dx * dx + dy * dy <= threshold2
            }
        }
    }

    private func selectedCanvasItemBounds() -> CGRect? {
        let layerIds = selectedCanvasLayerIds
        if !layerIds.isEmpty {
            let rects: [CGRect] = canvasLayers.compactMap { layer in
                guard layerIds.contains(layer.id) else { return nil }
                return boundsForCanvasLayer(layer)
            }
            guard let first = rects.first else { return nil }
            return rects.dropFirst().reduce(first) { $0.union($1) }
        }
        guard let item = selectedCanvasItem else { return nil }
        switch item {
        case .stroke(let id):
            guard let stroke = strokes.first(where: { $0.id == id }) else { return nil }
            return strokeBounds(stroke.points)
        case .text(let id):
            guard let line = importedTextLines.first(where: { $0.id == id }) else { return nil }
            return boundsForTextLine(line)
        }
    }

    private func isPointNearResizeHandle(_ point: CGPoint) -> Bool {
        guard let bounds = selectedCanvasItemBounds() else { return false }
        let handle = CGPoint(x: bounds.maxX, y: bounds.maxY)
        let dx = point.x - handle.x
        let dy = point.y - handle.y
        return (dx * dx + dy * dy) <= 220 / (scale * scale)
    }

    private func strokeContainsPoint(id: UUID, point: CGPoint) -> Bool {
        guard let stroke = strokes.first(where: { $0.id == id }) else { return false }
        let threshold = max(10, stroke.width) / scale
        let threshold2 = threshold * threshold
        return stroke.points.contains {
            let dx = $0.x - point.x
            let dy = $0.y - point.y
            return dx * dx + dy * dy <= threshold2
        }
    }

    private func textContainsPoint(id: UUID, point: CGPoint) -> Bool {
        guard let line = importedTextLines.first(where: { $0.id == id }) else { return false }
        return boundsForTextLine(line).contains(point)
    }

    private func moveStroke(id: UUID, delta: CGSize) {
        guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
        let dx = delta.width / scale
        let dy = delta.height / scale
        strokes[index].points = strokes[index].points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    private func moveText(id: UUID, delta: CGSize) {
        guard let index = importedTextLines.firstIndex(where: { $0.id == id }) else { return }
        let dx = delta.width / scale
        let dy = delta.height / scale
        importedTextLines[index].position = CGPoint(
            x: importedTextLines[index].position.x + dx,
            y: importedTextLines[index].position.y + dy
        )
    }

    private func resizeSelectedCanvasItem(delta: CGSize) {
        let amount = (delta.width + delta.height) / 220
        let factor = (1 + amount).clamped(to: 0.4...2.2)
        switch selectedCanvasItem {
        case .stroke(let id):
            guard let index = strokes.firstIndex(where: { $0.id == id }) else { return }
            let bounds = strokeBounds(strokes[index].points)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            strokes[index].points = strokes[index].points.map {
                CGPoint(x: center.x + ($0.x - center.x) * factor, y: center.y + ($0.y - center.y) * factor)
            }
            strokes[index].width = (strokes[index].width * factor).clamped(to: 1...48)
        case .text(let id):
            guard let index = importedTextLines.firstIndex(where: { $0.id == id }) else { return }
            importedTextLines[index].fontSize = (importedTextLines[index].fontSize * factor).clamped(to: 8...120)
        case nil:
            return
        }
    }

    private func boundsForCanvasLayer(_ layer: CanvasLayer) -> CGRect {
        switch layer {
        case .stroke(let stroke):
            return strokeBounds(stroke.points)
        case .text(let line):
            return boundsForTextLine(line)
        }
    }

    private func selectCanvasItems(in rect: CGRect) {
        let picked = canvasLayers.filter { layer in
            let bounds = boundsForCanvasLayer(layer)
            return bounds.intersects(rect)
        }
        selectedCanvasLayerIds = Set(picked.map(\.id))
        syncPrimarySelectionFromSet()
    }

    private func isPointInsideSelectedCanvasItems(_ point: CGPoint) -> Bool {
        guard !selectedCanvasLayerIds.isEmpty else { return false }
        return canvasLayers.contains { layer in
            selectedCanvasLayerIds.contains(layer.id) && boundsForCanvasLayer(layer).contains(point)
        }
    }

    private func moveSelectedCanvasItems(delta: CGSize) {
        let dx = delta.width / scale
        let dy = delta.height / scale
        for i in strokes.indices {
            let layerId = CanvasLayer.stroke(strokes[i]).id
            guard selectedCanvasLayerIds.contains(layerId) else { continue }
            strokes[i].points = strokes[i].points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
        for i in importedTextLines.indices {
            let layerId = CanvasLayer.text(importedTextLines[i]).id
            guard selectedCanvasLayerIds.contains(layerId) else { continue }
            importedTextLines[i].position = CGPoint(x: importedTextLines[i].position.x + dx, y: importedTextLines[i].position.y + dy)
        }
    }

    private func resizeSelectedCanvasItems(delta: CGSize) {
        guard let bounds = selectedCanvasItemBounds() else { return }
        let amount = (delta.width + delta.height) / 220
        let factor = (1 + amount).clamped(to: 0.4...2.2)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        for i in strokes.indices {
            let layerId = CanvasLayer.stroke(strokes[i]).id
            guard selectedCanvasLayerIds.contains(layerId) else { continue }
            strokes[i].points = strokes[i].points.map {
                CGPoint(x: center.x + ($0.x - center.x) * factor, y: center.y + ($0.y - center.y) * factor)
            }
            strokes[i].width = (strokes[i].width * factor).clamped(to: 1...48)
        }
        for i in importedTextLines.indices {
            let layerId = CanvasLayer.text(importedTextLines[i]).id
            guard selectedCanvasLayerIds.contains(layerId) else { continue }
            importedTextLines[i].position = CGPoint(
                x: center.x + (importedTextLines[i].position.x - center.x) * factor,
                y: center.y + (importedTextLines[i].position.y - center.y) * factor
            )
            importedTextLines[i].fontSize = (importedTextLines[i].fontSize * factor).clamped(to: 8...120)
        }
        syncPrimarySelectionFromSet()
    }

    private func applyWidthToSelectedLayers(_ width: CGFloat) {
        guard interactionMode == .draw, drawingTool == .cursor, !selectedCanvasLayerIds.isEmpty else { return }
        for i in strokes.indices {
            let layerId = CanvasLayer.stroke(strokes[i]).id
            guard selectedCanvasLayerIds.contains(layerId) else { continue }
            strokes[i].width = width
        }
    }

    private func applyOpacityToSelectedLayers(_ opacity: Double) {
        guard interactionMode == .draw, drawingTool == .cursor, !selectedCanvasLayerIds.isEmpty else { return }
        for i in strokes.indices {
            let layerId = CanvasLayer.stroke(strokes[i]).id
            guard selectedCanvasLayerIds.contains(layerId) else { continue }
            strokes[i].opacity = opacity
        }
    }

    private func applyColorToSelectedLayers(_ color: Color) {
        guard interactionMode == .draw, drawingTool == .cursor, !selectedCanvasLayerIds.isEmpty else { return }
        for i in strokes.indices {
            let layerId = CanvasLayer.stroke(strokes[i]).id
            guard selectedCanvasLayerIds.contains(layerId) else { continue }
            strokes[i].color = color
        }
        for i in importedTextLines.indices {
            let layerId = CanvasLayer.text(importedTextLines[i]).id
            guard selectedCanvasLayerIds.contains(layerId) else { continue }
            importedTextLines[i].color = color
        }
    }

    private func applyStyleToSelectedLayers(_ style: DrawingStyle) {
        guard interactionMode == .draw, drawingTool == .cursor, !selectedCanvasLayerIds.isEmpty else { return }
        for i in strokes.indices {
            let layerId = CanvasLayer.stroke(strokes[i]).id
            guard selectedCanvasLayerIds.contains(layerId) else { continue }
            strokes[i].style = style
        }
    }

    private func syncPrimarySelectionFromSet() {
        guard selectedCanvasLayerIds.count == 1, let id = selectedCanvasLayerIds.first else {
            selectedCanvasItem = nil
            return
        }
        if let uuid = UUID(uuidString: id.replacingOccurrences(of: "stroke-", with: "")), id.hasPrefix("stroke-") {
            selectedCanvasItem = .stroke(uuid)
            return
        }
        if let uuid = UUID(uuidString: id.replacingOccurrences(of: "textdoc-", with: "")), id.hasPrefix("textdoc-") {
            if let firstLine = importedTextLines.first(where: { $0.documentId == uuid }) {
                selectedCanvasItem = .text(firstLine.id)
                selectedTextLineId = firstLine.id
                selectedTextLineIds = Set(importedTextLines.filter { $0.documentId == uuid }.map(\.id))
            } else {
                selectedCanvasItem = nil
            }
            return
        }
        selectedCanvasItem = nil
    }

    private func detachSelectedTextLinesToNewDocumentIfNeeded() {
        guard !selectedTextLineIds.isEmpty else { return }
        let newDocumentId = UUID()
        for i in importedTextLines.indices where selectedTextLineIds.contains(importedTextLines[i].id) {
            importedTextLines[i].documentId = newDocumentId
        }
    }

    private func strokeBounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func eraseStrokes(at contentPoint: CGPoint) -> Bool {
        let radius = max(8, drawingWidth) / scale
        let r2 = radius * radius
        let old = strokes.count
        strokes.removeAll { stroke in
            guard !hiddenStrokeIds.contains(stroke.id) else { return false }
            return stroke.points.contains {
                let dx = $0.x - contentPoint.x
                let dy = $0.y - contentPoint.y
                return dx * dx + dy * dy <= r2
            }
        }
        return strokes.count != old
    }

    private func currentSnapshot() -> CanvasSnapshot {
        CanvasSnapshot(strokes: strokes, importedTextLines: importedTextLines)
    }

    private func pushUndoSnapshot() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
    }

    private func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        apply(snapshot: prev)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        apply(snapshot: next)
    }

    private func apply(snapshot: CanvasSnapshot) {
        strokes = snapshot.strokes
        importedTextLines = snapshot.importedTextLines
        hiddenStrokeIds = hiddenStrokeIds.intersection(Set(strokes.map(\.id)))
        hiddenTextLineIds = hiddenTextLineIds.intersection(Set(importedTextLines.map(\.id)))
        sanitizeLayerGroups()
        currentStroke = []
        selectedTextLineId = nil
        selectedTextLineIds = []
        editingTextLineId = nil
        editingTextLineText = ""
        isComposingNewText = false
        composingText = ""
        composingTextPosition = nil
        draggingTextLineId = nil
        draggingStrokeId = nil
        resizingCanvasItem = false
        selectedCanvasItem = nil
        selectedCanvasLayerIds = []
        cursorSelectionStartPoint = nil
        cursorSelectionRect = nil
        cursorPencilDragging = false
        cursorPencilResizing = false
        lastCursorPencilPointInView = nil
        hasCapturedTextDragUndo = false
        hasCapturedEraseUndo = false
        textSelectionStartPoint = nil
        textSelectionRect = nil
        pencilDraggingTextSelection = false
        lastPencilPointInView = nil
    }

    private func contentToView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width, y: point.y * scale + offset.height)
    }

    private func viewToContent(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.width) / scale, y: (point.y - offset.height) / scale)
    }

    private func searchRanges(in text: String, query: String) -> [NSRange] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let ns = text as NSString
        var result: [NSRange] = []
        var range = NSRange(location: 0, length: ns.length)
        while range.length > 0 {
            let found = ns.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: range)
            if found.location == NSNotFound { break }
            result.append(found)
            let next = found.location + max(1, found.length)
            if next >= ns.length { break }
            range = NSRange(location: next, length: ns.length - next)
        }
        return result
    }

    private func textWidthPrefix(_ text: String, length: Int, fontSize: CGFloat) -> CGFloat {
         let ns = text as NSString
        let l = min(max(0, length), ns.length)
        return (ns.substring(to: l) as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width
    }

    private var canvasLayers: [CanvasLayer] {
        let strokeLayers = strokes.map(CanvasLayer.stroke)
        let textLayers = Dictionary(grouping: importedTextLines, by: \.documentId)
            .values
            .compactMap { lines in
                lines.sorted { $0.order < $1.order }.first.map(CanvasLayer.text)
            }
        return strokeLayers + textLayers
    }

    private var layerGroupSections: [LayerGroupSection] {
        let layerMap = Dictionary(uniqueKeysWithValues: canvasLayers.map { ($0.id, $0) })
        var sections: [LayerGroupSection] = []
        var groupedIds: Set<String> = []

        for group in layerGroups {
            let layers = group.memberLayerIds.compactMap { layerMap[$0] }
            guard !layers.isEmpty else { continue }
            groupedIds.formUnion(layers.map(\.id))
            sections.append(
                LayerGroupSection(
                    id: "group-\(group.id.uuidString)",
                    title: group.name,
                    groupId: group.id,
                    layers: layers,
                    isExpanded: group.isExpanded
                )
            )
        }

        let ungrouped = canvasLayers.filter { !groupedIds.contains($0.id) }
        if !ungrouped.isEmpty {
            sections.append(
                LayerGroupSection(
                    id: "ungrouped",
                    title: "Без групи",
                    groupId: nil,
                    layers: ungrouped,
                    isExpanded: true
                )
            )
        }
        return sections
    }

    private func isLayerVisible(_ layer: CanvasLayer) -> Bool {
        switch layer {
        case .stroke(let stroke):
            return !hiddenStrokeIds.contains(stroke.id)
        case .text(let line):
            return !importedTextLines.contains(where: { $0.documentId == line.documentId && hiddenTextLineIds.contains($0.id) })
        }
    }

    private func toggleLayerVisibility(_ layer: CanvasLayer) {
        switch layer {
        case .stroke(let stroke):
            if hiddenStrokeIds.contains(stroke.id) {
                hiddenStrokeIds.remove(stroke.id)
            } else {
                hiddenStrokeIds.insert(stroke.id)
            }
        case .text(let line):
            let ids = importedTextLines.filter { $0.documentId == line.documentId }.map(\.id)
            let allHidden = ids.allSatisfy { hiddenTextLineIds.contains($0) }
            if allHidden {
                hiddenTextLineIds.subtract(ids)
            } else {
                hiddenTextLineIds.formUnion(ids)
                selectedTextLineIds.subtract(ids)
                if let selectedTextLineId, ids.contains(selectedTextLineId) { self.selectedTextLineId = nil }
                if let editingTextLineId, ids.contains(editingTextLineId) {
                    self.editingTextLineId = nil
                    editingTextLineText = ""
                }
            }
        }
    }

    private func toggleLayerSelectionForGrouping(_ layerId: String) {
        if selectedLayerIdsForGrouping.contains(layerId) {
            selectedLayerIdsForGrouping.remove(layerId)
        } else {
            selectedLayerIdsForGrouping.insert(layerId)
        }
    }

    private func createGroupFromSelection() {
        guard selectedLayerIdsForGrouping.count >= 2 else { return }
        let memberIds = Array(selectedLayerIdsForGrouping)
        for index in layerGroups.indices {
            layerGroups[index].memberLayerIds.removeAll { selectedLayerIdsForGrouping.contains($0) }
        }
        layerGroups.removeAll { $0.memberLayerIds.isEmpty }
        layerGroups.append(LayerGroup(name: "Група \(layerGroups.count + 1)", memberLayerIds: memberIds))
        selectedLayerIdsForGrouping.removeAll()
    }

    private func ungroup(_ groupId: UUID) {
        layerGroups.removeAll { $0.id == groupId }
    }

    private func toggleGroupExpansion(_ groupId: UUID) {
        guard let index = layerGroups.firstIndex(where: { $0.id == groupId }) else { return }
        layerGroups[index].isExpanded.toggle()
    }

    private func isSectionVisible(_ section: LayerGroupSection) -> Bool {
        section.layers.allSatisfy(isLayerVisible(_:))
    }

    private func toggleGroupVisibility(_ section: LayerGroupSection) {
        let makeVisible = !isSectionVisible(section)
        for layer in section.layers {
            setLayerVisibility(layer, isVisible: makeVisible)
        }
    }

    private func setLayerVisibility(_ layer: CanvasLayer, isVisible: Bool) {
        switch layer {
        case .stroke(let stroke):
            if isVisible {
                hiddenStrokeIds.remove(stroke.id)
            } else {
                hiddenStrokeIds.insert(stroke.id)
            }
        case .text(let line):
            if isVisible {
                let ids = importedTextLines.filter { $0.documentId == line.documentId }.map(\.id)
                hiddenTextLineIds.subtract(ids)
            } else {
                let ids = importedTextLines.filter { $0.documentId == line.documentId }.map(\.id)
                hiddenTextLineIds.formUnion(ids)
                selectedTextLineIds.subtract(ids)
                if let selectedTextLineId, ids.contains(selectedTextLineId) { self.selectedTextLineId = nil }
                if let editingTextLineId, ids.contains(editingTextLineId) {
                    self.editingTextLineId = nil
                    editingTextLineText = ""
                }
            }
        }
    }

    private func sanitizeLayerGroups() {
        let validIds = Set(canvasLayers.map(\.id))
        for index in layerGroups.indices {
            layerGroups[index].memberLayerIds.removeAll { !validIds.contains($0) }
        }
        layerGroups.removeAll { $0.memberLayerIds.isEmpty }
        selectedLayerIdsForGrouping = selectedLayerIdsForGrouping.intersection(validIds)
        customLayerNames = customLayerNames.filter { validIds.contains($0.key) }
        selectedCanvasLayerIds = selectedCanvasLayerIds.intersection(validIds)
        if let selected = selectedCanvasItem {
            switch selected {
            case .stroke(let id):
                if !strokes.contains(where: { $0.id == id }) { selectedCanvasItem = nil }
            case .text(let id):
                if !importedTextLines.contains(where: { $0.id == id }) { selectedCanvasItem = nil }
            }
        }
        if selectedCanvasItem == nil { syncPrimarySelectionFromSet() }
    }

    private func groupNameBinding(_ groupId: UUID) -> Binding<String> {
        Binding(
            get: {
                layerGroups.first(where: { $0.id == groupId })?.name ?? "Група"
            },
            set: { newValue in
                guard let index = layerGroups.firstIndex(where: { $0.id == groupId }) else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                layerGroups[index].name = trimmed.isEmpty ? "Група \(index + 1)" : newValue
            }
        )
    }

    private func layerNameBinding(_ layer: CanvasLayer) -> Binding<String> {
        Binding(
            get: {
                customLayerNames[layer.id] ?? layer.title
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed == layer.title {
                    customLayerNames.removeValue(forKey: layer.id)
                } else {
                    customLayerNames[layer.id] = newValue
                }
            }
        )
    }

    private var canvasStateFileURL: URL {
        projectStore.canvasFileURL(for: projectId)
    }

    private func saveCanvasState() {
        let state = CanvasStateDTO(
            scale: Double(scale),
            offsetX: Double(offset.width),
            offsetY: Double(offset.height),
            strokes: strokes.map(StrokeItemDTO.init),
            hiddenStrokeIds: Array(hiddenStrokeIds),
            importedTextLines: importedTextLines.map(ImportedTextLineDTO.init),
            hiddenTextLineIds: Array(hiddenTextLineIds),
            layerGroups: layerGroups.map(LayerGroupDTO.init),
            customLayerNames: customLayerNames,
            toolDockPlacement: toolDockPlacement.rawValue
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: canvasStateFileURL, options: .atomic)
        if let png = CanvasPreviewRenderer.pngData(from: state) {
            projectStore.writePreviewPNG(id: projectId, data: png)
        }
        projectStore.touchModified(id: projectId)
    }

    private func loadCanvasStateIfNeeded() {
        guard let data = try? Data(contentsOf: canvasStateFileURL),
              let state = try? JSONDecoder().decode(CanvasStateDTO.self, from: data) else { return }

        scale = CGFloat(state.scale).clamped(to: minScale...maxScale)
        offset = CGSize(width: CGFloat(state.offsetX), height: CGFloat(state.offsetY))
        strokes = state.strokes.map(\.strokeItem)
        hiddenStrokeIds = Set(state.hiddenStrokeIds)
        importedTextLines = state.importedTextLines.map(\.importedTextLine)
        hiddenTextLineIds = Set(state.hiddenTextLineIds)
        layerGroups = state.layerGroups.map(\.layerGroup)
        customLayerNames = state.customLayerNames
        if let raw = state.toolDockPlacement, let p = ToolDockPlacement(rawValue: raw) {
            toolDockPlacement = p
        } else {
            toolDockPlacement = .bottom
        }
        sanitizeLayerGroups()
    }
}

#Preview {
    NavigationStack {
        ContentView(projectId: UUID())
    }
}

//
//  ContentView.swift
//  DocumentsPainter
//
//  Created by Romsya Borysenko on 2/16/26.
//
