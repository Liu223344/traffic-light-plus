import AppKit

enum WindowAction: Int, CaseIterable {
    case close
    case minimize
    case zoom
}

final class OverlayButtonView: NSView {
    let action: WindowAction
    var style: ControlStyle = .macOS { didSet { needsDisplay = true } }
    var controlSize: CGFloat = 28 { didSet { needsDisplay = true } }
    var isControlEnabled = true { didSet { needsDisplay = true } }
    var actionHandler: ((WindowAction) -> Void)?

    private var isHovered = false
    private var isPressed = false
    private var trackingAreaRef: NSTrackingArea?

    init(action: WindowAction) {
        self.action = action
        super.init(frame: .zero)
        toolTip = action.accessibilityLabel
        setAccessibilityRole(.button)
        setAccessibilityLabel(action.accessibilityLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isControlEnabled else { NSSound.beep(); return }
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            isPressed = false
            needsDisplay = true
        }
        guard isControlEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        actionHandler?(action)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds
        let baseColor = color(for: action)
        let fillColor: NSColor

        if !isControlEnabled {
            fillColor = baseColor.withAlphaComponent(0.38)
        } else if isPressed {
            fillColor = baseColor.blended(withFraction: 0.24, of: .black) ?? baseColor
        } else if isHovered {
            fillColor = baseColor.blended(withFraction: 0.10, of: .black) ?? baseColor
        } else {
            fillColor = baseColor
        }

        let path = style == .macOS
            ? NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            : edgeSquarePath(in: rect)
        fillColor.setFill()
        path.fill()

        if style == .macOS {
            NSColor.black.withAlphaComponent(0.16).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        if style != .macOS || isHovered || isPressed {
            drawSymbol(in: rect)
        }
    }

    private func edgeSquarePath(in rect: NSRect) -> NSBezierPath {
        let radius = min(8, rect.height * 0.22)
        let path = NSBezierPath()

        switch action {
        case .close:
            path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
            path.curve(
                to: NSPoint(x: rect.minX + radius, y: rect.minY),
                controlPoint1: NSPoint(x: rect.minX, y: rect.minY + radius * 0.45),
                controlPoint2: NSPoint(x: rect.minX + radius * 0.45, y: rect.minY)
            )
        case .minimize, .zoom:
            path.appendRect(rect)
        }
        path.close()
        return path
    }

    private func color(for action: WindowAction) -> NSColor {
        switch action {
        case .close: return NSColor(red: 0.98, green: 0.28, blue: 0.26, alpha: 1)
        case .minimize: return NSColor(red: 1, green: 0.70, blue: 0.12, alpha: 1)
        case .zoom: return NSColor(red: 0.16, green: 0.74, blue: 0.32, alpha: 1)
        }
    }

    private func drawSymbol(in rect: NSRect) {
        let inset = style == .macOS ? controlSize * 0.31 : controlSize * 0.32
        let symbolRect = rect.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath()
        path.lineWidth = max(1.2, controlSize * 0.055)
        path.lineCapStyle = .round

        NSColor.labelColor.withAlphaComponent(isControlEnabled ? 0.82 : 0.36).setStroke()

        switch action {
        case .close:
            path.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.minY))
            path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.maxY))
            path.move(to: NSPoint(x: symbolRect.maxX, y: symbolRect.minY))
            path.line(to: NSPoint(x: symbolRect.minX, y: symbolRect.maxY))
        case .minimize:
            path.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.midY))
            path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.midY))
        case .zoom:
            path.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.maxY))
            path.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.minY))
        }
        path.stroke()
    }
}

final class OverlayPanel: NSPanel {
    let overlayView: OverlayButtonView

    init(action: WindowAction) {
        overlayView = OverlayButtonView(action: action)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = overlayView
        overlayView.frame = contentView?.bounds ?? .zero
        overlayView.autoresizingMask = [.width, .height]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}

private extension WindowAction {
    var accessibilityLabel: String {
        switch self {
        case .close: return "关闭窗口"
        case .minimize: return "最小化窗口"
        case .zoom: return "缩放窗口"
        }
    }
}
