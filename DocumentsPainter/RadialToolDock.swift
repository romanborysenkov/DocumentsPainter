import SwiftUI

/// Сектор кільця (між внутрішнім і зовнішнім радіусом).
struct RingSegmentShape: Shape {
    var index: Int
    var segmentCount: Int
    /// Внутрішній радіус як частка зовнішнього (0…1).
    var innerRadiusRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRadiusRatio
        let sweep = (2 * CGFloat.pi) / CGFloat(segmentCount)
        let start = -CGFloat.pi / 2 + CGFloat(index) * sweep
        let end = start + sweep

        var p = Path()
        p.addArc(center: c, radius: outerR, startAngle: Angle(radians: Double(start)), endAngle: Angle(radians: Double(end)), clockwise: false)
        p.addLine(to: CGPoint(x: c.x + innerR * cos(end), y: c.y + innerR * sin(end)))
        p.addArc(center: c, radius: innerR, startAngle: Angle(radians: Double(end)), endAngle: Angle(radians: Double(start)), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// Радіальна панель: сегменти інструментів + центральний «хаб» з товщиною, непрозорістю та кольором.
struct RadialToolDialView: View {
    let diameter: CGFloat
    var innerRadiusRatio: CGFloat = 0.5

    let undoStackIsEmpty: Bool
    let redoStackIsEmpty: Bool
    let interactionMode: InteractionMode
    let drawingTool: DrawingToolKind
    let drawingWidth: CGFloat
    let drawingOpacity: Double
    let drawingColor: Color

    @Binding var showStrokeSettings: Bool

    let onUndo: () -> Void
    let onRedo: () -> Void
    let onTextMode: () -> Void
    let onToolSelected: (DrawingToolKind) -> Void
    let onCustomColorSelected: (Color) -> Void

    private let segmentCount = 6

    private var iconFont: Font {
        .system(size: max(11, min(16, diameter * 0.068)), weight: .semibold)
    }

    private var selectedSegment: Int {
        if interactionMode == .text { return 0 }
        switch drawingTool {
        case .cursor: return 1
        case .pencil: return 2
        case .pen: return 3
        case .marker: return 4
        case .eraser: return 5
        }
    }

    private func selectSegment(_ i: Int) {
        switch i {
        case 0: onTextMode()
        case 1: onToolSelected(.cursor)
        case 2: onToolSelected(.pencil)
        case 3: onToolSelected(.pen)
        case 4: onToolSelected(.marker)
        case 5: onToolSelected(.eraser)
        default: break
        }
    }

    private func segmentIcon(_ i: Int) -> String {
        if i == 0 { return "text.cursor" }
        return DrawingToolKind.allCases[i - 1].icon
    }

    private func segmentPresetWidth(_ i: Int) -> CGFloat {
        if i == 0 { return 0 }
        return DrawingToolKind.allCases[i - 1].defaultWidth
    }

    private func midAngle(for index: Int) -> CGFloat {
        let sweep = (2 * CGFloat.pi) / CGFloat(segmentCount)
        return -CGFloat.pi / 2 + (CGFloat(index) + 0.5) * sweep
    }

    var body: some View {
        HStack(alignment: .center, spacing: max(4, diameter * 0.03)) {
            sideUndoRedo
            dialCore
        }
    }

    private var sideUndoRedo: some View {
        VStack(spacing: 6) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: max(12, diameter * 0.078), weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .rotationEffect(.degrees(-28))
            }
            .buttonStyle(.plain)
            .disabled(undoStackIsEmpty)
            .opacity(undoStackIsEmpty ? 0.35 : 1)
            .accessibilityLabel("Скасувати")

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: max(12, diameter * 0.078), weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .rotationEffect(.degrees(28))
            }
            .buttonStyle(.plain)
            .disabled(redoStackIsEmpty)
            .opacity(redoStackIsEmpty ? 0.35 : 1)
            .accessibilityLabel("Повторити")
        }
        .frame(width: diameter * 0.12)
    }

    private var dialCore: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outerR = s / 2
            let innerR = outerR * innerRadiusRatio
            let labelR = (innerR + outerR) / 2

            ZStack {
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.14), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)

                ForEach(0..<segmentCount, id: \.self) { i in
                    Button {
                        selectSegment(i)
                    } label: {
                        RingSegmentShape(index: i, segmentCount: segmentCount, innerRadiusRatio: innerRadiusRatio)
                            .fill(segmentFill(isSelected: selectedSegment == i))
                            .overlay(
                                RingSegmentShape(index: i, segmentCount: segmentCount, innerRadiusRatio: innerRadiusRatio)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(0..<segmentCount, id: \.self) { i in
                    let a = midAngle(for: i)
                    ZStack {
                        Image(systemName: segmentIcon(i))
                            .font(iconFont)
                            .foregroundStyle(Color.black)
                        if i > 0, diameter >= 168 {
                            Text(String(format: "%.1f", segmentPresetWidth(i)))
                                .font(.system(size: max(7, diameter * 0.034), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black)
                                .offset(y: max(12, diameter * 0.078))
                        }
                    }
                    .allowsHitTesting(false)
                    .position(x: c.x + labelR * cos(a), y: c.y + labelR * sin(a))
                }

                hub(hubDiameter: innerR * 2 * 0.92)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func segmentFill(isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.28)
        }
        return Color(white: 0.94)
    }

    private func hub(hubDiameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
            Circle()
                .stroke(Color.black.opacity(0.14), lineWidth: 1)

            VStack(spacing: max(2, hubDiameter * 0.04)) {
                Button {
                    showStrokeSettings = true
                } label: {
                    VStack(spacing: max(2, hubDiameter * 0.035)) {
                        HStack(spacing: 4) {
                            Image(systemName: "lineweight")
                                .font(.system(size: hubDiameter * 0.11, weight: .semibold))
                                .foregroundStyle(Color.black)
                            Text(String(format: "%.1f", drawingWidth))
                                .font(.system(size: hubDiameter * 0.13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black)
                            Text("pt")
                                .font(.system(size: hubDiameter * 0.1, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.55))
                        }

                        HStack(spacing: 2) {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.system(size: hubDiameter * 0.1, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.75))
                            Text("\(Int(drawingOpacity * 100))%")
                                .font(.system(size: hubDiameter * 0.11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Товщина й непрозорість")

                ZStack {
                    Circle()
                        .fill(drawingColor)
                        .frame(width: hubDiameter * 0.31, height: hubDiameter * 0.31)
                        .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                    ColorPicker(
                        "",
                        selection: Binding(get: { drawingColor }, set: onCustomColorSelected),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: hubDiameter * 0.36, height: hubDiameter * 0.36)
                    .contentShape(Circle())
                    .opacity(0.04)
                }
                .accessibilityLabel("Колір пера")
            }
            .padding(.horizontal, hubDiameter * 0.12)
            .padding(.vertical, hubDiameter * 0.1)
        }
        .frame(width: hubDiameter, height: hubDiameter)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
    }
}
