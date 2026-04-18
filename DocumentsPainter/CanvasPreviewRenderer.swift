import SwiftUI
import UIKit

enum CanvasPreviewRenderer {
    private static let previewSize = CGSize(width: 400, height: 280)

    static func pngData(from state: CanvasStateDTO) -> Data? {
        guard let image = image(from: state) else { return nil }
        return image.pngData()
    }

    static func image(from state: CanvasStateDTO) -> UIImage? {
        let artIds: [UUID]
        let fallback: UUID
        if let dtos = state.artLayers, !dtos.isEmpty {
            artIds = dtos.map(\.id)
            fallback = artIds[0]
        } else {
            fallback = UUID()
            artIds = [fallback]
        }
        let strokes = state.strokes.map { $0.strokeItem(fallbackLayerId: fallback) }
        let lines = state.importedTextLines.map { $0.importedTextLine(fallbackLayerId: fallback) }
        var bounds = CGRect.null
        for s in strokes {
            for p in s.points {
                bounds = bounds.union(CGRect(x: p.x, y: p.y, width: 1, height: 1))
            }
        }
        for l in lines {
            let w = (l.text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: l.fontSize)]).width
            bounds = bounds.union(CGRect(x: l.position.x, y: l.position.y, width: max(1, w), height: l.fontSize * 1.3))
        }
        if bounds.isNull || bounds.isEmpty {
            return nil
        }
        let pad: CGFloat = 24
        bounds = bounds.insetBy(dx: -pad, dy: -pad)
        let bw = max(bounds.width, 1)
        let bh = max(bounds.height, 1)
        let scale = min(previewSize.width / bw, previewSize.height / bh)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: previewSize, format: format)
        return renderer.image { ctx in
            let bg = CanvasBackgroundKind.decode(from: state.canvasBackground)
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: previewSize))
            drawBackgroundPattern(bg, in: ctx.cgContext, size: previewSize)

            let cg = ctx.cgContext
            cg.saveGState()
            let tx = (previewSize.width - bw * scale) / 2 - bounds.minX * scale
            let ty = (previewSize.height - bh * scale) / 2 - bounds.minY * scale
            cg.translateBy(x: tx, y: ty)
            cg.scaleBy(x: scale, y: scale)

            for lid in artIds {
                for line in lines where line.layerId == lid {
                    EditorCanvasHelpers.highlightedAttributedString(line).draw(at: line.position)
                }
                for stroke in strokes where stroke.layerId == lid {
                    guard stroke.points.count > 1 else { continue }
                    cg.setStrokeColor(UIColor(stroke.color).cgColor)
                    cg.setLineWidth(max(1, stroke.width))
                    cg.setLineCap(.round)
                    cg.setLineJoin(.round)
                    cg.setAlpha(CGFloat(stroke.opacity))
                    cg.beginPath()
                    cg.move(to: stroke.points[0])
                    for p in stroke.points.dropFirst() {
                        cg.addLine(to: p)
                    }
                    cg.strokePath()
                }
            }
            cg.restoreGState()
        }
    }

    private static func drawBackgroundPattern(_ kind: CanvasBackgroundKind, in cg: CGContext, size: CGSize) {
        switch kind {
        case .blank:
            return
        case .dots:
            let spacing: CGFloat = 20
            let r: CGFloat = 0.8
            cg.setFillColor(UIColor.black.withAlphaComponent(0.16).cgColor)
            var x: CGFloat = 0
            while x <= size.width {
                var y: CGFloat = 0
                while y <= size.height {
                    cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    y += spacing
                }
                x += spacing
            }
        case .lines:
            let spacing: CGFloat = 28
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.08).cgColor)
            cg.setLineWidth(1)
            var y: CGFloat = 0
            while y <= size.height {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
                cg.strokePath()
                y += spacing
            }
        case .grid:
            let spacing: CGFloat = 28
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.09).cgColor)
            cg.setLineWidth(1)
            var y: CGFloat = 0
            while y <= size.height {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
                cg.strokePath()
                y += spacing
            }
            var x: CGFloat = 0
            while x <= size.width {
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x, y: size.height))
                cg.strokePath()
                x += spacing
            }
        }
    }
}
