import SwiftUI
import UIKit
import Foundation

enum DrawingStyle: String, CaseIterable, Identifiable {
    case solid = "Суцільна"
    case dashed = "Пунктир"
    case dotted = "Крапки"
    var id: String { rawValue }
}

enum DrawingToolKind: String, CaseIterable, Identifiable {
    case cursor
    case pencil
    case pen
    case marker
    case eraser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cursor: return "Курсор"
        case .pencil: return "Олівець"
        case .pen: return "Ручка"
        case .marker: return "Маркер"
        case .eraser: return "Гумка"
        }
    }

    var icon: String {
        switch self {
        case .cursor: return "cursorarrow"
        case .pencil: return "pencil"
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .cursor: return 1
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

enum PencilTapShortcutAction: String, CaseIterable, Identifiable {
    case none
    case undo
    case redo
    case selectTextTool
    case selectCursorTool
    case selectPencilTool
    case selectPenTool
    case selectMarkerTool
    case selectEraserTool

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Нічого"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .selectTextTool: return "Інструмент: Текст"
        case .selectCursorTool: return "Інструмент: Курсор"
        case .selectPencilTool: return "Інструмент: Олівець"
        case .selectPenTool: return "Інструмент: Ручка"
        case .selectMarkerTool: return "Інструмент: Маркер"
        case .selectEraserTool: return "Інструмент: Гумка"
        }
    }

    var shortTitle: String {
        switch self {
        case .none: return "Нічого"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .selectTextTool: return "Текст"
        case .selectCursorTool: return "Курсор"
        case .selectPencilTool: return "Олівець"
        case .selectPenTool: return "Ручка"
        case .selectMarkerTool: return "Маркер"
        case .selectEraserTool: return "Гумка"
        }
    }

    var symbolName: String {
        switch self {
        case .none: return "xmark"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .selectTextTool: return "textformat"
        case .selectCursorTool: return "cursorarrow"
        case .selectPencilTool: return "pencil"
        case .selectPenTool: return "pencil.tip"
        case .selectMarkerTool: return "highlighter"
        case .selectEraserTool: return "eraser"
        }
    }
}

enum CanvasBackgroundKind: String, CaseIterable, Identifiable, Codable {
    case blank
    case dots
    case lines
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return "Пустий"
        case .dots: return "В крапочку"
        case .lines: return "В лінійку"
        case .grid: return "В сіточку"
        }
    }

    static func decode(from raw: String?) -> CanvasBackgroundKind {
        guard let raw else { return .dots }
        if let value = CanvasBackgroundKind(rawValue: raw) { return value }
        switch raw {
        case "white", "warm", "gray", "night":
            return .blank
        default:
            return .dots
        }
    }
}

/// Ім’я координатного простору для канви (жести, hit-testing).
enum EditorCanvasCoordinateSpace {
    static let name = "editorCanvasSpace"
}

struct StrokeItem: Identifiable {
    var id: UUID = UUID()
    /// Логічний шар (порядок шарів — у масиві `artLayers`).
    var layerId: UUID
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
    var layerId: UUID
    var text: String
    var position: CGPoint
    var fontSize: CGFloat
    var color: Color
    var backgroundHighlights: [TextBackgroundHighlight] = []
}

struct TextBackgroundHighlight {
    var location: Int
    var length: Int
    var color: Color
}

extension ImportedTextLine {
    init(text: String, position: CGPoint, fontSize: CGFloat, color: Color, layerId: UUID) {
        self.init(
            id: UUID(),
            documentId: UUID(),
            groupId: UUID(),
            order: 0,
            layerId: layerId,
            text: text,
            position: position,
            fontSize: fontSize,
            color: color,
            backgroundHighlights: []
        )
    }

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

