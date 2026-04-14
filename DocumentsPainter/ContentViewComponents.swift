import SwiftUI
import UIKit

struct ImportButtonView: View {
    @Binding var showImportPicker: Bool

    var body: some View {
        Button { showImportPicker = true } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Імпорт")
    }
}

struct ExportMenuButtonView: View {
    let exportKinds: [CanvasExportKind]
    let onSelect: (CanvasExportKind) -> Void
    @State private var showExportOptions = false

    var body: some View {
        Button {
            showExportOptions = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Експорт")
        .popover(isPresented: $showExportOptions) {
            exportPopoverContent
                .presentationCompactAdaptation(.popover)
        }
    }

    private var exportPopoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Експорт")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(exportKinds) { kind in
                        exportOptionButton(kind)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(minWidth: 360)
    }

    private func exportOptionButton(_ kind: CanvasExportKind) -> some View {
        Button {
            showExportOptions = false
            onSelect(kind)
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbolName(for: kind))
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 68, height: 68)
                    .foregroundStyle(.primary)
                    .background(
                        Circle()
                            .fill(Color(UIColor.tertiarySystemBackground))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(UIColor.separator).opacity(0.55), lineWidth: 1)
                    )

                Text(shortTitle(for: kind))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 86)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
    }

    private func symbolName(for kind: CanvasExportKind) -> String {
        switch kind {
        case .jpg:
            return "photo"
        case .png:
            return "photo.fill"
        case .svg:
            return "scribble.variable"
        case .pdfFlattened:
            return "doc.richtext"
        case .pdfVector:
            return "doc.text.image"
        }
    }

    private func shortTitle(for kind: CanvasExportKind) -> String {
        switch kind {
        case .jpg:
            return "JPG"
        case .png:
            return "PNG"
        case .svg:
            return "SVG"
        case .pdfFlattened:
            return "PDF flat"
        case .pdfVector:
            return "PDF vec"
        }
    }
}

struct SearchPanelView: View {
    @Binding var searchQuery: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Пошук", text: $searchQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                if !searchQuery.isEmpty {
                    Button { searchQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(width: 240)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1))
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}


struct LayerThumbnailView: View {
    let layer: CanvasLayer

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(UIColor.systemBackground))
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(UIColor.separator).opacity(0.35), lineWidth: 1)

            switch layer {
            case .stroke(let stroke):
                Canvas { context, size in
                    guard stroke.points.count > 1 else { return }
                    let bounds = strokeBounds(stroke.points)
                    guard bounds.width > 0, bounds.height > 0 else { return }
                    let inset: CGFloat = 4
                    let sx = (size.width - inset * 2) / bounds.width
                    let sy = (size.height - inset * 2) / bounds.height
                    let factor = min(sx, sy)
                    let dx = (size.width - bounds.width * factor) / 2
                    let dy = (size.height - bounds.height * factor) / 2

                    var path = Path()
                    let first = stroke.points[0]
                    path.move(to: CGPoint(x: (first.x - bounds.minX) * factor + dx, y: (first.y - bounds.minY) * factor + dy))
                    for point in stroke.points.dropFirst() {
                        path.addLine(to: CGPoint(x: (point.x - bounds.minX) * factor + dx, y: (point.y - bounds.minY) * factor + dy))
                    }
                    context.stroke(
                        path,
                        with: .color(stroke.color.opacity(stroke.opacity)),
                        style: strokeStyle(for: stroke.style, width: max(1.2, stroke.width * factor * 0.18))
                    )
                }
            case .text(let line):
                Text(line.text.isEmpty ? "Текст" : line.text)
                    .font(.system(size: 8))
                    .foregroundStyle(line.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 4)
            }
        }
        .frame(width: 42, height: 28)
    }

    private func strokeStyle(for style: DrawingStyle, width: CGFloat) -> StrokeStyle {
        switch style {
        case .solid: return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        case .dashed: return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [10, 6])
        case .dotted: return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [2, 5])
        }
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
}

