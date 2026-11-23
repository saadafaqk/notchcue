import CoreGraphics

public enum PlacementMode: String, Sendable, CaseIterable {
    case notch, topLeft, topRight, floating
}

/// Where the prompter panel goes on a screen. In notch mode on a notched display the panel's top band
/// (menu-bar tall) wraps the notch; the "ears" either side of the notch hold status (pace, timer, progress).
public struct PanelGeometry: Equatable, Sendable {
    public let frame: CGRect
    /// The band at the top of `frame` that sits in the menu-bar strip; `.zero` when there is no band.
    public let bandSize: CGSize
    /// Width of the physical notch inside the band; 0 when the screen has no notch.
    public var notchWidth: CGFloat = 0

    /// Where the panel starts its show animation (and ends its hide): collapsed up into the band, or a
    /// one-point strip at its top edge. Always on the same screen, so it never flashes on another display.
    public var collapsedFrame: CGRect {
        let height = bandSize.height > 0 ? bandSize.height : 1
        return CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    }

    public static let cornerInset: CGFloat = 12

    public static func compute(screenFrame s: CGRect, safeAreaTop: CGFloat,
                               auxiliaryLeftWidth: CGFloat, auxiliaryRightWidth: CGFloat,
                               menuBarHeight: CGFloat, size: CGSize, mode: PlacementMode,
                               floatingOrigin: CGPoint?) -> PanelGeometry {
        let belowMenuBar = s.maxY - menuBarHeight
        switch mode {
        case .notch where safeAreaTop > 0:
            let notchWidth = s.width - auxiliaryLeftWidth - auxiliaryRightWidth
            let width = max(size.width, notchWidth)
            let height = safeAreaTop + size.height
            return PanelGeometry(frame: CGRect(x: s.midX - width / 2, y: s.maxY - height, width: width, height: height),
                                 bandSize: CGSize(width: width, height: safeAreaTop), notchWidth: notchWidth)
        case .notch:
            return PanelGeometry(frame: CGRect(x: s.midX - size.width / 2, y: belowMenuBar - size.height,
                                               width: size.width, height: size.height), bandSize: .zero)
        case .topLeft:
            return PanelGeometry(frame: CGRect(x: s.minX + cornerInset, y: belowMenuBar - cornerInset - size.height,
                                               width: size.width, height: size.height), bandSize: .zero)
        case .topRight:
            return PanelGeometry(frame: CGRect(x: s.maxX - cornerInset - size.width,
                                               y: belowMenuBar - cornerInset - size.height,
                                               width: size.width, height: size.height), bandSize: .zero)
        case .floating:
            let origin = floatingOrigin ?? CGPoint(x: s.midX - size.width / 2, y: s.midY - size.height / 2)
            return PanelGeometry(frame: CGRect(origin: origin, size: size), bandSize: .zero)
        }
    }
}
