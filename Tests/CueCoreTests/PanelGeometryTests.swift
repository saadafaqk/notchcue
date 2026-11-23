import CoreGraphics
import Testing
@testable import CueCore

private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let monitor = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
private let size = CGSize(width: 520, height: 140)

private func geometry(_ screen: CGRect, notch: Bool, mode: PlacementMode, size: CGSize = size,
                      origin: CGPoint? = nil) -> PanelGeometry {
    PanelGeometry.compute(screenFrame: screen,
                          safeAreaTop: notch ? 37.5 : 0,
                          auxiliaryLeftWidth: notch ? 650 : 0,
                          auxiliaryRightWidth: notch ? 650 : 0,
                          menuBarHeight: notch ? 37.5 : 24,
                          size: size, mode: mode, floatingOrigin: origin)
}

@Test func notchModeHugsNotchWithNarrowBand() {
    let g = geometry(laptop, notch: true, mode: .notch)
    #expect(g.frame == CGRect(x: 496, y: 804.5, width: 520, height: 177.5))
    #expect(g.bandSize == CGSize(width: 212, height: 37.5))
}

@Test func notchModeWithoutNotchSitsBelowMenuBar() {
    let g = geometry(monitor, notch: false, mode: .notch)
    #expect(g.frame == CGRect(x: 1512 + 1020, y: 1276, width: 520, height: 140))
    #expect(g.bandSize == .zero)
}

@Test func cornersInsetBelowMenuBar() {
    #expect(geometry(monitor, notch: false, mode: .topLeft).frame.origin == CGPoint(x: 1524, y: 1264))
    #expect(geometry(monitor, notch: false, mode: .topRight).frame.origin == CGPoint(x: 1512 + 2028, y: 1264))
}

@Test func floatingUsesSavedOriginOrCenter() {
    #expect(geometry(monitor, notch: false, mode: .floating, origin: CGPoint(x: 2000, y: 300)).frame.origin
            == CGPoint(x: 2000, y: 300))
    #expect(geometry(monitor, notch: false, mode: .floating).frame.origin == CGPoint(x: 1512 + 1020, y: 650))
}

@Test func panelNeverNarrowerThanNotch() {
    let g = geometry(laptop, notch: true, mode: .notch, size: CGSize(width: 150, height: 100))
    #expect(g.frame.width == 212)
}
