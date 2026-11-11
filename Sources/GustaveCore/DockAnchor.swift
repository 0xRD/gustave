/// Where the panel is anchored while an auto-hiding Dock slides. All values in AppKit
/// coordinates (D36).
public enum DockAnchor {
    /// The icon frame to keep for the same icon. An auto-hiding Dock reports an icon while it
    /// is still sliding in or out, so a frame closer to the screen edge than the one already
    /// held is a Dock in motion, not a new place: the panel stays where the Dock rests.
    public static func settled(current: Rect, reported: Rect, edge: DockEdge) -> Rect {
        distanceFromEdge(reported, edge: edge) < distanceFromEdge(current, edge: edge) ? current : reported
    }

    /// Larger is further into the screen, away from the Dock's edge.
    private static func distanceFromEdge(_ frame: Rect, edge: DockEdge) -> Double {
        switch edge {
        case .bottom: frame.y
        case .left: frame.x
        case .right: -frame.maxX
        }
    }
}

/// The area that keeps the Dock panel open once the Dock no longer reports its icon (D36).
public enum DockPanelZone {
    /// On the panel, or in the corridor from the icon's far side to the panel. Not the icon
    /// itself, and not the rest of the rectangle around both: once the Dock says the pointer
    /// left the icon, or the Dock hid, resting there must let the panel close.
    public static func contains(_ pointer: Point, panel: Rect, icon: Rect, edge: DockEdge, slack: Double) -> Bool {
        panel.contains(pointer) || corridor(panel: panel, icon: icon, edge: edge, slack: slack).contains(pointer)
    }

    static func corridor(panel: Rect, icon: Rect, edge: DockEdge, slack: Double) -> Rect {
        switch edge {
        case .bottom:
            let low = icon.maxY - slack
            return Rect(x: icon.x - slack, y: low, width: icon.width + 2 * slack, height: max(panel.y - low, 0))
        case .left:
            let low = icon.maxX - slack
            return Rect(x: low, y: icon.y - slack, width: max(panel.x - low, 0), height: icon.height + 2 * slack)
        case .right:
            let high = icon.x + slack
            return Rect(x: panel.maxX, y: icon.y - slack, width: max(high - panel.maxX, 0), height: icon.height + 2 * slack)
        }
    }
}
