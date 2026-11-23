import CoreGraphics

public enum PlacementMode: String, Sendable, CaseIterable {
    case notch, topLeft, topRight, floating
}

/// Where the prompter panel goes on a screen. In notch mode on a notched display the panel has a
/// narrow top band (exactly the notch's width, menu-bar tall) so menus and status items stay visible,
/// and widens to the full prompter width only below the menu bar.
public struct PanelGeometry: Equatable, Sendable {
    public let frame: CGRect
    /// The notch-width band at the top of `frame`; `.zero` when there is no band.
    public let bandSize: CGSize

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
                                 bandSize: CGSize(width: notchWidth, height: safeAreaTop))
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