        func highlights(in target: NSRange, shiftBy shift: Int) -> [TextBackgroundHighlight] {
            backgroundHighlights.compactMap { highlight in
                guard highlight.length > 0 else { return nil }
                let source = NSRange(location: highlight.location, length: highlight.length)
                let intersection = NSIntersectionRange(source, target)
                guard intersection.length > 0 else { return nil }
                return TextBackgroundHighlight(
                    location: intersection.location + shift,
                    length: intersection.length,
                    color: highlight.color
                )
            }
        }

        let leftRange = NSRange(location: 0, length: range.location)
        let selectedRange = NSRange(location: range.location, length: range.length)
        let rightRange = NSRange(location: range.location + range.length, length: max(0, length - range.location - range.length))

        let left = leftText.isEmpty ? nil : ImportedTextLine(
            id: UUID(), documentId: documentId, groupId: groupId, order: order, layerId: layerId,
            text: leftText, position: position, fontSize: fontSize, color: color,
            backgroundHighlights: highlights(in: leftRange, shiftBy: 0)
        )
        let selected = selectedText.isEmpty ? nil : ImportedTextLine(
            id: UUID(), documentId: documentId, groupId: groupId, order: order + 1, layerId: layerId,
            text: selectedText,
            position: CGPoint(x: position.x + leftWidth + spacing, y: position.y), fontSize: fontSize, color: color,
            backgroundHighlights: highlights(in: selectedRange, shiftBy: -range.location)
        )
        let right = rightText.isEmpty ? nil : ImportedTextLine(
            id: UUID(), documentId: documentId, groupId: groupId, order: order + 2, layerId: layerId,
            text: rightText,
            position: CGPoint(x: position.x + leftWidth + selectedWidth + spacing * 2, y: position.y), fontSize: fontSize, color: color,
            backgroundHighlights: highlights(in: rightRange, shiftBy: -(range.location + range.length))
        )
        return (left, selected, right)
    }
}

struct CanvasSnapshot {
    var strokes: [StrokeItem]
    var importedTextLines: [ImportedTextLine]
    var artLayers: [CanvasArtLayer]
    var activeLayerId: UUID
    var hiddenArtLayerIds: Set<UUID>
}

struct CanvasArtLayer: Identifiable, Codable, Hashable, Equatable {
    var id: UUID
    var name: String
}

struct CanvasArtLayerDTO: Codable {
    var id: UUID
    var name: String

    init(_ layer: CanvasArtLayer) {
        id = layer.id
        name = layer.name
    }

    var artLayer: CanvasArtLayer {
        CanvasArtLayer(id: id, name: name)
    }
}

struct CanvasStateDTO: Codable {
    var scale: Double
    var offsetX: Double
    var offsetY: Double
    var strokes: [StrokeItemDTO]
    var hiddenStrokeIds: [UUID]
    var importedTextLines: [ImportedTextLineDTO]
    var hiddenTextLineIds: [UUID]
    var layerGroups: [LayerGroupDTO]
    var customLayerNames: [String: String]
    /// Застаріле поле з старих збережень; ігнорується.
    var toolDockPlacement: String?
    /// Фон канви. Якщо `nil` (старі збереження) — використовуємо білий.
    var canvasBackground: String?
    /// Нові поля; `nil` у старих файлах — міграція в `loadCanvasStateIfNeeded`.
    var artLayers: [CanvasArtLayerDTO]?
    var activeLayerId: UUID?
    var hiddenArtLayerIds: [UUID]?
}

struct StrokeItemDTO: Codable {
    var id: UUID
    var layerId: UUID?
    var points: [CGPointDTO]
    var color: RGBAColorDTO
    var width: Double
    var style: String
    var opacity: Double
}

struct ImportedTextLineDTO: Codable {
    var id: UUID
    var documentId: UUID
    var groupId: UUID
    var order: Int
    var layerId: UUID?
    var text: String
    var position: CGPointDTO
    var fontSize: Double
    var color: RGBAColorDTO
    var backgroundHighlights: [TextBackgroundHighlightDTO]?
}

