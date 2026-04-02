import SwiftUI

/// Фон + імпортований текст (без поточного штриха) — не залежить від `currentStroke`, тому не перемальовується на кожну точку олівця.
struct EditorImportedTextCanvasLayer: View {
    let center: CGPoint
    let scale: CGFloat
    let offset: CGSize
    let virtualCanvasSize: CGFloat
    let importedTextLines: [ImportedTextLine]
    let hiddenTextLineIds: Set<UUID>
    let searchQuery: String
    let selectedTextLineIds: Set<UUID>
    let textSelectionRect: CGRect?

    var body: some View {
        Canvas { context, size in
            let virtualRect = CGRect(
                x: center.x - (virtualCanvasSize / 2) * scale + offset.width,
                y: center.y - (virtualCanvasSize / 2) * scale + offset.height,
                width: virtualCanvasSize * scale,
                height: virtualCanvasSize * scale
            )
            context.fill(Path(virtualRect), with: .color(.white))
            context.stroke(Path(virtualRect), with: .color(.gray.opacity(0.08)), lineWidth: 1)

            let visibleContent = EditorCanvasHelpers.visibleContentRectPaddedForCulling(
                viewSize: size,
                scale: scale,
                offset: offset
            )

            for line in importedTextLines where !hiddenTextLineIds.contains(line.id) && EditorCanvasHelpers.isTextLineInVisibleContent(line, visible: visibleContent) {
                let matches = EditorCanvasHelpers.searchRanges(in: line.text, query: searchQuery)
                for m in matches {
                    let startX = EditorCanvasHelpers.textWidthPrefix(line.text, length: m.location, fontSize: line.fontSize)
                    let endX = EditorCanvasHelpers.textWidthPrefix(line.text, length: m.location + m.length, fontSize: line.fontSize)
                    let contentRect = CGRect(x: line.position.x + startX, y: line.position.y, width: max(1, endX - startX), height: line.fontSize * 1.3)
                    let o = EditorCanvasHelpers.contentToView(CGPoint(x: contentRect.minX, y: contentRect.minY), scale: scale, offset: offset)
                    let vr = CGRect(x: o.x, y: o.y, width: contentRect.width * scale, height: contentRect.height * scale)
                    context.fill(Path(roundedRect: vr.insetBy(dx: -1, dy: -1), cornerRadius: 3), with: .color(.yellow.opacity(0.45)))
                }

                context.draw(
                    Text(line.text).font(.system(size: line.fontSize * scale)).foregroundColor(line.color),
                    at: EditorCanvasHelpers.contentToView(line.position, scale: scale, offset: offset),
                    anchor: .topLeading
                )
            }

            for line in importedTextLines where selectedTextLineIds.contains(line.id) && !hiddenTextLineIds.contains(line.id) && EditorCanvasHelpers.isTextLineInVisibleContent(line, visible: visibleContent) {
                let b = EditorCanvasHelpers.boundsForTextLine(line)
                let o = EditorCanvasHelpers.contentToView(CGPoint(x: b.minX, y: b.minY), scale: scale, offset: offset)
                let vr = CGRect(x: o.x, y: o.y, width: b.width * scale, height: b.height * scale)
                context.stroke(Path(roundedRect: vr.insetBy(dx: -4, dy: -4), cornerRadius: 4), with: .color(.blue), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }

            if let rect = textSelectionRect, rect.intersects(visibleContent) {
                let o = EditorCanvasHelpers.contentToView(CGPoint(x: rect.minX, y: rect.minY), scale: scale, offset: offset)
                let vr = CGRect(x: o.x, y: o.y, width: rect.width * scale, height: rect.height * scale)
                let path = Path(roundedRect: vr, cornerRadius: 2)
                context.fill(path, with: .color(.blue.opacity(0.08)))
                context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
    }
}

/// Штрихи + поточний рух олівця + курсорні оверлеї — оновлюється часто під час малювання.
struct EditorStrokesCanvasLayer: View {
    let scale: CGFloat
    let offset: CGSize
    let strokes: [StrokeItem]
    let hiddenStrokeIds: Set<UUID>
    let currentStroke: [CGPoint]
    let drawingColor: Color
    let drawingOpacity: Double
    let drawingStyle: DrawingStyle
    let drawingWidth: CGFloat
    let drawingTool: DrawingToolKind
    let interactionMode: InteractionMode
    let selectedItemBounds: CGRect?
    let cursorMarqueeRect: CGRect?

    var body: some View {
        Canvas { context, size in
            let visibleContent = EditorCanvasHelpers.visibleContentRectPaddedForCulling(
                viewSize: size,
                scale: scale,
                offset: offset,
                paddingViewPoints: 80
            )

            for stroke in strokes where !hiddenStrokeIds.contains(stroke.id) {
                guard stroke.points.count > 1 else { continue }
                if let bb = EditorCanvasHelpers.boundingRect(of: stroke.points), !bb.intersects(visibleContent) { continue }
                var path = Path()
                path.move(to: EditorCanvasHelpers.contentToView(stroke.points[0], scale: scale, offset: offset))
                for p in stroke.points.dropFirst() { path.addLine(to: EditorCanvasHelpers.contentToView(p, scale: scale, offset: offset)) }
                context.stroke(
                    path,
                    with: .color(stroke.color.opacity(stroke.opacity)),
                    style: EditorCanvasHelpers.strokeStyle(for: stroke.style, width: stroke.width * scale)
                )
            }

            if currentStroke.count > 1,
               let curBB = EditorCanvasHelpers.boundingRect(of: currentStroke),
               curBB.intersects(visibleContent) {
                var path = Path()
                path.move(to: EditorCanvasHelpers.contentToView(currentStroke[0], scale: scale, offset: offset))
                for p in currentStroke.dropFirst() { path.addLine(to: EditorCanvasHelpers.contentToView(p, scale: scale, offset: offset)) }
                context.stroke(
                    path,
                    with: .color(drawingColor.opacity(drawingOpacity)),
                    style: EditorCanvasHelpers.strokeStyle(for: drawingStyle, width: drawingWidth * scale)
                )
            }

            if drawingTool == .cursor, interactionMode == .draw, let bounds = selectedItemBounds, bounds.intersects(visibleContent) {
                let o = EditorCanvasHelpers.contentToView(CGPoint(x: bounds.minX, y: bounds.minY), scale: scale, offset: offset)
                let vr = CGRect(x: o.x, y: o.y, width: bounds.width * scale, height: bounds.height * scale)
                context.stroke(Path(roundedRect: vr.insetBy(dx: -4, dy: -4), cornerRadius: 4), with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                let handle = CGRect(x: vr.maxX - 6, y: vr.maxY - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: handle), with: .color(.orange))
            }

            if drawingTool == .cursor, interactionMode == .draw, let rect = cursorMarqueeRect, rect.intersects(visibleContent) {
                let o = EditorCanvasHelpers.contentToView(CGPoint(x: rect.minX, y: rect.minY), scale: scale, offset: offset)
                let vr = CGRect(x: o.x, y: o.y, width: rect.width * scale, height: rect.height * scale)
                let path = Path(roundedRect: vr, cornerRadius: 2)
                context.fill(path, with: .color(.orange.opacity(0.08)))
                context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .allowsHitTesting(false)
    }
}
