import AppKit
import Testing
@testable import TrafficLightsPlus

@Test func stageManagerCloseButtonAnchorsToThumbnailTopLeft() {
    let thumbnail = CGRect(x: 16, y: 402, width: 110, height: 123)

    #expect(StageManagerCloseController.closeButtonFrame(for: thumbnail) == CGRect(
        x: 16,
        y: 402,
        width: 28,
        height: 28
    ))
}

@Test func stageManagerCloseButtonRevealsOnlyNearItsCorner() {
    let panelFrame = CGRect(x: 16, y: 700, width: 28, height: 28)

    #expect(StageManagerCloseController.shouldRevealCloseButton(
        mouseLocation: CGPoint(x: 10, y: 716),
        panelFrame: panelFrame
    ))
    #expect(!StageManagerCloseController.shouldRevealCloseButton(
        mouseLocation: CGPoint(x: 80, y: 716),
        panelFrame: panelFrame
    ))
}

@Test func stageManagerCloseClickConsumesOnlyTheVisibleButtonFrame() {
    let frame = CGRect(x: 16, y: 402, width: 28, height: 28)

    #expect(StageManagerCloseController.closeButtonContainsClick(
        CGPoint(x: 30, y: 416),
        frame: frame
    ))
    #expect(!StageManagerCloseController.closeButtonContainsClick(
        CGPoint(x: 50, y: 416),
        frame: frame
    ))
}

@Test func stageManagerGroupUsesFrontmostWindowServerRecord() {
    let group = StageManagerGroupID(windowIDs: [20, 30])
    let records = [
        StageManagerWindowRecord(
            id: 30,
            pid: 300,
            title: "Front",
            bounds: CGRect(x: 20, y: 100, width: 120, height: 100)
        ),
        StageManagerWindowRecord(
            id: 20,
            pid: 200,
            title: "Back",
            bounds: CGRect(x: 15, y: 95, width: 120, height: 100)
        )
    ]

    #expect(StageManagerCloseController.frontmostRecord(for: group, in: records)?.id == 30)
}

@Test func stageManagerWindowMatchingAvoidsAmbiguousCloses() {
    let candidates = [
        StageManagerWindowCandidate(title: "Document", isFocused: false, isMain: false),
        StageManagerWindowCandidate(title: "Settings", isFocused: false, isMain: true)
    ]

    #expect(StageManagerCloseController.matchingCandidateIndex(
        recordTitle: "Settings",
        candidates: candidates
    ) == 1)
    #expect(StageManagerCloseController.matchingCandidateIndex(
        recordTitle: "Unknown",
        candidates: candidates
    ) == nil)
    #expect(StageManagerCloseController.matchingCandidateIndex(
        recordTitle: "Anything",
        candidates: [StageManagerWindowCandidate(title: "", isFocused: false, isMain: false)]
    ) == 0)

    let duplicateTitles = [
        StageManagerWindowCandidate(title: "Document", isFocused: false, isMain: false),
        StageManagerWindowCandidate(title: "Document", isFocused: false, isMain: false)
    ]
    #expect(StageManagerCloseController.matchingCandidateIndex(
        recordTitle: "Document",
        candidates: duplicateTitles
    ) == nil)
}

@MainActor
@Test func stageManagerClosePanelIsNonactivatingAndUsesAFamiliarSymbol() {
    let panel = StageManagerClosePanel(language: .simplifiedChinese)

    #expect(panel.level == .floating)
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.frame.size == StageManagerClosePanel.panelSize)
    #expect(!panel.hasShadow)
    #expect(panel.ignoresMouseEvents)
    #expect(panel.closeButton.layer?.backgroundColor?.alpha == 0)
    #expect(panel.closeButton.image != nil)
    #expect(panel.closeButton.toolTip == "关闭台前调度窗口")
}
