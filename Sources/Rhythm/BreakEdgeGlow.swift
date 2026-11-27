import AppKit
import QuartzCore
import RhythmCore

@MainActor
final class BreakEdgeGlow {
    private var panels: [GlowPanel] = []
    private var visible = false
    private var color: NSColor?
    private var style = GlowStyle()

    func update(visible shouldShow: Bool, color nextColor: NSColor, style nextStyle: GlowStyle = GlowStyle()) {
        guard shouldShow else { hide(); return }
        guard !visible || color != nextColor || style != nextStyle || panels.isEmpty else { return }
        color = nextColor
        style = nextStyle
        let wasVisible = visible
        visible = true
        if panels.isEmpty { makePanels() }
        for panel in panels {
            (panel.contentView as? EdgeGlowView)?.apply(color: nextColor, style: nextStyle)
            if !wasVisible { panel.alphaValue = 0 }
            if !wasVisible { panel.orderFrontRegardless() }
        }
        if !wasVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.15 : 0.7
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for panel in panels { panel.animator().alphaValue = 1 }
            }
        }
    }

    func hide(immediately: Bool = false) {
        guard visible || immediately else { return }
        visible = false
        if immediately {
            for panel in panels { panel.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.15 : 0.55
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in panels { panel.animator().alphaValue = 0 }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.visible else { return }
                for panel in self.panels { panel.orderOut(nil) }
            }
        }
    }

    func screensChanged() {
        let wasVisible = visible
        let tint = color
        hide(immediately: true)
        panels.forEach { $0.close() }
        panels.removeAll()
        if wasVisible, let tint { update(visible: true, color: tint, style: style) }
    }

    private func makePanels() {
        panels = NSScreen.screens.map { screen in
            let panel = GlowPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Break glow"
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isExcludedFromWindowsMenu = true
            panel.animationBehavior = .none
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            panel.setAccessibilityElement(false)
            let view = EdgeGlowView(frame: NSRect(origin: .zero, size: screen.frame.size))
            panel.contentView = view
            return panel
        }
    }
}

private final class GlowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class EdgeGlowView: NSView {
    private let edges = (0..<4).map { _ in CAGradientLayer() }
    private var style = GlowStyle()
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for edge in edges { layer?.addSublayer(edge) }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    func apply(color: NSColor, style: GlowStyle) {
        self.style = style
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for edge in edges {
            edge.colors = [color.withAlphaComponent(style.intensity).cgColor, color.withAlphaComponent(style.intensity * 0.3125).cgColor, color.withAlphaComponent(0).cgColor]
            edge.locations = [0, 0.32, 1]
        }
        CATransaction.commit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let thickness = min(CGFloat(style.width), min(bounds.width, bounds.height) * 0.45)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edges[0].frame = CGRect(x: 0, y: 0, width: thickness, height: bounds.height)
        edges[0].startPoint = CGPoint(x: 0, y: 0.5); edges[0].endPoint = CGPoint(x: 1, y: 0.5)
        edges[1].frame = CGRect(x: bounds.width - thickness, y: 0, width: thickness, height: bounds.height)
        edges[1].startPoint = CGPoint(x: 1, y: 0.5); edges[1].endPoint = CGPoint(x: 0, y: 0.5)
        edges[2].frame = CGRect(x: 0, y: 0, width: bounds.width, height: thickness)
        edges[2].startPoint = CGPoint(x: 0.5, y: 0); edges[2].endPoint = CGPoint(x: 0.5, y: 1)
        edges[3].frame = CGRect(x: 0, y: bounds.height - thickness, width: bounds.width, height: thickness)
        edges[3].startPoint = CGPoint(x: 0.5, y: 1); edges[3].endPoint = CGPoint(x: 0.5, y: 0)
        CATransaction.commit()
    }
}
