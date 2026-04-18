import SwiftUI
import UIKit

enum EditorCanvasHelpers {
    private static let textWidthCache = NSCache<NSString, NSNumber>()
    private static let searchHighlightColor = Color.yellow.opacity(0.55)

    static func contentToView(_ point: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width, y: point.y * scale + offset.height)
    }

    static func textWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let key = "\(fontSize)|\(text)" as NSString
        if let cached = textWidthCache.object(forKey: key) {
            return CGFloat(cached.doubleValue)
        }
        let width = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width
        textWidthCache.setObject(NSNumber(value: Double(width)), forKey: key)
        return width
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

    static func highlightedText(_ line: ImportedTextLine, query: String) -> Text {
        var attributed = AttributedString(line.text)
        attributed.foregroundColor = line.color

        let persisted = sanitizedHighlights(line.backgroundHighlights, text: line.text)
        for highlight in persisted {
            let nsRange = NSRange(location: highlight.location, length: highlight.length)
            guard let range = Range(nsRange, in: line.text),
                  let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].backgroundColor = highlight.color
        }

        let persistedKeys = Set(persisted.map { "\($0.location):\($0.length)" })
        for nsRange in searchRanges(in: line.text, query: query) {
            let key = "\(nsRange.location):\(nsRange.length)"
            guard !persistedKeys.contains(key),
                  let range = Range(nsRange, in: line.text),
                  let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].backgroundColor = searchHighlightColor
            attributed[attrRange].foregroundColor = .black
        }

        return Text(attributed)
    }

    static func highlightedAttributedString(_ line: ImportedTextLine) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: line.text,
            attributes: [
                .font: UIFont.systemFont(ofSize: line.fontSize),
                .foregroundColor: UIColor(line.color)
            ]
        )
        for highlight in sanitizedHighlights(line.backgroundHighlights, text: line.text) {
            let nsRange = NSRange(location: highlight.location, length: highlight.length)
            attributed.addAttribute(.backgroundColor, value: UIColor(highlight.color), range: nsRange)
        }
        return attributed
    }

    static func mergedHighlights(
        existing: [TextBackgroundHighlight],
        addingRanges: [NSRange],
        color: Color,
        text: String
    ) -> [TextBackgroundHighlight] {
        let sanitizedExisting = sanitizedHighlights(existing, text: text)
        let sanitizedAdding = addingRanges.filter {
            $0.length > 0 && $0.location >= 0 && $0.location + $0.length <= (text as NSString).length
        }
        guard !sanitizedAdding.isEmpty else { return sanitizedExisting }

        func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
            NSIntersectionRange(a, b).length > 0
        }

        let keptExisting = sanitizedExisting.filter { item in
            let r = NSRange(location: item.location, length: item.length)
            return !sanitizedAdding.contains(where: { intersects(r, $0) })
        }

        let added = sanitizedAdding.map {
            TextBackgroundHighlight(location: $0.location, length: $0.length, color: color)
        }
        return (keptExisting + added).sorted { lhs, rhs in
            if lhs.location == rhs.location { return lhs.length < rhs.length }
            return lhs.location < rhs.location
        }
    }

    static func expandRangesToWholeWords(_ ranges: [NSRange], in text: String) -> [NSRange] {
        let ns = text as NSString
        let length = ns.length
        guard length > 0 else { return [] }

        func isWordScalar(_ scalar: UnicodeScalar) -> Bool {
            if CharacterSet.alphanumerics.contains(scalar) { return true }
            switch scalar {
            case "'", "’", "-", "_":
                return true
            default:
                return false
            }
        }

        func isWordIndex(_ index: Int) -> Bool {
            guard index >= 0, index < length,
                  let scalar = UnicodeScalar(ns.character(at: index)) else { return false }
            return isWordScalar(scalar)
        }

        var result: [NSRange] = []
        result.reserveCapacity(ranges.count)

        for raw in ranges where raw.length > 0 && raw.location >= 0 && raw.location + raw.length <= length {
            var start = raw.location
            var end = raw.location + raw.length

            while start > 0, isWordIndex(start - 1) { start -= 1 }
            while end < length, isWordIndex(end) { end += 1 }

            let expanded = NSRange(location: start, length: max(0, end - start))
            if expanded.length > 0 {
                result.append(expanded)
            }
        }

        // Дедуп і склейка перетинів, щоб уникнути дублювань одного слова.
        let sorted = result.sorted { lhs, rhs in
            if lhs.location == rhs.location { return lhs.length < rhs.length }
            return lhs.location < rhs.location
        }
        guard var current = sorted.first else { return [] }
        var merged: [NSRange] = []
        for next in sorted.dropFirst() {
            let currentEnd = current.location + current.length
            if next.location <= currentEnd {
                let nextEnd = next.location + next.length
                current.length = max(currentEnd, nextEnd) - current.location
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    static func sanitizedHighlights(_ highlights: [TextBackgroundHighlight], text: String) -> [TextBackgroundHighlight] {
        let length = (text as NSString).length
        return highlights.compactMap { item in
            guard item.length > 0, item.location >= 0, item.location + item.length <= length else { return nil }
            return item
        }
    }

    static func textWidthPrefix(_ text: String, length: Int, fontSize: CGFloat) -> CGFloat {
        let ns = text as NSString
        let l = min(max(0, length), ns.length)
        return (ns.substring(to: l) as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: fontSize)]).width
    }

    static func boundsForTextLine(_ line: ImportedTextLine) -> CGRect {
        let width = textWidth(line.text, fontSize: line.fontSize)
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
