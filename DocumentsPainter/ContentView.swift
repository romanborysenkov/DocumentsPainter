import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ZIPFoundation
import Foundation

enum DrawingStyle: String, CaseIterable, Identifiable {
    case solid = "Суцільна"
    case dashed = "Пунктир"
    case dotted = "Крапки"
    var id: String { rawValue }
}

enum DrawingToolKind: String, CaseIterable, Identifiable {
    case pencil
    case pen
    case marker
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pencil: return "Олівець"
        case .pen: return "Ручка"
        case .marker: return "Маркер"
        case .eraser: return "Гумка"
        }
    }

    var icon: String {
        switch self {
        case .pencil: return "pencil"
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .pencil: return 3
        case .pen: return 5
        case .marker: return 12
        case .eraser: return 18
        }
    }

    var opacity: Double {
        switch self {
        case .marker: return 0.35
        default: return 1
        }
    }
}

enum InteractionMode: String, CaseIterable, Identifiable {
    case draw = "Малювання"
    case text = "Текст"
    var id: String { rawValue }
}

struct StrokeItem {
    var points: [CGPoint]
    var color: Color
    var width: CGFloat
    var style: DrawingStyle
    var opacity: Double
}

struct ImportedTextLine: Identifiable {
    var id: UUID = UUID()
    var documentId: UUID = UUID()
    var groupId: UUID = UUID()
    var order: Int = 0
    var text: String
    var position: CGPoint
    var fontSize: CGFloat
    var color: Color
}

extension ImportedTextLine {
    func split(at range: NSRange) -> (left: ImportedTextLine?, selected: ImportedTextLine?, right: ImportedTextLine?) {
        let nsText = text as NSString
        let length = nsText.length
        guard range.location >= 0, range.length >= 0, range.location + range.length <= length else {
            return (self, nil, nil)
        }
        let leftText = nsText.substring(to: range.location)
        let selectedText = nsText.substring(with: range)
        let rightText = nsText.substring(from: range.location + range.length)

        let font = UIFont.systemFont(ofSize: fontSize)
        let leftWidth = (leftText as NSString).size(withAttributes: [.font: font]).width
        let selectedWidth = (selectedText as NSString).size(withAttributes: [.font: font]).width
        let spacing = max(8, fontSize * 0.6)

        let left = leftText.isEmpty ? nil : ImportedTextLine(
            id: UUID(), documentId: documentId, groupId: groupId, order: order, text: leftText,
            position: position, fontSize: fontSize, color: color
        )
        let selected = selectedText.isEmpty ? nil : ImportedTextLine(
            id: UUID(), documentId: documentId, groupId: groupId, order: order + 1, text: selectedText,
            position: CGPoint(x: position.x + leftWidth + spacing, y: position.y), fontSize: fontSize, color: color
        )
        let right = rightText.isEmpty ? nil : ImportedTextLine(
            id: UUID(), documentId: documentId, groupId: groupId, order: order + 2, text: rightText,
            position: CGPoint(x: position.x + leftWidth + selectedWidth + spacing * 2, y: position.y), fontSize: fontSize, color: color
        )
        return (left, selected, right)
    }
}

private struct CanvasSnapshot {
    var strokes: [StrokeItem]
    var importedTextLines: [ImportedTextLine]
}

struct ContentView: View {
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    @State private var currentStroke: [CGPoint] = []
    @State private var strokes: [StrokeItem] = []

    @State private var importedTextLines: [ImportedTextLine] = []
    @State private var selectedTextLineId: UUID?
    @State private var selectedTextLineIds: Set<UUID> = []
    @State private var draggingTextLineId: UUID?

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

    private let minScale: CGFloat = 0.2
    private let maxScale: CGFloat = 8
    private let virtualCanvasSize: CGFloat = 120000
    private let paletteColors: [Color] = [.black, .blue, .green, .yellow, .red]
    private static let docxUTType: UTType = UTType("org.openxmlformats.wordprocessingml.document")
        ?? UTType(filenameExtension: "docx")
        ?? .data

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Color.white.ignoresSafeArea()