struct TextBackgroundHighlightDTO: Codable {
    var location: Int
    var length: Int
    var color: RGBAColorDTO
}

struct LayerGroupDTO: Codable {
    var id: UUID
    var name: String
    var memberLayerIds: [String]
    var isExpanded: Bool
}

struct CGPointDTO: Codable {
    var x: Double
    var y: Double
}

struct RGBAColorDTO: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

extension CGPointDTO {
    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

extension RGBAColorDTO {
    init(_ color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var swiftUIColor: Color {
        Color(
            red: red.clamped(to: 0...1),
            green: green.clamped(to: 0...1),
            blue: blue.clamped(to: 0...1),
            opacity: alpha.clamped(to: 0...1)
        )
    }
}

extension StrokeItemDTO {
    init(_ stroke: StrokeItem) {
        id = stroke.id
        layerId = stroke.layerId
        points = stroke.points.map(CGPointDTO.init)
        color = RGBAColorDTO(stroke.color)
        width = stroke.width
        style = stroke.style.rawValue
        opacity = stroke.opacity
    }

    func strokeItem(fallbackLayerId: UUID) -> StrokeItem {
        StrokeItem(
            id: id,
            layerId: layerId ?? fallbackLayerId,
            points: points.map(\.cgPoint),
            color: color.swiftUIColor,
            width: width,
            style: DrawingStyle.allCases.first(where: { $0.rawValue == style }) ?? .solid,
            opacity: opacity
        )
    }
}

extension ImportedTextLineDTO {
    init(_ line: ImportedTextLine) {
        id = line.id
        documentId = line.documentId
        groupId = line.groupId
        order = line.order
        layerId = line.layerId
        text = line.text
        position = CGPointDTO(line.position)
        fontSize = line.fontSize
        color = RGBAColorDTO(line.color)
        backgroundHighlights = line.backgroundHighlights.map(TextBackgroundHighlightDTO.init)
    }

    func importedTextLine(fallbackLayerId: UUID) -> ImportedTextLine {
        ImportedTextLine(
            id: id,
            documentId: documentId,
            groupId: groupId,
            order: order,
            layerId: layerId ?? fallbackLayerId,
            text: text,
            position: position.cgPoint,
            fontSize: fontSize,
            color: color.swiftUIColor,
            backgroundHighlights: (backgroundHighlights ?? []).map(\.highlight)
        )
    }
}

extension TextBackgroundHighlightDTO {
    init(_ highlight: TextBackgroundHighlight) {
        location = highlight.location
        length = highlight.length
        color = RGBAColorDTO(highlight.color)
    }

    var highlight: TextBackgroundHighlight {
        TextBackgroundHighlight(
            location: location,
            length: length,
            color: color.swiftUIColor
        )
    }
}

extension LayerGroupDTO {
    init(_ group: LayerGroup) {
        id = group.id
        name = group.name
        memberLayerIds = group.memberLayerIds
        isExpanded = group.isExpanded
    }

    var layerGroup: LayerGroup {
        LayerGroup(
            id: id,
            name: name,
            memberLayerIds: memberLayerIds,
            isExpanded: isExpanded
        )
    }
}

struct LayerGroup: Identifiable {
    var id: UUID = UUID()
    var name: String
    var memberLayerIds: [String]
    var isExpanded: Bool = true
}

struct LayerGroupSection: Identifiable {
    var id: String
    var title: String
    var groupId: UUID?
    var layers: [CanvasLayer]
    var isExpanded: Bool
}

enum CanvasLayer: Identifiable {
    case stroke(StrokeItem)
    case text(ImportedTextLine)

    var id: String {
        switch self {
        case .stroke(let stroke): return "stroke-\(stroke.id.uuidString)"
        case .text(let line): return "textdoc-\(line.documentId.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .stroke: return "Малюнок"
        case .text(let line):
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Текст" : trimmed
        }
    }
}

enum SelectedCanvasItem {
    case stroke(UUID)
    case text(UUID)
}