struct ArtLayersPanelView: View {
    var listMaxHeight: CGFloat? = 280
    var useSidebarColumnWidth: Bool = false
    /// Плаває над канвою без зовнішньої «картки»; рядки з легким склом.
    var floatOnCanvas: Bool = false
    var panelWidth: CGFloat?

    let artLayers: [CanvasArtLayer]
    @Binding var activeLayerId: UUID
    @Binding var hiddenArtLayerIds: Set<UUID>
    let onAddLayer: () -> Void
    let onDeleteLayer: (CanvasArtLayer) -> Void
    let onMoveLayerTowardFront: (Int) -> Void
    let onMoveLayerTowardBack: (Int) -> Void
    let onRenameLayer: (CanvasArtLayer) -> Void

    private func isVisible(_ id: UUID) -> Bool { !hiddenArtLayerIds.contains(id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Слої")
                    .font(.headline)
                Spacer()
                Button { onAddLayer() } label: {
                    Label("Новий шар", systemImage: "plus.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Новий шар")
            }
            if artLayers.isEmpty {
                Text("Немає шарів")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(artLayers.enumerated().reversed()), id: \.element.id) { pair in
                            let index = pair.offset
                            let layer = pair.element
                            let towardFrontDisabled = index >= artLayers.count - 1
                            let towardBackDisabled = index <= 0
                            HStack(spacing: 8) {
                                Text(layer.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    onRenameLayer(layer)
                                } label: {
                                    Image(systemName: "pencil.line")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Перейменувати шар")
                                VStack(spacing: 2) {
                                    Button { onMoveLayerTowardFront(index) } label: {
                                        Image(systemName: "chevron.up")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(towardFrontDisabled)
                                    Button { onMoveLayerTowardBack(index) } label: {
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(towardBackDisabled)
                                }
                                .foregroundStyle(.secondary)
                                Button {
                                    if hiddenArtLayerIds.contains(layer.id) {
                                        hiddenArtLayerIds.remove(layer.id)
                                    } else {
                                        hiddenArtLayerIds.insert(layer.id)
                                    }
                                } label: {
                                    Image(systemName: isVisible(layer.id) ? "eye" : "eye.slash")
                                        .foregroundStyle(isVisible(layer.id) ? Color.primary : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isVisible(layer.id) ? "Приховати шар" : "Показати шар")
                                Button { onDeleteLayer(layer) } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red.opacity(0.85))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Видалити шар")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background { rowBackground(for: layer.id) }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(activeLayerId == layer.id ? Color.accentColor.opacity(0.45) : Color.primary.opacity(floatOnCanvas ? 0.08 : 0), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { activeLayerId = layer.id }
                        }
                    }
                }
                .frame(maxHeight: listMaxHeight ?? .infinity)
            }
        }
        .frame(width: panelFrameWidth, alignment: .topLeading)
        .frame(maxWidth: panelMaxWidth, alignment: .topLeading)
        .padding(panelPadding)
    }

    private var panelFrameWidth: CGFloat? {
        if floatOnCanvas { return panelWidth ?? 280 }
        if useSidebarColumnWidth { return nil }
        return 280
    }

    private var panelMaxWidth: CGFloat? {
        if floatOnCanvas { return nil }
        if useSidebarColumnWidth { return .infinity }
        return nil
    }

    private var panelPadding: CGFloat {
        if floatOnCanvas { return 0 }
        return useSidebarColumnWidth ? 8 : 12
    }

    @ViewBuilder
    private func rowBackground(for layerId: UUID) -> some View {
        let r = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if floatOnCanvas {
            r.fill(activeLayerId == layerId ? Color.accentColor.opacity(0.22) : Color(UIColor.secondarySystemFill))
        } else {
            r.fill(activeLayerId == layerId ? Color.accentColor.opacity(0.16) : Color(UIColor.systemBackground))
        }
    }
}

struct ToolDockContentView: View {
    /// Ширина для палітри (обмежує горизонтальний скрол).
    let paletteMaxWidth: CGFloat
    let undoStackIsEmpty: Bool
    let redoStackIsEmpty: Bool
    let interactionMode: InteractionMode
    let drawingTool: DrawingToolKind
    let drawingWidth: CGFloat
    let drawingOpacity: Double
    let drawingStyle: DrawingStyle
    let drawingColor: Color
    let selectedPaletteColorIndex: Int?
    let paletteColors: [Color]
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onTextMode: () -> Void
    let onToolSelected: (DrawingToolKind) -> Void
    let onDrawingWidthChanged: (CGFloat) -> Void
    let onDrawingOpacityChanged: (Double) -> Void
    let onPaletteColorSelected: (Int, Color) -> Void
    let onCustomColorSelected: (Color) -> Void
    let onDrawingStyleChanged: (DrawingStyle) -> Void

