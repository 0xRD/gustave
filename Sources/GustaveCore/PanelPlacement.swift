/// Where the window list goes next to a Dock icon. All values in AppKit coordinates.
public enum PanelPlacement {
    public static let gap = 8.0

    /// Beside the icon, on the side away from the Dock, then moved inside `bounds`. A
    /// panel larger than `bounds` is pinned to its origin.
    public static func frame(
        width: Double,
        height: Double,
        anchor: Rect,
        edge: DockEdge,
        bounds: Rect
    ) -> Rect {
        var x: Double
        var y: Double
        switch edge {
        case .bottom:
            x = anchor.midX - width / 2
            y = anchor.maxY + gap
        case .left:
            x = anchor.maxX + gap
            y = anchor.midY - height / 2
        case .right:
            x = anchor.x - gap - width
            y = anchor.midY - height / 2
        }
        x = clamp(x, lower: bounds.x, upper: bounds.maxX - width)
        y = clamp(y, lower: bounds.y, upper: bounds.maxY - height)
        return Rect(x: x, y: y, width: width, height: height)
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(value, upper))
    }
}
