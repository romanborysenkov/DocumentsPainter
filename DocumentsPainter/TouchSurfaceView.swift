import SwiftUI
import UIKit

/// Дозволяє збирати проміжні точки олівця через `coalescedTouches`, зберігаючи життєвий цикл `UIPanGestureRecognizer` (як раніше — без зайвого `began` на «тену» для подвійного тапу).
private final class TouchSurfaceHostView: UIView {
    weak var coordinator: TouchSurfaceView.Coordinator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let c = coordinator, c.isPencilPanTracking, let event else { return }
        for touch in touches where touch.type == .pencil {
            let samples = event.coalescedTouches(for: touch) ?? [touch]
            for t in samples {
                c.emitPencilMoved(t.location(in: self))
            }
            return
        }
    }
}

struct TouchSurfaceView: UIViewRepresentable {
    var onPencilBegan: (CGPoint) -> Void
    var onSingleTap: (CGPoint) -> Void
    var onDoubleTap: (CGPoint) -> Void
    var onPencilDoubleTap: (CGPoint) -> Void
    var onPencilMoved: (CGPoint) -> Void
    var onPencilEnded: () -> Void
    var onFingerPanBegan: (CGPoint) -> Void
    var onFingerPanChanged: (CGSize) -> Void
    var onFingerPanEnded: () -> Void
    var onTwoFingerPanChanged: (CGSize) -> Void
    var onPinchChanged: (_ scaleDelta: CGFloat, _ center: CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = TouchSurfaceHostView()
        view.coordinator = context.coordinator

        let pencilPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePencilPan(_:)))
        pencilPan.minimumNumberOfTouches = 1
        pencilPan.maximumNumberOfTouches = 1
        pencilPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pencilPan.delegate = context.coordinator
        pencilPan.cancelsTouchesInView = false

        let fingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFingerPan(_:)))
        fingerPan.minimumNumberOfTouches = 1
        fingerPan.maximumNumberOfTouches = 1
        fingerPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        fingerPan.delegate = context.coordinator

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.numberOfTouchesRequired = 1
        singleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        singleTap.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        doubleTap.delegate = context.coordinator
        singleTap.require(toFail: doubleTap)

        let pencilDoubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePencilDoubleTap(_:)))
        pencilDoubleTap.numberOfTapsRequired = 2
        pencilDoubleTap.numberOfTouchesRequired = 1
        pencilDoubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pencilDoubleTap.delegate = context.coordinator
        pencilDoubleTap.cancelsTouchesInView = false
        pencilDoubleTap.delaysTouchesEnded = false

        let navPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerPan(_:)))
        navPan.minimumNumberOfTouches = 2
        navPan.maximumNumberOfTouches = 2
        navPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        navPan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.delegate = context.coordinator

        view.addGestureRecognizer(pencilPan)
        view.addGestureRecognizer(fingerPan)
        view.addGestureRecognizer(singleTap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(pencilDoubleTap)
        view.addGestureRecognizer(navPan)
        view.addGestureRecognizer(pinch)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        (uiView as? TouchSurfaceHostView)?.coordinator = context.coordinator
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TouchSurfaceView
        fileprivate var isPencilPanTracking = false

        init(_ parent: TouchSurfaceView) { self.parent = parent }

        func emitPencilMoved(_ p: CGPoint) { parent.onPencilMoved(p) }

        @objc func handlePencilPan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                isPencilPanTracking = true
                parent.onPencilBegan(g.location(in: g.view))
            case .changed:
                break
            case .ended, .cancelled, .failed:
                isPencilPanTracking = false
                parent.onPencilEnded()
            default:
                break
            }
        }

        @objc func handleFingerPan(_ g: UIPanGestureRecognizer) {
            let p = g.location(in: g.view)
            switch g.state {
            case .began:
                parent.onFingerPanBegan(p)
            case .changed:
                let t = g.translation(in: g.view)
                parent.onFingerPanChanged(CGSize(width: t.x, height: t.y))
                g.setTranslation(.zero, in: g.view)
            case .ended, .cancelled, .failed:
                parent.onFingerPanEnded()
            default:
                break
            }
        }

        @objc func handleSingleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            parent.onSingleTap(g.location(in: g.view))
        }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            parent.onDoubleTap(g.location(in: g.view))
        }

        @objc func handlePencilDoubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            parent.onPencilDoubleTap(g.location(in: g.view))
        }

        @objc func handleTwoFingerPan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            parent.onTwoFingerPanChanged(CGSize(width: t.x, height: t.y))
            g.setTranslation(.zero, in: g.view)
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let view = g.view else { return }
            parent.onPinchChanged(g.scale, g.location(in: view))
            g.scale = 1
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let combo = (g is UIPinchGestureRecognizer && other is UIPanGestureRecognizer) || (g is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
            return combo
        }
    }
}
