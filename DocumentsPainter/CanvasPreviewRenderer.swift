import SwiftUI
import UIKit

enum CanvasPreviewRenderer {
    private static let previewSize = CGSize(width: 400, height: 280)

    static func pngData(from state: CanvasStateDTO) -> Data? {
        guard let image = image(from: state) else { return nil }
        return image.pngData()
    }

    static func image(from state: CanvasStateDTO) -> UIImage? {
        let strokes = state.strokes.map(\.strokeItem)
        let lines = state.importedTextLines.map(\.importedTextLine)
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
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: previewSize))

            let cg = ctx.cgContext
            cg.saveGState()
            let tx = (previewSize.width - bw * scale) / 2 - bounds.minX * scale
            let ty = (previewSize.height - bh * scale) / 2 - bounds.minY * scale
            cg.translateBy(x: tx, y: ty)
            cg.scaleBy(x: scale, y: scale)

            for line in lines {
                let ns = line.text as NSString
                let font = UIFont.systemFont(ofSize: line.fontSize)
                let color = UIColor(line.color)
                ns.draw(
                    at: line.position,
                    withAttributes: [.font: font, .foregroundColor: color]
                )
            }

            for stroke in strokes {
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
            cg.restoreGState()
        }
    }
}
