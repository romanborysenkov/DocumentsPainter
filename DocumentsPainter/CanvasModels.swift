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

/// Розташування панелі інструментів (фіксована, не перетягується).
enum ToolDockPlacement: String, CaseIterable, Identifiable, Codable {
    /// Вузька колонка зліва.
    case leading
    /// Смуга знизу.
    case bottom

    var id: String { rawValue }
}

/// Ім’я координатного простору для канви (жести, hit-testing).
enum EditorCanvasCoordinateSpace {
    static let name = "editorCanvasSpace"
}

struct StrokeItem: Identifiable {
    var id: UUID = UUID()
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

struct CanvasSnapshot {
    var strokes: [StrokeItem]
    var importedTextLines: [ImportedTextLine]
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
    /// `"leading"` | `"bottom"`. Якщо `nil` (старі збереження) — трактуємо як `bottom`.
    var toolDockPlacement: String?
}

struct StrokeItemDTO: Codable {
    var id: UUID
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
    var text: String
    var position: CGPointDTO
    var fontSize: Double
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
        points = stroke.points.map(CGPointDTO.init)
        color = RGBAColorDTO(stroke.color)
        width = stroke.width
        style = stroke.style.rawValue
        opacity = stroke.opacity
    }

    var strokeItem: StrokeItem {
        StrokeItem(
            id: id,
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
        text = line.text
        position = CGPointDTO(line.position)
        fontSize = line.fontSize
        color = RGBAColorDTO(line.color)
    }

    var importedTextLine: ImportedTextLine {
        ImportedTextLine(
            id: id,
            documentId: documentId,
            groupId: groupId,
            order: order,
            text: text,
            position: position.cgPoint,
            fontSize: fontSize,
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
