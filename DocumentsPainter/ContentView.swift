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
    @State private var artLayers: [CanvasArtLayer] = []
    @State private var activeLayerId: UUID = UUID()
    @State private var hiddenArtLayerIds: Set<UUID> = []
    @State private var selectedTextLineId: UUID?
    @State private var selectedTextLineIds: Set<UUID> = []
    @State private var selectedCanvasItem: SelectedCanvasItem?
    @State private var selectedCanvasLayerIds: Set<String> = []
    @State private var draggingTextLineId: UUID?
    @State private var draggingStrokeId: UUID?
    @State private var resizingCanvasItem = false
    /// Однопальцеве пересування всього полотна (порожній фон), без зміни вмісту.
    @State private var fingerPanningCanvas = false
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
    @State private var showExportPicker = false
    @State private var exportDocument = CanvasExportFileDocument(data: Data())
    @State private var exportContentType: UTType = .png
    @State private var exportDefaultFilename = "Canvas.png"
    @State private var exportErrorMessage: String?
    @State private var showCanvasSettings = false
    @State private var canvasBackground: CanvasBackgroundKind = .dots
    @AppStorage("settings.pencilTap2Action") private var pencilTap2ActionRaw = PencilTapShortcutAction.selectTextTool.rawValue
    @AppStorage("settings.fingerTap2Action") private var fingerTap2ActionRaw = PencilTapShortcutAction.undo.rawValue
    @AppStorage("settings.fingerTap3Action") private var fingerTap3ActionRaw = PencilTapShortcutAction.redo.rawValue
    @AppStorage("settings.fingerTap4Action") private var fingerTap4ActionRaw = PencilTapShortcutAction.selectTextTool.rawValue
    @State private var searchQuery = ""
    @State private var renameArtLayerId: UUID?
    @State private var renameArtLayerDraft: String = ""
    @State private var isCanvasStateDirty = false
    @State private var isPreviewDirty = false
    @State private var lastPreviewRenderAt: Date = .distantPast
    private let minScale: CGFloat = 0.2
    private let maxScale: CGFloat = 8
    private let virtualCanvasSize: CGFloat = 120000
    private let paletteColors: [Color] = [.black, .blue, .green, .yellow, .red]
    private let previewRenderThrottleSeconds: TimeInterval = 6
    private let previewLiveRenderTextLineLimit = 1800
    /// Ширина плаваючої колонки інструментів і слоїв (зверху зліва).
    private let toolDockFloatingColumnWidth: CGFloat = 280
    private static let docxUTType: UTType = UTType("org.openxmlformats.wordprocessingml.document")
        ?? UTType(filenameExtension: "docx")
        ?? .data
    private static let svgUTType: UTType = UTType("public.svg-image")
        ?? UTType("public.svg")
        ?? UTType("image/svg+xml")
        ?? .xml

    var body: some View {
        GeometryReader { geo in
            editorRoot(geo: geo)
        }
    }

    @ViewBuilder
    private func editorRoot(geo: GeometryProxy) -> some View {
        mainEditorContent(geo: geo)
    }

    private func mainEditorContent(geo: GeometryProxy) -> some View {
        editorWithNavigation(geo: geo)
    }

    private func editorMainLayout(geo: GeometryProxy) -> some View {
        canvasStack(size: geo.size)
    }

    private func editorWithSpatialChrome(geo: GeometryProxy) -> some View {
        editorMainLayout(geo: geo)
            .coordinateSpace(name: EditorCanvasCoordinateSpace.name)
            .overlay(alignment: .topTrailing) { editorTopTrailingChrome }
            .overlay(alignment: .topLeading) { editorFloatingToolsAndLayers(geo: geo) }
            .overlay { editorTextCompositionOverlays(geo: geo) }
    }

    private var editorTopTrailingChrome: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 10) {
                ImportButtonView(showImportPicker: $showImportPicker)
                ExportMenuButtonView(exportKinds: CanvasExportKind.allCases, onSelect: requestExport)
                canvasSettingsButton
            }
            SearchPanelView(searchQuery: $searchQuery)
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
    }

    @ViewBuilder
    private func editorFloatingToolsAndLayers(geo: GeometryProxy) -> some View {
        let w = min(toolDockFloatingColumnWidth, geo.size.width - 20)
        let listH = min(320, geo.size.height * 0.42)
        VStack(alignment: .leading, spacing: 10) {
            toolDockContent(paletteMaxWidth: w)
            layersPanelOverlay(panelWidth: w, listMaxHeight: listH)
        }
        .padding(.leading, 12)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func editorTextCompositionOverlays(geo: GeometryProxy) -> some View {
        if editingTextLineId != nil {
            editTextLineOverlay(size: geo.size)
        }
        if isComposingNewText {
            composingTextInlineOverlay(size: geo.size)
        }
        if editingTextLineId == nil, !isComposingNewText {
            selectedCanvasActionsOverlay(size: geo.size)
        }
    }

    private func editorWithFileAndObservers(geo: GeometryProxy) -> some View {
        editorWithSpatialChrome(geo: geo)
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [Self.docxUTType], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                importDOCX(from: url)
            }
            .fileExporter(
                isPresented: $showExportPicker,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportDefaultFilename
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                }
            }
            .alert("Експорт не вдався", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                Text(exportErrorMessage ?? "Спробуй ще раз.")
            }
            .onAppear {
                if let meta = projectStore.metadata(for: projectId) {
                    projectTitle = meta.title
                }
                loadCanvasStateIfNeeded()
                ensureArtLayersReady()
                markCanvasStateDirty(updatePreview: false)
            }
            .onChange(of: scale) { _ in markCanvasStateDirty(updatePreview: false) }
            .onChange(of: offset) { _ in markCanvasStateDirty(updatePreview: false) }
            .onChange(of: hiddenStrokeIds) { _ in markCanvasStateDirty(updatePreview: true) }
            .onChange(of: hiddenTextLineIds) { _ in markCanvasStateDirty(updatePreview: true) }
            .onChange(of: artLayers) { _ in markCanvasStateDirty(updatePreview: true) }
            .onChange(of: activeLayerId) { _ in markCanvasStateDirty(updatePreview: false) }
            .onChange(of: hiddenArtLayerIds) { _ in markCanvasStateDirty(updatePreview: true) }
            .onChange(of: canvasBackground) { _ in markCanvasStateDirty(updatePreview: true) }
            .onReceive(autoSaveTimer) { _ in saveCanvasStateIfNeeded() }
    }

    private func editorWithNavigation(geo: GeometryProxy) -> some View {
        editorWithFileAndObservers(geo: geo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TextField("Назва", text: $projectTitle)
                        .multilineTextAlignment(.center)
                        .submitLabel(.done)
                        .onSubmit { projectStore.renameProject(id: projectId, title: projectTitle) }
                }
            }
            .sheet(isPresented: renameArtLayerSheetPresented) {
                renameArtLayerSheet
            }
            .onDisappear {
                projectStore.renameProject(id: projectId, title: projectTitle)
                saveCanvasStateIfNeeded(force: true)
            }
    }

    private var renameArtLayerSheetPresented: Binding<Bool> {
        Binding(
            get: { renameArtLayerId != nil },
            set: { if !$0 { renameArtLayerId = nil } }
        )
    }

    private var renameArtLayerSheet: some View {
        NavigationStack {
            Form {
                TextField("Назва шару", text: $renameArtLayerDraft)
                    .submitLabel(.done)
                    .onSubmit { commitRenameArtLayer() }
            }
            .navigationTitle("Шар")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") { renameArtLayerId = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { commitRenameArtLayer() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationCompactAdaptation(.sheet)
    }

    private func openRenameArtLayerSheet(_ layer: CanvasArtLayer) {
        renameArtLayerId = layer.id
        renameArtLayerDraft = layer.name
    }

    private func commitRenameArtLayer() {
        guard let id = renameArtLayerId,
              let i = artLayers.firstIndex(where: { $0.id == id }) else {
            renameArtLayerId = nil
            return
        }
        let t = renameArtLayerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            artLayers[i].name = t
        }
        renameArtLayerId = nil
    }

    private func canvasStack(size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return ZStack {
            canvasBackgroundLayer(size: size)
            editorDrawingCanvas(center: center)
            editorTouchSurface()
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    @ViewBuilder
    private func canvasBackgroundLayer(size: CGSize) -> some View {
        let contentStepDots: CGFloat = 20
        let contentStepLines: CGFloat = 28
        let stepDots = max(2, contentStepDots * scale)
        let stepLines = max(2, contentStepLines * scale)

        ZStack {
            Color.white
            switch canvasBackground {
            case .blank:
                EmptyView()
            case .dots:
                Canvas { context, _ in
                    let radius: CGFloat = 0.9
                    let fill = Color.black.opacity(0.16)
                    var x: CGFloat = anchoredPatternStart(offset.width, step: stepDots)
                    while x <= size.width {
                        var y: CGFloat = anchoredPatternStart(offset.height, step: stepDots)
                        while y <= size.height {
                            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                            context.fill(Path(ellipseIn: rect), with: .color(fill))
                            y += stepDots
                        }
                        x += stepDots
                    }
                }
            case .lines:
                Canvas { context, _ in
                    let color = Color.black.opacity(0.08)
                    var y: CGFloat = anchoredPatternStart(offset.height, step: stepLines)
                    while y <= size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(color), lineWidth: 1)
                        y += stepLines
                    }
                }
            case .grid:
                Canvas { context, _ in
                    let color = Color.black.opacity(0.09)
                    var y: CGFloat = anchoredPatternStart(offset.height, step: stepLines)
                    while y <= size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(color), lineWidth: 1)
                        y += stepLines
                    }
                    var x: CGFloat = anchoredPatternStart(offset.width, step: stepLines)
                    while x <= size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(color), lineWidth: 1)
                        x += stepLines
                    }
                }
            }
        }
    }

    private func anchoredPatternStart(_ offsetValue: CGFloat, step: CGFloat) -> CGFloat {
        var start = offsetValue.truncatingRemainder(dividingBy: step)
        if start > 0 { start -= step }
        return start
    }

    private var pencilTap2Action: PencilTapShortcutAction {
        get { PencilTapShortcutAction(rawValue: pencilTap2ActionRaw) ?? .selectTextTool }
        set { pencilTap2ActionRaw = newValue.rawValue }
    }

    private var fingerTap2Action: PencilTapShortcutAction {
        get { PencilTapShortcutAction(rawValue: fingerTap2ActionRaw) ?? .undo }
        set { fingerTap2ActionRaw = newValue.rawValue }
    }

    private var fingerTap3Action: PencilTapShortcutAction {
        get { PencilTapShortcutAction(rawValue: fingerTap3ActionRaw) ?? .redo }
        set { fingerTap3ActionRaw = newValue.rawValue }
    }

    private var fingerTap4Action: PencilTapShortcutAction {
        get { PencilTapShortcutAction(rawValue: fingerTap4ActionRaw) ?? .selectTextTool }
        set { fingerTap4ActionRaw = newValue.rawValue }
    }

    private var canvasSettingsButton: some View {
        Button {
            showCanvasSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Налаштування канви")
        .popover(isPresented: $showCanvasSettings) { canvasSettingsPopoverContent }
    }

    private var canvasSettingsPopoverContent: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    canvasBackgroundSettingsSection
                    applePencilSettingsSection
                    interactionSettingsSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle("Налаштування")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showCanvasSettings = false }
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 320, minHeight: 420)
        .presentationCompactAdaptation(.sheet)
    }

    private var canvasBackgroundSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Фон канви")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CanvasBackgroundKind.allCases) { kind in
                    canvasBackgroundTile(kind: kind)
                }
            }
        }
    }

    private func canvasBackgroundTile(kind: CanvasBackgroundKind) -> some View {
        Button {
            canvasBackground = kind
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                canvasBackgroundSwatch(kind: kind)
                    .frame(height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(canvasBackground == kind ? Color.accentColor : Color.black.opacity(0.1), lineWidth: canvasBackground == kind ? 2 : 1)
                    )
                Text(kind.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(canvasBackground == kind ? Color.accentColor.opacity(0.08) : Color(UIColor.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var applePencilSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple Pencil")
                .font(.subheadline.weight(.semibold))
            PencilTapActionRow(title: "2 тапи олівцем", selection: pencilTap2ActionBinding)
        }
    }

    private var interactionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Interaction")
                .font(.subheadline.weight(.semibold))
            PencilTapActionRow(title: "2 пальці: 1 тап", selection: fingerTap2ActionBinding)
            PencilTapActionRow(title: "3 пальці: 1 тап", selection: fingerTap3ActionBinding)
            PencilTapActionRow(title: "4 пальці: 1 тап", selection: fingerTap4ActionBinding)
        }
    }

    private var pencilTap2ActionBinding: Binding<PencilTapShortcutAction> {
        Binding(
            get: { PencilTapShortcutAction(rawValue: pencilTap2ActionRaw) ?? .selectTextTool },
            set: { pencilTap2ActionRaw = $0.rawValue }
        )
    }

    private var fingerTap2ActionBinding: Binding<PencilTapShortcutAction> {
        Binding(
            get: { PencilTapShortcutAction(rawValue: fingerTap2ActionRaw) ?? .undo },
            set: { fingerTap2ActionRaw = $0.rawValue }
        )
    }

    private var fingerTap3ActionBinding: Binding<PencilTapShortcutAction> {
        Binding(
            get: { PencilTapShortcutAction(rawValue: fingerTap3ActionRaw) ?? .redo },
            set: { fingerTap3ActionRaw = $0.rawValue }
        )
    }

    private var fingerTap4ActionBinding: Binding<PencilTapShortcutAction> {
        Binding(
            get: { PencilTapShortcutAction(rawValue: fingerTap4ActionRaw) ?? .selectTextTool },
            set: { fingerTap4ActionRaw = $0.rawValue }
        )
    }

    @ViewBuilder
    private func canvasBackgroundSwatch(kind: CanvasBackgroundKind) -> some View {
        ZStack {
            Color.white
            switch kind {
            case .blank:
                EmptyView()
            case .dots:
                Canvas { context, size in
                    let spacing: CGFloat = 12
                    let radius: CGFloat = 0.8
                    let fill = Color.black.opacity(0.18)
                    var x: CGFloat = 0
                    while x <= size.width {
                        var y: CGFloat = 0
                        while y <= size.height {
                            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(fill))
                            y += spacing
                        }
                        x += spacing
                    }
                }
            case .lines:
                Canvas { context, size in
                    let spacing: CGFloat = 14
                    let color = Color.black.opacity(0.11)
                    var y: CGFloat = 0
                    while y <= size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(color), lineWidth: 1)
                        y += spacing
                    }
                }
            case .grid:
                Canvas { context, size in
                    let spacing: CGFloat = 14
                    let color = Color.black.opacity(0.11)
                    var y: CGFloat = 0
                    while y <= size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(p, with: .color(color), lineWidth: 1)
                        y += spacing
                    }
                    var x: CGFloat = 0
                    while x <= size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(p, with: .color(color), lineWidth: 1)
                        x += spacing
                    }
                }
            }
        }
    }

    private func editorDrawingCanvas(center: CGPoint) -> some View {
        EditorCompositeCanvasLayer(
            center: center,
            scale: scale,
            offset: offset,
            virtualCanvasSize: virtualCanvasSize,
            artLayers: artLayers,
            strokes: strokes,
            hiddenStrokeIds: hiddenStrokeIds,
            importedTextLines: importedTextLines,
            hiddenTextLineIds: hiddenTextLineIds,
            hiddenArtLayerIds: hiddenArtLayerIds,
            searchQuery: searchQuery,
            selectedTextLineIds: selectedTextLineIds,
            textSelectionRect: interactionMode == .text ? textSelectionRect : cursorSelectionRect,
            currentStroke: currentStroke,
            drawingColor: drawingColor,
            drawingOpacity: drawingOpacity,
            drawingStyle: drawingStyle,
            drawingWidth: drawingWidth,
            drawingTool: drawingTool,
            interactionMode: interactionMode,
            selectedItemBounds: selectedCanvasItemBounds(),
            cursorMarqueeRect: nil
        )
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
                if isPointNearResizeHandle(cp), !selectedCanvasLayerIds.isEmpty {
                    cursorPencilResizing = true
                    lastCursorPencilPointInView = p
                    hasCapturedTextDragUndo = false
                    textSelectionStartPoint = nil
                    textSelectionRect = nil
                    return
                }
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
                guard interactionMode == .text, editingTextLineId == nil, !isComposingNewText else { return }
                let cp = viewToContent(p)
                if let line = textLineAt(contentPoint: cp) {
                    selectCanvasItem(at: cp)
                } else {
                    selectedTextLineId = nil
                    selectedTextLineIds = []
                    selectedCanvasItem = nil
                    selectedCanvasLayerIds = []
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
            onPencilDoubleTap: {
                performShortcutAction(pencilTap2Action)
            },
            onMultiFingerTap: { fingerCount, _ in
                performFingerTapAction(fingerCount: fingerCount)
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
                        if eraseStrokes(at: viewToContent(p)) {
                            markCanvasStateDirty(updatePreview: true)
                        }
                    } else {
                        currentStroke.append(viewToContent(p))
                    }
                    return
                }
                guard interactionMode == .text else { return }
                if cursorPencilResizing {
                    guard let last = lastCursorPencilPointInView else { return }
                    if !hasCapturedTextDragUndo { pushUndoSnapshot(); hasCapturedTextDragUndo = true }
                    let delta = CGSize(width: p.x - last.x, height: p.y - last.y)
                    resizeSelectedCanvasItems(delta: delta)
                    lastCursorPencilPointInView = p
                } else if pencilDraggingTextSelection {
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
                    markCanvasStateDirty(updatePreview: true)
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
                        strokes.append(StrokeItem(layerId: activeLayerId, points: currentStroke, color: drawingColor, width: drawingWidth, style: drawingStyle, opacity: drawingOpacity))
                        markCanvasStateDirty(updatePreview: true)
                    }
                    currentStroke = []
                    return
                }
                guard interactionMode == .text else { return }
                if cursorPencilResizing {
                    cursorPencilResizing = false
                    lastCursorPencilPointInView = nil
                    hasCapturedTextDragUndo = false
                    return
                }
                if pencilDraggingTextSelection {
                    pencilDraggingTextSelection = false
                    lastPencilPointInView = nil
                    hasCapturedTextDragUndo = false
                    return
                }
                defer { textSelectionStartPoint = nil; textSelectionRect = nil }
                guard let rect = textSelectionRect else { return }
                finishTextAreaSelection(rect)
            },
            onFingerPanBegan: { p in
                if interactionMode == .draw, drawingTool == .cursor {
                    fingerPanningCanvas = false
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
                    fingerPanningCanvas = true
                    return
                }
                guard interactionMode == .text, editingTextLineId == nil, !isComposingNewText else { return }
                let cp = viewToContent(p)
                if isPointNearResizeHandle(cp), !selectedCanvasLayerIds.isEmpty {
                    resizingCanvasItem = true
                    hasCapturedTextDragUndo = false
                    return
                }
                if let hit = textLineAt(contentPoint: cp) {
                    if selectedTextLineIds.contains(hit.id) {
                        draggingTextLineId = hit.id
                    } else {
                        selectCanvasItem(at: cp)
                        draggingTextLineId = hit.id
                    }
                    textSelectionStartPoint = nil
                    textSelectionRect = nil
                    hasCapturedTextDragUndo = false
                } else {
                    draggingTextLineId = nil
                    textSelectionStartPoint = nil
                    textSelectionRect = nil
                }
            },
            onFingerPanChanged: { t in
                if interactionMode == .draw, drawingTool == .cursor {
                    if fingerPanningCanvas {
                        offset = CGSize(width: offset.width + t.width, height: offset.height + t.height)
                        return
                    }
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
                if resizingCanvasItem {
                    if !hasCapturedTextDragUndo { pushUndoSnapshot(); hasCapturedTextDragUndo = true }
                    resizeSelectedCanvasItems(delta: t)
                } else if let dragId = draggingTextLineId, importedTextLines.contains(where: { $0.id == dragId }) {
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
                    markCanvasStateDirty(updatePreview: true)
                } else if let start = textSelectionStartPoint {
                    let c = CGPoint(x: start.x + t.width / scale, y: start.y + t.height / scale)
                    textSelectionRect = CGRect(
                        x: min(start.x, c.x),
                        y: min(start.y, c.y),
                        width: abs(c.x - start.x),
                        height: abs(c.y - start.y)
                    )
                } else {
                    offset = CGSize(width: offset.width + t.width, height: offset.height + t.height)
                }
            },
            onFingerPanEnded: {
                if interactionMode == .text, let rect = textSelectionRect {
                    finishTextAreaSelection(rect)
                }
                textSelectionStartPoint = nil
                textSelectionRect = nil
                draggingTextLineId = nil
                draggingStrokeId = nil
                resizingCanvasItem = false
                hasCapturedTextDragUndo = false
                fingerPanningCanvas = false
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

    private func toolDockContent(paletteMaxWidth: CGFloat) -> some View {
        ToolDockContentView(
            paletteMaxWidth: paletteMaxWidth,
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
            onTextMode: { activateTextTool() },
            onToolSelected: { tool in activateDrawingTool(tool) },
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
                if !applySearchHighlightsIfNeeded(with: color) {
                    applyColorToSelectedLayers(color)
                }
            },
            onCustomColorSelected: { color in
                drawingColor = color
                selectedPaletteColorIndex = nil
                if !applySearchHighlightsIfNeeded(with: color) {
                    applyColorToSelectedLayers(color)
                }
            },
            onDrawingStyleChanged: {
                drawingStyle = $0
                applyStyleToSelectedLayers($0)
            }
        )
    }

    private func layersPanelOverlay(panelWidth: CGFloat, listMaxHeight: CGFloat) -> some View {
        ArtLayersPanelView(
            listMaxHeight: listMaxHeight,
            useSidebarColumnWidth: true,
            floatOnCanvas: true,
            panelWidth: panelWidth,
            artLayers: artLayers,
            activeLayerId: $activeLayerId,
            hiddenArtLayerIds: $hiddenArtLayerIds,
            onAddLayer: addArtLayer,
            onDeleteLayer: deleteArtLayer,
            onMoveLayerTowardFront: moveArtLayerTowardFront,
            onMoveLayerTowardBack: moveArtLayerTowardBack,
            onRenameLayer: openRenameArtLayerSheet
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
                SelectableTextView(
                    text: $editingTextLineText,
                    selectedRange: $editingTextSelectionRange,
                    textColor: UIColor(line.color)
                )
                    .frame(width: w, height: 92)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("Зберегти") { commitEditingTextLine() }
                    Button("Скасувати") { editingTextLineId = nil; editingTextLineText = "" }.foregroundStyle(.red)
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
                SelectableTextView(
                    text: $composingText,
                    selectedRange: $composingTextSelectionRange,
                    textColor: .black
                )
                    .frame(width: w, height: 52)
                    .background(Color.white.opacity(0.001))
                HStack(spacing: 10) {
                    Button("Вставити") { commitComposingText() }
                    Button("Скасувати") { cancelComposingText() }.foregroundStyle(.red)
                }
                .font(.caption)
            }
            .position(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func selectedCanvasActionsOverlay(size: CGSize) -> some View {
        if !selectedCanvasLayerIds.isEmpty,
           let bounds = selectedCanvasItemBounds() {
            let o = contentToView(CGPoint(x: bounds.midX, y: bounds.maxY))
            let y = min(max(o.y + 18, 56), size.height - 48)
            let x = min(max(o.x, 70), size.width - 70)

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    deleteSelectedCanvasSelection()
                } label: {
                    Label("Видалити", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                if hasTextLayerSelection {
                    Button {
                        startEditingFirstSelectedTextLine()
                    } label: {
                        Label("Редагувати", systemImage: "pencil")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .position(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var hasTextLayerSelection: Bool {
        !selectedTextLineIdsFromCanvasSelection().isEmpty
    }

    private func startEditingFirstSelectedTextLine() {
        if let current = selectedTextLineId {
            if !selectedTextLineIds.contains(current) {
                selectedTextLineId = selectedTextLineIds.first
            }
        } else {
            selectedTextLineId = selectedTextLineIds.first
        }
        startEditingSelectedTextLine()
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
                lines.append(ImportedTextLine(documentId: documentId, groupId: groupId, order: order, layerId: activeLayerId, text: t, position: CGPoint(x: topLeft.x, y: y), fontSize: 18, color: .black))
                y += 24
                order += 1
            }
            y += 10
        }
        guard !lines.isEmpty else { return }
        pushUndoSnapshot()
        importedTextLines.append(contentsOf: lines)
        markCanvasStateDirty(updatePreview: true)
    }

    private func requestExport(_ kind: CanvasExportKind) {
        let snapshot = CanvasExportSnapshot(
            background: canvasBackground,
            artLayers: artLayers,
            hiddenArtLayerIds: hiddenArtLayerIds,
            strokes: strokes,
            hiddenStrokeIds: hiddenStrokeIds,
            textLines: importedTextLines,
            hiddenTextLineIds: hiddenTextLineIds
        )
        guard let data = CanvasExportRenderer.data(for: kind, snapshot: snapshot) else {
            exportErrorMessage = "Канва порожня або формат не підтримується."
            return
        }
        exportDocument = CanvasExportFileDocument(data: data)
        exportContentType = contentType(for: kind)
        exportDefaultFilename = "\(normalizedExportName()).\(kind.fileExtension)"
        showExportPicker = true
    }

    private func contentType(for kind: CanvasExportKind) -> UTType {
        switch kind {
        case .jpg:
            return .jpeg
        case .png:
            return .png
        case .svg:
            return Self.svgUTType
        case .pdfFlattened, .pdfVector:
            return .pdf
        }
    }

    private func normalizedExportName() -> String {
        let raw = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = raw.isEmpty ? "Canvas" : raw
        let filtered = base.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return filtered
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
        for artLayer in artLayers.reversed() {
            if hiddenArtLayerIds.contains(artLayer.id) { continue }
            let candidates = importedTextLines.filter { $0.layerId == artLayer.id && !hiddenTextLineIds.contains($0.id) }
            if let hit = candidates.reversed().first(where: { boundsForTextLine($0).contains(contentPoint) }) {
                return hit
            }
        }
        return nil
    }

    private func boundsForTextLine(_ line: ImportedTextLine) -> CGRect {
        EditorCanvasHelpers.boundsForTextLine(line)
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
            importedTextLines[idx].backgroundHighlights = []
            markCanvasStateDirty(updatePreview: true)
        }
        editingTextLineId = nil
        editingTextLineText = ""
        editingTextSelectionRange = NSRange(location: 0, length: 0)
    }

    private func deleteSelectedTextLine() {
        guard !selectedTextLineIds.isEmpty else { return }
        pushUndoSnapshot()
        importedTextLines.removeAll { selectedTextLineIds.contains($0.id) }
        markCanvasStateDirty(updatePreview: true)
        sanitizeArtLayers()
        if case .text(let id)? = selectedCanvasItem, !importedTextLines.contains(where: { $0.id == id }) {
            selectedCanvasItem = nil
        }
        selectedTextLineId = nil
        selectedTextLineIds = []
    }

    private func deleteSelectedCanvasSelection() {
        guard !selectedCanvasLayerIds.isEmpty else { return }
        pushUndoSnapshot()

        let selectedStrokeIds = selectedStrokeIdsFromCanvasSelection()
        let selectedLineIdsForDeletion = selectedTextLineIdsFromCanvasSelection()

        if !selectedStrokeIds.isEmpty {
            strokes.removeAll { selectedStrokeIds.contains($0.id) }
            hiddenStrokeIds.subtract(selectedStrokeIds)
        }
        if !selectedLineIdsForDeletion.isEmpty {
            importedTextLines.removeAll { selectedLineIdsForDeletion.contains($0.id) }
            hiddenTextLineIds.subtract(selectedLineIdsForDeletion)
        }
        markCanvasStateDirty(updatePreview: true)

        selectedCanvasItem = nil
        selectedCanvasLayerIds = []
        selectedTextLineId = nil
        selectedTextLineIds = []
        sanitizeArtLayers()
    }

    private func startComposingNewText(at position: CGPoint) {
        composingTextPosition = position
        composingText = ""
        composingTextSelectionRange = NSRange(location: 0, length: 0)
        isComposingNewText = true
        selectedTextLineId = nil
        selectedTextLineIds = []
        selectedCanvasItem = nil
        selectedCanvasLayerIds = []
    }

    private func commitComposingText() {
        guard let position = composingTextPosition else { return }
        let trimmed = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            pushUndoSnapshot()
            let line = ImportedTextLine(text: composingText, position: position, fontSize: 18, color: .black, layerId: activeLayerId)
            importedTextLines.append(line)
            markCanvasStateDirty(updatePreview: true)
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
        markCanvasStateDirty(updatePreview: true)

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
        let picked = importedTextLines.filter { line in
            boundsForTextLine(line).intersects(rect)
        }
        let selectedIds = picked.map(\.id)
        selectedTextLineIds = Set(selectedIds)
        selectedTextLineId = selectedIds.first

        // Синхронізуємо canvas-вибір, щоб підсвітка/resize були однакові в обох режимах.
        selectedCanvasLayerIds = Set(picked.map(canvasSelectionId(forTextLine:)))
        syncPrimarySelectionFromSet()
    }

    private func finishTextAreaSelection(_ rect: CGRect) {
        let normalized = rect.standardized
        guard normalized.width > 3, normalized.height > 3 else { return }
        selectTextFragments(in: normalized)
        guard selectedTextLineIds.isEmpty else { return }
        let composeAnchor = CGPoint(x: normalized.minX + 6, y: normalized.minY + 6)
        startComposingNewText(at: composeAnchor)
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

    private func canvasSelectionId(for stroke: StrokeItem) -> String {
        "stroke-\(stroke.id.uuidString)"
    }

    private func canvasSelectionId(forTextLine line: ImportedTextLine) -> String {
        "textline-\(line.id.uuidString)"
    }

    private func selectedStrokeIdsFromCanvasSelection() -> Set<UUID> {
        Set(selectedCanvasLayerIds.compactMap { id -> UUID? in
            guard id.hasPrefix("stroke-") else { return nil }
            return UUID(uuidString: id.replacingOccurrences(of: "stroke-", with: ""))
        })
    }

    private func selectedTextLineIdsFromCanvasSelection() -> Set<UUID> {
        var result = Set(selectedCanvasLayerIds.compactMap { id -> UUID? in
            guard id.hasPrefix("textline-") else { return nil }
            return UUID(uuidString: id.replacingOccurrences(of: "textline-", with: ""))
        })

        let legacyDocIds: [UUID] = selectedCanvasLayerIds.compactMap { id -> UUID? in
            guard id.hasPrefix("textdoc-") else { return nil }
            return UUID(uuidString: id.replacingOccurrences(of: "textdoc-", with: ""))
        }
        if !legacyDocIds.isEmpty {
            let legacySet = Set(legacyDocIds)
            for line in importedTextLines where legacySet.contains(line.documentId) {
                result.insert(line.id)
            }
        }
        return result
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
            selectedCanvasLayerIds = [canvasSelectionId(forTextLine: line)]
            selectedTextLineId = line.id
            selectedTextLineIds = [line.id]
            return
        }
        if let stroke = strokeAt(contentPoint: contentPoint) {
            selectedCanvasItem = .stroke(stroke.id)
            selectedCanvasLayerIds = [canvasSelectionId(for: stroke)]
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
        for artLayer in artLayers.reversed() {
            if hiddenArtLayerIds.contains(artLayer.id) { continue }
            for stroke in strokes.reversed() where stroke.layerId == artLayer.id && !hiddenStrokeIds.contains(stroke.id) {
                if stroke.points.contains(where: { p in
                    let dx = p.x - contentPoint.x
                    let dy = p.y - contentPoint.y
                    return dx * dx + dy * dy <= threshold2
                }) { return stroke }
            }
        }
        return nil
    }

    private func selectedCanvasItemBounds() -> CGRect? {
        let layerIds = selectedCanvasLayerIds
        if !layerIds.isEmpty {
            let selectedStrokeIds = selectedStrokeIdsFromCanvasSelection()
            let selectedTextLineIds = selectedTextLineIdsFromCanvasSelection()
            let rects: [CGRect] =
                strokes.compactMap { stroke in
                    guard selectedStrokeIds.contains(stroke.id),
                          !hiddenStrokeIds.contains(stroke.id),
                          !hiddenArtLayerIds.contains(stroke.layerId) else { return nil }
                    return strokeBounds(stroke.points)
                } +
                importedTextLines.compactMap { line in
                    guard selectedTextLineIds.contains(line.id),
                          !hiddenTextLineIds.contains(line.id),
                          !hiddenArtLayerIds.contains(line.layerId) else { return nil }
                    return boundsForTextLine(line)
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
        markCanvasStateDirty(updatePreview: true)
    }

    private func moveText(id: UUID, delta: CGSize) {
        guard let index = importedTextLines.firstIndex(where: { $0.id == id }) else { return }
        let dx = delta.width / scale
        let dy = delta.height / scale
        importedTextLines[index].position = CGPoint(
            x: importedTextLines[index].position.x + dx,
            y: importedTextLines[index].position.y + dy
        )
        markCanvasStateDirty(updatePreview: true)
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
        markCanvasStateDirty(updatePreview: true)
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
        let pickedStrokeIds = strokes
            .filter { !hiddenStrokeIds.contains($0.id) && !hiddenArtLayerIds.contains($0.layerId) }
            .filter { strokeBounds($0.points).intersects(rect) }
            .map(\.id)

        let pickedTextLines = importedTextLines
            .filter { !hiddenTextLineIds.contains($0.id) && !hiddenArtLayerIds.contains($0.layerId) }
            .filter { boundsForTextLine($0).intersects(rect) }

        let strokeLayerIds = pickedStrokeIds.map { "stroke-\($0.uuidString)" }
        let textLayerIds = pickedTextLines.map(canvasSelectionId(forTextLine:))
        selectedCanvasLayerIds = Set(strokeLayerIds + textLayerIds)
        selectedTextLineIds = Set(pickedTextLines.map(\.id))
        selectedTextLineId = pickedTextLines.first?.id
        syncPrimarySelectionFromSet()
    }

    private func isPointInsideSelectedCanvasItems(_ point: CGPoint) -> Bool {
        guard !selectedCanvasLayerIds.isEmpty else { return false }
        let selectedStrokeIds = selectedStrokeIdsFromCanvasSelection()
        if strokes.contains(where: {
            selectedStrokeIds.contains($0.id) &&
            !hiddenStrokeIds.contains($0.id) &&
            !hiddenArtLayerIds.contains($0.layerId) &&
            strokeBounds($0.points).contains(point)
        }) {
            return true
        }
        let selectedTextLineIds = selectedTextLineIdsFromCanvasSelection()
        return importedTextLines.contains(where: {
            selectedTextLineIds.contains($0.id) &&
            !hiddenTextLineIds.contains($0.id) &&
            !hiddenArtLayerIds.contains($0.layerId) &&
            boundsForTextLine($0).contains(point)
        })
    }

    private func moveSelectedCanvasItems(delta: CGSize) {
        let dx = delta.width / scale
        let dy = delta.height / scale
        let selectedStrokeIds = selectedStrokeIdsFromCanvasSelection()
        let selectedTextLineIds = selectedTextLineIdsFromCanvasSelection()
        for i in strokes.indices {
            guard selectedStrokeIds.contains(strokes[i].id) else { continue }
            strokes[i].points = strokes[i].points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
        for i in importedTextLines.indices {
            guard selectedTextLineIds.contains(importedTextLines[i].id) else { continue }
            importedTextLines[i].position = CGPoint(x: importedTextLines[i].position.x + dx, y: importedTextLines[i].position.y + dy)
        }
        markCanvasStateDirty(updatePreview: true)
    }

    private func resizeSelectedCanvasItems(delta: CGSize) {
        guard let bounds = selectedCanvasItemBounds() else { return }
        let amount = (delta.width + delta.height) / 220
        let factor = (1 + amount).clamped(to: 0.4...2.2)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let selectedStrokeIds = selectedStrokeIdsFromCanvasSelection()
        let selectedTextLineIds = selectedTextLineIdsFromCanvasSelection()

        for i in strokes.indices {
            guard selectedStrokeIds.contains(strokes[i].id) else { continue }
            strokes[i].points = strokes[i].points.map {
                CGPoint(x: center.x + ($0.x - center.x) * factor, y: center.y + ($0.y - center.y) * factor)
            }
            strokes[i].width = (strokes[i].width * factor).clamped(to: 1...48)
        }
        for i in importedTextLines.indices {
            guard selectedTextLineIds.contains(importedTextLines[i].id) else { continue }
            importedTextLines[i].position = CGPoint(
                x: center.x + (importedTextLines[i].position.x - center.x) * factor,
                y: center.y + (importedTextLines[i].position.y - center.y) * factor
            )
            importedTextLines[i].fontSize = (importedTextLines[i].fontSize * factor).clamped(to: 8...120)
        }
        syncPrimarySelectionFromSet()
        markCanvasStateDirty(updatePreview: true)
    }

    private func applyWidthToSelectedLayers(_ width: CGFloat) {
        guard interactionMode == .draw, drawingTool == .cursor, !selectedCanvasLayerIds.isEmpty else { return }
        let selectedStrokeIds = selectedStrokeIdsFromCanvasSelection()
        for i in strokes.indices {
            guard selectedStrokeIds.contains(strokes[i].id) else { continue }
            strokes[i].width = width
        }
        markCanvasStateDirty(updatePreview: true)
    }

    private func applyOpacityToSelectedLayers(_ opacity: Double) {
        guard interactionMode == .draw, drawingTool == .cursor, !selectedCanvasLayerIds.isEmpty else { return }
        let selectedStrokeIds = selectedStrokeIdsFromCanvasSelection()
        for i in strokes.indices {
            guard selectedStrokeIds.contains(strokes[i].id) else { continue }
            strokes[i].opacity = opacity
        }
        markCanvasStateDirty(updatePreview: true)
    }

    private func applyColorToSelectedLayers(_ color: Color) {
        guard interactionMode == .draw, drawingTool == .cursor, !selectedCanvasLayerIds.isEmpty else { return }
        let selectedStrokeIds = selectedStrokeIdsFromCanvasSelection()
        let selectedTextLineIds = selectedTextLineIdsFromCanvasSelection()
        for i in strokes.indices {
            guard selectedStrokeIds.contains(strokes[i].id) else { continue }
            strokes[i].color = color
        }
        for i in importedTextLines.indices {
            guard selectedTextLineIds.contains(importedTextLines[i].id) else { continue }
            importedTextLines[i].color = color
        }
        markCanvasStateDirty(updatePreview: true)
    }

    private func applyStyleToSelectedLayers(_ style: DrawingStyle) {
        guard interactionMode == .draw, drawingTool == .cursor, !selectedCanvasLayerIds.isEmpty else { return }
        let selectedStrokeIds = selectedStrokeIdsFromCanvasSelection()
        for i in strokes.indices {
            guard selectedStrokeIds.contains(strokes[i].id) else { continue }
            strokes[i].style = style
        }
        markCanvasStateDirty(updatePreview: true)
    }

    private func syncPrimarySelectionFromSet() {
        selectedTextLineIds = selectedTextLineIdsFromCanvasSelection()
        if let current = selectedTextLineId {
            if !selectedTextLineIds.contains(current) {
                selectedTextLineId = selectedTextLineIds.first
            }
        } else {
            selectedTextLineId = selectedTextLineIds.first
        }

        guard selectedCanvasLayerIds.count == 1, let id = selectedCanvasLayerIds.first else {
            selectedCanvasItem = nil
            return
        }
        if let uuid = UUID(uuidString: id.replacingOccurrences(of: "stroke-", with: "")), id.hasPrefix("stroke-") {
            selectedCanvasItem = .stroke(uuid)
            return
        }
        if let uuid = UUID(uuidString: id.replacingOccurrences(of: "textline-", with: "")), id.hasPrefix("textline-") {
            if importedTextLines.contains(where: { $0.id == uuid }) {
                selectedCanvasItem = .text(uuid)
                selectedTextLineId = uuid
                selectedTextLineIds = [uuid]
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
        markCanvasStateDirty(updatePreview: true)
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
        var toRemove: UUID?
        outer: for artLayer in artLayers.reversed() {
            if hiddenArtLayerIds.contains(artLayer.id) { continue }
            for stroke in strokes.reversed() where stroke.layerId == artLayer.id && !hiddenStrokeIds.contains(stroke.id) {
                if stroke.points.contains(where: { p in
                    let dx = p.x - contentPoint.x
                    let dy = p.y - contentPoint.y
                    return dx * dx + dy * dy <= r2
                }) {
                    toRemove = stroke.id
                    break outer
                }
            }
        }
        guard let id = toRemove else { return false }
        let old = strokes.count
        strokes.removeAll { $0.id == id }
        markCanvasStateDirty(updatePreview: true)
        return strokes.count != old
    }

    private func currentSnapshot() -> CanvasSnapshot {
        CanvasSnapshot(
            strokes: strokes,
            importedTextLines: importedTextLines,
            artLayers: artLayers,
            activeLayerId: activeLayerId,
            hiddenArtLayerIds: hiddenArtLayerIds
        )
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
        artLayers = snapshot.artLayers
        activeLayerId = snapshot.activeLayerId
        hiddenArtLayerIds = snapshot.hiddenArtLayerIds
        hiddenStrokeIds = hiddenStrokeIds.intersection(Set(strokes.map(\.id)))
        hiddenTextLineIds = hiddenTextLineIds.intersection(Set(importedTextLines.map(\.id)))
        sanitizeArtLayers()
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
        fingerPanningCanvas = false
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

    @discardableResult
    private func applySearchHighlightsIfNeeded(with color: Color) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }

        let visibleLayerIds = Set(artLayers.filter { !hiddenArtLayerIds.contains($0.id) }.map(\.id))
        let targetIndices: [Int] = importedTextLines.indices.filter { idx in
            let line = importedTextLines[idx]
            guard !hiddenTextLineIds.contains(line.id), visibleLayerIds.contains(line.layerId) else { return false }
            return !searchRanges(in: line.text, query: query).isEmpty
        }
        guard !targetIndices.isEmpty else { return false }

        pushUndoSnapshot()
        for idx in targetIndices {
            let line = importedTextLines[idx]
            let matches = searchRanges(in: line.text, query: query)
            let wholeWordMatches = EditorCanvasHelpers.expandRangesToWholeWords(matches, in: line.text)
            importedTextLines[idx].backgroundHighlights = EditorCanvasHelpers.mergedHighlights(
                existing: line.backgroundHighlights,
                addingRanges: wholeWordMatches,
                color: color,
                text: line.text
            )
        }
        markCanvasStateDirty(updatePreview: true)
        return true
    }

    private func textWidthPrefix(_ text: String, length: Int, fontSize: CGFloat) -> CGFloat {
         let ns = text as NSString
        let l = min(max(0, length), ns.length)
        return (ns.substring(to: l) as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width
    }

    private func performFingerTapAction(fingerCount: Int) {
        let action: PencilTapShortcutAction
        switch fingerCount {
        case 2: action = fingerTap2Action
        case 3: action = fingerTap3Action
        case 4: action = fingerTap4Action
        default: return
        }
        performShortcutAction(action)
    }

    private func performShortcutAction(_ action: PencilTapShortcutAction) {
        switch action {
        case .none:
            return
        case .undo:
            undo()
        case .redo:
            redo()
        case .selectTextTool:
            activateTextTool()
        case .selectCursorTool:
            activateDrawingTool(.cursor)
        case .selectPencilTool:
            activateDrawingTool(.pencil)
        case .selectPenTool:
            activateDrawingTool(.pen)
        case .selectMarkerTool:
            activateDrawingTool(.marker)
        case .selectEraserTool:
            activateDrawingTool(.eraser)
        }
    }

    private func activateTextTool() {
        fingerPanningCanvas = false
        interactionMode = .text
    }

    private func activateDrawingTool(_ tool: DrawingToolKind) {
        fingerPanningCanvas = false
        interactionMode = .draw
        drawingTool = tool
        if tool != .eraser, tool != .cursor { drawingWidth = tool.defaultWidth }
        if tool != .cursor {
            selectedCanvasItem = nil
            selectedCanvasLayerIds = []
        }
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

    private func isRenderableCanvasLayer(_ layer: CanvasLayer) -> Bool {
        switch layer {
        case .stroke(let stroke):
            return !hiddenStrokeIds.contains(stroke.id) && !hiddenArtLayerIds.contains(stroke.layerId)
        case .text(let line):
            guard !hiddenArtLayerIds.contains(line.layerId) else { return false }
            let docIds = importedTextLines.filter { $0.documentId == line.documentId }.map(\.id)
            return !docIds.allSatisfy { hiddenTextLineIds.contains($0) }
        }
    }

    private func ensureArtLayersReady() {
        if artLayers.isEmpty {
            let id = UUID()
            artLayers = [CanvasArtLayer(id: id, name: "Шар 1")]
            activeLayerId = id
        }
        if !artLayers.contains(where: { $0.id == activeLayerId }) {
            activeLayerId = artLayers[0].id
        }
        let validLayerIds = Set(artLayers.map(\.id))
        hiddenArtLayerIds = hiddenArtLayerIds.intersection(validLayerIds)
    }

    private func sanitizeArtLayers() {
        ensureArtLayersReady()
        let validLayerIds = Set(artLayers.map(\.id))
        let fallback = artLayers[0].id
        for i in strokes.indices where !validLayerIds.contains(strokes[i].layerId) {
            strokes[i].layerId = fallback
        }
        for i in importedTextLines.indices where !validLayerIds.contains(importedTextLines[i].layerId) {
            importedTextLines[i].layerId = fallback
        }
        hiddenStrokeIds = hiddenStrokeIds.intersection(Set(strokes.map(\.id)))
        hiddenTextLineIds = hiddenTextLineIds.intersection(Set(importedTextLines.map(\.id)))
        let validIds = Set(strokes.map(canvasSelectionId(for:))) 
            .union(importedTextLines.map(canvasSelectionId(forTextLine:)))
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
        markCanvasStateDirty(updatePreview: true)
    }

    private func addArtLayer() {
        pushUndoSnapshot()
        let n = artLayers.count + 1
        let layer = CanvasArtLayer(id: UUID(), name: "Шар \(n)")
        artLayers.append(layer)
        activeLayerId = layer.id
        markCanvasStateDirty(updatePreview: true)
    }

    private func deleteArtLayer(_ layer: CanvasArtLayer) {
        guard let idx = artLayers.firstIndex(where: { $0.id == layer.id }) else { return }
        pushUndoSnapshot()

        let removedId = layer.id
        strokes.removeAll { $0.layerId == removedId }
        importedTextLines.removeAll { $0.layerId == removedId }

        if artLayers.count == 1 {
            // Для останнього шару видалення має реально очищати канву.
            let replacement = CanvasArtLayer(id: UUID(), name: "Шар 1")
            artLayers = [replacement]
            activeLayerId = replacement.id
        } else {
            artLayers.remove(at: idx)
            let fallbackIndex = min(idx, artLayers.count - 1)
            let fallbackId = artLayers[fallbackIndex].id
            if activeLayerId == removedId { activeLayerId = fallbackId }
        }

        hiddenArtLayerIds.remove(removedId)
        sanitizeArtLayers()
        markCanvasStateDirty(updatePreview: true)
    }

    private func moveArtLayerTowardFront(_ index: Int) {
        guard index < artLayers.count - 1 else { return }
        pushUndoSnapshot()
        artLayers.swapAt(index, index + 1)
        markCanvasStateDirty(updatePreview: true)
    }

    private func moveArtLayerTowardBack(_ index: Int) {
        guard index > 0 else { return }
        pushUndoSnapshot()
        artLayers.swapAt(index, index - 1)
        markCanvasStateDirty(updatePreview: true)
    }

    private var canvasStateFileURL: URL {
        projectStore.canvasFileURL(for: projectId)
    }

    private func markCanvasStateDirty(updatePreview: Bool) {
        isCanvasStateDirty = true
        if updatePreview {
            isPreviewDirty = true
        }
    }

    private func saveCanvasStateIfNeeded(force: Bool = false) {
        guard force || isCanvasStateDirty else { return }
        let state = CanvasStateDTO(
            scale: Double(scale),
            offsetX: Double(offset.width),
            offsetY: Double(offset.height),
            strokes: strokes.map(StrokeItemDTO.init),
            hiddenStrokeIds: Array(hiddenStrokeIds),
            importedTextLines: importedTextLines.map(ImportedTextLineDTO.init),
            hiddenTextLineIds: Array(hiddenTextLineIds),
            layerGroups: [],
            customLayerNames: [:],
            toolDockPlacement: nil,
            canvasBackground: canvasBackground.rawValue,
            artLayers: artLayers.map(CanvasArtLayerDTO.init),
            activeLayerId: activeLayerId,
            hiddenArtLayerIds: Array(hiddenArtLayerIds)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: canvasStateFileURL, options: .atomic)
        isCanvasStateDirty = false

        if shouldRenderPreview(for: state, force: force),
           let png = CanvasPreviewRenderer.pngData(from: state) {
            projectStore.writePreviewPNG(id: projectId, data: png)
            lastPreviewRenderAt = Date()
            isPreviewDirty = false
        }
        projectStore.touchModified(id: projectId)
    }

    private func shouldRenderPreview(for state: CanvasStateDTO, force: Bool) -> Bool {
        if force { return true }
        guard isPreviewDirty else { return false }
        if state.importedTextLines.count > previewLiveRenderTextLineLimit {
            return false
        }
        let elapsed = Date().timeIntervalSince(lastPreviewRenderAt)
        return elapsed >= previewRenderThrottleSeconds
    }

    private func loadCanvasStateIfNeeded() {
        guard let data = try? Data(contentsOf: canvasStateFileURL),
              let state = try? JSONDecoder().decode(CanvasStateDTO.self, from: data) else {
            return
        }

        scale = CGFloat(state.scale).clamped(to: minScale...maxScale)
        offset = CGSize(width: CGFloat(state.offsetX), height: CGFloat(state.offsetY))

        var loadedArt = (state.artLayers ?? []).map(\.artLayer)
        let fallback: UUID
        if loadedArt.isEmpty {
            fallback = UUID()
            loadedArt = [CanvasArtLayer(id: fallback, name: "Шар 1")]
        } else {
            fallback = loadedArt[0].id
        }
        artLayers = loadedArt
        strokes = state.strokes.map { $0.strokeItem(fallbackLayerId: fallback) }
        hiddenStrokeIds = Set(state.hiddenStrokeIds)
        importedTextLines = state.importedTextLines.map { $0.importedTextLine(fallbackLayerId: fallback) }
        hiddenTextLineIds = Set(state.hiddenTextLineIds)
        if let aid = state.activeLayerId, loadedArt.contains(where: { $0.id == aid }) {
            activeLayerId = aid
        } else {
            activeLayerId = loadedArt[0].id
        }
        canvasBackground = CanvasBackgroundKind.decode(from: state.canvasBackground)
        hiddenArtLayerIds = Set(state.hiddenArtLayerIds ?? []).intersection(Set(loadedArt.map(\.id)))
        sanitizeArtLayers()
        isCanvasStateDirty = false
        isPreviewDirty = false
    }
}

private struct PencilTapActionRow: View {
    let title: String
    @Binding var selection: PencilTapShortcutAction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PencilTapShortcutAction.allCases) { action in
                        shortcutOptionButton(action)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func shortcutOptionButton(_ action: PencilTapShortcutAction) -> some View {
        let isSelected = selection == action
        return Button {
            selection = action
        } label: {
            VStack(spacing: 7) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 68, height: 68)
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                    .background(
                        Circle()
                            .fill(isSelected ? Color(UIColor.systemBackground) : Color(UIColor.tertiarySystemBackground))
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.primary : Color(UIColor.separator).opacity(0.5), lineWidth: isSelected ? 2.2 : 1)
                    )

                Text(action.shortTitle)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 86)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
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
