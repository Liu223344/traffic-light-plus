import CoreGraphics
import Foundation

struct ControlLayout {
    static let sizeRange = 18.0...48.0
    static let spacingAdjustmentRange = -8.0...32.0
    static let activationPadding: CGFloat = 6

    static func effectiveSize(preferred: Double) -> CGFloat {
        CGFloat(min(max(preferred, sizeRange.lowerBound), sizeRange.upperBound))
    }

    static func effectiveSpacingAdjustment(preferred: Double) -> CGFloat {
        CGFloat(min(
            max(preferred, spacingAdjustmentRange.lowerBound),
            spacingAdjustmentRange.upperBound
        ))
    }

    static func centerByAdjustingSystemSpacing(
        _ nativeCenter: CGPoint,
        action: WindowAction,
        adjustment: CGFloat
    ) -> CGPoint {
        let index = displayOrder(for: .macOS).firstIndex(of: action) ?? 0
        return CGPoint(
            x: nativeCenter.x + CGFloat(index) * adjustment,
            y: nativeCenter.y
        )
    }

    static func frameCentered(on nativeFrame: CGRect, controlSize: CGFloat) -> CGRect {
        CGRect(
            x: nativeFrame.midX - controlSize / 2,
            y: nativeFrame.midY - controlSize / 2,
            width: controlSize,
            height: controlSize
        )
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

    static func unobscuredActions(
        controlFrames: [WindowAction: CGRect],
        coveringFrames: [CGRect]
    ) -> Set<WindowAction> {
        Set(controlFrames.compactMap { action, frame in
            coveringFrames.contains(where: { $0.intersects(frame) }) ? nil : action
        })
    }

    static func activationRegion(
        controlFrames: [WindowAction: CGRect],
        actions: Set<WindowAction>,
        padding: CGFloat = activationPadding
    ) -> CGRect? {
        let frames = actions.compactMap { controlFrames[$0] }
        guard var region = frames.first else { return nil }
        for frame in frames.dropFirst() { region = region.union(frame) }
        return region.insetBy(dx: -padding, dy: -padding)
    }

    static func interpolatedFrame(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        let progress = min(max(progress, 0), 1)
        return CGRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: start.minY + (end.minY - start.minY) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }

    static func nextPresentationProgress(
        current: CGFloat,
        elapsed: TimeInterval,
        expanding: Bool,
        duration: TimeInterval
    ) -> CGFloat {
        guard duration > 0 else { return expanding ? 1 : 0 }
        let delta = CGFloat(max(elapsed, 0) / duration)
        return expanding ? min(1, current + delta) : max(0, current - delta)
    }

    static func nearestAction(
        to point: CGPoint,
        controlFrames: [WindowAction: CGRect],
        actions: Set<WindowAction>,
        currentAction: WindowAction?,
        hysteresis: CGFloat = 4
    ) -> WindowAction? {
        let orderedActions = displayOrder(for: .macOS).filter { actions.contains($0) }
        let scored = orderedActions.compactMap { action -> (WindowAction, CGFloat, Bool)? in
            guard let frame = controlFrames[action] else { return nil }
            let distance = hypot(point.x - frame.midX, point.y - frame.midY)
            return (action, distance, frame.contains(point))
        }
        guard !scored.isEmpty else { return nil }

        let directHits = scored.filter(\.2)
        if let nearestDirectHit = directHits.min(by: { $0.1 < $1.1 }) {
            guard let currentAction,
                  currentAction != nearestDirectHit.0,
                  let currentHit = directHits.first(where: { $0.0 == currentAction }) else {
                return nearestDirectHit.0
            }
            return nearestDirectHit.1 + hysteresis < currentHit.1
                ? nearestDirectHit.0
                : currentAction
        }

        guard let nearest = scored.min(by: { $0.1 < $1.1 }) else { return nil }
        guard let currentAction,
              currentAction != nearest.0,
              let current = scored.first(where: { $0.0 == currentAction }) else {
            return nearest.0
        }
        return nearest.1 + hysteresis < current.1 ? nearest.0 : currentAction
    }

    static func revealActions(
        mode: HiddenTrafficLightRevealMode,
        pointer: CGPoint,
        controlFrames: [WindowAction: CGRect],
        actions: Set<WindowAction>,
        currentAction: WindowAction?
    ) -> Set<WindowAction> {
        switch mode {
        case .group:
            return actions
        case .nearest:
            return nearestAction(
                to: pointer,
                controlFrames: controlFrames,
                actions: actions,
                currentAction: currentAction
            ).map { Set([$0]) } ?? []
        }
    }

}
