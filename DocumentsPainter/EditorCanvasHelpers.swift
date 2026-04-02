import SwiftUI
import UIKit

enum EditorCanvasHelpers {
    static func contentToView(_ point: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width, y: point.y * scale + offset.height)
    }

    static func searchRanges(in text: String, query: String) -> [NSRange] {
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

    static func textWidthPrefix(_ text: String, length: Int, fontSize: CGFloat) -> CGFloat {
        let ns = text as NSString
        let l = min(max(0, length), ns.length)
        return (ns.substring(to: l) as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width
    }

    static func boundsForTextLine(_ line: ImportedTextLine) -> CGRect {
        let width = (line.text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: line.fontSize)]).width
        return CGRect(x: line.position.x, y: line.position.y, width: width, height: line.fontSize * 1.3)
    }

    /// Спочатку дешевий відсік по Y, потім повні межі — щоб не викликати `size` для кожного рядка при пані.
    static func isTextLineInVisibleContent(_ line: ImportedTextLine, visible: CGRect) -> Bool {
        let h = line.fontSize * 1.3
        guard line.position.y + h >= visible.minY && line.position.y <= visible.maxY else { return false }
        return boundsForTextLine(line).intersects(visible)
    }

    /// Прямокутник у координатах контенту, що відповідає видимій області канви (для culling).
    static func visibleContentRect(viewSize: CGSize, scale: CGFloat, offset: CGSize) -> CGRect {
        guard abs(scale) > 1e-9 else {
            return CGRect(x: -1e7, y: -1e7, width: 2e7, height: 2e7)
        }
        let x0 = (0 - offset.width) / scale
        let x1 = (viewSize.width - offset.width) / scale
        let y0 = (0 - offset.height) / scale
        let y1 = (viewSize.height - offset.height) / scale
        let minX = min(x0, x1)
        let maxX = max(x0, x1)
        let minY = min(y0, y1)
        let maxY = max(y0, y1)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Розширення видимої зони в одиницях контенту (~кілька сотень pt на екрані), щоб рядки на краю не «різались».
    static func visibleContentRectPaddedForCulling(viewSize: CGSize, scale: CGFloat, offset: CGSize, paddingViewPoints: CGFloat = 120) -> CGRect {
        let r = visibleContentRect(viewSize: viewSize, scale: scale, offset: offset)
        let pad = paddingViewPoints / max(abs(scale), 0.01)
        return r.insetBy(dx: -pad, dy: -pad)
    }

    static func boundingRect(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    static func strokeStyle(for style: DrawingStyle, width: CGFloat) -> StrokeStyle {
        switch style {
        case .solid: return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        case .dashed: return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [10, 6])
        case .dotted: return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [2, 5])
        }
    }
}
