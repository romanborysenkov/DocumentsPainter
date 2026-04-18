import SwiftUI
import UIKit

enum CanvasExportKind: CaseIterable, Identifiable {
    case jpg
    case png
    case svg
    case pdfFlattened
    case pdfVector

    var id: String { title }

    var title: String {
        switch self {
        case .jpg: return "JPG"
        case .png: return "PNG"
        case .svg: return "SVG"
        case .pdfFlattened: return "PDF (flattened)"
        case .pdfVector: return "PDF (vector paths)"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpg: return "jpg"
        case .png: return "png"
        case .svg: return "svg"
        case .pdfFlattened, .pdfVector: return "pdf"
        }
    }
}

struct CanvasExportSnapshot {
    var background: CanvasBackgroundKind
    var artLayers: [CanvasArtLayer]
    var hiddenArtLayerIds: Set<UUID>
    var strokes: [StrokeItem]
    var hiddenStrokeIds: Set<UUID>
    var textLines: [ImportedTextLine]
    var hiddenTextLineIds: Set<UUID>
}

enum CanvasExportRenderer {
    fileprivate static let exportPadding: CGFloat = 24
    private static let maxRasterSide: CGFloat = 4096

    static func data(for kind: CanvasExportKind, snapshot: CanvasExportSnapshot) -> Data? {
        let model = ExportModel(snapshot: snapshot)
        guard model.hasContent else { return nil }
        switch kind {
        case .jpg:
            return rasterData(model: model, asJPEG: true)
        case .png:
            return rasterData(model: model, asJPEG: false)
        case .svg:
            return svgData(model: model)
        case .pdfFlattened:
            return flattenedPDFData(model: model)
        case .pdfVector:
            return vectorPDFData(model: model)
        }
    }

