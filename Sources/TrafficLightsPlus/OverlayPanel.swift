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
    var isWindowActive = false { didSet { needsDisplay = true } }
    var isGroupHovered = false { didSet { needsDisplay = true } }
    var actionHandler: ((WindowAction) -> Void)?
    var hoverHandler: ((Bool) -> Void)?

    var isColorVisible: Bool { isWindowActive || isGroupHovered || isHovered || isPressed }
    var isPointerHighlightVisible: Bool { isGroupHovered || isHovered || isPressed }

    func setPointerInside(_ inside: Bool) {
        guard inside != isHovered else { return }
        isHovered = inside
        if !inside { isPressed = false }
        needsDisplay = true
    }

    func resetInteractionState() {
        isHovered = false
        isPressed = false
        isGroupHovered = false
        needsDisplay = true
    }

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
        setPointerInside(true)
        hoverHandler?(true)
    }

    override func mouseExited(with event: NSEvent) {
        setPointerInside(false)
        hoverHandler?(false)
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
        let actionColor = color(for: action)
        let idleColor = inactiveControlColor()
        let fillColor: NSColor

        if !isControlEnabled {
            fillColor = idleColor
        } else if isPressed {
            fillColor = actionColor.blended(withFraction: 0.24, of: .black) ?? actionColor
        } else if isHovered {
            fillColor = actionColor.blended(withFraction: 0.10, of: .black) ?? actionColor
        } else if isWindowActive || isGroupHovered {
            fillColor = actionColor
        } else {
            fillColor = idleColor
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

        if style != .macOS || isPointerHighlightVisible {
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
        case .close:
            return NSColor(srgbRed: 1.0, green: 0.37255, blue: 0.34118, alpha: 1.0)
        case .minimize:
            return NSColor(srgbRed: 0.99608, green: 0.73725, blue: 0.18039, alpha: 1.0)
        case .zoom:
            return NSColor(srgbRed: 0.15686, green: 0.78431, blue: 0.25098, alpha: 1.0)
        }
    }

    private func inactiveControlColor() -> NSColor {
        switch effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
        case .darkAqua:
            // Sampled from the center of a native inactive traffic-light button.
            return NSColor(srgbRed: 0.37647, green: 0.37647, blue: 0.37255, alpha: 1.0)
        default:
            return NSColor(srgbRed: 0.74510, green: 0.74510, blue: 0.73725, alpha: 1.0)
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
