import CoreGraphics

struct ControlLayout {
    static let sizeRange = 18.0...48.0

    static func effectiveSize(preferred: Double) -> CGFloat {
        CGFloat(min(max(preferred, sizeRange.lowerBound), sizeRange.upperBound))
    }

    static func frames(
        style: ControlStyle,
        controlSize: CGFloat,
        windowOrigin: CGPoint,
        windowSize: CGSize
    ) -> [WindowAction: CGRect] {
        let buttonWidth = controlSize
        let gap: CGFloat = style == .macOS ? 8 : 0
        let topInset: CGFloat = style == .edgeSquares ? 0 : 4
        let left: CGFloat

        switch style {
        case .macOS:
            left = windowOrigin.x + 12
        case .edgeSquares:
            left = windowOrigin.x
        }

        return Dictionary(uniqueKeysWithValues: displayOrder(for: style).enumerated().map { index, action in
            let spacing = buttonWidth + gap
            let frame = CGRect(
                x: left + CGFloat(index) * spacing,
                y: windowOrigin.y + topInset,
                width: buttonWidth,
                height: controlSize
            )
            return (action, frame)
        })
    }

    static func displayOrder(for style: ControlStyle) -> [WindowAction] {
        [.close, .minimize, .zoom]
    }
}