    private static func rasterData(model: ExportModel, asJPEG: Bool) -> Data? {
        let raster = model.rasterized(maxSide: maxRasterSide)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: raster.size, format: format)
        let image = renderer.image { ctx in
            drawBackground(kind: model.background, in: ctx.cgContext, rect: CGRect(origin: .zero, size: raster.size))
            drawAllContent(in: ctx.cgContext, model: model, transform: raster.transform)
        }
        if asJPEG {
            return image.jpegData(compressionQuality: 0.92)
        }
        return image.pngData()
    }

    private static func flattenedPDFData(model: ExportModel) -> Data? {
        let raster = model.rasterized(maxSide: maxRasterSide)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: raster.size, format: format)
        let image = renderer.image { ctx in
            drawBackground(kind: model.background, in: ctx.cgContext, rect: CGRect(origin: .zero, size: raster.size))
            drawAllContent(in: ctx.cgContext, model: model, transform: raster.transform)
        }

        let pdfBounds = CGRect(origin: .zero, size: raster.size)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: pdfBounds)
        return pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            image.draw(in: pdfBounds)
        }
    }

    private static func vectorPDFData(model: ExportModel) -> Data? {
        let pageSize = model.exportRect.size
        guard pageSize.width > 0, pageSize.height > 0 else { return nil }
        let pdfBounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: pdfBounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            drawBackground(kind: model.background, in: cg, rect: pdfBounds)
            let transform = CGAffineTransform(translationX: -model.exportRect.minX, y: -model.exportRect.minY)
            drawAllContent(in: cg, model: model, transform: transform)
        }
    }

    private static func svgData(model: ExportModel) -> Data? {
        let canvas = model.exportRect
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="\#(fmt(canvas.width))" height="\#(fmt(canvas.height))" viewBox="0 0 \#(fmt(canvas.width)) \#(fmt(canvas.height))">"#)
        lines.append(#"<rect x="0" y="0" width="\#(fmt(canvas.width))" height="\#(fmt(canvas.height))" fill="white"/>"#)
        lines.append(contentsOf: svgBackground(kind: model.background, size: canvas.size))

        for layerId in model.orderedLayerIds {
            for textLine in model.textByLayer[layerId] ?? [] {
                for highlight in EditorCanvasHelpers.sanitizedHighlights(textLine.backgroundHighlights, text: textLine.text) {
                    let startX = EditorCanvasHelpers.textWidthPrefix(textLine.text, length: highlight.location, fontSize: textLine.fontSize)
                    let endX = EditorCanvasHelpers.textWidthPrefix(textLine.text, length: highlight.location + highlight.length, fontSize: textLine.fontSize)
                    let x = textLine.position.x - canvas.minX + startX
                    let y = textLine.position.y - canvas.minY
                    let width = max(1, endX - startX)
                    let height = max(1, textLine.fontSize * 1.3)
                    let fill = svgColor(UIColor(highlight.color))
                    lines.append(#"<rect x="\#(fmt(x))" y="\#(fmt(y))" width="\#(fmt(width))" height="\#(fmt(height))" rx="2" ry="2" fill="\#(fill)"/>"#)
                }
                let color = svgColor(UIColor(textLine.color))
                let escaped = xmlEscaped(textLine.text)
                let x = textLine.position.x - canvas.minX
                let y = textLine.position.y - canvas.minY + textLine.fontSize
                lines.append(#"<text x="\#(fmt(x))" y="\#(fmt(y))" font-family="-apple-system, Helvetica, Arial, sans-serif" font-size="\#(fmt(textLine.fontSize))" fill="\#(color)">\#(escaped)</text>"#)
            }

            for stroke in model.strokesByLayer[layerId] ?? [] {
                guard let first = stroke.points.first else { continue }
                if stroke.points.count == 1 {
                    let strokeColor = svgColor(UIColor(stroke.color), alpha: CGFloat(stroke.opacity))
                    let cx = first.x - canvas.minX
                    let cy = first.y - canvas.minY
                    let radius = max(0.5, stroke.width / 2)
                    lines.append(#"<circle cx="\#(fmt(cx))" cy="\#(fmt(cy))" r="\#(fmt(radius))" fill="\#(strokeColor)"/>"#)
                    continue
                }
                var d = "M \(fmt(first.x - canvas.minX)) \(fmt(first.y - canvas.minY))"
                for point in stroke.points.dropFirst() {
                    d += " L \(fmt(point.x - canvas.minX)) \(fmt(point.y - canvas.minY))"
                }
                let style = strokeDashArray(style: stroke.style)
                let strokeColor = svgColor(UIColor(stroke.color), alpha: CGFloat(stroke.opacity))
                var tag = #"<path d="\#(d)" fill="none" stroke="\#(strokeColor)" stroke-width="\#(fmt(max(1, stroke.width)))" stroke-linecap="round" stroke-linejoin="round""#
                if !style.isEmpty {
                    tag += #" stroke-dasharray="\#(style)""#
                }
                tag += "/>"
                lines.append(tag)
            }
        }

        lines.append("</svg>")
        return lines.joined(separator: "\n").data(using: .utf8)
    }

    private static func drawAllContent(in cg: CGContext, model: ExportModel, transform: CGAffineTransform) {
        cg.saveGState()
        cg.concatenate(transform)
        for layerId in model.orderedLayerIds {
            for textLine in model.textByLayer[layerId] ?? [] {
                EditorCanvasHelpers.highlightedAttributedString(textLine).draw(at: textLine.position)
            }
            for stroke in model.strokesByLayer[layerId] ?? [] {
                drawStroke(stroke, in: cg)
            }
        }
        cg.restoreGState()
    }

    private static func drawStroke(_ stroke: StrokeItem, in cg: CGContext) {
        guard !stroke.points.isEmpty else { return }
        cg.saveGState()
        cg.setStrokeColor(UIColor(stroke.color).cgColor)
        cg.setAlpha(CGFloat(stroke.opacity))
        cg.setLineWidth(max(1, stroke.width))
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        let dash = strokeDashArray(style: stroke.style)
            .split(separator: ",")
            .compactMap { Double($0) }
            .map { CGFloat($0) }
        cg.setLineDash(phase: 0, lengths: dash)
        cg.beginPath()
        cg.move(to: stroke.points[0])
        if stroke.points.count == 1 {
            cg.addLine(to: CGPoint(x: stroke.points[0].x + 0.01, y: stroke.points[0].y + 0.01))
        } else {
            for point in stroke.points.dropFirst() {
                cg.addLine(to: point)
            }
        }
        cg.strokePath()
        cg.restoreGState()
    }

    private static func drawBackground(kind: CanvasBackgroundKind, in cg: CGContext, rect: CGRect) {
        cg.saveGState()
        cg.setFillColor(UIColor.white.cgColor)
        cg.fill(rect)
        switch kind {
        case .blank:
            break
        case .dots:
            let spacing: CGFloat = 20
            let radius: CGFloat = 0.8
            cg.setFillColor(UIColor.black.withAlphaComponent(0.16).cgColor)
            var x = rect.minX
            while x <= rect.maxX {
                var y = rect.minY
                while y <= rect.maxY {
                    cg.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    y += spacing
                }
                x += spacing
            }
        case .lines:
            let spacing: CGFloat = 28
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.08).cgColor)
            cg.setLineWidth(1)
            var y = rect.minY
            while y <= rect.maxY {
                cg.move(to: CGPoint(x: rect.minX, y: y))
                cg.addLine(to: CGPoint(x: rect.maxX, y: y))
                cg.strokePath()
                y += spacing
            }
        case .grid:
            let spacing: CGFloat = 28
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.09).cgColor)
            cg.setLineWidth(1)
            var y = rect.minY
            while y <= rect.maxY {
                cg.move(to: CGPoint(x: rect.minX, y: y))
                cg.addLine(to: CGPoint(x: rect.maxX, y: y))
                cg.strokePath()
                y += spacing
            }
            var x = rect.minX
            while x <= rect.maxX {
                cg.move(to: CGPoint(x: x, y: rect.minY))
                cg.addLine(to: CGPoint(x: x, y: rect.maxY))
                cg.strokePath()
                x += spacing
            }
        }
        cg.restoreGState()
    }

    private static func svgBackground(kind: CanvasBackgroundKind, size: CGSize) -> [String] {
        switch kind {
        case .blank:
            return []
        case .dots:
            var tags: [String] = []
            let spacing: CGFloat = 20
            let radius: CGFloat = 0.8
            var x: CGFloat = 0
            while x <= size.width {
                var y: CGFloat = 0
                while y <= size.height {
                    tags.append(#"<circle cx="\#(fmt(x))" cy="\#(fmt(y))" r="\#(fmt(radius))" fill="rgba(0,0,0,0.16)"/>"#)
                    y += spacing
                }
                x += spacing
            }
            return tags
        case .lines:
            var tags: [String] = []
            let spacing: CGFloat = 28
            var y: CGFloat = 0
            while y <= size.height {
                tags.append(#"<line x1="0" y1="\#(fmt(y))" x2="\#(fmt(size.width))" y2="\#(fmt(y))" stroke="rgba(0,0,0,0.08)" stroke-width="1"/>"#)
                y += spacing
            }
            return tags
        case .grid:
            var tags: [String] = []
            let spacing: CGFloat = 28
            var y: CGFloat = 0
            while y <= size.height {
                tags.append(#"<line x1="0" y1="\#(fmt(y))" x2="\#(fmt(size.width))" y2="\#(fmt(y))" stroke="rgba(0,0,0,0.09)" stroke-width="1"/>"#)
                y += spacing
            }
            var x: CGFloat = 0
            while x <= size.width {
                tags.append(#"<line x1="\#(fmt(x))" y1="0" x2="\#(fmt(x))" y2="\#(fmt(size.height))" stroke="rgba(0,0,0,0.09)" stroke-width="1"/>"#)
                x += spacing
            }
            return tags
        }
    }

    private static func strokeDashArray(style: DrawingStyle) -> String {
        switch style {
        case .solid: return ""
        case .dashed: return "10,6"
        case .dotted: return "2,5"
        }
    }

    private static func xmlEscaped(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
        return escaped
    }

    private static func svgColor(_ color: UIColor, alpha: CGFloat? = nil) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let finalAlpha = alpha ?? a
        return "rgba(\(Int(round(r * 255))),\(Int(round(g * 255))),\(Int(round(b * 255))),\(fmt(finalAlpha)))"
    }

    private static func fmt(_ value: CGFloat) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.3f", value)
    }
}

private struct ExportModel {
    let background: CanvasBackgroundKind
    let orderedLayerIds: [UUID]
    let strokesByLayer: [UUID: [StrokeItem]]
    let textByLayer: [UUID: [ImportedTextLine]]
    let exportRect: CGRect

    var hasContent: Bool {
        !orderedLayerIds.isEmpty && !exportRect.isNull && !exportRect.isEmpty
    }

    init(snapshot: CanvasExportSnapshot) {
        background = snapshot.background
        let orderedVisible = snapshot.artLayers.map(\.id).filter { !snapshot.hiddenArtLayerIds.contains($0) }
        orderedLayerIds = orderedVisible
        let visibleLayerSet = Set(orderedVisible)

        let visibleStrokes = snapshot.strokes.filter {
            !$0.points.isEmpty &&
            !snapshot.hiddenStrokeIds.contains($0.id) &&
            visibleLayerSet.contains($0.layerId)
        }
        let visibleText = snapshot.textLines.filter {
            !snapshot.hiddenTextLineIds.contains($0.id) &&
            visibleLayerSet.contains($0.layerId) &&
            !$0.text.isEmpty
        }

        strokesByLayer = Dictionary(grouping: visibleStrokes, by: \.layerId)
        textByLayer = Dictionary(grouping: visibleText, by: \.layerId)

        var bounds = CGRect.null
        for stroke in visibleStrokes {
            guard let first = stroke.points.first else { continue }
            var minX = first.x
            var minY = first.y
            var maxX = first.x
            var maxY = first.y
            for point in stroke.points.dropFirst() {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            let lineInset = max(1, stroke.width) * 0.6
            bounds = bounds.union(CGRect(
                x: minX - lineInset,
                y: minY - lineInset,
                width: max(1, maxX - minX) + lineInset * 2,
                height: max(1, maxY - minY) + lineInset * 2
            ))
        }
        for line in visibleText {
            let width = (line.text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: line.fontSize)]).width
            bounds = bounds.union(CGRect(
                x: line.position.x,
                y: line.position.y,
                width: max(1, width),
                height: max(1, line.fontSize * 1.35)
            ))
        }
        if bounds.isNull || bounds.isEmpty {
            exportRect = .null
        } else {
            exportRect = bounds.insetBy(dx: -CanvasExportRenderer.exportPadding, dy: -CanvasExportRenderer.exportPadding)
        }
    }

    func rasterized(maxSide: CGFloat) -> (size: CGSize, transform: CGAffineTransform) {
        let source = exportRect
        let side = max(source.width, source.height)
        let scale = side > maxSide ? (maxSide / side) : 1
        let rasterSize = CGSize(
            width: max(1, source.width * scale),
            height: max(1, source.height * scale)
        )
        let transform = CGAffineTransform(translationX: -source.minX, y: -source.minY)
            .scaledBy(x: scale, y: scale)
        return (rasterSize, transform)
    }
}