                Canvas { context, _ in
                    let virtualRect = CGRect(
                        x: center.x - (virtualCanvasSize / 2) * scale + offset.width,
                        y: center.y - (virtualCanvasSize / 2) * scale + offset.height,
                        width: virtualCanvasSize * scale,
                        height: virtualCanvasSize * scale
                    )
                    context.fill(Path(virtualRect), with: .color(.white))
                    context.stroke(Path(virtualRect), with: .color(.gray.opacity(0.08)), lineWidth: 1)

                    for stroke in strokes {
                        guard stroke.points.count > 1 else { continue }
                        var path = Path()
                        path.move(to: contentToView(stroke.points[0]))
                        for p in stroke.points.dropFirst() { path.addLine(to: contentToView(p)) }
                        context.stroke(
                            path,
                            with: .color(stroke.color.opacity(stroke.opacity)),
                            style: strokeStyle(for: stroke.style, width: stroke.width * scale)
                        )
                    }

                    if currentStroke.count > 1 {
                        var path = Path()
                        path.move(to: contentToView(currentStroke[0]))
                        for p in currentStroke.dropFirst() { path.addLine(to: contentToView(p)) }
                        context.stroke(
                            path,
                            with: .color(drawingColor.opacity(drawingOpacity)),
                            style: strokeStyle(for: drawingStyle, width: drawingWidth * scale)
                        )
                    }

                    for line in importedTextLines {
                        let matches = searchRanges(in: line.text, query: searchQuery)
                        for m in matches {
                            let startX = textWidthPrefix(line.text, length: m.location, fontSize: line.fontSize)
                            let endX = textWidthPrefix(line.text, length: m.location + m.length, fontSize: line.fontSize)
                            let contentRect = CGRect(x: line.position.x + startX, y: line.position.y, width: max(1, endX - startX), height: line.fontSize * 1.3)
                            let o = contentToView(CGPoint(x: contentRect.minX, y: contentRect.minY))
                            let vr = CGRect(x: o.x, y: o.y, width: contentRect.width * scale, height: contentRect.height * scale)
                            context.fill(Path(roundedRect: vr.insetBy(dx: -1, dy: -1), cornerRadius: 3), with: .color(.yellow.opacity(0.45)))
                        }

                        context.draw(
                            Text(line.text).font(.system(size: line.fontSize * scale)).foregroundColor(line.color),
                            at: contentToView(line.position),
                            anchor: .topLeading
                        )
                    }

                    for line in importedTextLines where selectedTextLineIds.contains(line.id) {
                        let b = boundsForTextLine(line)
                        let o = contentToView(CGPoint(x: b.minX, y: b.minY))
                        let vr = CGRect(x: o.x, y: o.y, width: b.width * scale, height: b.height * scale)
                        context.stroke(Path(roundedRect: vr.insetBy(dx: -4, dy: -4), cornerRadius: 4), with: .color(.blue), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }

                    if let rect = textSelectionRect {
                        let o = contentToView(CGPoint(x: rect.minX, y: rect.minY))
                        let vr = CGRect(x: o.x, y: o.y, width: rect.width * scale, height: rect.height * scale)
                        let path = Path(roundedRect: vr, cornerRadius: 2)
                        context.fill(path, with: .color(.blue.opacity(0.08)))
                        context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }

                TouchSurfaceView(
                    onPencilBegan: { p in
                        if interactionMode == .draw {
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
                            if !hasCapturedTextDragUndo { pushUndoSnapshot(); hasCapturedTextDragUndo = true }
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
                        if interactionMode == .draw {
                            offset = CGSize(width: offset.width + t.width, height: offset.height + t.height)
                            return
                        }
                        guard interactionMode == .text, editingTextLineId == nil, !isComposingNewText else { return }
                        if let dragId = draggingTextLineId, importedTextLines.contains(where: { $0.id == dragId }) {
                            if !hasCapturedTextDragUndo { pushUndoSnapshot(); hasCapturedTextDragUndo = true }
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
            .overlay(alignment: .topTrailing) { fileAndSearchPanel.padding(12) }
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    bottomToolDock

                    if interactionMode == .text, !selectedTextLineIds.isEmpty, editingTextLineId == nil {
                        HStack(spacing: 12) {
                            Button("Редагувати") { if selectedTextLineIds.count == 1 { startEditingSelectedTextLine() } }
                                .disabled(selectedTextLineIds.count != 1)
                            Button("Видалити", role: .destructive) { deleteSelectedTextLine() }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.bottom, 24)
            }
            .overlay { if editingTextLineId != nil { editTextLineOverlay(size: geo.size) } }
            .overlay { if isComposingNewText { composingTextInlineOverlay(size: geo.size) } }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [Self.docxUTType], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                importDOCX(from: url)
            }
        }
    }

    private var bottomToolDock: some View {
        HStack(spacing: 10) {
            /*Picker("Режим", selection: $interactionMode) {
                ForEach(InteractionMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)*/

            Divider()
                .frame(height: 36)

            Button { undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(UIColor.systemBackground).opacity(0.72)))
            }
            .buttonStyle(.plain)
            .disabled(undoStack.isEmpty)
            .opacity(undoStack.isEmpty ? 0.45 : 1)
            .accessibilityLabel("Скасувати")

            Button { redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(UIColor.systemBackground).opacity(0.72)))
            }
            .buttonStyle(.plain)
            .disabled(redoStack.isEmpty)
            .opacity(redoStack.isEmpty ? 0.45 : 1)
            .accessibilityLabel("Повторити")

            Divider()
                .frame(height: 36)

            Button {
                interactionMode = .text
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "text.cursor")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(interactionMode == .text ? Color.accentColor : Color.primary)
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(interactionMode == .text ? Color.accentColor.opacity(0.13) : Color(UIColor.systemBackground).opacity(0.7))
                        )
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(interactionMode == .text ? Color.accentColor : .clear)
                        .offset(y: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Текст")

            ForEach(DrawingToolKind.allCases) { tool in
                Button {
                    interactionMode = .draw
                    drawingTool = tool
                    if tool != .eraser { drawingWidth = tool.defaultWidth }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(interactionMode == .draw && drawingTool == tool ? Color.accentColor : Color.primary)
                            .frame(width: 46, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(interactionMode == .draw && drawingTool == tool ? Color.accentColor.opacity(0.13) : Color(UIColor.systemBackground).opacity(0.7))
                            )
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(interactionMode == .draw && drawingTool == tool ? Color.accentColor : .clear)
                            .offset(y: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tool.title)
            }

            Divider()
                .frame(height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("Товщина \(Int(drawingWidth))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $drawingWidth, in: 1...24, step: 1)
                    .frame(width: 120)
            }

            Divider()
                .frame(height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("Opacity \(Int(drawingOpacity * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $drawingOpacity, in: 0.05...1, step: 0.05) {
                    Text("Opacity")
                } minimumValueLabel: {
                    Image(systemName: "circle.lefthalf.filled")
                } maximumValueLabel: {
                    Image(systemName: "circle.fill")
                }
                .frame(width: 140)
            }

            Divider()
                .frame(height: 36)

            ForEach(Array(paletteColors.enumerated()), id: \.offset) { idx, color in
                Button {
                    drawingColor = color
                    selectedPaletteColorIndex = idx
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                                .padding(2)
                        )
                        .overlay(
                            Circle()
                                .stroke(selectedPaletteColorIndex == idx ? Color.accentColor : .clear, lineWidth: 3)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Колір \(idx + 1)")
            }

            ColorPicker(
                "",
                selection: Binding(
                    get: { drawingColor },
                    set: { newColor in
                        drawingColor = newColor
                        selectedPaletteColorIndex = nil
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))

            Divider()
                .frame(height: 36)

            Menu {
                Picker("Стиль", selection: $drawingStyle) {
                    ForEach(DrawingStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "ruler")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 46, height: 46)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.systemBackground).opacity(0.7)))
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.clear)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Лінійка та стиль")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var fileAndSearchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showImportPicker = true } label: { Label("Імпорт DOCX", systemImage: "doc.badge.plus") }
            VStack(alignment: .leading, spacing: 6) {
                Text("Пошук")
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Пошук у тексті", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(width: 240)
                .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
        importedTextLines.last { boundsForTextLine($0).contains(contentPoint) }
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

    private func eraseStrokes(at contentPoint: CGPoint) -> Bool {
        let radius = max(8, drawingWidth) / scale
        let r2 = radius * radius
        let old = strokes.count
        strokes.removeAll { stroke in
            stroke.points.contains {
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
        currentStroke = []
        selectedTextLineId = nil
        selectedTextLineIds = []
        editingTextLineId = nil
        editingTextLineText = ""
        isComposingNewText = false
        composingText = ""
        composingTextPosition = nil
        draggingTextLineId = nil
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
}

private enum DocxPlainTextParser {
    static func parseParagraphs(from url: URL) throws -> [String] {
        guard let archive = Archive(url: url, accessMode: .read), let entry = archive["word/document.xml"] else { return [] }
        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }
        let delegate = DocxDocumentXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.paragraphs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private final class DocxDocumentXMLDelegate: NSObject, XMLParserDelegate {
        var paragraphs: [String] = []
        private var inText = false
        private var currentParagraph = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
            switch name {
            case "p": currentParagraph = ""
            case "t": inText = true
            case "tab": currentParagraph.append("    ")
            case "br": currentParagraph.append("\n")
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { currentParagraph.append(string) }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
            switch name {
            case "t": inText = false
            case "p":
                paragraphs.append(currentParagraph)
                currentParagraph = ""
            default: break
            }
        }
    }
}

private struct TouchSurfaceView: UIViewRepresentable {
    var onPencilBegan: (CGPoint) -> Void
    var onSingleTap: (CGPoint) -> Void
    var onDoubleTap: (CGPoint) -> Void
    var onPencilDoubleTap: (CGPoint) -> Void
    var onPencilMoved: (CGPoint) -> Void
    var onPencilEnded: () -> Void
    var onFingerPanBegan: (CGPoint) -> Void
    var onFingerPanChanged: (CGSize) -> Void
    var onFingerPanEnded: () -> Void
    var onTwoFingerPanChanged: (CGSize) -> Void
    var onPinchChanged: (_ scaleDelta: CGFloat, _ center: CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pencilPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePencilPan(_:)))
        pencilPan.minimumNumberOfTouches = 1
        pencilPan.maximumNumberOfTouches = 1
        pencilPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pencilPan.delegate = context.coordinator

        let fingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFingerPan(_:)))
        fingerPan.minimumNumberOfTouches = 1
        fingerPan.maximumNumberOfTouches = 1
        fingerPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        fingerPan.delegate = context.coordinator

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.numberOfTouchesRequired = 1
        singleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        singleTap.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        doubleTap.delegate = context.coordinator
        singleTap.require(toFail: doubleTap)

        let pencilDoubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePencilDoubleTap(_:)))
        pencilDoubleTap.numberOfTapsRequired = 2
        pencilDoubleTap.numberOfTouchesRequired = 1
        pencilDoubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pencilDoubleTap.delegate = context.coordinator

        let navPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        navPan.minimumNumberOfTouches = 2
        navPan.maximumNumberOfTouches = 2
        navPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        navPan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.delegate = context.coordinator

        view.addGestureRecognizer(pencilPan)
        view.addGestureRecognizer(fingerPan)
        view.addGestureRecognizer(singleTap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(pencilDoubleTap)
        view.addGestureRecognizer(navPan)
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TouchSurfaceView
        init(_ parent: TouchSurfaceView) { self.parent = parent }

        @objc func handlePencilPan(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began: parent.onPencilBegan(p)
            case .changed: parent.onPencilMoved(p)
            case .ended, .cancelled, .failed: parent.onPencilEnded()
            default: break
            }
        }

        @objc func handleFingerPan(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began:
                parent.onFingerPanBegan(p)
            case .changed:
                let t = g.translation(in: g.view)
                parent.onFingerPanChanged(CGSize(width: t.x, height: t.y))
                g.setTranslation(.zero, in: g.view)
            case .ended, .cancelled, .failed:
                parent.onFingerPanEnded()
            default:
                break
            }
        }

        @objc func handleSingleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            parent.onSingleTap(g.location(in: g.view))
        }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            parent.onDoubleTap(g.location(in: g.view))
        }

        @objc func handlePencilDoubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            parent.onPencilDoubleTap(g.location(in: g.view))
        }

        @objc func handleTwoFingerPan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            parent.onTwoFingerPanChanged(CGSize(width: t.x, height: t.y))
            g.setTranslation(.zero, in: g.view)
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let view = g.view else { return }
            parent.onPinchChanged(g.scale, g.location(in: view))
            g.scale = 1
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let combo = (g is UIPinchGestureRecognizer && other is UIPanGestureRecognizer) || (g is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
            return combo
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  DocumentsPainter
//
//  Created by Romsya Borysenko on 2/16/26.
//