    @State private var showStrokeSettings = false

    private let dialDiameter: CGFloat = 196

    private let paletteChipCorner: CGFloat = 5
    private let paletteChipW: CGFloat = 32
    private let paletteChipH: CGFloat = 22

    var body: some View {
        VStack(spacing: 10) {
            RadialToolDialView(
                diameter: dialDiameter,
                innerRadiusRatio: 0.5,
                undoStackIsEmpty: undoStackIsEmpty,
                redoStackIsEmpty: redoStackIsEmpty,
                interactionMode: interactionMode,
                drawingTool: drawingTool,
                drawingWidth: drawingWidth,
                drawingOpacity: drawingOpacity,
                drawingColor: drawingColor,
                showStrokeSettings: $showStrokeSettings,
                onUndo: onUndo,
                onRedo: onRedo,
                onTextMode: onTextMode,
                onToolSelected: onToolSelected,
                onCustomColorSelected: onCustomColorSelected
            )
            radialPaletteStrip
        }
        .frame(maxWidth: paletteMaxWidth, alignment: .leading)
        .popover(isPresented: $showStrokeSettings) {
            strokeSettingsPopoverContent
                .presentationCompactAdaptation(.popover)
        }
    }

    private var radialPaletteStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(paletteColors.enumerated()), id: \.offset) { idx, color in
                    Button { onPaletteColorSelected(idx, color) } label: {
                        RoundedRectangle(cornerRadius: paletteChipCorner, style: .continuous)
                            .fill(color)
                            .frame(width: paletteChipW, height: paletteChipH)
                            .overlay(
                                RoundedRectangle(cornerRadius: paletteChipCorner, style: .continuous)
                                    .stroke(Color.white.opacity(0.75), lineWidth: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: paletteChipCorner, style: .continuous)
                                    .stroke(selectedPaletteColorIndex == idx ? Color.accentColor : Color.clear, lineWidth: 2.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Колір \(idx + 1)")
                }

                ColorPicker(
                    "",
                    selection: Binding(get: { drawingColor }, set: onCustomColorSelected),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: paletteChipW, height: paletteChipH)
                .clipShape(RoundedRectangle(cornerRadius: paletteChipCorner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: paletteChipCorner, style: .continuous)
                        .stroke(Color.white.opacity(0.75), lineWidth: 1)
                )

                Menu {
                    Picker(
                        "Стиль",
                        selection: Binding(get: { drawingStyle }, set: onDrawingStyleChanged)
                    ) {
                        ForEach(DrawingStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                } label: {
                    Image(systemName: "lineweight")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: paletteChipH)
                        .background(
                            RoundedRectangle(cornerRadius: paletteChipCorner, style: .continuous)
                                .fill(Material.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: paletteChipCorner, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Стиль штриха")
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    private var strokeSettingsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Перо")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("Товщина \(Int(drawingWidth))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { drawingWidth }, set: onDrawingWidthChanged),
                    in: 1...24,
                    step: 1
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Непрозорість \(Int(drawingOpacity * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { drawingOpacity }, set: onDrawingOpacityChanged),
                    in: 0.05...1,
                    step: 0.05
                )
                .accessibilityLabel("Непрозорість")
            }
        }
        .padding(16)
        .frame(minWidth: 280)
    }
}
