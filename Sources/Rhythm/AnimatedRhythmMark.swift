import AppKit
import SwiftUI
import QuartzCore

struct AnimatedRhythmMark: NSViewRepresentable {
    @EnvironmentObject var store: AppStore
    var spinning: Bool
    var highlighted: Bool
    var animationsEnabled: Bool

    func makeNSView(context: Context) -> SpinningMarkView { SpinningMarkView() }

    func updateNSView(_ view: SpinningMarkView, context: Context) {
        view.update(spinning: spinning, color: highlighted ? store.accentNSColor : NSColor.labelColor.withAlphaComponent(0.62), animationsEnabled: animationsEnabled)
    }
}

final class SpinningMarkView: NSView {
    private let rotor = CALayer()
    private let arcs = CAShapeLayer()
    private let dot = CAShapeLayer()

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(rotor)
        rotor.addSublayer(arcs)
        rotor.addSublayer(dot)
        arcs.fillColor = nil
        arcs.lineCap = .round
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rotor.frame = bounds
        let size = min(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        for start in [0.04, 0.54] {
            let angle = start * .pi * 2 - .pi / 6
            path.move(to: CGPoint(x: center.x + cos(angle) * size * 0.42, y: center.y + sin(angle) * size * 0.42))
            path.addArc(center: center, radius: size * 0.42, startAngle: angle, endAngle: angle + .pi * 0.8, clockwise: false)
        }
        arcs.path = path
        arcs.lineWidth = size * 0.11
        dot.path = CGPath(ellipseIn: CGRect(x: center.x - size * 0.075, y: center.y - size * 0.075, width: size * 0.15, height: size * 0.15), transform: nil)
        CATransaction.commit()
    }

    func update(spinning: Bool, color: NSColor, animationsEnabled: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            arcs.strokeColor = color.cgColor
            dot.fillColor = color.cgColor
        }
        CATransaction.commit()

        if !animationsEnabled {
            rotor.removeAnimation(forKey: "spin")
            rotor.speed = 1; rotor.timeOffset = 0; rotor.beginTime = 0
        } else if spinning {
            if rotor.animation(forKey: "spin") == nil {
                rotor.speed = 1; rotor.timeOffset = 0; rotor.beginTime = 0
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0; spin.toValue = Double.pi * 2
                spin.duration = 8
                spin.repeatCount = .infinity
                spin.timingFunction = CAMediaTimingFunction(name: .linear)
                rotor.add(spin, forKey: "spin")
            } else if rotor.speed == 0 {
                let paused = rotor.timeOffset
                rotor.speed = 1; rotor.timeOffset = 0; rotor.beginTime = 0
                rotor.beginTime = rotor.convertTime(CACurrentMediaTime(), from: nil) - paused
            }
        } else if rotor.animation(forKey: "spin") != nil, rotor.speed != 0 {
            let paused = rotor.convertTime(CACurrentMediaTime(), from: nil)
            rotor.speed = 0
            rotor.timeOffset = paused
        }
    }
}
