import SwiftUI

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
        //.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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

struct LayersPanelView: View {
    /// `nil` — висота списку шарів займає доступний простір у батьківському `VStack`.
    var listMaxHeight: CGFloat? = 280
    /// У боковій колонці тягнемось на ширину колонки замість фіксованих 280 pt.
    var useSidebarColumnWidth: Bool = false

    let canvasLayers: [CanvasLayer]
    let layerGroupSections: [LayerGroupSection]
    let selectedLayerIdsForGrouping: Set<String>
    let createGroupFromSelection: () -> Void
    let ungroup: (UUID) -> Void
    let toggleGroupExpansion: (UUID) -> Void
    let toggleGroupVisibility: (LayerGroupSection) -> Void
    let isSectionVisible: (LayerGroupSection) -> Bool
    let toggleLayerSelectionForGrouping: (String) -> Void
    let layerNameBinding: (CanvasLayer) -> Binding<String>
    let groupNameBinding: (UUID) -> Binding<String>
    let toggleLayerVisibility: (CanvasLayer) -> Void
    let isLayerVisible: (CanvasLayer) -> Bool

    private var layerSectionsScroll: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(layerGroupSections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: section.groupId == nil ? "square.stack.3d.down.right" : "folder")
                                .foregroundStyle(.secondary)
                            if let groupId = section.groupId {
                                TextField("Назва групи", text: groupNameBinding(groupId))
                                    .font(.caption.bold())
                            } else {
                                Text(section.title)
                                    .font(.caption.bold())
                            }
                            Spacer()
                            if let groupId = section.groupId {
                                Button { ungroup(groupId) } label: {
                                    Image(systemName: "link.badge.minus")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Розгрупувати")
                            }
                            Button {
                                if let groupId = section.groupId { toggleGroupExpansion(groupId) }
                            } label: {
                                Image(systemName: section.groupId == nil || section.isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(section.groupId == nil)
                            Button { toggleGroupVisibility(section) } label: {
                                Image(systemName: isSectionVisible(section) ? "eye" : "eye.slash")
                                    .foregroundStyle(isSectionVisible(section) ? Color.primary : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isSectionVisible(section) ? "Приховати групу" : "Показати групу")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 8))

                        if section.groupId == nil || section.isExpanded {
                            ForEach(section.layers.reversed()) { layer in
                                HStack(spacing: 8) {
                                    Button { toggleLayerSelectionForGrouping(layer.id) } label: {
                                        Image(systemName: selectedLayerIdsForGrouping.contains(layer.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedLayerIdsForGrouping.contains(layer.id) ? Color.accentColor : Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    LayerThumbnailView(layer: layer)
                                    TextField("Назва шару", text: layerNameBinding(layer))
                                        .font(.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button { toggleLayerVisibility(layer) } label: {
                                        Image(systemName: isLayerVisible(layer) ? "eye" : "eye.slash")
                                            .foregroundStyle(isLayerVisible(layer) ? Color.primary : Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isLayerVisible(layer) ? "Приховати шар" : "Показати шар")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    (selectedLayerIdsForGrouping.contains(layer.id) ? Color.accentColor.opacity(0.14) : Color(UIColor.systemBackground)),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Слої")
                    .font(.headline)
                Spacer()
                Button("Згрупувати") { createGroupFromSelection() }
                    .font(.caption)
                    .disabled(selectedLayerIdsForGrouping.count < 2)
            }
            if canvasLayers.isEmpty {
                Text("Поки що немає шарів")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                layerSectionsScroll
                    .frame(maxHeight: listMaxHeight ?? .infinity)
            }
        }
        .frame(maxWidth: useSidebarColumnWidth ? .infinity : nil)
        .frame(width: useSidebarColumnWidth ? nil : 280, alignment: .topLeading)
        .padding(useSidebarColumnWidth ? 8 : 12)
    }
}

struct ToolDockContentView: View {
    /// Розмір виділеної зони панелі (фіксована смуга зліва або знизу).
    let dockFrameSize: CGSize
    let placement: ToolDockPlacement
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

    var body: some View {
        switch placement {
        case .leading:
            leadingSidebarToolbar
        case .bottom:
            bottomToolbarGrid
        }
    }

    /// Ліва колонка: ряд 1 — дії й інструменти; ряд 2 — палітра й стиль; ряд 3 — товщина та opacity.
    private var leadingSidebarToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button { onUndo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(UIColor.systemBackground).opacity(0.72)))
                    }
                    .buttonStyle(.plain)
                    .disabled(undoStackIsEmpty)
                    .opacity(undoStackIsEmpty ? 0.45 : 1)
                    .accessibilityLabel("Скасувати")

                    Button { onRedo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(UIColor.systemBackground).opacity(0.72)))
                    }
                    .buttonStyle(.plain)
                    .disabled(redoStackIsEmpty)
                    .opacity(redoStackIsEmpty ? 0.45 : 1)
                    .accessibilityLabel("Повторити")

                    Button { onTextMode() } label: {
                        Image(systemName: "text.cursor")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(interactionMode == .text ? Color.accentColor : Color.primary)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(interactionMode == .text ? Color.accentColor.opacity(0.13) : Color(UIColor.systemBackground).opacity(0.7))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Текст")

                    ForEach(DrawingToolKind.allCases) { tool in
                        Button { onToolSelected(tool) } label: {
                            Image(systemName: tool.icon)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(interactionMode == .draw && drawingTool == tool ? Color.accentColor : Color.primary)
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(interactionMode == .draw && drawingTool == tool ? Color.accentColor.opacity(0.13) : Color(UIColor.systemBackground).opacity(0.7))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tool.title)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 10) {
                    ForEach(Array(paletteColors.enumerated()), id: \.offset) { idx, color in
                        Button { onPaletteColorSelected(idx, color) } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2).padding(2))
                                .overlay(Circle().stroke(selectedPaletteColorIndex == idx ? Color.accentColor : .clear, lineWidth: 3))
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
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
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
                        Image(systemName: "ruler")
                            .font(.system(size: 18, weight: .regular))
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(UIColor.systemBackground).opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Лінійка та стиль")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Товщина \(Int(drawingWidth))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(get: { drawingWidth }, set: onDrawingWidthChanged),
                        in: 1...24,
                        step: 1
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Opacity \(Int(drawingOpacity * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(get: { drawingOpacity }, set: onDrawingOpacityChanged),
                        in: 0.05...1,
                        step: 0.05
                    )
                    .accessibilityLabel("Opacity")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var bottomToolbarGrid: some View {
        let innerW = max(1, dockFrameSize.width - 16)
        let innerH = max(1, dockFrameSize.height - 16)
        let spacing: CGFloat = 5
        let minCellWidth: CGFloat = 88
        let availableWidth = max(1, innerW - 20)
        let columnsCount = max(1, Int((availableWidth + spacing) / (minCellWidth + spacing)))
        let columns = Array(repeating: GridItem(.flexible(minimum: minCellWidth, maximum: 220), spacing: spacing), count: columnsCount)
        let sliderGridSpan = min(2, columnsCount)

        return ScrollView(.vertical) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                    Button { onUndo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Color(UIColor.systemBackground).opacity(0.72)))
                    }
                    .buttonStyle(.plain)
                    .disabled(undoStackIsEmpty)
                    .opacity(undoStackIsEmpty ? 0.45 : 1)
                    .accessibilityLabel("Скасувати")
                    .frame(maxWidth: .infinity, minHeight: 56)

                    Button { onRedo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(Color(UIColor.systemBackground).opacity(0.72)))
                    }
                    .buttonStyle(.plain)
                    .disabled(redoStackIsEmpty)
                    .opacity(redoStackIsEmpty ? 0.45 : 1)
                    .accessibilityLabel("Повторити")
                    .frame(maxWidth: .infinity, minHeight: 56)

                    Button { onTextMode() } label: {
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
                    .frame(maxWidth: .infinity, minHeight: 56)

                    ForEach(DrawingToolKind.allCases) { tool in
                        Button { onToolSelected(tool) } label: {
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
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Товщина \(Int(drawingWidth))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { drawingWidth },
                                set: onDrawingWidthChanged
                            ),
                            in: 1...24,
                            step: 1
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .gridCellColumns(sliderGridSpan)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Opacity \(Int(drawingOpacity * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { drawingOpacity },
                                set: onDrawingOpacityChanged
                            ),
                            in: 0.05...1,
                            step: 0.05
                        )
                        .accessibilityLabel("Opacity")
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .gridCellColumns(sliderGridSpan)

                    ForEach(Array(paletteColors.enumerated()), id: \.offset) { idx, color in
                        Button { onPaletteColorSelected(idx, color) } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2).padding(2))
                                .overlay(Circle().stroke(selectedPaletteColorIndex == idx ? Color.accentColor : .clear, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Колір \(idx + 1)")
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }

                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { drawingColor },
                            set: onCustomColorSelected
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .frame(maxWidth: .infinity, minHeight: 56)

                    Menu {
                        Picker(
                            "Стиль",
                            selection: Binding(
                                get: { drawingStyle },
                                set: onDrawingStyleChanged
                            )
                        ) {
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
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .frame(maxWidth: .infinity, minHeight: max(1, innerH - 2), alignment: .topLeading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}
